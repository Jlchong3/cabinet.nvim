local cabinet = require('cabinet')

---@class UI
---@field open fun(opts: vim.api.keyset.win_config?): nil
---@field close fun(): nil
local M = {}

---@type integer
local buf = -1
---@type integer
local win = -1

--- True while the buffer is showing a drawer's file list;
--- false when showing the top-level drawer list.
---@type boolean
local in_drawer_view = false

--- 1-based index of the drawer whose files are currently displayed.
--- nil when in the top-level drawer list view.
---@type integer|nil
local current_drawer_index = nil

--- Window config overrides supplied by the caller of `M.open`.
---@type vim.api.keyset.win_config?
local saved_opts = nil

--- Strips `basedir` (and an optional trailing slash) from the beginning of `path`.
---@param basedir string The base directory prefix to remove
---@param path string The full path to make relative
---@return string relpath The path with `basedir` stripped, or the original path if it did not match
local function get_relative_path(basedir, path)
    local relpath = path:gsub('^' .. basedir .. '/?', '')
    return relpath
end

--- Ensures the module buffer exists and is empty.
--- Creates a new scratch buffer when the current one is invalid,
--- otherwise wipes its content. Sets `bufhidden=wipe` and `filetype=drawer`.
local function reset_buffer()
    if not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
    else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    end

    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'drawer'
end

--- Populates the buffer with the ordered list of drawer names
--- and switches to the top-level drawer list view.
local function buf_set_drawers()
    in_drawer_view = false
    current_drawer_index = nil

    reset_buffer()

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, cabinet.get_drawer_order())
end

--- Populates the buffer with the relative paths of all files in `drawer_index`
--- and switches to the file list view for that drawer.
---@param drawer_index integer 1-based index of the drawer whose files to display
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

--- Syncs the in-memory cabinet with the current buffer contents while in
--- the top-level drawer list view.
--- - Lines that match an existing drawer name are kept in their new order.
--- - Lines with a new name create a new drawer.
--- - Drawers no longer present in the buffer are removed.
local function update_drawers()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local drawers = cabinet.get_drawers()
    local drawer_order = cabinet.get_drawer_order()

    local seen = {}
    local new_order = {}

    for _, name in ipairs(lines) do
        name = vim.trim(name)
        if name ~= "" and not seen[name] then
            seen[name] = true
            if drawers[name] then
                table.insert(new_order, name)
            else
                cabinet.add_drawer(name)
                table.insert(new_order, name)
            end
        end
    end

    -- remove drawers the user deleted
    for drawer, _ in pairs(drawers) do
        if not seen[drawer] then
            cabinet.remove_drawer_by_name(drawer)
        end
    end

    -- replace the order table in-place so the reference cabinet holds stays valid
    for i = #drawer_order, 1, -1 do
        drawer_order[i] = nil
    end
    for i, name in ipairs(new_order) do
        drawer_order[i] = name
    end
end

--- Syncs the current drawer's file list with the buffer contents while in
--- the file list view.
--- - Lines matching a known path preserve cursor position metadata.
--- - New lines are added with a default cursor position of `{1, 0}`.
--- - Files no longer present in the buffer are removed.
local function update_files()
    local drawer_files = assert(cabinet.get_drawer_files(current_drawer_index))
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    ---@type table<string, FileInfo>
    local old_files_map = {}
    for _, file_info in ipairs(drawer_files) do
        old_files_map[file_info.path] = file_info
    end

    ---@type FileInfo[]
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
                    cursor_pos = { 1, 0 },
                })
            end
        end
    end

    local drawer_name = cabinet.get_drawer_order()[current_drawer_index]
    local drawers = cabinet.get_drawers()
    drawers[drawer_name] = new_list
end

--- Builds the `nvim_open_win` config for the floating drawer window.
--- The window is centered and sized at 40% of the editor width and 30% of the editor height.
--- Any keys in `opts` override the defaults via `vim.tbl_deep_extend`.
---@param opts vim.api.keyset.win_config Window config overrides
---@return vim.api.keyset.win_config window_config Merged window configuration
local function drawer_win_config(opts)
    local win_conf = cabinet.config.window

    local max_width = vim.o.columns
    local max_height = vim.o.lines

    -- Support both percentages (e.g., 0.4) and absolute integers (e.g., 80)
    local width = win_conf.width
    if type(width) == "number" and width <= 1 then
        width = math.floor(max_width * width)
    end

    local height = win_conf.height
    if type(height) == "number" and height <= 1 then
        height = math.floor(max_height * height)
    end

    local row = math.floor((max_height - height) / 2)
    local col = math.floor((max_width - width) / 2)

    local window_config = vim.tbl_deep_extend('force', {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        title = win_conf.title,
        style = win_conf.style,
        border = win_conf.border,
    }, opts or {})

    return window_config
end

--- Opens the drawer floating window.
--- If the window is already open, focuses it without reinitializing.
--- Sets up all buffer-local keymaps and autocommands on first open:
---
--- Keymaps (normal mode):
--- - `<CR>` — in drawer list: open selected drawer's file list;
---            in file list: close window and open the selected file.
--- - `-`    — in file list: return to the drawer list.
--- - `q`    — close the window.
---
--- Autocommands (buffer-local):
--- - `InsertLeave` — persist edits and refresh the buffer.
--- - `VimResized`  — recompute and apply the window dimensions.
---@param opts vim.api.keyset.win_config? Optional overrides for the window configuration
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

    vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
        callback = function()
            local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
            if not in_drawer_view then
                update_drawers()
                buf_set_files(cursor_row)
            else
                M.close()
                cabinet.open_file(cursor_row, current_drawer_index)
            end
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(buf, 'n', '-', '', {
        callback = function()
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

--- Closes the floating drawer window and persists any edits made in the buffer.
--- Flushes drawer list edits when in the top-level view,
--- or file list edits when in the file list view.
M.close = function()
    if not in_drawer_view then
        update_drawers()
    else
        update_files()
    end

    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, false)
    end
end

return M
