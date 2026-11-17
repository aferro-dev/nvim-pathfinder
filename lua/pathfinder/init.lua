local M = {}
local api, uv = vim.api, vim.uv
local context = require('pathfinder.tree.context')
local model = require('pathfinder.tree.model')
local view = require('pathfinder.tree.view')
local navigation = require('pathfinder.tree.navigation')
local actions = require('pathfinder.tree.actions')
local current, children, index_map = model.current, model.children, model.index_map
local update_gitignore = model.update_gitignore
local render, dimensions = view.render, view.dimensions

-- Preserve the public API while each module owns one explorer responsibility.
for _, name in ipairs({ 'vertical', 'horizontal', 'parent', 'center', 'toggle_preview',
  'set_expanded', 'expand_all', 'collapse_all' }) do
  M[name] = navigation[name]
end
for _, name in ipairs({ 'create', 'delete', 'refresh', 'toggle_gitignore' }) do
  M[name] = actions[name]
end

function M.close()
  local s = context.state
  if not s then return end
  context.state = nil
  require('pathfinder.preview').close()
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_buf_is_valid(s.buf) then api.nvim_buf_delete(s.buf, { force = true }) end
  if api.nvim_win_is_valid(s.origin) then api.nvim_set_current_win(s.origin) end
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

function M.database()
  require('pathfinder.database').toggle({ root = context.state and context.state.root.path or nil })
end

function M.open(opts)
  opts = opts or {}
  if context.state and api.nvim_win_is_valid(context.state.win) then M.close(); return end
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
  context.state = { buf = buf, win = win, origin = origin, rows = {},
    root = { path = root, name = vim.fs.basename(root), dir = true, open = true } }
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'pathfinder'
  vim.bo[buf].swapfile = false
  require('pathfinder.theme').setup()
  local display_root = vim.fn.fnamemodify(root, ':~'):gsub('%%', '%%%%'):gsub('%%c', ' ')
  api.nvim_set_option_value('winbar', '%=%#PathfinderSelectedEdge#%#PathfinderBadge# 󰉋 pathfinder %#PathfinderSelectedEdge#%#PathfinderNormal#  %#PathfinderMuted#' .. display_root .. '  p preview  ·  D database  ·  zR/zM expand/collapse all  ·  q close%=', { win = win, scope = 'local' })
  api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = win, scope = 'local' })
  vim.wo[win].fillchars = 'eob: '
  vim.wo[win].cursorline = false
  vim.wo[win].sidescrolloff = 3
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 0
  require('pathfinder.tree.keymaps').attach(buf, M)
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if context.state and context.state.buf == buf and api.nvim_win_is_valid(win) then
      local node = current()
      api.nvim_win_set_config(win, dimensions())
      render(node and node.path)
    end
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if context.state and context.state.buf == buf then
      require('pathfinder.preview').close()
      context.state = nil
    end
  end })
  update_gitignore()
  local node = context.state.root
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
  context.config = vim.tbl_deep_extend('force', context.config, opts or {})
  require('pathfinder.tree.startup').setup(M)
end

return M
