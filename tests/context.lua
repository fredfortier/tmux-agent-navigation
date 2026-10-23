-- Deterministic selection proof at the Docker CLI boundary; not live acceptance.
local context = dofile(assert(vim.env.TMUX_AGENT_ROOT) .. "/lua/context.lua")
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
local original_system = vim.system
local identity = string.rep("a", 64)
local records, inspected = {}, 0
vim.system = function(args)
    assert(args[1] == "docker", "Unexpected external command")
    local output
    if args[2] == "ps" then
        output = table.remove(records, 1)
    else
        assert(args[2] == "inspect")
        inspected = inspected + 1
        output = table.remove(records, 1)
    end
    return {
        wait = function()
            return { code = 0, stdout = assert(output) }
        end,
    }
end
local ok, err = pcall(function()
    records = { identity, vim.json.encode({ id = identity, workspace = fixture, running = true }) }
    assert(vim.deep_equal(context.workspace(fixture), { workspace = fixture, container = identity }))
    for _, ids in ipairs({ "", identity .. "\n" .. string.rep("b", 64) }) do
        records, inspected = { ids }, 0
        assert(not pcall(context.workspace, fixture), "Ambiguous carrier was selected")
        assert(inspected == 0, "An ambiguous carrier was inspected")
    end
    for _, record in ipairs({
        { id = identity, workspace = fixture, running = false },
        { id = identity, workspace = "/not-the-checkout", running = true },
    }) do
        records = { identity, vim.json.encode(record) }
        assert(not pcall(context.workspace, fixture), "Wrong carrier was selected")
    end
end)
vim.system = original_system
vim.fn.delete(fixture, "rf")
assert(ok, err)
print("container selection: exact workspace, absent/ambiguous/stopped targets passed")
