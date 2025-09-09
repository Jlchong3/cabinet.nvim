local cabinet = require('cabinet')

local M = {}

local buf = -1
local win = -1
local in_drawer_view = false
local current_drawer_index = nil

local saved_opts = nil

local function get_relative_path(basedir, path)
    local relpath = path:gsub('^' .. basedir .. '/?', '')
    return relpath
end

local function reset_buffer()
    if not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    end

    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'drawer'
end

local function buf_set_drawers()
    in_drawer_view = false
    current_drawer_index = nil

    reset_buffer()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, cabinet.get_drawer_order())
end

--- Refresh buffer with files of the current drawer
local function buf_set_files(drawer_index)
    in_drawer_view = true
    current_drawer_index = drawer_index

    reset_buffer()

    local files = assert(cabinet.get_drawer_files(drawer_index))
    local lines = {}
    for _, f in ipairs(files) do
        local relpath = get_relative_path(vim.fn.getcwd(), f.path)
        table.insert(lines, relpath)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function update_drawers()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local drawers = cabinet.get_drawers()
    local drawer_order = cabinet.get_drawer_order()

    local seen = {}

    for i, name in ipairs(lines) do
        name = vim.trim(name)
        if name ~= "" then
            seen[name] = true

            if drawers[name] then
                drawer_order[i] = name
            else
                cabinet.add_drawer(name)
            end
        end
    end

    for drawer, _ in pairs(drawers) do
        if not seen[drawer] then
            cabinet.remove_drawer_by_name(drawer)
        end
    end

end

local function update_files()
    local drawer_files = assert(cabinet.get_drawer_files(current_drawer_index))
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
                    cursor_pos = {1, 0},
                })
            end
        end
    end

    local drawer_name = cabinet.get_drawer_order()[current_drawer_index]
    local drawers = cabinet.get_drawers()
    drawers[drawer_name] = new_list
end

local function drawer_win_config(opts)
    local width = math.floor(vim.o.columns * 0.4)
    local height = math.floor(vim.o.lines * 0.3)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    local window_config = vim.tbl_deep_extend('force', {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        title = { {'Drawers', 'DrawerTitle'} },
        style = 'minimal',
        border = 'single',
    }, opts)

    return window_config
end

--- Open the floating UI
M.open = function(opts)
    saved_opts = opts or {}

    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        return
    end

    buf_set_drawers()

    win = vim.api.nvim_open_win(buf, true, drawer_win_config(saved_opts))

    vim.api.nvim_set_hl(0, "DrawerTitle", { fg = "#BFDFFF", bold = true })
    vim.wo[win].number = true

    -- Drawer selection keys
    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if not in_drawer_view then
                update_drawers()
                buf_set_files(cursor_row)
            else
                M.close()
                cabinet.open_file(current_drawer_index, cursor_row)
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', '-', '', {
        callback = function ()
            if in_drawer_view then
                update_files()
                buf_set_drawers()
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
            local cursor_pos = vim.api.nvim_win_get_cursor(win)
            if not in_drawer_view then
                update_drawers()
                buf_set_drawers()
            else
                update_files()
                buf_set_files(current_drawer_index)
            end
            vim.api.nvim_win_set_cursor(win, cursor_pos)
        end
    })

    vim.api.nvim_create_autocmd('VimResized', {
        buffer = buf,
        callback = function()
            vim.api.nvim_win_set_config(win, drawer_win_config(saved_opts))
            vim.wo[win].number = true
        end
    })
end


M.close = function ()
    if not in_drawer_view then
        update_drawers()
    else
        update_files()
    end

    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, false)
    end

end

M.open()

return M
