# nvim-pathfinder

A full-screen, two-dimensional file tree for Neovim 0.11+. Each directory appears once, connected directly to its children in the next column. Nodes occupy one row each, with compact capsules and short connectors between columns. The map is centered horizontally and vertically and adjusts as branches expand or the terminal resizes.

Directories, selection, and shortcut labels use rounded capsules with Nerd Font glyphs. Colors follow the editor directly: backgrounds use `Normal`, selection uses `Visual`, directories use `Directory`, and borders use `WinSeparator`, including database views and modals. Rounded caps derive their colors from those surfaces and update when the colorscheme changes. Icon glyphs and colors come from `mini.icons` or `nvim-web-devicons`, with built-in fallbacks. You can customize the `Pathfinder*` highlight groups in your Neovim configuration.

Pathfinder replaces netrw: it opens with `nvim`, `nvim .`, `nvim /path/to/directory`, and when you open a directory with `:edit`. `:Explore` also opens Pathfinder. Starting Neovim with a file opens that file normally. To disable this integration, call `setup({ default_explorer = false })` before plugins load.

`:Pathfinder` opens the Git repository root, or the current working directory if no repository is found. It expands the current file's ancestors and selects the file. Other directories start collapsed. Your splits, buffers, and unsaved changes are preserved. Use `:Pathfinder /path/to/directory` to choose an explicit root.

## Shortcuts

| Key | Action |
| --- | --- |
| `j/k`, `↓/↑` | Next/previous node at the same depth; wrap at either end and skip shorter branches |
| `h`, `←` | Previous column, selecting the nearest node vertically |
| `l`, `→` | Expand the selected directory and enter its first child; files stay selected |
| `Enter` | Open file or toggle directory; expanding selects the first child |
| `Space` | Toggle directory; expanding selects the first child |
| `zo` / `zc` | Expand / collapse node |
| `zR` / `zM` | Expand all nodes / collapse all nodes |
| `zz` | Center the view vertically and horizontally on the selected node (within map boundaries) |
| `Backspace`, `-` | Select parent |
| `a` | Create file or directory |
| `r` | Rename selected file or directory (updates open buffer paths) |
| `d` | Delete file or directory after confirmation |
| `D` | Switch to database UML; enter a URL or a project `.env` variable |
| `I` | Toggle Git-ignored files |
| `Ctrl-Alt-P`, `/` | Search file and directory names in the tree |
| `n` / `N` | Next / previous search match |
| `R` | Refresh tree, preserving expanded nodes |
| `q`, `Esc`, `Ctrl-P` | Close Pathfinder and return to the original window |

`zR` keeps the selected node. `zM` selects its ancestor in the root directory when necessary. Bulk expansion follows the configured filters and never traverses symbolic links.

`Ctrl-Alt-P` also opens Pathfinder from the editor. Type a name in the command line to reveal matching paths live in the normal tree and highlight matching names (case insensitive, literal substring). Press Enter to navigate results, then Enter on a file to open it in the original editor window. Search respects the explorer filters and does not follow directory symlinks. An empty query clears the highlights and restores the previous expansions; Escape cancels the query edit.

The root path appears in the top bar, with shortcuts in the top bar. Long names are shortened, and the viewport follows the selected node. Movements support counts such as `3j` and stop at the boundaries.

The tree automatically refreshes when files or directories change externally, preserving the selection and expanded paths. Changes are grouped over 100 ms; returning focus to Neovim also refreshes the tree. Only loaded directories are watched, and watchers are released when Pathfinder closes.

Hidden files are visible by default; Git-ignored files are hidden, and `.git` is always excluded by the default name filter. Press `I` to hide or show Git-ignored entries. The footer displays `ignored: hidden` or `ignored: shown`. Set `gitignore = false` in `setup()` to start with ignored entries visible. The filter uses Git itself, including nested ignore files, negation rules, repository excludes, and global excludes; tracked files remain visible. Git must be installed for this filter. `R` reloads the ignore rules after edits. Directories load when expanded and appear before files, sorted by name. Symbolic links remain leaf nodes to prevent cycles. Git status indicators are not included.

## Database UML

Press `D` in the file tree, or run `:PathfinderDatabase`. A centered modal opens with `DATABASE_URL` prefilled. Enter a connection URL or a variable from the project root's `.env` file; press Enter to connect or Esc to cancel. The connection panel has a bordered URL field that grows to show long URLs, with continuation arrows when wrapping. Instructions, connection status and errors occupy separate rows; the layout adapts to terminal size. Failed attempts keep your input editable: correct it and press Enter to retry. Esc cancels an active request; reopening the panel restores your last input:

```text
DATABASE_URL
$DATABASE_URL
${DATABASE_URL}
sqlite:///absolute/path/database.db
sqlite://relative/database.db
mongodb://localhost:27017/database
mongodb+srv://user:password@cluster.example/database
postgresql://user:password@localhost:5432/database
postgres://user:password@localhost:5432/database
redis://localhost:6379/0
rediss://default:password@redis.example:6380/0
```

`.env` entries can use `export`, single or double quotes, and trailing comments. Values are read literally; shell commands and variable interpolation are not evaluated. Relative SQLite paths resolve from the project root. URL-encode special characters in URLs. SQLite requires an existing file and opens it read-only for browsing; PostgreSQL reads metadata in a read-only transaction. MongoDB URLs must name a database; the overview lists its accessible collections without inferring relationships.

Press `c` to manage connections for the current project: Enter switches, `a` adds, `u` edits, `r` renames, and `dd` removes an entry from the list. The overview and data browser also accept `a` to add and `c` to open the list; Ctrl-L opens it from the URL field. Each successful connection has its own cached schema, selection, hidden tables and expansion state. Entries are retained per project for the current Neovim session, including when switching projects; URLs and passwords are never persisted by Pathfinder. Switching uses the cached map; `R` reconnects and refreshes it. Removing a connection does not modify the database.

The database map starts with every table collapsed, occupying one row per table. Spacing between layers and tables expands to use the available window and stays compact when the graph exceeds the viewport. Tables are arranged by their relationships, with directed connectors that remain visible when columns are collapsed. Selected tables and their incoming and outgoing connections are highlighted; other connections stay dim. Parallel foreign keys between the same tables share a connector, with every column mapping available in the detail modal. Large graphs scroll with the selected table. `hjkl` / arrow keys move between tables; `Tab` / `Shift-Tab` select the next or previous table. Enter opens a centered table modal with aligned key, column, type, and nullability fields, plus separate outgoing and incoming relationship sections. The map omits the common `public.` prefix and abbreviates long PostgreSQL type names; the modal retains the full table and column names. Esc or `q` closes the modal. Composite foreign keys show each column mapping, and PostgreSQL table names include their schema.

Space toggles inline columns; `zo` / `zc` expand or collapse a table, and `zR` / `zM` expand or collapse all tables. `H` hides the selected table; `I` restores hidden tables. `R` reloads metadata (and rereads a `.env` variable); `u` opens the connection modal. `D`, `q`, or Esc returns to the file tree. Each view retains its selection and expansion state when switching. Both main views fill the screen without an outer frame; shortcuts appear in the top bar. Connections load asynchronously, and the last successful schema remains available if reconnecting fails. Pathfinder does not write connection details to project files or include credentials in error messages.

Redis support requires Python 3 with its standard library. SQLite support requires Python 3 with its standard `sqlite3` module; PostgreSQL requires `psql`, and MongoDB requires `mongosh` on `PATH`. The Nixvim module includes all three dependencies. Other installations must provide them separately. PostgreSQL password prompts are disabled: supply credentials in the URL or through libpq configuration such as `.pgpass`. Connections time out rather than blocking Neovim.

## Database data

Table and collection names appear in bordered cards with bold headings. The detail modal follows the connected database: SQL tables show columns, keys and relationships; MongoDB collections show top-level fields and BSON types observed in up to 50 documents, plus index names and keys. Sampled fields are not schema constraints; fields absent from the sample are not shown. Press `v` from the detail modal to browse records.

Press `v` in the database overview to browse the selected table or collection. PostgreSQL, MongoDB (including `mongodb+srv://`), SQLite, and Redis are supported. The data view fetches 50 records per page asynchronously, with a 15-second client timeout. PostgreSQL browsing queries use a read-only transaction. MongoDB uses `find()` and [canonical Extended JSON](https://www.mongodb.com/docs/mongodb-shell/reference/ejson/stringify/) to retain BSON types such as ObjectId and dates.

| Key | Action |
| --- | --- |
| `t` | Choose a table or collection |
| `Tab` / `Shift-Tab` | Next / previous table or collection |
| `]` / `[` | Next / previous page |
| `h/l`, `←/→` | Select previous / next column |
| `j/k`, `↓/↑` | Select next / previous record |
| `Enter` | Show the selected record as full JSON; `q` or `Esc` returns |
| `R` | Reload the current page |
| `u` | Return to the connection modal |
| `v`, `q`, `Esc`, `D`, `Ctrl-P` | Return to the database overview |

The selected row and column are highlighted, with a stronger highlight on the active cell and its column header. Movement stays within the records, supports counts such as `3j`, and scrolls to keep the active cell visible. Columns are capped at 32 characters in the grid; the record detail retains full values. MongoDB columns are the union of fields on the current page. Missing fields display `—`, while explicit nulls display `null`. Empty tables and collections remain navigable. Pages sort by PostgreSQL primary keys (or physical row identifiers when there is no primary key), MongoDB `_id`, and SQLite primary keys (or `rowid`). Concurrent database changes can shift records between pages; each page is a separate read. Connection URLs and `.env` variables use the same modal as the schema view.

Redis URLs accept `redis://` and verified TLS with `rediss://`, optional percent-encoded username/password, a port (default 6379), and a database number (default 0). Query parameters and fragments are rejected. Redis Cluster redirection, Sentinel, custom TLS certificates, and module-specific value previews are not supported. See the [Redis URL format](https://redis.io/docs/latest/develop/clients/connection-urls/).

The Redis `Keys` card opens a grid with key, type, TTL in seconds (`-1` means no expiry), size, value and a truncation flag. Strings, hashes, lists, sets, sorted sets and streams have previews; binary keys/values use `{ "base64": "…" }` objects. Values are limited to 100 entries or 16 KiB per string. Keys are paged using [SCAN](https://redis.io/docs/latest/commands/scan/), without `KEYS`; pages are a live view and may shift when the database changes. Each page scans from the start to its offset, so deep pages can take longer and hit the client timeout.

Open a complete Redis string with Enter or `e`, change only `value`, and use `:w` to save. Redis 6+ is required for string updates, which preserve TTL with `KEEPTTL`. Use `dd` to delete a complete key of any supported type after confirmation. Writes use `WATCH` and a transaction to reject concurrent changes. Truncated previews cannot be edited or deleted; other value types have a read-only JSON preview. The Redis user needs permission for the read commands used by its value types and, for writes, `WATCH`, `MULTI`, `EXEC`, `SET` and `DEL`.

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
nvim --headless -u NONE -l tests/rename.lua
nvim --headless -u NONE -l tests/watch.lua
nvim --headless -u NONE -l tests/gitignore.lua
nvim --headless -u NONE -l tests/search.lua
nvim --headless -u NONE -l tests/database.lua
nvim --headless -u NONE -l tests/database_data.lua
nvim --headless -u NONE -l tests/database_connections.lua
nvim --headless -u NONE -l tests/database_form.lua
nvim --headless -u NONE -l tests/database_write.lua
nvim --headless -u NONE -l tests/theme.lua
python3 tests/startup.py
```

For Redis integration tests, point `REDIS_TEST_URL` at a disposable Redis database, then run `python3 tests/redis.py`. The test creates and removes keys prefixed with `pathfinder-test:` and exercises the connection manager in Neovim.

The data browser fills the screen with a scrollable grid, padded cells, alternating row colors and distinct colors for IDs, dates, numbers and nested values. Move between cells with `hjkl` or arrows; use `Ctrl-d` / `Ctrl-u` or the mouse wheel to move vertically. MongoDB BSON wrappers are displayed as readable IDs, UTC dates and exact numeric strings, including nested values. Record details are editable Vim buffers using Extended JSON for MongoDB.

`zz` centers the selection vertically and horizontally in every Pathfinder view: the file tree, database map, data grid, table/collection detail and record detail. The grid centers the selected cell and the database map centers the selected card. Detail views scroll horizontally without wrapping. Centering respects the beginning of the buffer.

Use Space, Enter or `e` on a record to open its complete JSON in an editable buffer. MongoDB edits use canonical Extended JSON to preserve BSON types. Use normal Vim commands: `:w` saves to the database, `:q` closes and `:q!` discards unsaved changes. Use `dd` to delete the selected record and confirm the prompt. SQL writes require a non-null primary key; primary keys and MongoDB `_id` cannot be changed. Writes check the original record and fail if it has changed or disappeared, then refresh the page after success. SQL column removal is rejected; use JSON `null` to clear a nullable column.

Horizontal movement changes nesting depth only: Right moves to the next depth and Left to the previous, selecting the closest vertical position. Hidden paths are opened as needed. Right at the deepest level wraps to the first; Left at the first wraps to the deepest. Vertical movement cycles through nodes at the same depth across branches, opening the selected path without ever falling back to a shallower node.
