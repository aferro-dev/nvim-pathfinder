local M = {}
local api = vim.api
local context = require('pathfinder.tree.context')
local ns = api.nvim_create_namespace('pathfinder')

local function fit(text, width)
  if vim.fn.strdisplaywidth(text) > width then
    while vim.fn.strdisplaywidth(text .. '…') > width do
      text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
    end
    text = text .. '…'
  end
  return text .. string.rep(' ', width - vim.fn.strdisplaywidth(text))
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
  local child = context.state.columns[parent.depth + 1].byrow[row]
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

function M.dimensions()
  local width = math.max(1, vim.o.columns)
  if context.state and context.state.preview_enabled then width = width - require('pathfinder.preview').width() end
  return { relative = 'editor', row = 0, col = 0, width = width,
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 50 }
end

function M.render(target)
  local s = context.state
  local selected = s.nodes[target] or (s.selected and s.nodes[s.selected.path]) or s.columns[1][1]
  s.selected = selected
  api.nvim_win_set_config(s.win, M.dimensions())
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
  if s.preview_enabled then require('pathfinder.preview').show(s.selected) end
end

return M
