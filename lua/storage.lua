---@private
---@class Storage
---@field data_path string Absolute path to the directory where cabinet data files are stored
---@field save fun(tbl: table, is_empty: fun(tbl: table): boolean): nil
---@field load fun(): table|nil
local storage = {}

---@private
---@param path string Absolute path to check
---@return boolean|nil
local dir_exists = function(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == 'directory'
end

---@private
---@param path string Absolute path to check
---@return boolean|nil
local file_exists = function(path)
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == 'file'
end

---@private
---@param path string Directory path to create if missing
local ensure_dir = function(path)
    if not dir_exists(path) then
        os.execute('mkdir -p ' .. path)
    end
end

---@private
--- Returns the SHA-256 hex digest of the given string.
---@param string string The string to hash
---@return string hash Hex-encoded SHA-256 digest
local hash = function(string)
    return vim.fn.sha256(string)
end

---@private
--- Joins a base directory and a filename into a full file path.
---@param basedir string Base directory (no trailing slash)
---@param filename string File name (no leading slash)
---@return string path The joined path
local create_file_path = function(basedir, filename)
    return string.format('%s/%s', basedir, filename)
end

---@private
--- Derives a stable, filesystem-safe file name from a given string.
--- The returned name is a SHA-256 hex digest with a `.lua` extension.
---@param filename string The source string (typically the current working directory)
---@return string data_filename SHA-256 based `.lua` file name
local get_data_file_name = function(filename)
    return hash(filename) .. '.lua'
end

---@private
--- Recursively serializes a Lua table into a string that can be loaded
--- back with `load()`. Handles nested tables, strings, and non-string keys.
---@param tbl table The table to serialize
---@return string serialized A Lua expression string representing the table
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

---@private
--- Absolute path to the directory where cabinet state files are persisted.
--- Defaults to `{stdpath('data')}/cabinet`.
storage.data_path = string.format('%s/cabinet', vim.fn.stdpath('data'))

---@private
--- Persists the cabinet table to disk for the current working directory.
--- The file is named after a SHA-256 hash of the cwd path, so each project
--- gets its own isolated state file.
--- If `is_empty` returns true and no file exists yet, the write is skipped
--- to avoid creating empty data files.
---@param tbl table The cabinet table to persist
---@param is_empty fun(tbl: table): boolean Predicate that returns true when the cabinet holds no meaningful data
storage.save = function(tbl, is_empty)
    ensure_dir(M.data_path)
    local filename = get_data_file_name(vim.fn.getcwd())
    local data_file_path = create_file_path(M.data_path, filename)
    if is_empty(tbl) and not file_exists(data_file_path) then return end
    local f = assert(io.open(data_file_path, 'w'))
    f:write('return' .. serialize(tbl))
    f:close()
end

---@private
--- Loads the cabinet table previously saved for the current working directory.
--- Returns nil when no data file exists yet (first run in this project).
---@return table|nil cabinet The deserialized cabinet table, or nil if no data file is found
storage.load = function()
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

return storage
