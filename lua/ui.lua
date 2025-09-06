local drawer_api = require("drawer")

local M = {}

local state = {
    buf = nil,
    win = nil,
    in_drawer_view = false,
    current_drawer_index = nil,
}

---@param basedir string
---@param path string
---@return string
local function get_relative_path(basedir, path)
    local relpath = path:gsub('^' .. basedir .. '/?', '')
    return relpath
end

--- Refresh buffer with a list of drawers
local function show_drawers()
    state.in_drawer_view = false
    state.current_drawer_index = nil

    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, true)
    else
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
    end

    local lines = {}
    local drawers = drawer_api.get_drawers()
    for _, d in ipairs(drawers) do
        table.insert(lines, d.name)
    end

    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
end

--- Refresh buffer with files of the current drawer
local function show_files(drawer_index)
    state.in_drawer_view = true
    state.current_drawer_index = drawer_index

    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end

    local files = drawer_api.get_drawer_files(drawer_index)
    local lines = {}
    for _, f in ipairs(files) do
        local relpath = get_relative_path(vim.fn.getcwd(), f.path)
        table.insert(lines, relpath)
    end

    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
end

local function update_drawers()
    local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local old_drawers = drawer_api.get_drawers()

    local old_map = {}
    for _, d in ipairs(old_drawers) do
        old_map[d.name] = d
    end

    -- Build the new list in buffer order
    local new_list = {}
    for _, name in ipairs(lines) do
        name = vim.trim(name)
        if name ~= "" then
            if old_map[name] then
                table.insert(new_list, old_map[name])
                old_map[name] = nil
            else
                table.insert(new_list, {
                    name = name,
                    files = {},
                })
            end
        end
    end

    local drawers = drawer_api.get_drawers()
    for i = #drawers, 1, -1 do
        drawer_api.remove_drawer(i)
    end

    for _, d in ipairs(new_list) do
        drawer_api.add_drawer(d.name)
        local added = drawer_api.get_drawers()[#drawer_api.get_drawers()]
        added.files = d.files
    end
end

local function update_files()
    local drawer_files = drawer_api.get_drawer_files(state.current_drawer_index)
    local buf_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)

    local old_files_map = {}
    for _, file_info in ipairs(drawer_files) do
        old_files_map[file_info.path] = file_info
    end

    local new_list = {}

    for _, line in ipairs(buf_lines) do
        local relpath = vim.trim(line)
        if relpath ~= "" then
            local fullpath = vim.fn.getcwd() .. "/" .. relpath

            local old_file_info = old_files_map[fullpath]
            if old_file_info then
                table.insert(new_list, old_file_info)
            else
                table.insert(new_list, {
                    path = fullpath,
                    cursor_pos = {1, 0}, -- default position
                })
            end
        end
    end

    local drawers = drawer_api.get_drawers()
    drawers[state.current_drawer_index].files = new_list
end

--- Open the floating UI
M.open = function()

    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
        return
    end

    local width = math.floor(vim.o.columns * 0.5)
    local height = math.floor(vim.o.lines * 0.5)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, true)
    end

    state.win = vim.api.nvim_open_win(state.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    vim.bo[state.buf].bufhidden = 'wipe'
    vim.bo[state.buf].filetype = 'drawer'

    -- Drawer selection keys
    vim.api.nvim_buf_set_keymap(state.buf, 'n', '<CR>', '', {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if not state.in_drawer_view then
                update_drawers()
                show_files(cursor_row)
            else
                M.close()
                drawer_api.open_file(cursor_row)
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(state.buf, 'n', '-', '', {
        callback = function ()
            update_files()
            show_drawers()
        end,
        noremap = true,
        silent = true,
    })


    vim.api.nvim_buf_set_keymap(state.buf, 'n', 'q', '', {
        callback = function()
            M.close()
        end,
        noremap = true,
        silent = true,
    })


    show_drawers()
end

M.close = function ()
    if not state.in_drawer_view then
        update_drawers()
    else
        update_files()
    end
    vim.api.nvim_win_close(state.win, false)
end

return M
