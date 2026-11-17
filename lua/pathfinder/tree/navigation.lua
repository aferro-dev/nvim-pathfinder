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
  local function neighboring_branch(from)
    local target, distance
    for _, candidate in ipairs(context.state.columns[from.depth] or {}) do
      if candidate ~= from and candidate.dir and #children(candidate) > 0 then
        local d = math.abs(candidate.map_row - from.map_row)
        if not distance or d < distance then target, distance = candidate, d end
      end
    end
    if not target then return from end
    local bottom = target.map_row < from.map_row
    -- Follow the nearest edge through every nested directory, even when closed.
    while target.dir do
      local entries = children(target)
      if #entries == 0 then break end
      target.open = true
      target = entries[bottom and #entries or 1]
    end
    index_map()
    return target
  end
  for _ = 1, vim.v.count1 do
    local row = node.map_row
    if delta > 0 then
      if node.dir and #children(node) > 0 then
        node.open = true
        index_map()
        node = children(node)[1]
      else
        node = neighboring_branch(node)
      end
    else
      local column = context.state.columns[node.depth + delta]
      if not column then
        node = neighboring_branch(node)
      else
        local target, distance
        for _, candidate in ipairs(column) do
          local d = math.abs(candidate.map_row - row)
          if not distance or d < distance then target, distance = candidate, d end
        end
        node = target
      end
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
