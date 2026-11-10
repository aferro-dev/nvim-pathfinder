local M = {}
local api = vim.api
local uv = vim.uv
local config = { hidden = true, ignored = { '.git' } }
local state
local ns = api.nvim_create_namespace('pathfinder')

local function children(node)
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
    if not vim.tbl_contains(config.ignored, name) and (config.hidden or name:sub(1, 1) ~= '.') then
      local path = vim.fs.joinpath(node.path, name)
      -- Symlink directories remain leaves: traversal never follows a cycle.
      table.insert(node.children, { name = name, path = path, dir = kind == 'directory', parent = node })
    end
  end
  table.sort(node.children, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name < b.name
  end)
  return node.children
end

local function current()
  if not state or not api.nvim_win_is_valid(state.win) then return end
  return state.rows[api.nvim_win_get_cursor(state.win)[1]]
end

local function render(target)
  local s = state
  local lines, rows, highlights = {}, {}, {}
  local selected = 1
  local function visit(node, prefix, last, root)
    local branch = root and '' or (last and '└─ ' or '├─ ')
    local icon = node.dir and (node.open and '▾ ' or '▸ ') or '  '
    local text = prefix .. branch .. icon .. node.name .. (node.dir and '/' or '')
    rows[#rows + 1], lines[#lines + 1] = node, text
    if target and node.path == target then selected = #rows end
    highlights[#highlights + 1] = { #rows - 1, #prefix + #branch, node.dir and 'Directory' or 'Normal' }
    if node.dir and node.open then
      local entries = children(node)
      local next_prefix = prefix .. (root and '' or (last and '   ' or '│  '))
      for i, child in ipairs(entries) do visit(child, next_prefix, i == #entries, false) end
    end
  end
  visit(s.root, '', true, true)
  s.rows = rows
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, hl in ipairs(highlights) do
    api.nvim_buf_set_extmark(s.buf, ns, hl[1], hl[2], { end_col = #lines[hl[1] + 1], hl_group = hl[3] })
  end
  vim.bo[s.buf].modifiable = false
  api.nvim_win_set_cursor(s.win, { selected, 0 })
  api.nvim_win_call(s.win, function() vim.cmd('normal! zz') end)
end

local function reveal(path)
  local node = state.root
  if path == node.path then return node end
  local relative = vim.fs.relpath(node.path, path)
  if not relative then return node end
  for part in relative:gmatch('[^/]+') do
    node.open = true
    local found
    for _, child in ipairs(children(node)) do if child.name == part then found = child; break end end
    if not found then return node end
    node = found
  end
  return node
end

function M.close()
  local s = state
  if not s then return end
  state = nil
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
  if api.nvim_win_is_valid(s.origin) then api.nvim_set_current_win(s.origin) end
end

function M.vertical(delta)
  local node = current()
  if not node or not node.parent then return end
  local siblings = children(node.parent)
  for i, sibling in ipairs(siblings) do
    if sibling == node then
      local index = math.max(1, math.min(#siblings, i + delta * vim.v.count1))
      render(siblings[index].path)
      return
    end
  end
end

function M.horizontal(delta)
  local node = current()
  if not node or not node.parent or not node.parent.parent then return end
  local parent = node.parent
  local dirs = vim.tbl_filter(function(n) return n.dir end, children(parent.parent))
  for i, dir in ipairs(dirs) do
    if dir == parent then
      local destination = dirs[i + delta * vim.v.count1]
      if not destination then return end
      destination.open = true
      local entries = children(destination)
      local index = 1
      for j, sibling in ipairs(children(parent)) do if sibling == node then index = j end end
      local target = entries[math.min(index, #entries)] or destination
      for _, entry in ipairs(entries) do if entry.name == node.name then target = entry; break end end
      render(target.path)
      return
    end
  end
end

function M.activate()
  local node = current()
  if not node then return end
  if node.dir then
    node.open = not node.open
    local entries = node.open and children(node) or {}
    render(entries[1] and entries[1].path or node.path)
  else
    local path = node.path
    M.close()
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    api.nvim_set_current_buf(buf)
  end
end

function M.parent()
  local node = current()
  if node and node.parent then render(node.parent.path) end
end

function M.refresh()
  local node = current()
  if not node then return end
  local opened = {}
  local function save(n)
    if n.open then opened[n.path] = true end
    for _, c in ipairs(n.children or {}) do save(c) end
  end
  save(state.root)
  state.root.children = nil
  local function restore(n)
    n.open = opened[n.path]
    if n.open then for _, c in ipairs(children(n)) do restore(c) end end
  end
  restore(state.root)
  render(reveal(node.path).path)
end

local function dimensions()
  return { relative = 'editor', row = 0, col = 0, width = vim.o.columns,
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 50 }
end

function M.open(opts)
  opts = opts or {}
  if state and api.nvim_win_is_valid(state.win) then M.close(); return end
  local file = api.nvim_buf_get_name(0)
  local cwd = uv.cwd()
  local start = file ~= '' and file or cwd
  local root = vim.fs.normalize(opts.root or vim.fs.root(start, { '.git' }) or cwd)
  if not opts.root and file ~= '' and not vim.fs.relpath(root, file) then root = vim.fs.dirname(file) end
  local buf = api.nvim_create_buf(false, true)
  local origin = api.nvim_get_current_win()
  local win = api.nvim_open_win(buf, true, dimensions())
  state = { buf = buf, win = win, origin = origin, rows = {},
    root = { path = root, name = root, dir = true, open = true } }
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'pathfinder'
  vim.bo[buf].swapfile = false
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 3
  local maps = {
    j = function() M.vertical(1) end, k = function() M.vertical(-1) end,
    h = function() M.horizontal(-1) end, l = function() M.horizontal(1) end,
    ['<Down>'] = function() M.vertical(1) end, ['<Up>'] = function() M.vertical(-1) end,
    ['<Left>'] = function() M.horizontal(-1) end, ['<Right>'] = function() M.horizontal(1) end,
    ['<CR>'] = M.activate, ['<BS>'] = M.parent, ['-'] = M.parent,
    q = M.close, ['<Esc>'] = M.close, ['<C-p>'] = M.close, R = M.refresh,
    ['<Space>'] = function()
      local node = current()
      if node and node.dir then node.open = not node.open; render(node.path) end
    end,
  }
  for key, action in pairs(maps) do vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true }) end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if state and state.buf == buf and api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, dimensions()) end
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if state and state.buf == buf then state = nil end
  end })
  render(reveal(file).path)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
end

return M
