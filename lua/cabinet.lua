local storage = require('storage')

local load_cabinet = function()
    return storage.load() or { current_drawer = nil, drawers = {}, drawer_order = {} }
end

local drawer_autocmds = function ()
    vim.api.nvim_create_augroup('drawer', { clear = true })
    vim.api.nvim_create_autocmd('VimLeave', {
        group = 'drawer',
        callback = function ()
        end
    })

    vim.api.nvim_create_autocmd('BufLeave', {
        group = 'drawer',
        callback = function ()
        end
    })
end

local cabinet = load_cabinet()

local function get_drawer_pos(drawer)
    for i, drawer_key in ipairs(cabinet.drawer_order) do
        if drawer_key == drawer then
            return i
        end
    end
end

local M = {}

M.setup = function (opts)
    drawer_autocmds()

    return M
end

M.get_current_drawer = function ()
    return cabinet.current_drawer
end

M.add_drawer = function(drawer)
    cabinet.drawers[drawer] = { }
    table.insert(cabinet.drawer_order, drawer)
end

M.drawer_exist = function(drawer)
    return cabinet.drawers[drawer]
end

M.remove_drawer = function(drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    local drawer = cabinet.drawer_order[drawer_pos]
    table.remove(cabinet.drawer_order, drawer_pos)

    cabinet.drawers[drawer] = nil

    if #cabinet.drawer_order == 0 then
        cabinet.current_drawer = nil
    elseif cabinet.current_drawer and cabinet.current_drawer >= drawer_pos then
        cabinet.current_drawer = math.min(cabinet.current_drawer, #cabinet.drawer_order)
    end
end

M.remove_drawer_by_name = function(drawer)
    if not cabinet.drawers[drawer] then return end
    cabinet.drawers[drawer] = nil
    local drawer_pos = get_drawer_pos(drawer)
    table.remove(cabinet.drawer_order, drawer_pos)

    if #cabinet.drawer_order == 0 then
        cabinet.current_drawer = nil
    elseif cabinet.current_drawer and cabinet.current_drawer >= drawer_pos then
        cabinet.current_drawer = math.min(cabinet.current_drawer, #cabinet.drawer_order)
    end
end

M.open_drawer_by_name = function(drawer)
    if not cabinet.drawers[drawer] then return end
    cabinet.current_drawer = get_drawer_pos(drawer)
end

M.open_drawer = function(drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    cabinet.current_drawer = drawer_pos
end

M.rename_drawer_by_name = function(drawer, new_name)
    if not cabinet.drawers[drawer] then return end
    if cabinet.drawers[new_name] then return end

    cabinet.drawer_order[get_drawer_pos(drawer)] = new_name

    local drawer_content = cabinet.drawers[drawer]
    cabinet.drawers[drawer] = nil
    cabinet.drawers[new_name] = drawer_content
end

M.rename_drawer = function(drawer_pos, new_name)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    if cabinet.drawers[new_name] then return end

    local drawer = cabinet.drawer_order[drawer_pos]
    local drawer_content = cabinet.drawers[drawer]

    cabinet.drawers[drawer] = nil
    cabinet.drawers[new_name] = drawer_content
    cabinet.drawer_order[drawer_pos] = new_name
end

M.get_drawers = function()
    return cabinet.drawers
end

M.get_drawer_order = function()
    return cabinet.drawer_order
end

M.get_drawer_files_by_name = function(drawer)
    return cabinet.drawers[drawer]
end

M.get_drawer_files = function(drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end

    local drawer = cabinet.drawer_order[drawer_pos]
    return cabinet.drawers[drawer]
end

M.add_file = function(drawer_pos)
    drawer_pos = drawer_pos or cabinet.current_drawer
    if not drawer_pos then return end
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end

    local drawer = cabinet.drawer_order[drawer_pos]

    table.insert(cabinet.drawers[drawer], {
        path = vim.api.nvim_buf_get_name(0),
        cursor_pos = vim.api.nvim_win_get_cursor(0)
    })
end

M.remove_file = function(drawer_pos, file_index)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    local drawer = cabinet.drawer_order[drawer_pos]
    if not cabinet.drawers[drawer] or file_index <= 0 or file_index > #cabinet.drawers[drawer] then return end

    table.remove(cabinet.drawers[drawer], file_index)
end

M.open_file = function(drawer_pos, file_index)
    drawer_pos = drawer_pos or cabinet.current_drawer
    if not drawer_pos then return end
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end

    local drawer = cabinet.drawer_order[drawer_pos]

    if file_index <= 0 or file_index > #cabinet.drawers[drawer] then return end

    local file = cabinet.drawers[drawer][file_index]

    if file.path == vim.api.nvim_buf_get_name(0) then return end

    vim.cmd.edit(file.path)
    vim.api.nvim_win_set_cursor(0, file.cursor_pos)
end

---@param opts vim.api.keyset.win_config?
M.open = function (opts)
    require('ui').open(opts)
end

M.close = function ()
    require('ui').close()
end

return M
