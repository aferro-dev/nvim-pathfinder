# nvim-pathfinder

A full-screen, two-dimensional file tree for Neovim 0.11+. Each directory appears once, connected directly to its children in the next column. The map is centered horizontally and vertically and adjusts as branches expand or the terminal resizes.

Directories, selection, and shortcut labels use rounded capsules with Nerd Font glyphs. Colors follow your Neovim colorscheme: surfaces, selection, borders, and shortcut labels link to standard highlight groups. Rounded caps derive their colors from those surfaces and update when the colorscheme changes. Icon glyphs and colors come from `mini.icons` or `nvim-web-devicons`, with built-in fallbacks. You can customize the `Pathfinder*` highlight groups in your Neovim configuration.

Pathfinder replaces netrw: it opens with `nvim`, `nvim .`, `nvim /path/to/directory`, and when you open a directory with `:edit`. `:Explore` also opens Pathfinder. Starting Neovim with a file opens that file normally. To disable this integration, call `setup({ default_explorer = false })` before plugins load.

`:Pathfinder` opens the Git repository root, or the current working directory if no repository is found. It expands the current file's ancestors and selects the file. Other directories start collapsed. Your splits, buffers, and unsaved changes are preserved. Use `:Pathfinder /path/to/directory` to choose an explicit root.

## Shortcuts

| Key | Action |
| --- | --- |
| `j/k`, `↓/↑` | Next/previous node; expand the adjacent branch to keep depth, or move up when needed |
| `h`, `←` | Previous column, selecting the nearest node vertically |
| `l`, `→` | Expand the selected directory and enter its first child; files stay selected |
| `Enter` | Open file or toggle directory; expanding selects the first child |
| `Space` | Toggle directory; expanding selects the first child |
| `zo` / `zc` | Expand / collapse node |
| `zR` / `zM` | Expand all nodes / collapse all nodes |
| `Backspace`, `-` | Select parent |
| `a` | Create file or directory |
| `d` | Delete file or directory after confirmation |
| `I` | Toggle Git-ignored files |
| `R` | Refresh tree, preserving expanded nodes |
| `q`, `Esc`, `Ctrl-P` | Close Pathfinder and return to the original window |

`zR` keeps the selected node. `zM` selects its ancestor in the root directory when necessary. Bulk expansion follows the configured filters and never traverses symbolic links.

The root path appears in the top bar, with shortcuts along the bottom frame. Long names are shortened, and the viewport follows the selected node. Movements support counts such as `3j` and stop at the boundaries.

Hidden files and Git-ignored files are visible by default; `.git` is always excluded by the default name filter. Press `I` to hide or show Git-ignored entries. The footer displays `ignored: hidden` or `ignored: shown`. Set `gitignore = true` in `setup()` to start with ignored entries hidden. The filter uses Git itself, including nested ignore files, negation rules, repository excludes, and global excludes; tracked files remain visible. Git must be installed for this filter. `R` reloads the ignore rules after edits. Directories load when expanded and appear before files, sorted by name. Symbolic links remain leaf nodes to prevent cycles. Git status indicators are not included.

## File actions

Press `a` to create an entry inside the selected directory, or alongside the selected file. Enter a relative name such as `new-file.lua`, `nested/new-file.lua`, or `new-directory/`. A trailing `/` creates a directory; missing parent directories are created automatically. Existing entries are never overwritten. The map refreshes and selects the new entry.

Press `d` to delete the selected entry. Choose **Delete** to confirm; **Cancel** leaves it unchanged. Deleting a directory permanently removes its contents. Deleting a symbolic link removes the link only. Deletion is blocked if the entry or any descendant has a buffer with unsaved changes. The repository root cannot be deleted.

## Lua installation

Add the plugin directory to your runtimepath, or install it with your plugin manager, then configure it:

```lua
require('pathfinder').setup({ hidden = true, ignored = { '.git' } })
vim.keymap.set('n', '<C-p>', '<cmd>Pathfinder<CR>', { silent = true })
```

Use a Nerd Font in your terminal to display the icons and rounded capsules correctly.

## Nix / Nixvim

Build the standalone package from a local checkout:

```sh
nix build path:.
```

Using `path:.` includes files that have not yet been added to Git.

In a Home Manager module that already imports the Nixvim Home Manager module:

```nix
{ pkgs, ... }: {
  imports = [ /path/to/nvim-pathfinder/nix/nixvim.nix ];
}
```

Alternatively, add the package to `programs.nixvim.extraPlugins`:

```nix
(import /path/to/nvim-pathfinder/default.nix { inherit pkgs; })
```

The flake also exports `packages.<system>.default` and `homeManagerModules.default`. The Home Manager module requires Nixvim's Home Manager module and sets up Pathfinder with a `Ctrl-P` shortcut.

For local development, use an absolute source path accessible to the build process. Nix packages contain an immutable copy of the source: rebuild Nixvim after making changes.

## Verification

```sh
nvim --headless -u NONE -l tests/smoke.lua
nvim --headless -u NONE -l tests/grid.lua
nvim --headless -u NONE -l tests/actions.lua
nvim --headless -u NONE -l tests/gitignore.lua
python3 tests/startup.py
```
