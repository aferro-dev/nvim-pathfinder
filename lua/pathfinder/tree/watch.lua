local M = {}
local api, uv = vim.api, vim.uv
local context = require('pathfinder.tree.context')

function M.stop(session)
  local watch = session.watch
  if not watch then return end
  session.watch = nil
  for _, handle in pairs(watch.handles) do handle:stop(); handle:close() end
  watch.timer:stop()
  watch.timer:close()
  api.nvim_del_augroup_by_id(watch.group)
end

function M.sync()
  local session = context.state
  if not session then return end
  if not session.watch then
    local watch = { handles = {}, timer = uv.new_timer(),
      group = api.nvim_create_augroup('PathfinderWatch', { clear = true }) }
    session.watch = watch
    local function refresh()
      if context.state ~= session or session.watch ~= watch or not api.nvim_win_is_valid(session.win) then return end
      require('pathfinder.tree.actions').refresh()
      vim.cmd('redraw')
    end
    watch.changed = function()
      if session.watch ~= watch then return end
      watch.timer:start(100, 0, vim.schedule_wrap(refresh))
    end
    api.nvim_create_autocmd('FocusGained', { group = watch.group, callback = refresh })
  end
  local watch, wanted = session.watch, {}
  local function visit(node)
    if not node.dir or not node.children then return end
    wanted[node.path] = true
    for _, child in ipairs(node.children) do visit(child) end
  end
  visit(session.root)
  for path, handle in pairs(watch.handles) do
    if not wanted[path] then
      handle:stop(); handle:close()
      watch.handles[path] = nil
    end
  end
  for path in pairs(wanted) do
    if not watch.handles[path] then
      local handle = uv.new_fs_event()
      if handle then
        local ok = handle:start(path, {}, watch.changed)
        if ok then watch.handles[path] = handle else handle:close() end
      end
    end
  end
end

return M
