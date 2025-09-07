---@class FileInfo
---@field path string                       -- path to file
---@field cursor_pos integer[]              -- {row, col}

---@class DrawerInfo
---@field name string                       -- Name of the drawer
---@field files FileInfo[]                  -- Files stored in the drawer

---@class Cabinet
---@field data DrawerInfo[]                 -- List of drawers
---@field current_drawer integer|nil        -- Active drawer index
local Cabinet = {}
Cabinet.__index = Cabinet

---@return Cabinet
function Cabinet.new(data)
    local self = setmetatable({}, Cabinet)
    self.data = data or {}
    self.current_drawer = #self.data > 0 and 1 or nil
    return self
end

---@return boolean
function Cabinet:is_empty()
    return #self.data == 0
end

---@param name string
---@return nil
function Cabinet:add_drawer(name)
    ---@type DrawerInfo
    if self:drawer_exist(name) then print('Drawer already exists') return end
    local drawer_info = {
        name = name,
        files = {}
    }

    table.insert(self.data, drawer_info)
end


function Cabinet:drawer_exist(name)
    for _, v in ipairs(self.data) do
        if v.name == name then return true end
    end
    return false
end

---@param index integer
---@return nil
function Cabinet:remove_drawer(index)
    if index then
        table.remove(self.data, index)
        if self.current_drawer and self.current_drawer > #self.data then
            self.current_drawer = #self.data > 0 and 1 or nil
        end
        return
    end
end

---@param index integer
---@return nil
function Cabinet:open_drawer(index)
    if index < 0 or #self.data < index then return end
    self.current_drawer = index
end

---@param index integer
---@param new_name string
---@return nil
function Cabinet:rename_drawer(index, new_name)
    if index < 0 or #self.data < index or not new_name then return end
    if self:drawer_exist(new_name) then print('Drawer already exists') return end
    self.data[index].name = new_name
end

function Cabinet:get_drawers()
    return self.data
end

---@param index integer
---@return FileInfo[]
function Cabinet:get_drawer_files(index)
    index = index or self.current_drawer
    if not index or not self.data[index] then
        return {}
    end
    return self.data[index].files
end

---@param index integer
---@return FileInfo|nil
function Cabinet:get_file(index, drawer)
    return self:get_drawer_files(drawer)[index]
end

---@param drawer integer
---@return nil
function Cabinet:add_file(drawer)
    local current_file = vim.api.nvim_buf_get_name(0)
    if current_file == '' then return end

    ---@type FileInfo
    local file_info = {
        path = current_file,
        cursor_pos = vim.api.nvim_win_get_cursor(0)
    }

    table.insert(self:get_drawer_files(drawer), file_info)
end

---@param index integer
---@param drawer integer
---@return nil
function Cabinet:remove_file(index, drawer)
    if index < 0 and #self:get_drawer_files(drawer) < index then return end
    table.remove(self:get_drawer_files(drawer), index)
end

---@param drawer integer
---@param index integer
---@return nil
function Cabinet:open_file(index, drawer)
    if not drawer then return end
    if index < 0 or #self:get_drawer_files(drawer) < index then return end

    local file_info = assert(self:get_file(index, drawer))

    if file_info.path == vim.api.nvim_buf_get_name(0) then return end
    vim.cmd.edit(file_info.path)
    vim.api.nvim_win_set_cursor(0, file_info.cursor_pos)
end

return Cabinet
