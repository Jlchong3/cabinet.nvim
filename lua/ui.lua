local drawer_api = require("drawer")

local M = {}

---@type integer
local buf = nil
---@type integer
local win = nil
---@type boolean
local in_drawer_view = false
---@type integer?
local current_drawer_index = nil

--- Refresh buffer with a list of drawers
local function show_drawers()
    in_drawer_view = false
    current_drawer_index = nil

    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    end

    local lines = {}
    local drawers = drawer_api.get_drawers()
    for i, d in ipairs(drawers) do
        table.insert(lines, string.format("%d: %s", i, d.name))
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

--- Refresh buffer with files of the current drawer
local function show_files(drawer_index)
    in_drawer_view = true
    current_drawer_index = drawer_index

    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local files = drawer_api.get_drawer_files(drawer_index)
    local lines = {}
    for _, f in ipairs(files) do
        table.insert(lines, f.path:gsub("^" .. vim.fn.getcwd() .. "/?", ""))
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

--- Open the floating UI
M.open = function()
    local width = math.floor(vim.o.columns * 0.5)
    local height = math.floor(vim.o.lines * 0.5)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    end

    win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'drawer'

    -- Drawer selection keys
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if not in_drawer_view then
                show_files(cursor_row)
            else
                drawer_api.open_file(cursor_row)
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "-", "", {
        callback = function()
            if in_drawer_view then
                show_drawers()
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "a", "", {
        callback = function()
            if in_drawer_view then
                drawer_api.add_file()
                show_files(current_drawer_index)
            else
                drawer_api.add_drawer()
                show_drawers()
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, "n", "dd", "", {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if in_drawer_view then
                drawer_api.remove_file(cursor_row)
                show_files(current_drawer_index)
            else
                drawer_api.remove_drawer(cursor_row)
                show_drawers()
            end
        end,
        noremap = true,
        silent = true,
    })

    show_drawers()
end

return M
