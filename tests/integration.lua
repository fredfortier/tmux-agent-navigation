-- Run against a disposable tmux server attached to a real PTY, never a user
-- server: nvim --headless -u NONE -i NONE -l <this-file> <socket-name>.
local server = assert(arg[1], "Pass a disposable attached tmux socket name")
assert(server:match("^nav%-"), "Use a disposable nav-* server")
local function run(args)
    local result = vim.system(args, { text = true }):wait()
    assert(result.code == 0, result.stderr)
    return vim.trim(result.stdout)
end
local function tmux(...)
    return run({ "tmux", "-L", server, ... })
end
local function fmt(pane, format)
    return tmux("display-message", "-p", "-t", pane, format)
end
assert(tmux("list-clients") ~= "", "Attach a PTY client first")
-- Feed the attached client's PTY rather than send-keys -K (tmux 3.4+).
-- This exercises real terminal key dispatch on the supported tmux minimum too.
local function client_keys(key)
    local input = assert(io.open(assert(vim.env.TMUX_AGENT_TEST_INPUT), "w"))
    input:write(key == "C-b" and string.char(2) or key)
    input:close()
end
local thumbs = arg[2] == "thumbs"
local split = arg[2] == "split"
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
local file = fixture .. (thumbs and "/navigation.conf" or "/a (nested).md")
vim.fn.writefile({ "one", "two", "three" }, file)
local encoded = file:gsub(" ", "%%20"):gsub("%(", "%%28"):gsub("%)", "%%29")
local forms = {
    { encoded .. "#L2", 2 },
    { "[source](" .. encoded .. "#L2-L3)", 2 },
    { "[source](<" .. file .. '#L2> "title")', 2 },
    { "[a [nested] label](" .. encoded .. "#L2 'title')", 2 },
    { '"' .. file .. ':2:1"', 2 },
    { "Browse " .. fixture .. "/.", 1, true, 8 },
}
if thumbs then
    local nested = fixture .. "/.config/tmux"
    vim.fn.mkdir(nested, "p")
    vim.fn.writefile({ "one", "two", "three" }, nested .. "/navigation.conf")
    local long = fixture .. "/" .. string.rep("wrapped-directory-", 5)
    vim.fn.mkdir(long, "p")
    vim.fn.writefile({ "one", "two", "three" }, long .. "/navigation.conf")
    forms = {
        { file .. "#L2", 2 },
        { "navigation.conf:2", 2 },
        { "navigation.conf (" .. file .. "#L2)", 2 },
        { "navigation.conf (.config/tmux/navigation.conf#L2)", 2, false, nil, nested .. "/navigation.conf" },
        { "navigation.conf (" .. long .. "/navigation.conf#L2)", 2, false, nil, long .. "/navigation.conf" },
        { "[navigation.conf](" .. file .. "#L2)", 2 },
        { fixture .. "/", 1, true },
    }
end
local ok, err = pcall(function()
    for index, form in ipairs(forms) do
        local script = fixture .. "/show.sh"
        local commands = { "printf '%s\\n' " .. vim.fn.shellescape(form[1]) }
        if split then
            commands[#commands + 1] = "printf 'older output\\n%.0s' {1..60}"
            commands[#commands + 1] = "printf 'LIVE_BOTTOM\\n'"
        end
        commands[#commands + 1] = "exec bash --noprofile --norc"
        vim.fn.writefile(commands, script)
        local pane = tmux(
            "new-window",
            "-P",
            "-F",
            "#{pane_id}",
            "-c",
            fixture,
            "bash",
            "--noprofile",
            "--norc",
            script
        )
        assert(
            vim.wait(10000, function()
                return tmux("capture-pane", "-p", "-S", "-", "-t", pane):find(form[1]:sub(1, 15), 1, true)
                    ~= nil
            end, 25),
            "Fixture did not render case " .. index
        )
        local sibling, sibling_geometry
        if split and index == 2 then
            sibling = tmux(
                "split-window",
                "-h",
                "-d",
                "-t",
                pane,
                "-P",
                "-F",
                "#{pane_id}",
                "bash",
                "--noprofile",
                "--norc"
            )
            sibling_geometry = fmt(sibling, "#{pane_left}:#{pane_width}:#{pane_height}")
            tmux("resize-pane", "-Z", "-t", pane)
        end
        tmux("copy-mode", "-t", pane)
        tmux("send-keys", "-t", pane, "-X", "history-top")
        tmux("send-keys", "-t", pane, "-X", "start-of-line")
        for _ = 1, form[4] or 3 do
            tmux("send-keys", "-t", pane, "-X", "cursor-right")
        end
        if split and index == 1 then
            tmux("send-keys", "-t", pane, "-X", "begin-selection")
        end
        local before = fmt(pane, "#{copy_cursor_x}:#{copy_cursor_y}:#{scroll_position}")
        local before_text = fmt(pane, "#{copy_cursor_line}")
        if thumbs then
            local window = fmt(pane, "#{window_id}")
            local function pick(key)
                client_keys("C-b")
                client_keys("F")
                assert(
                    vim.wait(5000, function()
                        local overlay = fmt(window, "#{pane_id}")
                        return overlay ~= pane and tmux("capture-pane", "-p", "-t", window):match("%S") ~= nil
                    end, 25),
                    "Thumbs overlay did not render"
                )
                tmux("send-keys", "-t", window, key)
                assert(
                    vim.wait(5000, function()
                        return fmt(window, "#{pane_id}") == pane
                    end, 25),
                    "Thumbs did not return the original pane"
                )
            end
            tmux("set-buffer", "thumbs-test-sentinel")
            pick("a")
            assert(
                vim.wait(3000, function()
                    return tmux("show-buffer") ~= "thumbs-test-sentinel"
                end, 25),
                "Lowercase did not copy a hint"
            )
            local copied = tmux("show-buffer")
            assert(copied == form[1] or copied == file .. "#L2", "Wrong copied hint: " .. copied)
            assert(fmt(pane, "#{@nav_child}") == "", "Lowercase opened an editor")
            pick("A")
        else
            client_keys("g")
            assert(vim.wait(1000, function()
                return tmux("list-clients", "-F", "#{client_key_table}") == "agent-navigation-g"
            end, 25))
            client_keys(split and "n" or "f")
        end
        local child, socket
        assert(
            vim.wait(10000, function()
                child = fmt(pane, "#{@nav_child}")
                if child == "" then
                    return false
                end
                socket = fmt(child, "#{@nav_socket}")
                return socket ~= "" and vim.uv.fs_stat(socket) ~= nil
            end, 50),
            (thumbs and "hint" or (split and "gn" or "gf")) .. " did not open case " .. index
        )
        local actual
        assert(
            vim.wait(5000, function()
                local result = vim.system({
                    "nvim",
                    "--server",
                    socket,
                    "--remote-expr",
                    "json_encode([expand('%:p'),line('.'),col('.'),&filetype])",
                }, { text = true }):wait()
                if result.code ~= 0 then
                    return false
                end
                actual = vim.json.decode(result.stdout)
                return form[3] and actual[4] == "netrw" or actual[1] == (form[5] or file)
            end, 50),
            "Wrong buffer in case " .. index
        )
        if not form[3] then
            assert(actual[2] == form[2] and actual[3] == 1, vim.inspect(actual))
        end
        if index == 1 then
            local status = vim.system(
                { vim.env.TMUX_AGENT_ROOT .. "/bin/agent-navigation", "status", pane },
                { env = { TMUX = tmux("display-message", "-p", "#{socket_path}") .. ",0,0" }, text = true }
            ):wait()
            assert(status.code == 0, status.stderr)
            local snapshot = vim.json.decode(status.stdout)
            assert(snapshot.parent.pane == pane and snapshot.editor.ready)
            assert(snapshot.editor.buffer == file and snapshot.editor.line == form[2])
        end
        if split and index == 1 then
            -- Reuse one child while switching between fullscreen and split;
            -- opening another reference must not accumulate editor panes.
            for _, key in ipairs({ "f", "n", "n" }) do
                tmux("select-pane", "-t", pane)
                tmux("copy-mode", "-t", pane)
                tmux("send-keys", "-t", pane, "-X", "history-top")
                tmux("send-keys", "-t", pane, "-X", "start-of-line")
                tmux("send-keys", "-t", pane, "-X", "cursor-right")
                client_keys("g")
                assert(vim.wait(1000, function()
                    return tmux("list-clients", "-F", "#{client_key_table}") == "agent-navigation-g"
                end, 25))
                client_keys(key)
                assert(
                    vim.wait(3000, function()
                        return fmt(child, "#{pane_active}") == "1"
                            and fmt(child, "#{window_zoomed_flag}") == (key == "f" and "1" or "0")
                            and (key == "f" or fmt(pane, "#{pane_in_mode}") == "0")
                    end, 25),
                    "Existing child layout did not change for g" .. key
                )
                assert(fmt(pane, "#{@nav_child}") == child)
                assert(#vim.split(tmux("list-panes", "-t", pane, "-F", "#{pane_id}"), "\n") == 2)
            end
        end
        if split then
            assert(fmt(child, "#{window_zoomed_flag}") == "0")
            assert(fmt(child, "#{pane_active}") == "1")
            assert(tonumber(fmt(child, "#{pane_top}")) < tonumber(fmt(pane, "#{pane_top}")))
            assert(
                math.abs(tonumber(fmt(child, "#{pane_height}")) - tonumber(fmt(pane, "#{pane_height}"))) <= 1
            )
            assert(fmt(pane, "#{pane_in_mode}") == "0")
            assert(tmux("capture-pane", "-p", "-t", pane):find("LIVE_BOTTOM", 1, true))
            if sibling then
                assert(fmt(sibling, "#{pane_left}:#{pane_width}:#{pane_height}") == sibling_geometry)
            end
            assert(fmt(child, "#{E:status-left}"):find("prefix e zoom", 1, true))
            if index == 1 then
                for _, expected in ipairs({ "1", "0" }) do
                    client_keys("C-b")
                    client_keys("e")
                    assert(vim.wait(3000, function()
                        return fmt(child, "#{window_zoomed_flag}") == expected
                            and fmt(expected == "1" and child or pane, "#{pane_active}") == "1"
                    end, 25))
                    assert(
                        fmt(child, "#{E:status-left}"):find(
                            expected == "1" and "prefix e split" or "prefix e zoom",
                            1,
                            true
                        )
                    )
                end
                tmux("select-pane", "-t", child)
            end
        else
            assert(fmt(child, "#{window_zoomed_flag}") == "1")
        end
        tmux("send-keys", "-t", child, "Escape", ":q", "Enter")
        assert(vim.wait(5000, function()
            return fmt(pane, "#{@nav_child}") == ""
        end, 25))
        assert(fmt(pane, "#{pane_active}") == "1")
        if split then
            assert(fmt(pane, "#{pane_in_mode}") == "0")
            assert(fmt(pane, "#{window_zoomed_flag}") == (sibling and "1" or "0"))
        else
            assert(fmt(pane, "#{pane_in_mode}") == "1")
            assert(fmt(pane, "#{copy_cursor_x}:#{copy_cursor_y}:#{scroll_position}") == before)
            assert(fmt(pane, "#{copy_cursor_line}") == before_text)
        end
        tmux("kill-window", "-t", pane)
    end
end)
if not ok then
    for message in tmux("show-messages"):gmatch("[^\n]+") do
        if message:find("tmux-agent-navigation:", 1, true) then
            io.stderr:write(message .. "\n")
        end
    end
end
vim.fn.delete(fixture, "rf")
assert(ok, err)
print(
    "tmux links: "
        .. #forms
        .. (thumbs and " thumbs copy/open" or (split and " gn split" or " gf"))
        .. "/editor/:q cases passed"
)
