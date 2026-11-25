local M = {}
local api, uv = vim.api, vim.uv
local context = require('pathfinder.tree.context')
local model = require('pathfinder.tree.model')
local current, children, index_map = model.current, model.children, model.index_map
local update_gitignore = model.update_gitignore
local view = require('pathfinder.tree.view')
local render, dimensions = view.render, view.dimensions

local function reload(path, reveal)
  update_gitignore()
  local opened = {}
  for name, entry in pairs(context.state.nodes) do if entry.open then opened[name] = true end end
  if reveal then
    local parent = vim.fs.dirname(path)
    while parent and (parent == context.state.root.path or vim.fs.relpath(context.state.root.path, parent)) do
      opened[parent] = true
      if parent == context.state.root.path then break end
      parent = vim.fs.dirname(parent)
    end
  end
  context.state.root.children = nil
  local function restore(node)
    node.open = opened[node.path] or node == context.state.root
    if node.open then for _, child in ipairs(children(node)) do restore(child) end end
  end
  restore(context.state.root)
  index_map()
  while path ~= context.state.root.path and not context.state.nodes[path] do path = vim.fs.dirname(path) end
  render(path)
end

function M.refresh()
  local node = current()
  if node then
    local query = context.state.search_query
    reload(node.path)
    if query and query ~= '' then
      require('pathfinder.tree.search').update(query)
      render(node.path)
    end
  end
end

local function action_error(message)
  vim.notify('Pathfinder: ' .. message, vim.log.levels.ERROR)
end

function M.create()
  local node = current()
  if not node then return end
  local session = context.state
  local base = node.dir and node.path or node.parent.path
  vim.ui.input({ prompt = 'Create in ' .. base .. ' (end with / for a directory): ' }, function(name)
    if context.state ~= session or not name or name == '' then return end
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

function M.rename()
  local node = current()
  if not node or node == context.state.root then return end
  local session, old_path = context.state, node.path
  vim.ui.input({ prompt = 'Rename: ', default = node.name }, function(name)
    if context.state ~= session or not name or name == '' or name == node.name then return end
    if name == '.' or name == '..' or name:find('/', 1, true) or name:find('%c') then
      action_error('Enter a file or directory name without a path')
      return
    end
    local new_path = vim.fs.joinpath(node.parent.path, name)
    if uv.fs_lstat(new_path) then action_error('Already exists: ' .. new_path); return end
    local stat = uv.fs_lstat(old_path)
    if not stat then action_error('No longer exists: ' .. old_path); return end
    local buffers = {}
    for _, buf in ipairs(api.nvim_list_bufs()) do
      local old_name = api.nvim_buf_get_name(buf)
      local relative = stat.type == 'directory' and vim.fs.relpath(old_path, old_name)
      if old_name == old_path or relative then
        local new_name = relative and vim.fs.joinpath(new_path, relative) or new_path
        local existing = vim.fn.bufnr(new_name)
        if existing ~= -1 and existing ~= buf then
          action_error('A buffer already exists for: ' .. new_name)
          return
        end
        buffers[#buffers + 1] = { buf = buf, old = old_name, new = new_name }
      end
    end
    local ok, err = uv.fs_rename(old_path, new_path)
    if not ok then action_error(tostring(err)); return end
    for _, entry in ipairs(buffers) do
      local renamed, rename_err = pcall(api.nvim_buf_set_name, entry.buf, entry.new)
      if not renamed then
        uv.fs_rename(new_path, old_path)
        for _, rollback in ipairs(buffers) do pcall(api.nvim_buf_set_name, rollback.buf, rollback.old) end
        action_error(tostring(rename_err))
        return
      end
    end
    -- Preserve expanded descendants under the new directory name.
    local opened = {}
    for path, entry in pairs(session.nodes) do
      local relative = stat.type == 'directory' and vim.fs.relpath(old_path, path)
      if path == old_path or relative then
        opened[relative and vim.fs.joinpath(new_path, relative) or new_path] = entry
      end
    end
    for path, entry in pairs(opened) do session.nodes[path] = entry end
    reload(new_path, true)
    if session.search_query and session.search_query ~= '' then
      require('pathfinder.tree.search').update(session.search_query)
      render(new_path)
    end
  end)
end

function M.delete()
  local node = current()
  if not node or node == context.state.root then return end
  local session = context.state
  local path, parent = node.path, node.parent.path
  local prompt = 'Delete ' .. path .. (node.dir and ' and all its contents?' or '?')
  local choice = vim.fn.confirm(prompt, '&Yes\n&No', 2)
  if context.state ~= session or choice ~= 1 then return end
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

end

function M.toggle_gitignore()
  local node = current()
  if not node then return end
  context.config.gitignore = not context.config.gitignore
  reload(node.path)
  api.nvim_win_set_config(context.state.win, dimensions())
end

return M
