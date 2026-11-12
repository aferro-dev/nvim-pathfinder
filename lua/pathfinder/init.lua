local M = {}
local api = vim.api
local uv = vim.uv
local config = { hidden = true, ignored = { '.git' }, default_explorer = true, gitignore = false }
local state
local ns = api.nvim_create_namespace('pathfinder')

local function update_gitignore()
  state.git_ignored = {}
  if not config.gitignore or vim.fn.executable('git') ~= 1 then return end
  local result = vim.system({ 'git', '-C', state.root.path, 'ls-files',
    '--others', '--ignored', '--exclude-standard', '--directory', '-z', '--', '.' },
    { text = false }):wait(5000)
  if result.code ~= 0 then return end -- Non-Git directories remain usable.
  for entry in (result.stdout or ''):gmatch('[^%z]+') do
    local path = vim.fs.normalize(vim.fs.joinpath(state.root.path, entry)):gsub('/$', '')
    state.git_ignored[path] = true
  end
end

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
      if not (config.gitignore and state.git_ignored and state.git_ignored[path]) then
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

local function current()
  if not state or not api.nvim_win_is_valid(state.win) then return end
  local cursor = api.nvim_win_get_cursor(state.win)
  for _, column in ipairs(state.columns or {}) do
    for _, node in ipairs(column) do
      if cursor[1] == node.row and node.map_row == (state.top or 1) + cursor[1] - 1 - (state.pad_y or 0)
        and cursor[2] >= node.col and cursor[2] < node.end_col then
        return node
      end
    end
  end
  return state.selected
end

local function fit(text, width)
  if vim.fn.strdisplaywidth(text) > width then
    while vim.fn.strdisplaywidth(text .. '…') > width do
      text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
    end
    text = text .. '…'
  end
  return text .. string.rep(' ', width - vim.fn.strdisplaywidth(text))
end

local function icon(node)
  local ok, mini = pcall(require, 'mini.icons')
  if ok then
    local glyph, hl = mini.get(node.dir and 'directory' or 'file', node.path)
    return glyph .. ' ', hl
  end
  if node.dir then
    local glyph = config.icons and config.icons.directory or '󰉋'
    return glyph and glyph .. ' ' or '', 'Directory'
  end
  local available, devicons = pcall(require, 'nvim-web-devicons')
  if available then
    local glyph, hl = devicons.get_icon(node.name, nil, { default = true })
    return glyph and glyph .. ' ' or '', hl
  end
  return ' ', 'Normal'
end

local function index_map()
  local s = state
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
    local entries = node.dir and node.open and children(node) or {}
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
  for _, node in ipairs(children(s.root)) do visit(node, 1) end
  if #s.columns == 0 then visit(s.root, 1) end
  s.total_rows = math.max(1, next_row - 1)
  for _, column in ipairs(s.columns) do
    table.sort(column, function(a, b) return a.map_row < b.map_row end)
    table.sort(column.edges, function(a, b) return a.first_row < b.first_row end)
    for i, node in ipairs(column) do node.index = i end
  end
end

local function connector(column, row)
  local edges = column.edges
  local low, high = 1, #edges
  while low <= high do
    local mid = math.floor((low + high) / 2)
    if edges[mid].last_row < row then low = mid + 1 else high = mid - 1 end
  end
  local parent = edges[low]
  if not parent or row < parent.first_row then return '   ' end
  local child = state.columns[parent.depth + 1].byrow[row]
  child = child and child.parent == parent
  if parent.first_row == parent.last_row then return '── ' end
  if row == parent.map_row then
    if row == parent.first_row then return '─┬─' end
    if row == parent.last_row then return '─┴─' end
    return child and '─┼─' or '─┤ '
  end
  if child then
    if row == parent.first_row then return ' ╭─' end
    if row == parent.last_row then return ' ╰─' end
    return ' ├─'
  end
  return ' │ '
end

local function render(target)
  local s = state
  local selected = s.nodes[target] or (s.selected and s.nodes[s.selected.path]) or s.columns[1][1]
  s.selected = selected
  local height = api.nvim_win_get_height(s.win)
  local width = api.nvim_win_get_width(s.win)
  local map_width = 0
  for _, column in ipairs(s.columns) do map_width = map_width + column.width + 2 end
  map_width = map_width + (#s.columns - 1) * 3
  local pad_x = math.max(0, math.floor((width - map_width) / 2))
  s.pad_y = math.max(0, math.floor((height - s.total_rows) / 2))
  local top = s.top or 1
  if selected.map_row < top then top = selected.map_row end
  if selected.map_row >= top + height then top = selected.map_row - height + 1 end
  s.top = math.max(1, math.min(top, math.max(1, s.total_rows - height + 1)))
  local lines, marks = {}, {}
  local ancestors, ancestor = {}, selected.parent
  while ancestor do ancestors[ancestor] = true; ancestor = ancestor.parent end
  for _ = 1, s.pad_y do lines[#lines + 1] = '' end
  for screen_row = s.pad_y + 1, math.min(height, s.pad_y + s.total_rows - s.top + 1) do
    local row = s.top + screen_row - 1 - s.pad_y
    local text = string.rep(' ', pad_x)
    for depth, column in ipairs(s.columns) do
      local node = column.byrow[row]
      local start = #text
      local content = node and node.text or ''
      local rounded = node and (node.dir or node == selected)
      local left, right = rounded and '' or ' ', rounded and '' or ' '
      local fitted = fit(content, column.width)
      local label = rounded and fitted or fitted:gsub(' +$', '')
      local tail = column.width - vim.fn.strdisplaywidth(label)
      text = text .. left .. label .. right
      local label_end = #text
      text = text .. string.rep(' ', tail)
      if node then
        node.row, node.col, node.end_col = screen_row, start, label_end
        node.cursor_col = start + #left
        local group = node == selected and 'PathfinderSelected'
          or ancestors[node] and 'PathfinderAncestor' or node.dir and 'PathfinderDirectory' or nil
        if group then
          marks[#marks + 1] = { screen_row - 1, start + #left, label_end - #right, group }
          local edge = node == selected and 'PathfinderSelectedEdge'
            or ancestors[node] and 'PathfinderAncestorEdge' or 'PathfinderDirectoryEdge'
          marks[#marks + 1] = { screen_row - 1, start, start + #left, edge }
          marks[#marks + 1] = { screen_row - 1, label_end - #right, label_end, edge }
        end
        if node.glyph ~= '' and node.icon_hl then
          local icon_start = node.cursor_col + #(node.dir and (node.open and '⌄ ' or '› ') or '  ')
          marks[#marks + 1] = { screen_row - 1, icon_start, icon_start + #node.glyph,
            node.icon_hl }
        end
      end
      if depth < #s.columns then
        local edge_start = #text
        text = text .. connector(column, row)
        marks[#marks + 1] = { screen_row - 1, edge_start, #text, 'PathfinderConnector' }
      end
    end
    lines[#lines + 1] = text
  end
  while #lines < height do lines[#lines + 1] = '' end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    api.nvim_buf_set_extmark(s.buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4], hl_mode = 'combine' })
  end
  vim.bo[s.buf].modifiable = false
  api.nvim_win_set_cursor(s.win, { selected.row, selected.cursor_col })
  api.nvim_win_call(s.win, function() vim.fn.winrestview({ topline = 1 }) end)
end

function M.close()
  local s = state
  if not s then return end
  state = nil
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
  if api.nvim_win_is_valid(s.origin) then api.nvim_set_current_win(s.origin) end
end

-- Cross neighboring branches, opening only the path needed to keep depth.
function M.vertical(delta)
  local node = current()
  if not node then return end
  for _ = 1, vim.v.count1 do
    local depth = node.depth
    local branch, candidate = node, nil
    while branch.parent do
      local siblings = children(branch.parent)
      for i, sibling in ipairs(siblings) do
        if sibling == branch then candidate = siblings[i + delta]; break end
      end
      if candidate then break end
      branch = branch.parent
    end
    if not candidate then break end
    local candidate_depth = branch.depth
    while candidate_depth < depth and candidate.dir do
      candidate.open = true
      local entries = children(candidate)
      local child = entries[delta > 0 and 1 or #entries]
      if not child then break end
      candidate = child
      candidate_depth = candidate_depth + 1
    end
    index_map()
    node = candidate
  end
  render(node.path)
end

function M.horizontal(delta)
  local node = current()
  if not node then return end
  local row = node.map_row
  for _ = 1, vim.v.count1 do
    if delta > 0 then
      if not node.dir then break end
      node.open = true
      index_map()
      node = children(node)[1] or node
    else
      local column = state.columns[node.depth + delta]
      if not column then break end
      local target, distance
      for _, candidate in ipairs(column) do
        local d = math.abs(candidate.map_row - row)
        if not distance or d < distance then target, distance = candidate, d end
      end
      node = target
    end
  end
  render(node.path)
end

function M.set_expanded(expanded)
  local node = current()
  if not node or not node.dir then return end
  local was_open = node.open
  node.open = expanded == nil and not node.open or expanded == true
  index_map()
  local first_child = node.open and not was_open and children(node)[1]
  render(first_child and first_child.path or node.path)
end

function M.expand_all()
  local node = current()
  if not node then return end
  local pending = { state.root }
  while #pending > 0 do
    local directory = table.remove(pending)
    directory.open = true
    for _, child in ipairs(children(directory)) do
      if child.dir then pending[#pending + 1] = child end
    end
  end
  index_map()
  render(node.path)
end

function M.collapse_all()
  local node = current()
  if not node then return end
  while node.parent and node.parent ~= state.root do node = node.parent end
  local function collapse(directory)
    for _, child in ipairs(directory.children or {}) do
      child.open = false
      if child.dir then collapse(child) end
    end
  end
  collapse(state.root)
  index_map()
  render(node.path)
end

function M.activate()
  local node = current()
  if not node then return end
  if node.dir then
    M.set_expanded()
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

local function reload(path, reveal)
  update_gitignore()
  local opened = {}
  for name, entry in pairs(state.nodes) do if entry.open then opened[name] = true end end
  if reveal then
    local parent = vim.fs.dirname(path)
    while parent and (parent == state.root.path or vim.fs.relpath(state.root.path, parent)) do
      opened[parent] = true
      if parent == state.root.path then break end
      parent = vim.fs.dirname(parent)
    end
  end
  state.root.children = nil
  local function restore(node)
    node.open = opened[node.path] or node == state.root
    if node.open then for _, child in ipairs(children(node)) do restore(child) end end
  end
  restore(state.root)
  index_map()
  while path ~= state.root.path and not state.nodes[path] do path = vim.fs.dirname(path) end
  render(path)
end

function M.refresh()
  local node = current()
  if node then reload(node.path) end
end

local function action_error(message)
  vim.notify('Pathfinder: ' .. message, vim.log.levels.ERROR)
end

function M.create()
  local node = current()
  if not node then return end
  local session = state
  local base = node.dir and node.path or node.parent.path
  vim.ui.input({ prompt = 'Create in ' .. base .. ' (end with / for a directory): ' }, function(name)
    if state ~= session or not name or name == '' then return end
    local directory = name:sub(-1) == '/'
    local path = vim.fs.normalize(vim.fs.joinpath(base, name))
    if name:sub(1, 1) == '/' or name:find('%c') or path == base or not vim.fs.relpath(base, path) then
      action_error('Enter a relative path inside the selected directory')
      return
    end
    if uv.fs_lstat(path) then action_error('Already exists: ' .. path); return end
    local parent = vim.fs.dirname(path)
    local ancestor = parent
    while not uv.fs_lstat(ancestor) and ancestor ~= vim.fs.dirname(ancestor) do ancestor = vim.fs.dirname(ancestor) end
    local real_base, real_ancestor = uv.fs_realpath(base), uv.fs_realpath(ancestor)
    if not real_base or not real_ancestor or (real_ancestor ~= real_base and not vim.fs.relpath(real_base, real_ancestor)) then
      action_error('The destination resolves outside the selected directory')
      return
    end
    local ok, err = pcall(vim.fn.mkdir, directory and path or parent, 'p')
    if not ok then action_error(tostring(err)); return end
    if not directory then
      local fd, open_err = uv.fs_open(path, 'wx', 420)
      if not fd then action_error(tostring(open_err)); return end
      uv.fs_close(fd)
    elseif not uv.fs_stat(path) then
      action_error('Could not create directory: ' .. path)
      return
    end
    reload(path, true)
  end)
end

function M.delete()
  local node = current()
  if not node or node == state.root then return end
  local session = state
  local path, parent = node.path, node.parent.path
  local prompt = 'Delete ' .. path .. (node.dir and ' and all its contents?' or '?')
  vim.ui.select({ 'Cancel', 'Delete' }, { prompt = prompt }, function(choice)
    if state ~= session or choice ~= 'Delete' then return end
    local buffers = {}
    for _, buf in ipairs(api.nvim_list_bufs()) do
      local name = api.nvim_buf_get_name(buf)
      if name == path or (node.dir and vim.fs.relpath(path, name)) then
        if vim.bo[buf].modified then
          action_error('Save or discard unsaved changes before deleting: ' .. name)
          return
        end
        buffers[#buffers + 1] = buf
      end
    end
    -- Recheck the type: a directory replaced by a symlink is unlinked, not traversed.
    local stat = uv.fs_lstat(path)
    if not stat then action_error('No longer exists: ' .. path); return end
    local ok, result = pcall(vim.fn.delete, path, stat.type == 'directory' and 'rf' or '')
    if not ok or result ~= 0 then action_error('Could not delete: ' .. path); return end
    for _, buf in ipairs(buffers) do
      if api.nvim_buf_is_valid(buf) then pcall(api.nvim_buf_delete, buf, {}) end
    end
    reload(parent)
  end)
end

local function dimensions()
  return { relative = 'editor', row = 0, col = 0, width = math.max(1, vim.o.columns),
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 50 }
end

function M.toggle_gitignore()
  local node = current()
  if not node then return end
  config.gitignore = not config.gitignore
  reload(node.path)
  api.nvim_win_set_config(state.win, dimensions())
end

function M.database()
  require('pathfinder.database').toggle({ root = state and state.root.path or nil })
end

function M.open(opts)
  opts = opts or {}
  if state and api.nvim_win_is_valid(state.win) then M.close(); return end
  local file = api.nvim_buf_get_name(0)
  local cwd = uv.cwd()
  local start = file ~= '' and file or cwd
  local root = vim.fs.normalize(opts.root or vim.fs.root(start, { '.git' }) or cwd)
  if not opts.root and file ~= '' and not vim.fs.relpath(root, file) then root = vim.fs.dirname(file) end
  local stat = uv.fs_stat(root)
  if not stat or stat.type ~= 'directory' then
    vim.notify('Pathfinder: directory not found: ' .. root, vim.log.levels.ERROR)
    return
  end
  local buf = api.nvim_create_buf(false, true)
  local origin = api.nvim_get_current_win()
  local win = api.nvim_open_win(buf, true, dimensions())
  state = { buf = buf, win = win, origin = origin, rows = {},
    root = { path = root, name = vim.fs.basename(root), dir = true, open = true } }
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'pathfinder'
  vim.bo[buf].swapfile = false
  require('pathfinder.theme').setup()
  local display_root = vim.fn.fnamemodify(root, ':~'):gsub('%%', '%%%%'):gsub('%%c', ' ')
  api.nvim_set_option_value('winbar', '%=%#PathfinderSelectedEdge#%#PathfinderBadge# 󰉋 pathfinder %#PathfinderSelectedEdge#%#PathfinderNormal#  %#PathfinderMuted#' .. display_root .. '  D database  ·  zR/zM expand/collapse all  ·  q close%=', { win = win, scope = 'local' })
  api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = win, scope = 'local' })
  vim.wo[win].fillchars = 'eob: '
  vim.wo[win].cursorline = false
  vim.wo[win].sidescrolloff = 3
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 0
  local maps = {
    j = function() M.vertical(1) end, k = function() M.vertical(-1) end,
    h = function() M.horizontal(-1) end, l = function() M.horizontal(1) end,
    ['<Down>'] = function() M.vertical(1) end, ['<Up>'] = function() M.vertical(-1) end,
    ['<Left>'] = function() M.horizontal(-1) end, ['<Right>'] = function() M.horizontal(1) end,
    ['<CR>'] = M.activate, ['<BS>'] = M.parent, ['-'] = M.parent,
    q = M.close, ['<Esc>'] = M.close, ['<C-p>'] = M.close, R = M.refresh,
    ['<Space>'] = function() M.set_expanded() end,
    zo = function() M.set_expanded(true) end,
    zc = function() M.set_expanded(false) end,
    zR = M.expand_all, zM = M.collapse_all,
    a = M.create, d = M.delete, I = M.toggle_gitignore,
    D = M.database,

  }
  local descriptions = {
    j = 'Next node', k = 'Previous node', h = 'Previous column', l = 'Expand directory and select first child',
    ['<Down>'] = 'Next node', ['<Up>'] = 'Previous node',
    ['<Left>'] = 'Previous column', ['<Right>'] = 'Expand directory and select first child',
    ['<CR>'] = 'Open file or toggle directory', ['<Space>'] = 'Toggle directory',
    ['<BS>'] = 'Select parent', ['-'] = 'Select parent',
    q = 'Close Pathfinder', ['<Esc>'] = 'Close Pathfinder', ['<C-p>'] = 'Close Pathfinder',
    R = 'Refresh tree', zo = 'Expand node', zc = 'Collapse node',
    zR = 'Expand all nodes', zM = 'Collapse all nodes',
    a = 'Create file or directory', d = 'Delete file or directory', I = 'Toggle Git-ignored files',
    D = 'Switch to database UML',
  }
  for key, action in pairs(maps) do
    vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true, desc = descriptions[key] })
  end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if state and state.buf == buf and api.nvim_win_is_valid(win) then
      local node = current()
      api.nvim_win_set_config(win, dimensions())
      render(node and node.path)
    end
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if state and state.buf == buf then state = nil end
  end })
  update_gitignore()
  local node = state.root
  local relative = vim.fs.relpath(root, file)
  if relative then
    for part in relative:gmatch('[^/]+') do
      node.open = true
      local found
      for _, child in ipairs(children(node)) do if child.name == part then found = child; break end end
      if not found then break end
      node = found
    end
  end
  index_map()
  render(file)
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
  local group = api.nvim_create_augroup('PathfinderExplorer', { clear = true })
  if not config.default_explorer then return end
  vim.g.loaded_netrw = 1
  vim.g.loaded_netrwPlugin = 1

  local function open_directory(buf, win)
    if state or not api.nvim_buf_is_valid(buf) or not api.nvim_win_is_valid(win)
      or api.nvim_win_get_buf(win) ~= buf then return end
    local path = api.nvim_buf_get_name(buf)
    local stat = uv.fs_stat(path)
    if not stat or stat.type ~= 'directory' then return end
    api.nvim_set_current_win(win)
    -- Return to an ordinary empty buffer when the explorer is closed.
    api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
    M.open({ root = path })
  end

  api.nvim_create_autocmd('BufEnter', { group = group, callback = function(args)
    if vim.v.vim_did_enter == 0 then return end
    local win = api.nvim_get_current_win()
    vim.schedule(function() open_directory(args.buf, win) end)
  end })
  api.nvim_create_autocmd('VimEnter', { group = group, once = true, callback = function()
    local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    open_directory(buf, win)
    if not state and vim.fn.argc() == 0 and api.nvim_buf_get_name(buf) == ''
      and vim.bo[buf].buftype == '' and not vim.bo[buf].modified
      and api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == '' then
      M.open()
    end
  end })
  api.nvim_create_user_command('Explore', function(args)
    M.open({ root = args.args ~= '' and vim.fn.fnamemodify(args.args, ':p') or vim.fn.getcwd() })
  end, { nargs = '?', complete = 'dir', desc = 'Explore with Pathfinder', force = true })
end

return M
