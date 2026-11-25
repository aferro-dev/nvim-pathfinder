local M = {}
local api, uv = vim.api, vim.uv
local context = require('pathfinder.tree.context')

function M.update_gitignore()
  context.state.git_ignored = {}
  if not context.config.gitignore or vim.fn.executable('git') ~= 1 then return end
  local result = vim.system({ 'git', '-C', context.state.root.path, 'ls-files',
    '--others', '--ignored', '--exclude-standard', '--directory', '-z', '--', '.' },
    { text = false }):wait(5000)
  if result.code ~= 0 then return end -- Non-Git directories remain usable.
  for entry in (result.stdout or ''):gmatch('[^%z]+') do
    local path = vim.fs.normalize(vim.fs.joinpath(context.state.root.path, entry)):gsub('/$', '')
    context.state.git_ignored[path] = true
  end
end

function M.children(node)
  if node.children then return node.children end
  node.children = {}
  local scan, err = uv.fs_scandir(node.path)
  if not scan then
    vim.notify('Pathfinder: ' .. tostring(err), vim.log.levels.WARN)
    return node.children
  end
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then break end
    if not vim.tbl_contains(context.config.ignored, name) and (context.config.hidden or name:sub(1, 1) ~= '.') then
      local path = vim.fs.joinpath(node.path, name)
      if not (context.config.gitignore and context.state.git_ignored and context.state.git_ignored[path]) then
        -- Symlink directories remain leaves: traversal never follows a cycle.
        table.insert(node.children, { name = name, path = path, dir = kind == 'directory', open = false, parent = node })
      end
    end
  end
  table.sort(node.children, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name < b.name
  end)
  return node.children
end

function M.current()
  if not context.state or not api.nvim_win_is_valid(context.state.win) then return end
  local cursor = api.nvim_win_get_cursor(context.state.win)
  for _, column in ipairs(context.state.columns or {}) do
    for _, node in ipairs(column) do
      if cursor[1] == node.row and node.map_row == (context.state.top or 1) + cursor[1] - 1 - (context.state.pad_y or 0)
        and cursor[2] >= node.col and cursor[2] < node.end_col then
        return node
      end
    end
  end
  return context.state.selected
end

local function icon(node)
  local ok, mini = pcall(require, 'mini.icons')
  if ok then
    local glyph, hl = mini.get(node.dir and 'directory' or 'file', node.path)
    return glyph .. ' ', hl
  end
  if node.dir then
    local glyph = context.config.icons and context.config.icons.directory or '󰉋'
    return glyph and glyph .. ' ' or '', 'Directory'
  end
  local available, devicons = pcall(require, 'nvim-web-devicons')
  if available then
    local glyph, hl = devicons.get_icon(node.name, nil, { default = true })
    return glyph and glyph .. ' ' or '', hl
  end
  return ' ', 'Normal'
end

function M.index_map()
  local s = context.state
  s.columns, s.nodes = {}, {}
  local next_row = 1
  local function visit(node, depth)
    node.depth = depth
    s.nodes[node.path] = node
    local column = s.columns[depth]
    if not column then column = { width = 4, byrow = {}, edges = {} }; s.columns[depth] = column end
    local glyph, hl = icon(node)
    node.glyph, node.icon_hl = glyph, hl
    node.text = (node.dir and (node.open and '⌄ ' or '› ') or '  ') .. glyph .. node.name:gsub('%c', ' ') .. (node.dir and '/' or '')
    column.width = math.min(28, math.max(column.width, vim.fn.strdisplaywidth(node.text)))
    local entries = node.dir and node.open and M.children(node) or {}
    for _, child in ipairs(entries) do visit(child, depth + 1) end
    if #entries > 0 then
      node.first_row, node.last_row = entries[1].map_row, entries[#entries].map_row
      node.map_row = math.floor((node.first_row + node.last_row) / 2)
      column.edges[#column.edges + 1] = node
    else
      node.map_row = next_row
      next_row = next_row + 1
    end
    column[#column + 1] = node
    column.byrow[node.map_row] = node
  end
  for _, node in ipairs(M.children(s.root)) do visit(node, 1) end
  if #s.columns == 0 then visit(s.root, 1) end
  s.total_rows = math.max(1, next_row - 1)
  for _, column in ipairs(s.columns) do
    table.sort(column, function(a, b) return a.map_row < b.map_row end)
    table.sort(column.edges, function(a, b) return a.first_row < b.first_row end)
    for i, node in ipairs(column) do node.index = i end
  end
  require('pathfinder.tree.watch').sync()
end

return M
