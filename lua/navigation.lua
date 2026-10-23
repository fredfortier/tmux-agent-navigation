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
    -- Older tmux includes the position header in copy_cursor_line, covering
    -- real text on row zero. Capture both header states and restore the user's
    -- state immediately; neither toggle moves the cursor or selection.
    local cursor_lines = { text }
    if y == 0 then
        tmux("send-keys", "-t", pane, "-X", "toggle-position")
        local ok, alternate = pcall(fmt, pane, "#{copy_cursor_line}")
        tmux("send-keys", "-t", pane, "-X", "toggle-position")
        assert(ok, alternate)
        cursor_lines[#cursor_lines + 1] = alternate
    end
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
            for _, cursor_line in ipairs(cursor_lines) do
                local current = cursor_line:gsub("%s+$", "")
                if current ~= "" and logical:find(current, 1, true) then
                    text = logical
                    x = x + (row - physical) * width
                    break
                end
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

function M.parse(text, x, host_workspace, container_workspace)
    local mapping = host_workspace
            and container_workspace
            and { from = host_workspace, to = container_workspace }
        or nil
    local file, line, col = M.resolve(text, tonumber(x), container_workspace or vim.fn.getcwd(), mapping)
    local directory = vim.fn.isdirectory(file) == 1 and file or vim.fs.dirname(file)
    io.write(vim.json.encode({
        file = file,
        line = line,
        col = col,
        root = vim.fs.root(directory, ".git") or directory,
    }))
end

local function container_root(pane)
    local root = fmt(pane, "#{@agent-container-root}")
    if root == "" then
        return nil
    end
    root = vim.fs.normalize(root)
    assert(
        root:sub(1, 1) == "/" and root ~= "/",
        "Set @agent-container-root to an absolute workspace directory"
    )
    assert(vim.env.TMUX_AGENT_CONTAINER_PACKAGE, "Set TMUX_AGENT_CONTAINER_PACKAGE for container routing")
    return root
end

local function foreground(pane)
    if not vim.env.TMUX_AGENT_CONTAINER_PACKAGE then
        return nil
    end
    return dofile(base .. "lua/context.lua").foreground(tonumber(fmt(pane, "#{pane_pid}")))
end

function M.context(pane)
    assert(alive(pane), "Originating pane is gone")
    io.write(vim.json.encode(foreground(pane) or vim.NIL))
end

function M.pick(pane, text, x, cwd, layout)
    local context = foreground(pane)
    local remote_root = container_root(pane)
    if not context and remote_root then
        local workspace = vim.fs.root(cwd, ".git")
        if workspace and vim.uv.fs_stat(workspace .. "/.devcontainer/devcontainer.json") then
            local file = M.resolve(text, x, cwd, { from = remote_root, to = workspace })
            if file == workspace or file:sub(1, #workspace + 1) == workspace .. "/" then
                context = dofile(base .. "lua/context.lua").workspace(workspace)
            end
        end
    end
    if context then
        -- Resolve in the selected container. Optional mapping translates host
        -- checkout spellings; ~/ and outside-workspace paths stay container-local.
        local command = {
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
        }
        if remote_root then
            vim.list_extend(command, { context.workspace, remote_root })
        end
        local target = vim.json.decode(run(command))
        context.root = target.root
        M.launch(pane, target.file, target.line, target.col, context, layout)
    else
        local file, line, col = M.resolve(text, x, cwd)
        M.launch(pane, file, line, col, nil, layout)
    end
end

-- RPC remains owned by this package; callers use the public status command.
local function remote(child, expression)
    local runtime = fmt(child, "#{@nav_runtime}")
    local command = { vim.v.progpath }
    if runtime == "container" then
        command = {
            "devcontainer",
            "exec",
            "--container-id",
            fmt(child, "#{@nav_container}"),
            "--workspace-folder",
            fmt(child, "#{@nav_workspace}"),
            "nvim",
        }
    end
    vim.list_extend(
        command,
        { "-u", "NONE", "-i", "NONE", "--server", fmt(child, "#{@nav_socket}"), "--remote-expr", expression }
    )
    return run(command)
end

function M.status(pane)
    assert(alive(pane), "Pane is gone")
    local parent = fmt(pane, "#{@nav_parent}")
    if not alive(parent) then
        parent = pane
    end
    local child = fmt(parent, "#{@nav_child}")
    local data = {
        parent = {
            pane = parent,
            active = fmt(parent, "#{pane_active}") == "1",
            copy_mode = fmt(parent, "#{pane_in_mode}") == "1",
            cursor = fmt(parent, "#{copy_cursor_x}:#{copy_cursor_y}:#{scroll_position}"),
            zoomed = fmt(parent, "#{window_zoomed_flag}") == "1",
        },
        editor = vim.NIL,
    }
    if alive(child) then
        data.editor = {
            pane = child,
            runtime = fmt(child, "#{@nav_runtime}"),
            container = fmt(child, "#{@nav_container}"),
            active = fmt(child, "#{pane_active}") == "1",
            zoomed = fmt(child, "#{window_zoomed_flag}") == "1",
            ready = false,
        }
        if fmt(child, "#{@nav_socket}") ~= "" and fmt(child, "#{@nav_editor}") == "" then
            local ok, value = pcall(
                remote,
                child,
                "json_encode([expand('%:p'),line('.'),col('.'),getcwd(),getpid(),&filetype])"
            )
            if ok then
                local info = vim.json.decode(value)
                data.editor.ready = true
                data.editor.buffer, data.editor.line, data.editor.column = info[1], info[2], info[3]
                data.editor.cwd, data.editor.pid, data.editor.filetype = info[4], info[5], info[6]
            end
        end
    end
    io.write(vim.json.encode(data))
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
    local nvim_config = fmt(pane, "#{@agent-nvim-config}")
    assert(not context or editor == "", "Custom editors currently support host paths only")
    local oldchild = fmt(pane, "#{@nav_child}")
    if alive(oldchild) then
        assert(
            nvim_config == fmt(oldchild, "#{@nav_nvim_config}"),
            "Close the editor before changing Neovim configuration"
        )
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
        remote(oldchild, ("v:lua.TerminalNavOpen(%s,%d,%d)"):format(vim.fn.string(editor_file), line, col))
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
        nvim_config = nvim_config,
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
    tmux("set-option", "-p", "-t", child, "@nav_nvim_config", nvim_config)
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
    tmux("select-pane", "-t", data.parent)
    local zoomed = fmt(data.parent, "#{window_zoomed_flag}")
    if zoomed ~= data.zoom then
        tmux("resize-pane", "-Z", "-t", data.parent)
    end
    -- Publish completion only after both focus and zoom are restored.
    tmux("set-option", "-pu", "-t", data.parent, "@nav_child")
end

if arg and arg[1] then
    local ok, err = pcall(function()
        local commands = {
            open = M.open,
            toggle = M.toggle,
            thumb = M.thumb,
            parse = M.parse,
            context = M.context,
            status = M.status,
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
