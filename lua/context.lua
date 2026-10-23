-- Discover a foreground `devcontainer exec` without changing its invocation.
local M = {}
function M.foreground(pane_pid)
    local function run(args)
        local result = vim.system(args, { text = true }):wait()
        assert(result.code == 0, "Cannot inspect the foreground container")
        return vim.trim(result.stdout)
    end
    local processes = {}
    for pid, parent, group, foreground in
        run({ "ps", "-e", "-o", "pid=,ppid=,pgid=,tpgid=" }):gmatch("(%d+)%s+(%d+)%s+(%-?%d+)%s+(%-?%d+)")
    do
        processes[tonumber(pid)] =
            { parent = tonumber(parent), group = tonumber(group), foreground = tonumber(foreground) }
    end
    local function descendant(pid, ancestor)
        local seen = {}
        while processes[pid] and not seen[pid] do
            if pid == ancestor then
                return true
            end
            seen[pid] = true
            pid = processes[pid].parent
        end
        return false
    end
    local function arguments(pid)
        local file = io.open("/proc/" .. pid .. "/cmdline", "rb")
        if not file then
            return {}
        end
        local content = file:read("*a")
        file:close()
        return vim.split(content, "\0", { plain = true, trimempty = true })
    end
    local function executable(path)
        if not path then
            return nil
        end
        return vim.uv.fs_realpath(path:find("/", 1, true) and path or vim.fn.exepath(path))
    end
    local cli, docker = executable("devcontainer"), executable("docker")
    if not cli or not docker then
        return nil
    end
    local execs = {}
    for pid, process in pairs(processes) do
        if process.group == process.foreground and descendant(pid, pane_pid) then
            local args = arguments(pid)
            local script = executable(args[1]) == cli and 1 or (executable(args[2]) == cli and 2 or nil)
            if script and args[script + 1] == "exec" then
                execs[#execs + 1] = pid
            end
        end
    end
    if #execs == 0 then
        return nil
    end
    local values = {
        ["-e"] = true,
        ["--env"] = true,
        ["--env-file"] = true,
        ["-u"] = true,
        ["--user"] = true,
        ["-w"] = true,
        ["--workdir"] = true,
        ["--detach-keys"] = true,
    }
    local targets = {}
    for pid, process in pairs(processes) do
        if process.group == process.foreground then
            for _, exec_pid in ipairs(execs) do
                if descendant(pid, exec_pid) then
                    -- Docker's environment arguments can contain secrets.
                    -- Skip their values; never log or return command lines.
                    local args = arguments(pid)
                    if executable(args[1]) == docker and args[2] == "exec" then
                        local i = 3
                        while args[i] and args[i]:sub(1, 1) == "-" do
                            i = i + (values[args[i]] and 2 or 1)
                        end
                        local target = args[i]
                        if target and #target >= 12 and #target <= 64 and target:match("^%x+$") then
                            targets[target] = true
                        end
                    end
                end
            end
        end
    end
    local ids = vim.tbl_keys(targets)
    assert(#ids == 1, "Cannot identify one foreground devcontainer for this pane")
    local template = '{"id":{{json .Id}},"workspace":{{json (index .Config.Labels "devcontainer.local_folder")}},'
        .. '"running":{{json .State.Running}}}'
    local actual = vim.json.decode(run({ docker, "inspect", "--format", template, ids[1] }))
    assert(actual.running, "The foreground container is not running")
    actual.workspace = actual.workspace and vim.uv.fs_realpath(actual.workspace)
    assert(actual.workspace, "The foreground carrier has no accessible workspace label")
    return { workspace = actual.workspace, container = actual.id }
end

-- Explicit checkout routing is separate from foreground process inspection.
-- Multiple carriers are an error; never choose whichever Docker lists first.
function M.workspace(workspace)
    local function run(args)
        local result = vim.system(args, { text = true }):wait()
        assert(result.code == 0, "Cannot inspect the workspace container")
        return vim.trim(result.stdout)
    end
    local ids = vim.split(
        run({
            "docker",
            "ps",
            "--quiet",
            "--no-trunc",
            "--filter",
            "label=devcontainer.local_folder=" .. workspace,
        }),
        "\n",
        { trimempty = true }
    )
    assert(#ids == 1, "Expected one running devcontainer for this checkout")
    local template =
        '{"id":{{json .Id}},"workspace":{{json (index .Config.Labels "devcontainer.local_folder")}},"running":{{json .State.Running}}}'
    local actual = vim.json.decode(run({ "docker", "inspect", "--format", template, ids[1] }))
    assert(
        actual.running and actual.workspace and vim.uv.fs_realpath(actual.workspace) == workspace,
        "The running container does not match this checkout"
    )
    return { workspace = workspace, container = actual.id }
end
return M
