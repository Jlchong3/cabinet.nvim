local drawer_api = require('drawer')

local M = {}

---@type integer
local buf = -1

---@type integer
local win = -1

---@type boolean
local in_drawer_view = false

---@type integer | nil
local current_drawer_index = nil

local ns = vim.api.nvim_create_namespace('drawer_icons')

---@param basedir string
---@param path string
---@return string
local function get_relative_path(basedir, path)
    local relpath = path:gsub('^' .. basedir .. '/?', '')
    return relpath
end

--- Refresh buffer with a list of drawers
local function show_drawers()
    in_drawer_view = false
    current_drawer_index = nil

    if not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1) -- clear old icons
    end

    local lines = {}
    local drawers = drawer_api.get_drawers()
    for i, d in ipairs(drawers) do
        table.insert(lines, d.name)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    for i, _ in ipairs(drawers) do
        vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, {
            virt_text = { {"󰪶 ", "DrawerTitle"} },
            virt_text_pos = 'inline',
        })
    end
end

--- Refresh buffer with files of the current drawer
local function show_files(drawer_index)
    in_drawer_view = true
    current_drawer_index = drawer_index
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

    local files = drawer_api.get_drawer_files(drawer_index)
    local lines = {}
    for _, f in ipairs(files) do
        local relpath = get_relative_path(vim.fn.getcwd(), f.path)
        table.insert(lines, relpath)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function update_drawers()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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
    local current_active = drawer_api.get_active_drawer_index()
    for i = #drawers, 1, -1 do
        drawer_api.remove_drawer(i)
    end

    for _, d in ipairs(new_list) do
        drawer_api.add_drawer(d.name)
        local added = drawer_api.get_drawers()[#drawer_api.get_drawers()]
        added.files = d.files
    end

    if current_active <= #new_list then drawer_api.open_drawer(current_active) end
end

local function update_files()
    local drawer_files = drawer_api.get_drawer_files(current_drawer_index)
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

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
    drawers[current_drawer_index].files = new_list
end

local function drawer_win(buffer)
    local width = math.floor(vim.o.columns * 0.4)
    local height = math.floor(vim.o.lines * 0.3)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local window = vim.api.nvim_open_win(buffer, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        title = { {'Drawers', 'DrawerTitle'} },
        style = 'minimal',
        border = 'single',
    })

    vim.api.nvim_set_hl(0, "DrawerTitle", { fg = "#BFDFFF", bold = true })
    vim.wo[window].number = true
    vim.bo[buffer].bufhidden = 'wipe'
    vim.bo[buffer].filetype = 'drawer'

    return window
end

--- Open the floating UI
M.open = function()

    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    end

    win = drawer_win(buf)

    -- Drawer selection keys
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if not in_drawer_view then
                update_drawers()
                show_files(cursor_row)
            else
                M.close()
                drawer_api.open_file(cursor_row, current_drawer_index)
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', '-', '', {
        callback = function ()
            if in_drawer_view then
                update_files()
                show_drawers()
            end
        end,
        noremap = true,
        silent = true,
    })


    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
        callback = function()
            M.close()
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_create_autocmd('InsertLeave', {
        buffer = buf,
        callback = function()
            if not in_drawer_view then
                update_drawers()
                show_drawers()
            else
                update_files()
                show_files(current_drawer_index)
            end
        end
    })


    show_drawers()
end

M.close = function ()
    if not in_drawer_view then
        update_drawers()
    else
        update_files()
    end

    vim.api.nvim_win_close(win, false)
end

M.open()

return M
