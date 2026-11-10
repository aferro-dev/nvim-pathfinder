# nvim-pathfinder

A full-screen, two-dimensional file tree for Neovim 0.11+. Each directory appears once, connected directly to its children in the next column. The map is centered horizontally and vertically and adjusts as branches expand or the terminal resizes.

Directories, selection, and shortcut labels use rounded capsules with Nerd Font glyphs. Thin lines connect the nodes, while a dedicated dark blue-violet palette provides subtle directory backgrounds and a lilac selection accent. Folder icons use soft blue; file icons use lavender gray. Glyphs come from `mini.icons` or `nvim-web-devicons`, with built-in fallbacks.

Pathfinder replaces netrw: it opens with `nvim`, `nvim .`, `nvim /path/to/directory`, and when you open a directory with `:edit`. `:Explore` also opens Pathfinder. Starting Neovim with a file opens that file normally. To disable this integration, call `setup({ default_explorer = false })` before plugins load.

`:Pathfinder` opens the Git repository root, or the current working directory if no repository is found. It expands the current file's ancestors and selects the file. Other directories start collapsed. Your splits, buffers, and unsaved changes are preserved. Use `:Pathfinder /path/to/directory` to choose an explicit root.

## Shortcuts

| Key | Action |
| --- | --- |
| `j/k`, `↓/↑` | Next/previous node; expand the adjacent branch to keep depth, or move up when needed |
| `h/l`, `←/→` | Previous/next column, selecting the nearest node vertically |
| `Enter` | Open file or toggle directory; expanding selects the first child |
| `Space` | Toggle directory; expanding selects the first child |
| `zo` / `zc` | Expand / collapse node |
| `zR` / `zM` | Expand all nodes / collapse all nodes |
| `Backspace`, `-` | Select parent |
| `R` | Refresh tree, preserving expanded nodes |
| `q`, `Esc`, `Ctrl-P` | Close Pathfinder and return to the original window |

`zR` keeps the selected node. `zM` selects its ancestor in the root directory when necessary. Bulk expansion follows the configured filters and never traverses symbolic links.

The root path appears in the top bar, with shortcuts along the bottom frame. Long names are shortened, and the viewport follows the selected node. Movements support counts such as `3j` and stop at the boundaries.

Hidden files are visible; `.git` is excluded. Directories load when expanded and appear before files, sorted by name. Symbolic links remain leaf nodes to prevent cycles. Pathfinder focuses on navigation and does not provide file modification actions or Git status indicators.

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
python3 tests/startup.py
```
