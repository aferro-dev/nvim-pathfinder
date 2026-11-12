# nvim-pathfinder

A full-screen, two-dimensional file tree for Neovim 0.11+. Each directory appears once, connected directly to its children in the next column. Nodes occupy one row each, with compact capsules and short connectors between columns. The map is centered horizontally and vertically and adjusts as branches expand or the terminal resizes.

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
| `D` | Switch to database UML; enter a URL or a project `.env` variable |
| `I` | Toggle Git-ignored files |
| `R` | Refresh tree, preserving expanded nodes |
| `q`, `Esc`, `Ctrl-P` | Close Pathfinder and return to the original window |

`zR` keeps the selected node. `zM` selects its ancestor in the root directory when necessary. Bulk expansion follows the configured filters and never traverses symbolic links.

The root path appears in the top bar, with shortcuts in the top bar. Long names are shortened, and the viewport follows the selected node. Movements support counts such as `3j` and stop at the boundaries.

Hidden files and Git-ignored files are visible by default; `.git` is always excluded by the default name filter. Press `I` to hide or show Git-ignored entries. The footer displays `ignored: hidden` or `ignored: shown`. Set `gitignore = true` in `setup()` to start with ignored entries hidden. The filter uses Git itself, including nested ignore files, negation rules, repository excludes, and global excludes; tracked files remain visible. Git must be installed for this filter. `R` reloads the ignore rules after edits. Directories load when expanded and appear before files, sorted by name. Symbolic links remain leaf nodes to prevent cycles. Git status indicators are not included.

## Database UML

Press `D` in the file tree, or run `:PathfinderDatabase`. A centered modal opens with `DATABASE_URL` prefilled. Enter a connection URL or a variable from the project root's `.env` file; press Enter to connect or Esc to cancel:

```text
DATABASE_URL
$DATABASE_URL
${DATABASE_URL}
sqlite:///absolute/path/database.db
sqlite://relative/database.db
postgresql://user:password@localhost:5432/database
postgres://user:password@localhost:5432/database
```

`.env` entries can use `export`, single or double quotes, and trailing comments. Values are read literally; shell commands and variable interpolation are not evaluated. Relative SQLite paths resolve from the project root. URL-encode special characters in URLs. SQLite requires an existing file and opens it read-only; PostgreSQL reads metadata in a read-only transaction.

The database map starts with every table collapsed, occupying one row per table. Spacing between layers and tables expands to use the available window and stays compact when the graph exceeds the viewport. Tables are arranged by their relationships, with directed connectors that remain visible when columns are collapsed. Selected tables and their incoming and outgoing connections are highlighted; other connections stay dim. Parallel foreign keys between the same tables share a connector, with every column mapping available in the detail modal. Large graphs scroll with the selected table. `hjkl` / arrow keys move between tables; `Tab` / `Shift-Tab` select the next or previous table. Enter opens a centered table modal with aligned key, column, type, and nullability fields, plus separate outgoing and incoming relationship sections. The map omits the common `public.` prefix and abbreviates long PostgreSQL type names; the modal retains the full table and column names. Esc or `q` closes the modal. Composite foreign keys show each column mapping, and PostgreSQL table names include their schema.

Space toggles inline columns; `zo` / `zc` expand or collapse a table, and `zR` / `zM` expand or collapse all tables. `H` hides the selected table; `I` restores hidden tables. `R` reloads metadata (and rereads a `.env` variable); `u` opens the connection modal. `D`, `q`, or Esc returns to the file tree. Each view retains its selection and expansion state when switching. Both main views fill the screen without an outer frame; shortcuts appear in the top bar. Connections load asynchronously, and the last successful schema remains available if reconnecting fails. Pathfinder does not write connection details to project files or include credentials in error messages.

SQLite support requires Python 3 with its standard `sqlite3` module; PostgreSQL requires `psql` on `PATH`. The Nixvim module includes both dependencies. Other installations must provide them separately. PostgreSQL password prompts are disabled: supply credentials in the URL or through libpq configuration such as `.pgpass`. Connections time out rather than blocking Neovim.

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
nvim --headless -u NONE -l tests/database.lua
python3 tests/startup.py
```
