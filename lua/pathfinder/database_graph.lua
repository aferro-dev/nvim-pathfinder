local M = {}
local function clean(text) return (tostring(text):gsub('%c', ' ')) end
local function fit(text, width)
  text = clean(text)
  if vim.fn.strdisplaywidth(text) > width then
    while vim.fn.strdisplaywidth(text .. '…') > width do text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1) end
    text = text .. '…'
  end
  return text .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(text)))
end
local function short(name) return (name:gsub('^public%.', '')) end

-- An undirected breadth-first layering keeps every association in its own gutter:
-- connected tables are either in adjacent layers or the same layer, never behind a box.
function M.render(schema, viewport, expanded, selected, viewport_height)
  if #schema == 0 then return { 'No visible tables. Press I to restore hidden tables.' }, {}, {} end
  expanded, selected = expanded or {}, selected or 1
  local byname, adjacency, edges, degree = {}, {}, {}, {}
  for i, tbl in ipairs(schema) do byname[tbl.name], adjacency[i], degree[i] = i, {}, 0 end
  for i, tbl in ipairs(schema) do
    local pairs_seen = {}
    for _, fk in ipairs(tbl.foreign_keys) do
      local target = byname[fk.target_table]
      if target and not pairs_seen[target] then
        pairs_seen[target] = true
        edges[#edges + 1] = { from = i, to = target }
        adjacency[i][#adjacency[i] + 1] = target
        adjacency[target][#adjacency[target] + 1] = i
        degree[i], degree[target] = degree[i] + 1, degree[target] + 1
      end
    end
  end
  local rank, layers = {}, {}
  local function component(root)
    local queue, head = { root }, 1
    rank[root] = 1
    while head <= #queue do
      local i = queue[head]; head = head + 1
      local depth = rank[i]
      layers[depth] = layers[depth] or {}
      layers[depth][#layers[depth] + 1] = i
      for _, target in ipairs(adjacency[i]) do
        if not rank[target] then rank[target] = depth + 1; queue[#queue + 1] = target end
      end
    end
  end
  while true do
    local root
    for i = 1, #schema do if not rank[i] and (not root or degree[i] > degree[root]) then root = i end end
    if not root then break end
    component(root)
  end
  local boxes, widths, heights, positions, related = {}, {}, {}, {}, {}
  for _, edge in ipairs(edges) do
    if edge.from == selected then related[edge.to] = true end
    if edge.to == selected then related[edge.from] = true end
  end
  for depth, layer in ipairs(layers) do
    widths[depth], heights[depth] = 18, 0
    for _, i in ipairs(layer) do
      local tbl, fields = schema[i], {}
      local title = (expanded[tbl.name] and '⌄ ' or '› ') .. short(tbl.name)
      local width = math.min(42, math.max(18, vim.fn.strdisplaywidth(title) + 4))
      if expanded[tbl.name] then
        local foreign = {}
        for _, fk in ipairs(tbl.foreign_keys) do foreign[fk.column] = true end
        for _, field in ipairs(tbl.columns) do
          local kind = field.type:gsub('timestamp with time zone', 'timestamptz'):gsub('timestamp without time zone', 'timestamp'):gsub('character varying', 'varchar')
          local text = (field.pk and 'PK ' or '') .. (foreign[field.name] and 'FK ' or '') .. field.name .. ': ' .. kind .. (field.nullable and ' ?' or '')
          fields[#fields + 1] = text
          width = math.min(48, math.max(width, vim.fn.strdisplaywidth(text) + 4))
        end
      end
      boxes[i] = { title = title, fields = fields, height = #fields > 0 and #fields + 4 or 3, gap = 1 }
      widths[depth] = math.max(widths[depth], width)
      heights[depth] = heights[depth] + boxes[i].height + boxes[i].gap
    end
  end
  local gap, width_sum = 8, 0
  for _, width in ipairs(widths) do width_sum = width_sum + width end
  if #layers > 1 then
    gap = math.max(gap, math.floor(((viewport or 120) * 0.9 - width_sum - 8) / (#layers - 1)))
  end
  local total_width = width_sum + (#layers - 1) * gap + 8
  local x = math.max(1, math.floor(((viewport or 120) - total_width) / 2) + 1)
  local maxheight = math.max(unpack(heights))
  local target_height = maxheight
  if viewport_height and maxheight <= viewport_height then
    target_height = math.max(maxheight, math.floor(viewport_height * 0.85))
  end
  for depth, layer in ipairs(layers) do
    local spare = target_height - heights[depth]
    local spread = viewport_height and maxheight <= viewport_height and #layer > 1
    local y = spread and 1 or math.floor(spare / 2) + 1
    for index, i in ipairs(layer) do
      local box = boxes[i]
      local offset = spread and math.floor((index - 1) * spare / (#layer - 1)) or 0
      box.x, box.y, box.width = x, y + offset, widths[depth]
      positions[i] = { row = box.y + (box.height == 1 and 0 or 1), col = x + 1, top = box.y, bottom = box.y + box.height - 1, width = box.width }
      y = y + box.height + box.gap
    end
    x = x + widths[depth] + gap
  end
  local canvas, lastrow, lastcol = {}, 0, 0
  local function cell(xc, yc, text, group, mask)
    canvas[yc] = canvas[yc] or {}
    canvas[yc][xc] = { text = text, group = group, mask = mask }
    lastrow, lastcol = math.max(lastrow, yc), math.max(lastcol, xc)
  end
  local glyphs = { [1] = '│', [2] = '─', [4] = '│', [8] = '─', [5] = '│', [10] = '─',
    [3] = '╰', [6] = '╭', [9] = '╯', [12] = '╮', [7] = '├', [11] = '┴', [13] = '┤', [14] = '┬', [15] = '┼' }
  local function wire(xc, yc, mask, active)
    local old = canvas[yc] and canvas[yc][xc]
    local merged = bit.bor(mask, old and old.mask or 0)
    cell(xc, yc, glyphs[merged] or '─', active and 'DiagnosticInfo' or old and old.group or 'PathfinderConnector', merged)
  end
  local function segment(x1, y1, x2, y2, active)
    local dx, dy = x2 == x1 and 0 or (x2 > x1 and 1 or -1), y2 == y1 and 0 or (y2 > y1 and 1 or -1)
    local forward = dx == 1 and 2 or dx == -1 and 8 or dy == 1 and 4 or 1
    local reverse = dx == 1 and 8 or dx == -1 and 2 or dy == 1 and 1 or 4
    while x1 ~= x2 or y1 ~= y2 do
      wire(x1, y1, forward, active)
      x1, y1 = x1 + dx, y1 + dy
      wire(x1, y1, reverse, active)
    end
  end
  local arrows = {}
  -- Render selected relationships last, so they remain visible at crossings.
  table.sort(edges, function(a, b)
    local aa, bb = a.from == selected or a.to == selected, b.from == selected or b.to == selected
    if aa ~= bb then return not aa end
    if a.from ~= b.from then return a.from < b.from end
    return a.to < b.to
  end)
  for n, edge in ipairs(edges) do
    local a, b = boxes[edge.from], boxes[edge.to]
    local active = edge.from == selected or edge.to == selected
    local ax, bx, ay, by = a.x + a.width, b.x - 1, a.y + (a.height == 1 and 0 or 1), b.y + (b.height == 1 and 0 or 1)
    local lane
    if rank[edge.from] < rank[edge.to] then lane = ax + 1 + (n % (gap - 3))
    elseif rank[edge.from] > rank[edge.to] then
      ax, bx = a.x - 1, b.x + b.width
      lane = bx + 1 + (n % (gap - 3))
    else
      bx = b.x + b.width
      lane = math.max(ax, bx) + 1 + (n % 5)
      if edge.from == edge.to then bx, by = b.x + math.floor(b.width / 2), a.y + a.height end
    end
    segment(ax, ay, lane, ay, active)
    segment(lane, ay, lane, by, active)
    segment(lane, by, bx, by, active)
    arrows[#arrows + 1] = { x = bx, y = by, text = edge.from == edge.to and '▲' or bx < b.x and '▶' or '◀', active = active }
  end
  local function text(xc, yc, value, group)
    for char in value:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
      local w = vim.fn.strdisplaywidth(char)
      cell(xc, yc, char, group)
      for extra = 1, w - 1 do cell(xc + extra, yc, '', group) end
      xc = xc + w
    end
  end
  for i, box in ipairs(boxes) do
    local group = i == selected and 'PathfinderSelected' or related[i] and 'DiagnosticInfo' or 'PathfinderBorder'
    local title_group = i == selected and 'PathfinderDatabaseSelected' or 'PathfinderDatabaseTitle'
    local w = box.width - 2
    if box.height == 1 then
      text(box.x, box.y, '│ ' .. fit(box.title, w - 2) .. ' │', group)
    else
      text(box.x, box.y, '╭' .. string.rep('─', w) .. '╮', group)
      text(box.x, box.y + 1, '│ ' .. fit(box.title, w - 2) .. ' │', group)
      text(box.x + 2, box.y + 1, fit(box.title, w - 2), title_group)
      local y = box.y + 2
      if #box.fields > 0 then
        text(box.x, y, '├' .. string.rep('─', w) .. '┤', group); y = y + 1
        for _, field in ipairs(box.fields) do text(box.x, y, '│ ' .. fit(field, w - 2) .. ' │', 'Normal'); y = y + 1 end
      end
      text(box.x, y, '╰' .. string.rep('─', w) .. '╯', group)
    end
  end
  for _, arrow in ipairs(arrows) do cell(arrow.x, arrow.y, arrow.text, arrow.active and 'DiagnosticInfo' or 'PathfinderConnector') end
  local lines, marks = {}, {}
  for row = 1, lastrow do
    local parts, bytes = {}, 0
    local run, start
    for col = 1, lastcol do
      local entry = canvas[row] and canvas[row][col]
      local char, group = entry and entry.text or ' ', entry and entry.group
      if group ~= run then
        if run then marks[#marks + 1] = { row - 1, start, bytes, run } end
        run, start = group, bytes
      end
      parts[#parts + 1], bytes = char, bytes + #char
    end
    if run then marks[#marks + 1] = { row - 1, start, bytes, run } end
    lines[row] = table.concat(parts)
  end
  local first = 1
  while first < #lines and not lines[first]:find('%S') do first = first + 1 end
  if first > 1 then
    lines = vim.list_slice(lines, first)
    for _, pos in ipairs(positions) do pos.row, pos.top, pos.bottom = pos.row - first + 1, pos.top - first + 1, pos.bottom - first + 1 end
    for _, mark in ipairs(marks) do mark[1] = mark[1] - first + 1 end
  end
  return lines, positions, marks
end

function M.details(tbl, schema, database_kind)
  if database_kind == 'redis' then
    return { '  Redis · Keyspace', '', '  v: browse keys · edit strings · delete complete keys',
      '  Types: string, hash, list, set, sorted set, stream.',
      '  TTL is in seconds; -1 means no expiry.',
      '  Values are previews: 100 entries or 16 KiB per string.',
      '  Partial previews cannot be edited or deleted.',
      '  String updates retain TTL and check for concurrent changes.',
      '  Binary keys and values use base64 objects.',
      '  SCAN pages are a live view; changes can move keys between pages.' }
  end
  if database_kind == 'mongo' then
    local lines = { '  ' .. clean(tbl.name), '', '  COLLECTION · MongoDB',
      '  Fields observed in ' .. tostring(tbl.sample_size or 0) .. ' documents (limit 50).',
      '  Sampled types are not schema constraints.', '', '  FIELDS / BSON TYPES' }
    for _, col in ipairs(tbl.columns) do
      lines[#lines + 1] = '  ' .. clean(col.name) .. '  :  ' .. clean(col.type)
    end
    if #tbl.columns == 0 then lines[#lines + 1] = '  No fields observed; the collection may be empty.' end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '  INDEXES'
    for _, index in ipairs(tbl.indexes or {}) do
      lines[#lines + 1] = '  ' .. clean(index.name) .. (index.unique and ' [unique]' or '')
      lines[#lines + 1] = '    ' .. clean(index.keys)
    end
    if #(tbl.indexes or {}) == 0 then lines[#lines + 1] = '  No indexes.' end
    lines[#lines + 1] = ''
    lines[#lines + 1] = '  v: browse documents'
    return lines
  end
  local foreign, name_width, type_width = {}, 6, 4
  for _, fk in ipairs(tbl.foreign_keys) do foreign[fk.column] = true end
  for _, col in ipairs(tbl.columns) do name_width = math.max(name_width, vim.fn.strdisplaywidth(clean(col.name))) end
  local function kind(col) return clean(col.type):gsub('timestamp with time zone', 'timestamptz'):gsub('timestamp without time zone', 'timestamp'):gsub('character varying', 'varchar') end
  for _, col in ipairs(tbl.columns) do type_width = math.max(type_width, vim.fn.strdisplaywidth(kind(col))) end
  local function aligned(value, width) return fit(value, width) end
  local lines = { '  ' .. clean(tbl.name), '', '  KEY    ' .. aligned('COLUMN', name_width) .. '  ' .. aligned('TYPE', type_width) .. '  NULL',
    '  ' .. string.rep('─', 7 + name_width + type_width + 8) }
  for _, col in ipairs(tbl.columns) do
    local key = (col.pk and 'PK' or '') .. (foreign[col.name] and (col.pk and '/FK' or 'FK') or '')
    lines[#lines + 1] = '  ' .. aligned(key, 5) .. '  ' .. aligned(clean(col.name), name_width) .. '  ' .. aligned(kind(col), type_width) .. '  ' .. (col.nullable and 'yes' or '—')
  end
  for _, outgoing in ipairs({ true, false }) do
    lines[#lines + 1] = ''
    lines[#lines + 1] = outgoing and '  REFERENCES →' or '  REFERENCED BY ←'
    local count = #lines
    for _, entry in ipairs(schema) do
      for _, fk in ipairs(entry.foreign_keys) do
        if outgoing and entry.name == tbl.name then
          lines[#lines + 1] = '  ' .. clean(fk.column) .. ' → ' .. clean(short(fk.target_table) .. '.' .. fk.target_column)
        elseif not outgoing and fk.target_table == tbl.name then
          lines[#lines + 1] = '  ' .. clean(short(entry.name) .. '.' .. fk.column) .. ' → ' .. clean(fk.target_column)
        end
      end
    end
    if #lines == count then lines[#lines + 1] = '  —' end
  end
  return lines
end
return M
