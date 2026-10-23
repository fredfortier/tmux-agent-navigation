--- Resolve visible local references without executing terminal text.
local M = {}
-- All terminal text remains data; no captured text is evaluated by a shell.
--- Return absolute file, one-based line, and byte column for a display-cell cursor.
--- Existing literal names take priority over prose and location syntax.
function M.resolve(text, x, cwd)
    local candidates = {}
    local function add(first, last, ref)
        local left = vim.fn.strdisplaywidth(text:sub(1, first - 1))
        local right = vim.fn.strdisplaywidth(text:sub(1, last))
        if x >= left and x < right then
            candidates[#candidates + 1] = ref
        end
    end
    -- Agent transcripts may print filename labels followed by a parenthesized path.
    for first, label, ref, last in text:gmatch("()([.%w_@~-]+)%s+%(([^%s()]+)%)()") do
        local path = ref:gsub("#L%d+.*$", ""):gsub(":%d+.*$", "")
        if label == vim.fs.basename(path) then
            add(first, last - 1, ref)
        end
    end
    -- Scan balanced Markdown links rather than stopping at the first ')'.
    -- Escapes and angle destinations allow spaces and parentheses in paths.
    for first, opening in text:gmatch("()%b[]()%(") do
        local i, depth, angle, quote = opening + 1, 1, false, nil
        while i <= #text do
            local c = text:sub(i, i)
            if c == "\\" then
                i = i + 1
            elseif quote then
                if c == quote then
                    quote = nil
                end
            elseif angle then
                if c == ">" then
                    angle = false
                end
            elseif c == "<" then
                angle = true
            elseif (c == '"' or c == "'") and text:sub(i - 1, i - 1):match("%s") then
                quote = c
            elseif c == "(" then
                depth = depth + 1
            elseif c == ")" then
                depth = depth - 1
                if depth == 0 then
                    local destination = vim.trim(text:sub(opening + 1, i - 1))
                    local ref
                    if destination:sub(1, 1) == "<" then
                        ref = destination:match("^<(.-)>")
                    else
                        local j = 1
                        while j <= #destination do
                            local d = destination:sub(j, j)
                            if d == "\\" then
                                j = j + 1
                            elseif d:match("%s") then
                                break
                            end
                            j = j + 1
                        end
                        ref = destination:sub(1, j - 1)
                    end
                    if ref then
                        add(first, i, ref)
                    end
                    break
                end
            end
            i = i + 1
        end
    end
    for _, quote in ipairs({ "`", '"', "'" }) do
        local pattern = "()" .. quote .. "([^" .. quote .. "]+)" .. quote .. "()"
        for first, ref, last in text:gmatch(pattern) do
            add(first, last - 1, ref)
        end
    end
    for first, ref, last in text:gmatch("()<([^<>]+)>()") do
        add(first, last - 1, ref)
    end
    for first, ref, last in text:gmatch("()(%S+)()") do
        add(first, last - 1, ref)
    end
    local function resolve(ref, literal)
        local path, line, col = ref:match("^(.-):(%d+):(%d+)$")
        if not path then
            path, line = ref:match("^(.-):(%d+)%-%d+$")
        end
        if not path then
            path, line = ref:match("^(.-):(%d+)$")
        end
        if not path then
            path, line = ref:match("^(.-)#L(%d+)$")
        end
        if not path then
            path, line = ref:match("^(.-)#L(%d+)%-L%d+$")
        end
        if not path then
            path, line = ref:match("^(.-)#L(%d+)%-%d+$")
        end
        if literal then
            path, line, col = ref, nil, nil
        end
        path = path or ref
        if path:sub(1, 2) == "~/" then
            path = vim.env.HOME .. path:sub(2)
        end
        if not path:match("^%a[%w+.-]*://") then
            local choices = { path:sub(1, 1) == "/" and path or (cwd .. "/" .. path) }
            if path:sub(1, 1) ~= "/" then
                local root = vim.fs.root(cwd, ".git")
                if root then
                    choices[#choices + 1] = root .. "/" .. path
                end
            end
            for _, file in ipairs(choices) do
                local stat = vim.uv.fs_stat(file)
                if stat and (stat.type == "file" or stat.type == "directory") then
                    return vim.fs.normalize(file),
                        math.max(1, tonumber(line) or 1),
                        math.max(1, tonumber(col) or 1)
                end
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        local variants = { candidate }
        -- Preserve literal filenames first; decode only as a fallback.
        local decoded = candidate:gsub("\\([%p%s])", "%1"):gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        if decoded ~= candidate then
            variants[#variants + 1] = decoded
        end
        for _, original in ipairs(variants) do
            local ref = original
            while ref ~= "" do
                local file, line, col = resolve(ref, true)
                if not file then
                    file, line, col = resolve(ref)
                end
                if file then
                    return file, line, col
                end
                -- Remove prose wrappers only after trying the exact spelling.
                if ref:match("^[%[%(<'\"`]") then
                    ref = ref:sub(2)
                elseif ref:match("[%]%)>,;:'\"`%.!?]$") then
                    ref = ref:sub(1, -2)
                else
                    break
                end
            end
        end
    end
    error("No existing file or directory under the copy-mode cursor")
end

return M
