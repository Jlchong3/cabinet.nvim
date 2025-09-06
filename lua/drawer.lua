local storage = require('storage')
local Cabinet = require('cabinet')

local drawer = Cabinet.new(storage.load() or {})

local M = {}

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
            if #drawer:get_drawer_files() == 0 then return end

            local filepath = vim.api.nvim_buf_get_name(0)
            if filepath == '' then return end

            for _, file_info in ipairs(drawer:get_drawer_files()) do
                if file_info.path == filepath then
                    file_info.cursor_pos = vim.api.nvim_win_get_cursor(0)
                    break
                end
            end
        end
    })
    return M
end

M.add_drawer = function (name)
    local drawer_name = name or vim.fn.input('Drawer name: ')
    if drawer_name == nil then return end
    if drawer_name == '' then drawer_name = 'default' end
    drawer:add_drawer(drawer_name)

    if not drawer.current_drawer then drawer:open_drawer(1) end
end

M.open_drawer = function (index)
    drawer:open_drawer(index)
end

M.remove_drawer = function (index)
    drawer:remove_drawer(index)
end

M.add_file = function ()
    if not drawer.current_drawer then M.add_drawer() end
    drawer:add_file()
end

M.open_file = function (index)
    drawer:open_file(index)
end

M.remove_file = function (index)
    drawer:remove_file(index)
end

M.get_drawers = function ()
    return drawer:get_drawers()
end

M.get_active_drawer_index = function ()
    return drawer.current_drawer
end

M.get_drawer_files = function (index)
    return drawer:get_drawer_files(index)
end

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
