---@class Storage
---@field save fun(tbl:table)
---@field load fun(): table|nil
local M = {}

---@param path string
local dir_exists = function(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == 'directory'
end

---@param path string
local file_exists = function(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == 'file'
end

---@param path string
local ensure_dir = function(path)
    if not dir_exists(path) then
        os.execute('mkdir -p ' .. path)
    end
end

---@param string string
local hash = function(string)
    return vim.fn.sha256(string)
end

---@param basedir string
---@param filename string
local create_file_path = function(basedir, filename)
    return string.format('%s/%s', basedir, filename)
end

---@param filename string
local get_data_file_name = function(filename)
    return hash(filename) .. '.lua'
end

---@param tbl table
local function serialize(tbl)
    local result = '{'
    for k, v in pairs(tbl) do
        local key
        if type(k) == 'string' then
            key = string.format('[%q]', k)
        else
            key = '[' .. tostring(k) .. ']'
        end

        local value
        if type(v) == 'table' then
            value = serialize(v)
        elseif type(v) == 'string' then
            value = string.format('%q', v)
        else
            value = tostring(v)
        end

        result = result .. key .. '=' .. value .. ','
    end

    result = result .. '}'
    return result
end


M.data_path = string.format('%s/cabinet', vim.fn.stdpath('data'))

local function is_empty(tbl)
    return tbl.drawer_order == nil or #tbl.drawer_order == 0
end

---@param tbl table
M.save = function(tbl)
    ensure_dir(M.data_path)

    local filename = get_data_file_name(vim.fn.getcwd()) -- filename is based on cwd
    local data_file_path = create_file_path(M.data_path, filename)

    if is_empty(tbl) and file_exists(data_file_path) then return end

    local f = assert(io.open(data_file_path, 'w'))

    f:write('return' .. serialize(tbl))
    f:close()
end

M.load = function ()
    local filename = get_data_file_name(vim.fn.getcwd())
    local data_file_path = create_file_path(M.data_path, filename)

    local f = io.open(data_file_path)
    if not f then
        return nil
    end
    local content = f:read('*a')
    f:close()
    local chunk = assert(load(content))
    return chunk()
end

return M
