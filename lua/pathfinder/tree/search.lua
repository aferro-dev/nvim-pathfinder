local M = {}
local api = vim.api
local context = require('pathfinder.tree.context')
local model = require('pathfinder.tree.model')

function M.next(delta)
  local s = context.state
  if not s or not s.search_matches or #s.search_matches == 0 then return end
  local current = model.current()
  local index = delta > 0 and 0 or 1
  for i, node in ipairs(s.search_matches) do if node == current then index = i; break end end
  local node = s.search_matches[(index - 1 + delta) % #s.search_matches + 1]
  local parent = node.parent
  while parent do parent.open = true; parent = parent.parent end
  model.index_map()
  require('pathfinder.tree.view').render(node.path)
end

function M.update(query)
  local s = context.state
  if not s then return end
  if not s.search_expanded then
    s.search_expanded = {}
    local function save(node)
      s.search_expanded[node.path] = node.open
      for _, child in ipairs(node.children or {}) do save(child) end
    end
    save(s.root)
  end
  s.search_query = query:lower()
  s.search_matches = {}
  local function visit(directory)
    local found = false
    for _, node in ipairs(s.search_query == '' and (directory.children or {}) or model.children(directory)) do
      local matches = s.search_query ~= '' and node.name:lower():find(s.search_query, 1, true) ~= nil
      if matches then s.search_matches[#s.search_matches + 1] = node end
      local descendant = node.dir and visit(node)
      if node.dir then
        node.open = s.search_query == '' and s.search_expanded[node.path] or descendant or false
      end
      found = found or matches or descendant
    end
    return found
  end
  visit(s.root)
  if s.search_query == '' then s.search_expanded = nil end
  s.top = 1
  model.index_map()
  local first = s.search_matches[1]
  require('pathfinder.tree.view').render(first and first.path)
  return #s.search_matches
end

function M.open()
  local explorer = require('pathfinder')
  if not context.state then explorer.open() end
  local s = context.state
  if not s or s.search_prompt then return end
  s.search_prompt = true
  local previous = s.search_query or ''
  api.nvim_set_current_win(s.win)
  -- Draw the explorer before input() takes over the command line.
  -- This also flushes the redraw deferred by a silent key mapping.
  vim.cmd('redraw')
  local event = api.nvim_create_autocmd('CmdlineChanged', { callback = function()
    if context.state == s and vim.fn.getcmdtype() == '@' then
      M.update(vim.fn.getcmdline())
      -- input() otherwise defers the tree's screen update until it returns.
      vim.cmd('redraw')
    end
  end })
  local ok, query = pcall(vim.fn.input, { prompt = 'Find in Pathfinder: ', default = previous,
    cancelreturn = '\027' })
  api.nvim_del_autocmd(event)
  s.search_prompt = nil
  if context.state ~= s then return end
  M.update(ok and query ~= '\027' and query or previous)
  if #s.search_matches == 0 and s.search_query ~= '' then
    vim.notify('Pathfinder: no matching files or directories', vim.log.levels.INFO)
  end
end

return M
