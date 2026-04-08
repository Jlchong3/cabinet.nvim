local storage = require('storage')

--- Represents a single file tracked inside a drawer.
---@class FileInfo
---@field path string Absolute path to the file
---@field cursor_pos integer[] Last known cursor position as a `{row, col}` tuple (1-based row, 0-based col)

--- The top-level state container persisted to disk.
---@class Cabinet
---@field current_drawer integer|nil 1-based index into `drawer_order` of the active drawer, or nil when no drawers exist
---@field drawers table<string, FileInfo[]> Map of drawer name to its ordered list of tracked files
---@field drawer_order string[] Ordered list of drawer names; the order is what the user sees in the UI

--- Initializes a new empty cabinet.
---@return Cabinet
local load_cabinet = function()
    return storage.load() or { current_drawer = nil, drawers = {}, drawer_order = {} }
end

---@type Cabinet
local cabinet

local M = {}

local default_config = {
    window = {
        width = 0.4,  -- If <= 1, treated as a percentage. If > 1, treated as fixed columns.
        height = 0.3, -- If <= 1, treated as a percentage. If > 1, treated as fixed lines.
        border = 'single',
        style = 'minimal',
        title = { { 'Drawers', 'DrawerTitle' } },
    }
}

M.config = vim.deepcopy(default_config)

--- Registers all autocommands required by the cabinet.
--- - `UIEnter`: loads persisted cabinet state from disk (runs once).
--- - `VimLeave`: saves cabinet state to disk.
--- - `BufLeave`: snapshots the cursor position of the current file before leaving.
local drawer_autocmds = function()
    vim.api.nvim_create_augroup('drawer', { clear = true })

    -- Load cabinet after UIEnter
    vim.api.nvim_create_autocmd('UIEnter', {
        once = true,
        callback = function()
            cabinet = load_cabinet()
        end
    })

    vim.api.nvim_create_autocmd('VimLeave', {
        group = 'drawer',
        callback = function()
            ---@param cabinet_tbl Cabinet
            ---@return boolean
            local cabinet_is_empty = function(cabinet_tbl)
                return cabinet_tbl.drawer_order == nil or #cabinet_tbl.drawer_order == 0
            end
            storage.save(cabinet, cabinet_is_empty)
        end
    })

    vim.api.nvim_create_autocmd('BufLeave', {
        group = 'drawer',
        callback = function()
            local current = cabinet.current_drawer
            if not current or current <= 0 or current > #cabinet.drawer_order then return end

            local files = assert(M.get_drawer_files(cabinet.current_drawer))
            if #files == 0 then return end

            local filepath = vim.api.nvim_buf_get_name(0)
            if filepath == '' then return end

            for _, file_info in ipairs(files) do
                if file_info.path == filepath then
                    file_info.cursor_pos = vim.api.nvim_win_get_cursor(0)
                    break
                end
            end
        end
    })
end

--- Returns the 1-based position of `drawer` inside `cabinet.drawer_order`,
--- or nil if the drawer does not exist.
---@param drawer string Drawer name to locate
---@return integer|nil position 1-based index, or nil if not found
local function get_drawer_pos(drawer)
    for i, drawer_key in ipairs(cabinet.drawer_order) do
        if drawer_key == drawer then
            return i
        end
    end
end

--- Initializes the cabinet module: registers autocommands and returns the public API.
---@param opts table? Reserved for future configuration options
---@return table M The public cabinet API
M.setup = function(opts)
    M.config = vim.tbl_deep_extend('force', M.config, opts or {})

    drawer_autocmds()
    return M
end

--- Returns the 1-based index of the currently active drawer, or nil when no drawer is open.
---@return integer|nil drawer_pos
M.get_current_drawer = function()
    return cabinet.current_drawer
end

--- Creates a new drawer with the given name.
--- If `drawer` is nil the user is prompted interactively.
--- If `drawer` is an empty string, `"default"` is used.
--- Returns nil if the drawer already exists or the input was cancelled.
---@param drawer string? Name for the new drawer (optional; prompts if nil)
---@return string|nil drawer The name of the created drawer, or nil on failure
M.add_drawer = function(drawer)
    drawer = drawer or vim.fn.input('Drawer name: ')

    if drawer == nil then return end
    if drawer == '' then drawer = 'default' end
    if cabinet.drawers[drawer] then
        print('Drawer already exists')
        return
    end

    cabinet.drawers[drawer] = {}
    table.insert(cabinet.drawer_order, drawer)

    if not cabinet.current_drawer then cabinet.current_drawer = #cabinet.drawer_order end

    return drawer
end

--- Returns the file list table for `drawer` if it exists, or nil otherwise.
--- This is truthy even when the drawer is empty (it returns an empty table).
---@param drawer string Drawer name to check
---@return FileInfo[]|nil files The drawer's file list, or nil if the drawer does not exist
M.drawer_exist = function(drawer)
    return cabinet.drawers[drawer]
end

--- Removes the drawer at position `drawer_pos` from the cabinet.
--- Adjusts `current_drawer` so it remains valid after the removal.
--- Does nothing when `drawer_pos` is out of range.
---@param drawer_pos integer 1-based index of the drawer to remove
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

--- Removes the drawer with the given name.
--- Adjusts `current_drawer` so it remains valid after the removal.
--- Does nothing when the drawer does not exist.
---@param drawer string Name of the drawer to remove
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

--- Sets the active drawer to the one with the given name.
--- Does nothing when the drawer does not exist.
---@param drawer string Name of the drawer to open
M.open_drawer_by_name = function(drawer)
    if not cabinet.drawers[drawer] then return end
    cabinet.current_drawer = get_drawer_pos(drawer)
end

--- Sets the active drawer to the one at position `drawer_pos`.
--- Does nothing when `drawer_pos` is out of range.
---@param drawer_pos integer 1-based index of the drawer to open
M.open_drawer = function(drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    cabinet.current_drawer = drawer_pos
end

--- Renames the drawer with the given name.
--- Does nothing when `drawer` does not exist or `new_name` is already taken.
---@param drawer string Current name of the drawer
---@param new_name string Desired new name
M.rename_drawer_by_name = function(drawer, new_name)
    if not cabinet.drawers[drawer] then return end
    if cabinet.drawers[new_name] then return end

    cabinet.drawer_order[get_drawer_pos(drawer)] = new_name

    local drawer_content = cabinet.drawers[drawer]
    cabinet.drawers[drawer] = nil
    cabinet.drawers[new_name] = drawer_content
end

--- Renames the drawer at position `drawer_pos`.
--- Does nothing when `drawer_pos` is out of range or `new_name` is already taken.
---@param drawer_pos integer 1-based index of the drawer to rename
---@param new_name string Desired new name
M.rename_drawer = function(drawer_pos, new_name)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    if cabinet.drawers[new_name] then return end

    local drawer = cabinet.drawer_order[drawer_pos]
    local drawer_content = cabinet.drawers[drawer]

    cabinet.drawers[drawer] = nil
    cabinet.drawers[new_name] = drawer_content
    cabinet.drawer_order[drawer_pos] = new_name
end

--- Returns the full drawers map (name → file list).
---@return table<string, FileInfo[]>
M.get_drawers = function()
    return cabinet.drawers
end

--- Returns the ordered list of drawer names.
---@return string[]
M.get_drawer_order = function()
    return cabinet.drawer_order
end

--- Returns the file list for the drawer with the given name.
--- Returns nil when the drawer does not exist.
---@param drawer string Drawer name
---@return FileInfo[]|nil
M.get_drawer_files_by_name = function(drawer)
    return cabinet.drawers[drawer]
end

--- Returns the file list for the drawer at position `drawer_pos`.
--- Returns nil when `drawer_pos` is out of range.
---@param drawer_pos integer 1-based index into `drawer_order`
---@return FileInfo[]|nil
M.get_drawer_files = function(drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end

    local drawer = cabinet.drawer_order[drawer_pos]
    return cabinet.drawers[drawer]
end

--- Appends the current buffer to a drawer and records its cursor position.
--- If `drawer_pos` is nil, uses the active drawer; creates one named `"default"`
--- when no drawers exist yet.
--- Returns the 1-based index of the newly added file within its drawer, or nil on failure.
---@param drawer_pos integer? 1-based index of the target drawer (defaults to `current_drawer`)
---@return integer|nil file_index Index of the added file within the drawer, or nil on failure
M.add_file = function(drawer_pos)
    drawer_pos = drawer_pos or cabinet.current_drawer

    local drawer
    if not drawer_pos then
        M.add_drawer()
        cabinet.current_drawer = #cabinet.drawer_order
        drawer = cabinet.drawer_order[cabinet.current_drawer]
    elseif 0 < drawer_pos and drawer_pos <= #cabinet.drawer_order then
        drawer = cabinet.drawer_order[drawer_pos]
    else
        return
    end

    table.insert(cabinet.drawers[drawer], {
        path = vim.api.nvim_buf_get_name(0),
        cursor_pos = vim.api.nvim_win_get_cursor(0)
    })

    return #cabinet.drawers[drawer]
end

--- Removes the file at `file_index` from the drawer at `drawer_pos`.
--- Does nothing when either index is out of range.
---@param file_index integer 1-based index of the file within the drawer
---@param drawer_pos integer 1-based index of the drawer in `drawer_order`
M.remove_file = function(file_index, drawer_pos)
    if drawer_pos <= 0 or drawer_pos > #cabinet.drawer_order then return end
    local drawer = cabinet.drawer_order[drawer_pos]
    if not cabinet.drawers[drawer] or file_index <= 0 or file_index > #cabinet.drawers[drawer] then return end

    table.remove(cabinet.drawers[drawer], file_index)
end

--- Opens the file at `file_index` inside the drawer at `drawer_pos`.
--- If `drawer_pos` is nil, uses the active drawer.
--- Restores the previously saved cursor position after opening.
--- Does nothing when the file is already the current buffer or indices are out of range.
---@param file_index integer 1-based index of the file within the drawer
---@param drawer_pos integer? 1-based index of the drawer (defaults to `current_drawer`)
M.open_file = function(file_index, drawer_pos)
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

--- Opens the drawer floating window. Delegates to the `ui` module.
---@param opts vim.api.keyset.win_config? Optional overrides for the window configuration
M.open = function(opts)
    require('ui').open(opts)
end

--- Closes the drawer floating window. Delegates to the `ui` module.
M.close = function()
    require('ui').close()
end

return M
