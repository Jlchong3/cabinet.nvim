# cabinet.nvim

A lightweight buffer navigation plugin for Neovim.

Instead of maintaining a single global list of marked buffers, with `cabinet.nvim` you organize your workflow into isolated "drawers." It is perfect for grouping related files by feature, component, or task—allowing you to instantly switch contexts and jump between buffers.

## Features

* **Grouped Contexts:** Create multiple drawers to separate frontend files from backend files, tests from implementations, or however you structure your work.
* **Project-Local Persistence:** State is persisted to disk automatically based on your current working directory.
* **Minimal UI:** Includes a simple, floating scratch buffer for visually managing your drawers and files.

## Installation

Install the plugin using your preferred package manager:

**Using lazy.nvim:**
```lua
{
    'Jlchong3/cabinet.nvim',
    opts = {}
}
```

**Using built-in package manager (vim.pack.add):**
```lua
vim.pack.add {
    'https://github.com/Jlchong3/cabinet.nvim'
}
require('cabinet').setup()
```

## Configuration

`cabinet.nvim` does not map any keys by default. Below is an example configuration.

```lua
local cabinet = require('cabinet').setup()

-- Global Actions
vim.keymap.set('n', '<A-e>', cabinet.open, { desc = 'Cabinet: Toggle UI' })
vim.keymap.set('n', '<leader>da', cabinet.add_drawer, { desc = 'Cabinet: Add new drawer' })
vim.keymap.set('n', '<leader>a', cabinet.add_file, { desc = 'Cabinet: Add buffer to drawer' })

-- Jump to buffers in the active drawer
vim.keymap.set('n', '<A-j>', function() cabinet.open_file(1) end)
vim.keymap.set('n', '<A-k>', function() cabinet.open_file(2) end)
vim.keymap.set('n', '<A-l>', function() cabinet.open_file(3) end)
vim.keymap.set('n', '<A-;>', function() cabinet.open_file(4) end)

-- Switch the active drawer
vim.keymap.set('n', '<A-f>', function() cabinet.open_drawer(1) end)
vim.keymap.set('n', '<A-d>', function() cabinet.open_drawer(2) end)
vim.keymap.set('n', '<A-s>', function() cabinet.open_drawer(3) end)
vim.keymap.set('n', '<A-a>', function() cabinet.open_drawer(4) end)
```

## The UI

Calling `cabinet.open()` opens a floating, editable scratch buffer. You can use standard Neovim motions to navigate, and edit the text directly to manage your state (e.g., type a new name on an empty line to create a drawer, or delete a line to remove a drawer or untrack a buffer).

The buffer provides the following local mappings:

`<CR>` : Open the selected drawer to view its buffers, or jump directly to the selected buffer.

`-` : Go back to the main drawer list.

`q` : Close the UI.

Changes made to the text are saved automatically when leaving insert mode or closing the window.

## API Reference

If you want to build custom workflows, you can utilize the public API. For full documentation, run `:help cabinet` inside Neovim.

| Function | Description |
| :--- | :--- |
| `cabinet.setup(opts)` | Initializes the plugin and merges config. |
| `cabinet.open(opts?)` | Opens the floating UI. |
| `cabinet.close()` | Closes the floating UI. |
| `cabinet.add_drawer(name?)` | Prompts for a name and creates a new drawer. |
| `cabinet.remove_drawer(pos)` | Removes the drawer at the 1-based index. |
| `cabinet.add_file(drawer_pos?)`| Adds the current buffer to a drawer. |
| `cabinet.open_file(index)` | Opens the buffer at the 1-based index of the active drawer. |
| `cabinet.open_drawer(pos)` | Sets the active drawer to the 1-based index. |
| `cabinet.get_drawers()` | Returns the full table of drawers and tracked files. |
