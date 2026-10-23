-- Loaded only by child editors. Keep ordinary user plugins and save semantics.
local data = vim.json.decode(vim.env.TMUX_NAV_PAYLOAD)
vim.g.terminal_navigation = data
vim.o.swapfile = false
function _G.TerminalNavOpen(file, requested_line, col)
    local is_directory = vim.fn.isdirectory(file) == 1
    local directory = is_directory and file or vim.fs.dirname(file)
    local root = vim.fs.root(directory, ".git") or directory
    vim.cmd.cd(root)
    if is_directory then
        -- Some file-browser plugins disable netrw. Enable the built-in
        -- directory buffer only in this child, so normal :q returns to the parent.
        vim.g.loaded_netrwPlugin = nil
        vim.cmd.runtime("plugin/netrwPlugin.vim")
        vim.cmd.Explore(vim.fn.fnameescape(file))
        assert(vim.bo.filetype == "netrw", "Directory browser did not open")
        return true
    end
    vim.cmd.edit(vim.fn.fnameescape(file))
    local count = vim.api.nvim_buf_line_count(0)
    local line = math.min(requested_line, count)
    local content = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
    vim.api.nvim_win_set_cursor(0, { line, math.min(col - 1, #content) })
    vim.cmd.normal({ "zvzz", bang = true })
    return true
end
TerminalNavOpen(data.file, data.line, data.col)

local function configure_quit()
    -- Ordinary sessions abbreviate :q to a buffer-closing command. A child
    -- needs the native :q behavior so it returns to the originating terminal.
    vim.cmd("silent! cunabbrev q")
end
configure_quit()
vim.api.nvim_create_autocmd("User", { pattern = "VeryLazy", once = true, callback = configure_quit })
