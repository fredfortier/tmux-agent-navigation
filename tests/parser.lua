local root = assert(vim.env.TMUX_AGENT_ROOT)
local nav = dofile(root .. "/lua/resolve.lua")
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. "/nested/src", "p")
vim.fn.mkdir(fixture .. "/.git", "p")
vim.fn.writefile({ "gitdir: ../git-metadata" }, fixture .. "/nested/.git")
vim.fn.writefile({ "one", "two", "three" }, fixture .. "/nested/src/example.lua")
local file = fixture .. "/nested/src/example.lua"
local cases = {
    { "  src/example.lua:2:3", 8, fixture .. "/nested", file, 2, 3 },
    { "[read this](" .. file .. ":2)", 3, "/tmp", file, 2, 1 },
    { "`" .. file .. "#L3-L8`", 4, "/tmp", file, 3, 1 },
    { file .. ":2-10,", 4, "/tmp", file, 2, 1 },
    { "界 src/example.lua:2", 8, fixture .. "/nested", file, 2, 1 },
    { "src/example.lua:2", 4, fixture .. "/nested/src", file, 2, 1 },
    { "Browse nested/src/.", 12, fixture, fixture .. "/nested/src", 1, 1 },
    { "[directory](" .. fixture .. "/nested/)", 3, "/tmp", fixture .. "/nested", 1, 1 },
    {
        "Home is ~/.",
        9,
        "/tmp",
        vim.env.HOME,
        1,
        1,
    },
}
local unusual = fixture .. "/odd ' $(touch PWNED).txt"
vim.fn.writefile({ "data" }, unusual)
cases[#cases + 1] = { "`" .. unusual .. ":2`", 5, "/tmp", unusual, 2, 1 }
local special = fixture .. "/nested/src/a (b).md"
vim.fn.writefile({ "one", "two", "three" }, special)
local balanced = fixture .. "/nested/src/a(b(c)).md"
vim.fn.writefile({ "one", "two", "three" }, balanced)
local unicode = fixture .. "/nested/src/界.md"
vim.fn.writefile({ "one", "two", "three" }, unicode)
local encoded = special:gsub(" ", "%%20"):gsub("%(", "%%28"):gsub("%)", "%%29")
local forms = {
    { file .. "#L2", file },
    { file .. "#L2-L3", file },
    { file .. "#L2-3", file },
    { "[source](" .. file .. "#L2)", file },
    { "[a [nested] label](" .. file .. '#L2 "title")', file },
    { "[source](" .. file .. "#L2 'title')", file },
    { "[source](" .. file .. "#L2 (title))", file },
    { "[source](<" .. special .. '#L2> "title")', special },
    { "[source](" .. encoded .. "#L2)", special },
    { "[source](" .. balanced .. "#L2)", balanced },
    { "[界 source](" .. unicode .. "#L2)", unicode },
    { "[source](" .. special:gsub(" ", "\\ "):gsub("%(", "\\("):gsub("%)", "\\)") .. "#L2)", special },
    { "[source](" .. fixture .. "/nested/src/example.lua#L2)", file },
    { "<" .. encoded .. "#L2>", special },
    { '"' .. special .. '#L2"', special },
    { "`" .. special .. "#L2`", special },
    { "(" .. file .. "#L2).", file },
    { file .. "#L2!", file },
    { file .. "#L2?", file },
    { file .. "#L2,", file },
    { file .. "#L2;", file },
    { "'" .. file .. "#L2'", file },
    { "[source](src/example.lua#L2)", file, fixture .. "/nested" },
    { "[source](./src/example.lua#L2)", file, fixture .. "/nested" },
    { "[source](../src/example.lua#L2)", file, fixture .. "/nested/src" },
    { "[source](" .. file .. ":2:1)", file },
    { "[source](" .. file .. ":2-3)", file },
    { "[source](" .. file .. ":2)", file },
    { "example.lua (" .. file .. "#L2)", file },
}
for _, form in ipairs(forms) do
    -- Every display cell in the entire reference must select the same target,
    -- including the label, destination, title, and punctuation.
    for x = 0, vim.fn.strdisplaywidth(form[1]) - 1 do
        cases[#cases + 1] = { form[1], x, form[3] or "/tmp", form[2], 2, 1 }
    end
end
local ok, err = pcall(function()
    for _, case in ipairs(cases) do
        local success, path, line, col = pcall(nav.resolve, case[1], case[2], case[3])
        assert(success, vim.inspect(case) .. "\n" .. tostring(path))
        assert(path == case[4] and line == case[5] and col == case[6], vim.inspect(case))
    end
    assert(not pcall(nav.resolve, "missing.lua:3", 3, fixture))
    for _, suffix in ipairs({ "#L2garbage", "#L2-Loops", "#heading", "#L2-L3tail" }) do
        assert(not pcall(nav.resolve, file .. suffix, 4, "/tmp"), "Invalid anchor accepted: " .. suffix)
    end
    for _, spelling in ipairs({ "trailing.", "literal%20name.md", "literal#L2", "(wrapped).md" }) do
        local literal = fixture .. "/" .. spelling
        vim.fn.writefile({ "literal" }, literal)
        assert(nav.resolve(literal, 0, "/tmp") == literal, "Literal filename changed: " .. spelling)
    end
    assert(not pcall(nav.resolve, "https://example.com" .. file .. "#L2", 4, "/tmp"))
    assert(not pcall(nav.resolve, "[remote](https://example.com" .. file .. "#L2)", 3, "/tmp"))
    assert(not pcall(nav.resolve, "unrelated " .. file .. "#L2", 1, "/tmp"))
    assert(vim.fs.root(file, ".git") == fixture .. "/nested", "nearest .git file wins")
end)
vim.fn.delete(fixture, "rf")
assert(ok, err)
print(
    "terminal navigation: "
        .. #cases
        .. " cursor cases, invalid anchors, missing paths, nearest worktree root passed"
)
