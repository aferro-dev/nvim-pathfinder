local M = {}
local api = vim.api
local context = require('pathfinder.tree.context')
local model = require('pathfinder.tree.model')
local current, children, index_map = model.current, model.children, model.index_map
local render = require('pathfinder.tree.view').render

function M.toggle_preview()
  local node = current()
  if not node then return end
  context.state.preview_enabled = not context.state.preview_enabled
  if not context.state.preview_enabled then require('pathfinder.preview').close() end
  render(node.path)
end

function M.center()
  local node = current()
  if not node then return end
  context.state.top = node.map_row - math.floor(api.nvim_win_get_height(context.state.win) / 2)
  render(node.path)
  api.nvim_win_call(context.state.win, function()
    local left = math.max(0, vim.fn.virtcol('.') - 1 - math.floor(api.nvim_win_get_width(context.state.win) / 2))
    vim.fn.winrestview({ topline = 1, leftcol = left })
  end)
end

-- Navigation axes are independent: vertical moves never change depth.
function M.vertical(delta)
  local node = current()
  if not node then return end
  local entries = {}
  local function collect(directory, depth)
    for _, entry in ipairs(children(directory)) do
      if depth == node.depth then entries[#entries + 1] = entry
      elseif entry.dir then collect(entry, depth + 1) end
    end
  end
  collect(context.state.root, 1)
  if #entries == 0 then return end
  local selected = 1
  for i, entry in ipairs(entries) do if entry == node then selected = i; break end end
  node = entries[(selected - 1 + delta * vim.v.count1) % #entries + 1]
  local ancestor = node.parent
  while ancestor do ancestor.open = true; ancestor = ancestor.parent end
  index_map()
  render(node.path)
end

-- Reveal only one path when the next depth is still hidden.
local function reveal_depth(depth, from)
  if context.state.columns[depth] then return true end
  local function path_to(directory, remaining)
    local entries = children(directory)
    if #entries == 0 then return end
    if remaining == 1 then return { directory } end
    for _, entry in ipairs(entries) do
      if entry.dir then
        local path = path_to(entry, remaining - 1)
        if path then table.insert(path, 1, directory); return path end
      end
    end
  end
  for level = depth - 1, 1, -1 do
    local best, distance
    for _, candidate in ipairs(context.state.columns[level] or {}) do
      if candidate.dir then
        local path = path_to(candidate, depth - level)
        local d = math.abs(candidate.map_row - from.map_row)
        if path and (not distance or d < distance) then best, distance = path, d end
      end
    end
    if best then
      for _, directory in ipairs(best) do directory.open = true end
      index_map()
      return true
    end
  end
  return false
end

function M.horizontal(delta)
  local node = current()
  if not node then return end
  for _ = 1, vim.v.count1 do
    local depth = node.depth + delta
    if delta > 0 then
      if node.dir and #children(node) > 0 then node.open = true; index_map() end
      if not reveal_depth(depth, node) then depth = 1 end
    elseif depth < 1 then
      depth = #context.state.columns
      while reveal_depth(depth + 1, node) do depth = depth + 1 end
    end
    local target, distance
    for _, candidate in ipairs(context.state.columns[depth] or {}) do
      local d = math.abs(candidate.map_row - node.map_row)
      if not distance or d < distance then target, distance = candidate, d end
    end
    node = target or node
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
  local pending = { context.state.root }
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
  while node.parent and node.parent ~= context.state.root do node = node.parent end
  local function collapse(directory)
    for _, child in ipairs(directory.children or {}) do
      child.open = false
      if child.dir then collapse(child) end
    end
  end
  collapse(context.state.root)
  index_map()
  render(node.path)
end

function M.parent()
  local node = current()
  if node and node.parent then render(node.parent.path) end
end

return M
