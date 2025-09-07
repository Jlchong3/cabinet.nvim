local storage = require('storage')
local Cabinet = require('cabinet')

local drawer = Cabinet.new(storage.load() or {})

local M = {}

---@param opts table
---@return table
M.setup = function (opts)
    vim.api.nvim_create_augroup('drawer', {})

    vim.api.nvim_create_autocmd('VimLeave', {
        group = 'drawer',
        callback = function ()
            storage.save(drawer:get_drawers())
        end
    })

    vim.api.nvim_create_autocmd('BufLeave', {
        group = 'drawer',
        callback = function ()
            if drawer:is_empty() then return end
            if #drawer:get_drawer_files(drawer.current_drawer) == 0 then return end

            local filepath = vim.api.nvim_buf_get_name(0)
            if filepath == '' then return end

            for _, file_info in ipairs(drawer:get_drawer_files(drawer.current_drawer)) do
                if file_info.path == filepath then
                    file_info.cursor_pos = vim.api.nvim_win_get_cursor(0)
                    break
                end
            end
        end
    })

    return M
end

---@param name string?
M.add_drawer = function (name)
    local drawer_name = name or vim.fn.input('Drawer name: ')
    if drawer_name == nil then return end
    if drawer_name == '' then drawer_name = 'default' end
    drawer:add_drawer(drawer_name)

    if not drawer.current_drawer then drawer:open_drawer(1) end
end

---@param index integer
M.open_drawer = function (index)
    drawer:open_drawer(index)
end

---@param index integer
M.remove_drawer = function (index)
    drawer:remove_drawer(index)
end

---@param drawer_index integer?
M.add_file = function (drawer_index)
    drawer_index = drawer_index or drawer.current_drawer

    if not drawer_index then M.add_drawer() end
    if drawer_index > #drawer:get_drawers() then return end

    drawer:add_file(assert(drawer_index))
end

---@param index integer
---@param drawer_index integer?
M.open_file = function (index, drawer_index)
    drawer_index = drawer_index or drawer.current_drawer
    if not drawer_index or drawer_index > #drawer:get_drawers() then return end

    drawer:open_file(index, drawer_index)
end

---@param index integer
---@param drawer_index integer?
M.remove_file = function (index, drawer_index)
    drawer_index = drawer_index or drawer.current_drawer
    if not drawer_index or drawer_index > #drawer:get_drawers() then return end

    drawer:remove_file(index, drawer_index)
end

---@return DrawerInfo[]
M.get_drawers = function ()
    return drawer:get_drawers()
end

---@return integer
M.get_active_drawer_index = function ()
    return drawer.current_drawer
end

---@return FileInfo[]
M.get_drawer_files = function (index)
    return drawer:get_drawer_files(index)
end

---@return any
M.ui = function (ui_module)
    return ui_module or require('ui')
end

M.open = function ()
    M.ui().open()
end

M.close = function ()
    M.ui().close()
end

return M
