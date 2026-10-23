-- Exercise the public custom-editor argv boundary through actual pane processes.
local server = assert(arg[1])
assert(server:match("^nav%-"))
local root = assert(vim.env.TMUX_AGENT_ROOT)
local function run(args)
    local result = vim.system(args, { text = true }):wait()
    assert(result.code == 0, result.stderr)
    return vim.trim(result.stdout)
end
local function tmux(...)
    return run({ "tmux", "-L", server, ... })
end
local function fmt(pane, value)
    return tmux("display-message", "-p", "-t", pane, value)
end
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
local file = fixture .. '/odd " $(touch PWNED).txt'
local adapter = fixture .. "/custom editor"
local log = fixture .. "/argv"
vim.fn.writefile({ "one", "two", "three" }, file)
vim.fn.writefile(
    { "#!/bin/bash", 'printf "%s\\n" "$@" > ' .. vim.fn.shellescape(log), "read -r answer" },
    adapter
)
assert(vim.fn.setfperm(adapter, "rwx------") == 1)
local pane
local ok, err = pcall(function()
    local original_status = tmux("show-option", "-gqv", "status-left")
    local original_mode = tmux("show-option", "-gqv", "mode-keys")
    local socket = tmux("display-message", "-p", "#{socket_path}")
    local setup = vim.system(
        { "bash", root .. "/agent-navigation.tmux" },
        { env = { TMUX = socket .. ",0,0" }, text = true }
    ):wait()
    assert(setup.code == 0, setup.stderr)
    assert(tmux("show-option", "-gqv", "status-left") == original_status)
    assert(tmux("show-option", "-gqv", "mode-keys") == original_mode)
    tmux("set-option", "-g", "@agent-editor", adapter)
    pane = tmux("new-window", "-P", "-F", "#{pane_id}", "-c", fixture, "bash", "--noprofile", "--norc")
    local command = { root .. "/bin/agent-navigation", "open", pane }
    -- Use pick directly with the test socket environment: same launcher boundary,
    -- without depending on shell prompt positioning for a hostile-looking filename.
    local pick = fixture .. "/pick.lua"
    vim.fn.writefile({
        "local args = arg; arg = nil",
        'local nav = dofile(vim.env.TMUX_AGENT_ROOT .. "/lua/navigation.lua")',
        'nav.pick(args[1], "`" .. args[2] .. ":2:3`", 2, args[3])',
    }, pick)
    command = { "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", pick, pane, file, fixture }
    local result = vim.system(command, { env = { TMUX = socket .. ",0,0" }, text = true }):wait()
    assert(result.code == 0, result.stderr)
    assert(vim.wait(5000, function()
        return vim.fn.filereadable(log) == 1
    end, 25))
    assert(vim.deep_equal(vim.fn.readfile(log), { file, "2", "3" }), "Custom adapter argv changed")
    assert(vim.fn.filereadable(fixture .. "/PWNED") == 0, "Terminal text was executed")
    local child = fmt(pane, "#{@nav_child}")
    assert(child ~= "")
    tmux("send-keys", "-t", child, "Enter")
    assert(vim.wait(5000, function()
        return fmt(pane, "#{@nav_child}") == ""
    end, 25))
    assert(fmt(pane, "#{pane_active}") == "1")
    assert(fmt(pane, "#{window_zoomed_flag}") == "0")
end)
tmux("set-option", "-gu", "@agent-editor")
if pane then
    tmux("kill-window", "-t", pane)
end
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("custom adapter: literal argv, safe path, return, idempotent setup passed")
