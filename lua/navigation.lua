-- Pane orchestration owns focus, zoom, and child identity; parsing stays separate.
local M = {}
local base = assert(vim.env.TMUX_AGENT_ROOT, "TMUX_AGENT_ROOT is required") .. "/"
M.resolve = dofile(base .. "lua/resolve.lua").resolve
local function run(args, optional)
    local result = vim.system(args, { text = true }):wait()
    if result.code ~= 0 and not optional then
        error(vim.trim(result.stderr or "command failed"))
    end
    return (result.stdout or ""):gsub("\n$", ""), result.code
end
local function tmux(...)
    return run({ "tmux", ... })
end
local function fmt(pane, value)
    return (tmux("display-message", "-p", "-t", pane, value))
end
local function alive(pane)
    if not pane or not pane:match("^%%%d+$") then
        return false
    end
    local found, code = run({ "tmux", "display-message", "-p", "-t", pane, "#{pane_id}" }, true)
    return code == 0 and found == pane
end

function M.open(pane, layout)
    if fmt(pane, "#{pane_in_mode}") ~= "1" then
        error("Enter copy mode first: Ctrl-b [")
    end
    local text = fmt(pane, "#{copy_cursor_line}")
    local x = tonumber(fmt(pane, "#{copy_cursor_x}")) or 0
    -- Reconstruct soft-wrapped references around the cursor, without moving it.
    local y = tonumber(fmt(pane, "#{copy_cursor_y}")) or 0
    local scroll = tonumber(fmt(pane, "#{scroll_position}")) or 0
    local history = tonumber(fmt(pane, "#{history_size}")) or 0
    local width = tonumber(fmt(pane, "#{pane_width}")) or 80
    local height = tonumber(fmt(pane, "#{pane_height}")) or 24
    local row = y - scroll
    local first = math.max(-history, row - 16)
    local last = math.min(height - 1, row + 16)
    local joined = tmux("capture-pane", "-p", "-J", "-t", pane, "-S", tostring(first), "-E", tostring(last))
    local physical = first
    for _, logical in ipairs(vim.split(joined, "\n", { plain = true })) do
        local rows = math.max(1, math.ceil(vim.fn.strdisplaywidth(logical) / width))
        if row >= physical and row < physical + rows then
            -- After pane resizing tmux's scroll offsets can lag its cursor
            -- line. Never replace that authoritative line with unrelated text.
            local current = text:gsub("%s+$", "")
            if current ~= "" and logical:find(current, 1, true) then
                text = logical
                x = x + (row - physical) * width
            end
            break
        end
        physical = physical + rows
    end
    local cwd = fmt(pane, "#{pane_current_path}")
    M.pick(pane, text, x, cwd, layout)
end

function M.thumb(ref)
    local pane = vim.env.TMUX_NAV_ORIGIN or vim.env.TMUX_PANE
    assert(alive(pane), "Originating pane is gone")
    M.pick(pane, ref, 0, fmt(pane, "#{pane_current_path}"))
end

function M.parse(text, x)
    local file, line, col = M.resolve(text, tonumber(x), vim.fn.getcwd())
    local directory = vim.fn.isdirectory(file) == 1 and file or vim.fs.dirname(file)
    io.write(vim.json.encode({
        file = file,
        line = line,
        col = col,
        root = vim.fs.root(directory, ".git") or directory,
    }))
end

function M.pick(pane, text, x, cwd, layout)
    local context
    if vim.env.TMUX_AGENT_CONTAINER_PACKAGE then
        context = dofile(base .. "lua/context.lua")(tonumber(fmt(pane, "#{pane_pid}")))
    end
    if context then
        -- Resolve in the carrier, so ~/ and paths outside the workspace never select
        -- a different host file with the same spelling.
        local result = run({
            "devcontainer",
            "exec",
            "--container-id",
            context.container,
            "--workspace-folder",
            context.workspace,
            vim.env.TMUX_AGENT_CONTAINER_PACKAGE .. "/bin/agent-navigation",
            "parse",
            text,
            tostring(x),
        })
        local target = vim.json.decode(result)
        context.root = target.root
        M.launch(pane, target.file, target.line, target.col, context, layout)
    else
        local file, line, col = M.resolve(text, x, cwd)
        M.launch(pane, file, line, col, nil, layout)
    end
end

function M.launch(pane, file, line, col, context, layout)
    assert(layout == nil or layout == "split", "Unknown editor layout")
    local workspace = vim.fs.root(fmt(pane, "#{pane_current_path}"), ".git")
    local runtime = "host"
    local editor_file = file
    local directory = vim.fn.isdirectory(file) == 1 and file or vim.fs.dirname(file)
    local root = vim.fs.root(directory, ".git") or directory
    local editor_root = root
    if context then
        runtime = "container"
        workspace = context.workspace
        root = workspace
        editor_root = context.root
    end
    local editor = fmt(pane, "#{@agent-editor}")
    assert(not context or editor == "", "Custom editors currently support host paths only")
    local oldchild = fmt(pane, "#{@nav_child}")
    if alive(oldchild) then
        assert(
            editor == "" and fmt(oldchild, "#{@nav_editor}") == "",
            "Close the custom editor before opening another reference"
        )
        assert(
            (context and context.container or "") == fmt(oldchild, "#{@nav_container}"),
            "Close the editor before changing container identity"
        )
        if fmt(oldchild, "#{@nav_runtime}") ~= runtime then
            error("Close the current editor with :q before switching between host and container paths")
        end
        if runtime == "container" and fmt(oldchild, "#{@nav_workspace}") ~= workspace then
            error("Close the current editor with :q before switching between container workspaces")
        end
        local socket = fmt(oldchild, "#{@nav_socket}")
        if socket == "" then
            error("Child editor is still starting; try opening again")
        end
        local command = runtime == "container"
                and { "devcontainer", "exec", "--workspace-folder", workspace, "nvim" }
            or { vim.v.progpath }
        local container = fmt(oldchild, "#{@nav_container}")
        if runtime == "container" and container ~= "" then
            command = {
                "devcontainer",
                "exec",
                "--container-id",
                container,
                "--workspace-folder",
                workspace,
                "nvim",
            }
        end
        vim.list_extend(command, {
            "-u",
            "NONE",
            "-i",
            "NONE",
            "--server",
            socket,
            "--remote-expr",
            ("v:lua.TerminalNavOpen(%s,%d,%d)"):format(vim.fn.string(editor_file), line, col),
        })
        run(command)
        if layout == "split" then
            if fmt(oldchild, "#{window_zoomed_flag}") == "1" then
                tmux("resize-pane", "-Z", "-t", oldchild)
            end
            local height = tonumber(fmt(oldchild, "#{pane_height}")) + tonumber(fmt(pane, "#{pane_height}"))
            tmux("resize-pane", "-t", oldchild, "-y", tostring(math.floor(height / 2)))
            if fmt(pane, "#{pane_in_mode}") == "1" then
                tmux("send-keys", "-t", pane, "-X", "cancel")
            end
            tmux("select-pane", "-t", oldchild)
        else
            tmux("select-pane", "-t", oldchild)
            if fmt(oldchild, "#{window_zoomed_flag}") ~= "1" then
                tmux("resize-pane", "-Z", "-t", oldchild)
            end
        end
        return
    end
    local zoom = fmt(pane, "#{window_zoomed_flag}")
    -- One JSON value carries the path safely through tmux's exec argv boundary.
    local payload = vim.json.encode({
        file = editor_file,
        line = line,
        col = col,
        root = editor_root,
        parent = pane,
        zoom = zoom,
        runtime = runtime,
        editor = editor,
        package = vim.env.TMUX_AGENT_CONTAINER_PACKAGE,
        workspace = workspace,
        container = context and context.container or nil,
    })
    local command = { "split-window", "-b", "-v", "-l", layout == "split" and "50%" or "75%" }
    if layout ~= "split" then
        command[#command + 1] = "-Z"
    end
    vim.list_extend(command, {
        "-P",
        "-F",
        "#{pane_id}",
        "-t",
        pane,
        "-c",
        root,
        "/bin/bash",
        base .. "bin/child-editor",
        payload,
    })
    local child = tmux(unpack(command))
    tmux("set-option", "-p", "-t", pane, "@nav_child", child)
    tmux("set-option", "-p", "-t", child, "@nav_parent", pane)
    tmux("set-option", "-p", "-t", child, "@nav_runtime", runtime)
    tmux("set-option", "-p", "-t", child, "@nav_editor", editor)
    if workspace then
        tmux("set-option", "-p", "-t", child, "@nav_workspace", workspace)
    end
    if context then
        tmux("set-option", "-p", "-t", child, "@nav_container", context.container)
    end
    if layout == "split" and fmt(pane, "#{pane_in_mode}") == "1" then
        tmux("send-keys", "-t", pane, "-X", "cancel")
    end
end

function M.toggle(pane)
    local parent = fmt(pane, "#{@nav_parent}")
    local child = pane
    if not alive(parent) then
        parent = pane
        child = fmt(pane, "#{@nav_child}")
    end
    if not alive(child) or child == parent then
        error("No child editor for this pane")
    end
    if fmt(child, "#{window_zoomed_flag}") == "1" then
        tmux("resize-pane", "-Z", "-t", child)
        tmux("select-pane", "-t", parent)
    else
        tmux("select-pane", "-t", child)
        tmux("resize-pane", "-Z", "-t", child)
    end
end

function M.restore(payload)
    local data = vim.json.decode(payload)
    local child = vim.env.TMUX_PANE
    assert(child and child:match("^%%%d+$") and data.parent:match("^%%%d+$"), "Invalid pane identity")
    assert(data.zoom == "0" or data.zoom == "1", "Invalid zoom state")
    -- tmux unzooms when it removes a pane. Restore only after that removal.
    tmux(
        "run-shell",
        "-b",
        ("%s restore_after %s %s %s"):format(
            vim.fn.shellescape(base .. "bin/agent-navigation"),
            child,
            data.parent,
            data.zoom
        )
    )
end

function M.restore_after(child, parent, zoom)
    assert(
        vim.wait(5000, function()
            return not alive(child)
        end, 25),
        "Child pane did not exit"
    )
    local data = { parent = parent, zoom = zoom }
    if not alive(data.parent) then
        return
    end
    tmux("set-option", "-pu", "-t", data.parent, "@nav_child")
    tmux("select-pane", "-t", data.parent)
    local zoomed = fmt(data.parent, "#{window_zoomed_flag}")
    if zoomed ~= data.zoom then
        tmux("resize-pane", "-Z", "-t", data.parent)
    end
end

if arg and arg[1] then
    local ok, err = pcall(function()
        local commands = {
            open = M.open,
            toggle = M.toggle,
            thumb = M.thumb,
            parse = M.parse,
            restore = M.restore,
            restore_after = M.restore_after,
        }
        assert(commands[arg[1]], "Usage: agent-navigation open|toggle PANE")(unpack(arg, 2))
    end)
    if not ok then
        local message = tostring(err):gsub("^.-:%d+: ", "")
        if arg[1] ~= "parse" then
            run({ "tmux", "display-message", "-l", "-d", "5000", "tmux-agent-navigation: " .. message }, true)
        end
        io.stderr:write(message .. "\n")
        os.exit(1)
    end
end
return M
