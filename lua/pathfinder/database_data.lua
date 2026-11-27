local M = {}
local api = vim.api
local client = require('pathfinder.database_client')
local session
local ns = api.nvim_create_namespace('pathfinder_database_data')
local selection_ns = api.nvim_create_namespace('pathfinder_database_data_selection')

local function clean(value) return tostring(value):gsub('%c', ' ') end

-- Keep numeric BSON payloads as strings to preserve int64/decimal precision.
function M.readable(value)
  if value == vim.NIL or type(value) ~= 'table' then return value end
  local key, payload = next(value)
  if key and next(value, key) == nil then
    if key == '$oid' or key == '$numberInt' or key == '$numberLong' or key == '$numberDouble' or key == '$numberDecimal' then
      return tostring(payload)
    elseif key == '$date' then
      if type(payload) == 'string' then return payload end
      local ms = tonumber(type(payload) == 'table' and payload['$numberLong'] or payload)
      if ms then
        local seconds = math.floor(ms / 1000)
        local ok, date = pcall(os.date, '!%Y-%m-%dT%H:%M:%S', seconds)
        if ok and date then return date .. string.format('.%03dZ', ms - seconds * 1000) end
      end
    elseif key == '$binary' and type(payload) == 'table' then
      return 'Binary(' .. tostring(payload.subType) .. '): ' .. tostring(payload.base64)
    elseif key == '$regularExpression' and type(payload) == 'table' then
      return '/' .. tostring(payload.pattern) .. '/' .. tostring(payload.options)
    elseif key == '$timestamp' and type(payload) == 'table' then
      return 'Timestamp(' .. tostring(payload.t) .. ', ' .. tostring(payload.i) .. ')'
    elseif key == '$minKey' then return 'MinKey'
    elseif key == '$maxKey' then return 'MaxKey' end
  end
  local result = vim.islist(value) and {} or vim.empty_dict()
  for name, entry in pairs(value) do result[name] = M.readable(entry) end
  return result
end

local function cell(value)
  if value == vim.NIL then return 'null' end
  if value == nil then return '—' end
  if type(value) == 'table' then return vim.json.encode(value) end
  return clean(value)
end

local function fit(value, width)
  value = clean(value)
  if vim.fn.strdisplaywidth(value) > width then
    value = vim.fn.strcharpart(value, 0, width)
    while vim.fn.strdisplaywidth(value) > width - 1 do
      value = vim.fn.strcharpart(value, 0, vim.fn.strchars(value) - 1)
    end
    value = value .. '…'
  end
  return value .. string.rep(' ', width - vim.fn.strdisplaywidth(value))
end

-- Format JSON without changing BSON wrappers, nulls, or numeric values.
function M.pretty(value)
  local encoded = vim.json.encode(value)
  local out, depth, quoted, escaped = {}, 0, false, false
  for i = 1, #encoded do
    local c = encoded:sub(i, i)
    if quoted then
      out[#out + 1] = c
      if escaped then escaped = false elseif c == '\\' then escaped = true elseif c == '"' then quoted = false end
    elseif c == '"' then quoted = true; out[#out + 1] = c
    elseif c == '{' or c == '[' then
      depth = depth + 1; out[#out + 1] = c .. '\n' .. string.rep('  ', depth)
    elseif c == '}' or c == ']' then
      depth = depth - 1; out[#out + 1] = '\n' .. string.rep('  ', depth) .. c
    elseif c == ',' then out[#out + 1] = ',\n' .. string.rep('  ', depth)
    elseif c == ':' then out[#out + 1] = ': '
    else out[#out + 1] = c end
  end
  return vim.split(table.concat(out), '\n', { plain = true })
end

function M.grid(tbl, rows, database_kind)
  if database_kind == 'mongo' then
    local readable = {}
    for i, row in ipairs(rows) do readable[i] = M.readable(row) end
    rows = readable
  end
  local columns, seen = {}, {}
  for _, column in ipairs(tbl.columns or {}) do
    columns[#columns + 1], seen[column.name] = column.name, true
  end
  local extra = {}
  for _, row in ipairs(rows) do
    for name in pairs(row) do if not seen[name] then extra[#extra + 1], seen[name] = name, true end end
  end
  table.sort(extra)
  vim.list_extend(columns, extra)
  local widths = {}
  for i, name in ipairs(columns) do
    widths[i] = math.min(24, math.max(6, vim.fn.strdisplaywidth(clean(name))))
    for _, row in ipairs(rows) do widths[i] = math.min(24, math.max(widths[i], vim.fn.strdisplaywidth(cell(row[name])))) end
  end
  local cells, marks = {}, {}
  local function value_group(value, name)
    if value == nil or value == vim.NIL then return 'PathfinderDataNull' end
    if name == '_id' or name:match('Id$') then return 'PathfinderDataId' end
    if type(value) == 'boolean' then return 'PathfinderDataBoolean' end
    if type(value) == 'number' or type(value) == 'string' and tonumber(value) then return 'PathfinderDataNumber' end
    if type(value) == 'table' then return 'PathfinderDataObject' end
    if type(value) == 'string' and value:match('^%d%d%d%d%-%d%d%-%d%dT') then return 'PathfinderDataDate' end
    return 'PathfinderDataText'
  end
  local function line(row, header)
    local text, ranges, screen_col = '   ', {}, 3
    for i, name in ipairs(columns) do
      local value = fit(header and name or cell(row[name]), widths[i])
      ranges[i] = { start = #text, finish = #text + #value, left = screen_col, right = screen_col + widths[i] }
      marks[#marks + 1] = { row = header and 0 or #cells + 1, start = #text, finish = #text + #value,
        group = header and 'PathfinderDataHeading' or value_group(row[name], name) }
      text = text .. value
      screen_col = screen_col + widths[i]
      if i < #columns then
        marks[#marks + 1] = { row = header and 0 or #cells + 1, start = #text + 2, finish = #text + 5, group = 'PathfinderDataBorder' }
        text = text .. '  │  '; screen_col = screen_col + 5
      end
    end
    text = text .. '   '
    cells[#cells + 1] = ranges
    return text
  end
  local lines = { line(nil, true) }
  local rules = {}
  for i, width in ipairs(widths) do rules[i] = string.rep('─', width) end
  lines[2] = '   ' .. table.concat(rules, '──┼──') .. '   '
  for _, row in ipairs(rows) do lines[#lines + 1] = line(row) end
  if #rows == 0 then lines[#lines + 1] = '  No records on this page.' end
  return lines, { columns = columns, cells = cells, marks = marks }
end

local function dimensions()
  return { relative = 'editor', row = 0, col = 0, width = math.max(1, vim.o.columns),
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 65 }
end

local function sync_header(s)
  if not s.header or not api.nvim_win_is_valid(s.header) or not api.nvim_win_is_valid(s.win) then return end
  local view = api.nvim_win_call(s.win, vim.fn.winsaveview)
  local column = api.nvim_win_get_cursor(s.win)[2]
  api.nvim_win_set_cursor(s.header, { s.grid and 3 or 1, column })
  api.nvim_win_call(s.header, function()
    vim.fn.winrestview({ topline = 1, leftcol = view.leftcol })
  end)
end

local function select_cell()
  local s = session
  if not s or not api.nvim_win_is_valid(s.win) then return end
  api.nvim_buf_clear_namespace(s.buf, selection_ns, 0, -1)
  if not s.grid or #s.rows == 0 or #s.grid.columns == 0 then return end
  s.row = math.max(1, math.min(s.row or 1, #s.rows))
  s.column = math.max(1, math.min(s.column or 1, #s.grid.columns))
  local line = s.row + 3 -- zero-based buffer row; the records start on line five
  api.nvim_buf_set_extmark(s.buf, selection_ns, line, 0, {
    line_hl_group = 'PathfinderDataRow', priority = 100,
  })
  for i, ranges in ipairs(s.grid.cells) do
    local range = ranges[s.column]
    local row = i == 1 and 2 or i + 2
    api.nvim_buf_set_extmark(s.buf, selection_ns, row, range.start, {
      end_col = range.finish,
      hl_group = i == 1 and 'PathfinderDataHeader' or i == s.row + 1 and 'PathfinderDataCell' or 'PathfinderDataColumn',
      priority = (i == 1 or i == s.row + 1) and 130 or 110,
      hl_mode = (i == 1 or i == s.row + 1) and 'replace' or 'combine',
    })
  end
  local range = s.grid.cells[s.row + 1][s.column]
  api.nvim_win_set_cursor(s.win, { s.row + 4, range.start })
  api.nvim_win_call(s.win, function()
    local view = vim.fn.winsaveview()
    -- The fixed header covers the first four screen rows.
    if s.row + 4 - view.topline < 4 then view.topline = math.max(1, s.row) end
    local width = api.nvim_win_get_width(s.win)
    if range.left < view.leftcol or range.right - range.left >= width then
      view.leftcol = math.max(0, range.left - 2)
    elseif range.right >= view.leftcol + width then
      view.leftcol = math.max(0, range.right - width + 3)
    end
    vim.fn.winrestview(view)
  end)
  sync_header(s)
end

local function render()
  local s = session
  if not s or not api.nvim_buf_is_valid(s.buf) then return end
  local tbl = s.tables[s.index]
  local title = tbl and clean(tbl.name) or 'No tables or collections'
  local lines = { '   ' .. title .. '  [' .. (#s.tables == 0 and 0 or s.index) .. '/' .. #s.tables .. ']  ·  Page ' .. (s.page + 1)
    .. '  ·  ' .. #s.rows .. ' records' .. (s.has_next and '  ·  more →' or ''), '' }
  if s.connection.kind == 'redis' then
    lines[1] = '   Redis · ' .. clean(s.label or 'Keys') .. ' · Page ' .. (s.page + 1)
      .. ' · ' .. #s.rows .. ' keys' .. (s.has_next and ' · more →' or '')
    lines[2] = '   Match: ' .. clean(s.filter.pattern) .. '   Type: ' .. (s.filter.kind or 'all')
      .. '   / filter · t type · n new · T TTL · Enter value'
  end
  s.grid = nil
  if s.loading then lines[#lines + 1] = '  Loading…'
  elseif s.error then lines[#lines + 1] = '  ' .. s.error
  elseif tbl then
    local grid
    grid, s.grid = M.grid(tbl, s.rows, s.connection.kind)
    vim.list_extend(lines, grid)
  end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  api.nvim_buf_set_extmark(s.buf, ns, 0, 0, { end_col = #lines[1], hl_group = 'Title' })
  if not s.loading and not s.error and tbl then
    api.nvim_buf_set_extmark(s.buf, ns, 2, 0, { line_hl_group = 'PathfinderDataHeading', priority = 40 })
    api.nvim_buf_set_extmark(s.buf, ns, 3, 0, { end_col = #lines[4], hl_group = 'PathfinderDataBorder', priority = 60 })
    for row = 1, #s.rows do
      if row % 2 == 0 then
        api.nvim_buf_set_extmark(s.buf, ns, row + 3, 0, { line_hl_group = 'PathfinderDataStripe', priority = 40 })
      end
    end
    for _, mark in ipairs(s.grid.marks) do
      api.nvim_buf_set_extmark(s.buf, ns, mark.row + 2, mark.start, {
        end_col = mark.finish, hl_group = mark.group, priority = 60,
      })
    end
    api.nvim_win_set_cursor(s.win, { #s.rows > 0 and 5 or 3, 0 })
  end
  api.nvim_win_call(s.win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
  select_cell()
  sync_header(s)
end

local function load()
  local s = session
  if not s then return end
  if s.job then s.job:kill(15); s.job = nil end
  s.request = (s.request or 0) + 1
  local request = s.request
  s.rows, s.has_next, s.error, s.loading = {}, false, nil, false
  s.row = 1
  local tbl = s.tables[s.index]
  if not tbl then render(); return end
  local command, opts = client.data_command(s.connection, tbl, s.page, s.filter)
  if not command then s.error = opts; render(); return end
  s.loading = true
  render()
  local ok, job = pcall(vim.system, command, opts, function(result)
    vim.schedule(function()
      if session ~= s or s.request ~= request then return end
      s.loading, s.job = false, nil
      if result.code ~= 0 then
        s.error = require('pathfinder.database').connection_error(result, s.connection.url or '')
      else
        local decoded, rows = pcall(vim.json.decode, result.stdout or '')
        if not decoded or type(rows) ~= 'table' or not vim.islist(rows) then
          s.error = 'Invalid database data response'
        else
          for _, row in ipairs(rows) do
            if type(row) ~= 'table' or row == vim.NIL then s.error = 'Invalid database record'; break end
          end
          if not s.error then
            s.has_next = #rows > client.page_size
            while #rows > client.page_size do table.remove(rows) end
            s.rows = rows
          end
        end
      end
      render()
    end)
  end)
  if ok then s.job = job else s.loading = false; s.error = 'Could not start the database client'; render() end
end

local function close_detail(s)
  if s.detail and api.nvim_win_is_valid(s.detail) then api.nvim_win_close(s.detail, true) end
  s.detail = nil
end

function M.close()
  local s = session
  if not s then return end
  session = nil
  if s.job then s.job:kill(15) end
  if s.write_job then s.write_job:kill(15) end
  close_detail(s)
  if s.header and api.nvim_win_is_valid(s.header) then api.nvim_win_close(s.header, true) end
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_win_is_valid(s.origin) then
    if s.hidden_origin then api.nvim_win_set_config(s.origin, { hide = false }) end
    api.nvim_set_current_win(s.origin)
  end
end

local function write_record(s, tbl, original, replacement, on_saved)
  if session ~= s or s.writing then return end
  local command, opts = client.write_command(s.connection, tbl, original, replacement)
  if not command then vim.notify('Pathfinder: ' .. opts, vim.log.levels.ERROR); return end
  s.writing = true
  local ok, job = pcall(vim.system, command, opts, function(result)
    vim.schedule(function()
      if session ~= s then return end
      s.writing, s.write_job = false, nil
      if result.code ~= 0 then
        vim.notify('Pathfinder: ' .. require('pathfinder.database').connection_error(result, s.connection.url or ''):gsub('Database connection', 'Database write'), vim.log.levels.ERROR)
        return
      end
      if on_saved then on_saved() end
      vim.notify(replacement and 'Pathfinder: Record saved' or 'Pathfinder: Record deleted')
      load()
    end)
  end)
  if ok then s.write_job = job else s.writing = false; vim.notify('Pathfinder: Could not start database writer', vim.log.levels.ERROR) end
end

local function edit_record()
  local s = session
  local original = s.rows[s.row or 1]
  if s.loading or s.writing or not original then return end
  local tbl = s.tables[s.index]
  close_detail(s)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].swapfile, vim.bo[buf].filetype = 'acwrite', false, 'json'
  api.nvim_buf_set_name(buf, 'pathfinder://record/' .. buf .. '/' .. clean(tbl.name):gsub('/', '_'))
  api.nvim_buf_set_lines(buf, 0, -1, false, M.pretty(original))
  vim.bo[buf].modified = false
  local readonly = s.connection.kind == 'redis' and (original.type ~= 'string' or original.truncated ~= false)
  if readonly then vim.bo[buf].modifiable, vim.bo[buf].buftype = false, 'nofile' end
  local function layout()
    local w, h = math.max(1, math.min(100, vim.o.columns - 6)), math.max(1, math.min(30, vim.o.lines - vim.o.cmdheight - 6))
    return { relative = 'editor', row = math.max(0, math.floor((vim.o.lines - h - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - w - 2) / 2)), width = w, height = h,
      style = 'minimal', border = 'rounded', zindex = 75,
      title = ' ' .. clean(tbl.name) .. ' · Record ' .. (s.page * client.page_size + (s.row or 1)) .. (s.connection.kind == 'mongo' and ' · Extended JSON ' or ' · JSON '),
      footer = readonly and ' Read-only Redis preview · :q close ' or ' :w save · :q close · :q! discard ' }
  end
  local win = api.nvim_open_win(buf, true, layout())
  s.detail = win
  vim.wo[win].wrap = false
  vim.wo[win].winhighlight = 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder'
  require('pathfinder.viewport').bind(buf)
  api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = function()
    if readonly then error('Redis previews are read-only') end
    if session ~= s then error('Database session is closed') end
    if s.writing then error('A database write is already running') end
    local ok, replacement = pcall(vim.json.decode, table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    if not ok or type(replacement) ~= 'table' or replacement == vim.NIL or vim.islist(replacement) then
      error('Enter a valid JSON object')
    end
    if vim.deep_equal(original, replacement) then vim.bo[buf].modified = false; return end
    local tick = api.nvim_buf_get_changedtick(buf)
    write_record(s, tbl, original, replacement, function()
      original = replacement
      if api.nvim_buf_is_valid(buf) and api.nvim_buf_get_changedtick(buf) == tick then vim.bo[buf].modified = false end
    end)
    -- :wq must wait for acknowledgement before Vim decides whether to close.
    vim.wait(16000, function() return not s.writing end, 10)
    if vim.bo[buf].modified then error('Record was not saved; the buffer is still modified') end
  end })
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, layout()) end
  end })
end

local function delete_record()
  local s = session
  local original = s.rows[s.row or 1]
  if s.loading or s.writing or not original then return end
  local tbl = s.tables[s.index]
  local command, err = client.write_command(s.connection, tbl, original, nil)
  if not command then vim.notify('Pathfinder: ' .. err, vim.log.levels.ERROR); return end
  local choice = vim.fn.confirm('Delete record from ' .. clean(tbl.name) .. '?', '&Yes\n&No', 2)
  if choice == 1 and session == s then write_record(s, tbl, original, nil) end
end


local function redis_mutation(s, mode, payload)
  if session ~= s or s.writing then return end
  local command, opts = client.redis_command(s.connection, mode, payload)
  s.writing = true
  local ok, job = pcall(vim.system, command, opts, function(result)
    vim.schedule(function()
      if session ~= s then return end
      s.writing, s.write_job = false, nil
      if result.code ~= 0 then
        vim.notify('Pathfinder: ' .. require('pathfinder.database').connection_error(result, s.connection.url), vim.log.levels.ERROR)
      else
        load()
      end
    end)
  end)
  if ok then s.write_job = job else s.writing = false; vim.notify('Pathfinder: Could not start Redis client', vim.log.levels.ERROR) end
end


function M.open(opts)
  vim.cmd.stopinsert()
  if session then M.close() end
  local origin = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, dimensions())
  session = { buf = buf, win = win, origin = origin, tables = opts.tables, connection = opts.connection,
    index = math.max(1, math.min(opts.index or 1, #opts.tables)), page = 0, rows = {}, label = opts.label, filter = { pattern = '*', kind = nil } }
  local s = session
  if vim.bo[api.nvim_win_get_buf(origin)].filetype == 'pathfinder_database' then
    s.hidden_origin = true
    api.nvim_win_set_config(origin, { hide = true })
  end
  vim.wo[win].winblend = 0
  require('pathfinder.theme').setup()
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = 'wipe', false, 'pathfinder_database_data'
  vim.wo[win].wrap, vim.wo[win].cursorline, vim.wo[win].sidescrolloff = false, false, 0
  vim.wo[win].winhighlight = 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,FloatBorder:PathfinderDialogBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderDialog,WinBarNC:PathfinderDialog'
  vim.wo[win].winbar = '   Data · hjkl: cells · Space/Enter: record · e: edit · dd: delete · Tab: collection · [/]: page · R: reload · q: back'
  if s.connection.kind == 'redis' then
    vim.wo[win].winbar = '   Redis · / search · t type · n new · T TTL · Enter value · dd delete · [/]: page · c connections · q files'
  end
  local function header_layout()
    return { relative = 'win', win = win, row = 0, col = 0, width = api.nvim_win_get_width(win),
      height = math.min(4, api.nvim_win_get_height(win)), style = 'minimal', border = 'none',
      focusable = false, zindex = 66 }
  end
  s.header = api.nvim_open_win(buf, false, header_layout())
  vim.wo[s.header].wrap, vim.wo[s.header].winbar = false, ''
  vim.wo[s.header].winblend = 0
  vim.wo[s.header].winhighlight = vim.wo[win].winhighlight
  vim.wo[s.header].sidescrolloff = 0
  local scroll_event = api.nvim_create_autocmd('WinScrolled', { pattern = tostring(win), callback = function()
    if session == s then sync_header(s) end
  end })
  api.nvim_create_autocmd('WinClosed', { pattern = tostring(win), once = true, callback = function()
    api.nvim_del_autocmd(scroll_event)
    if session == s then M.close() end
  end })
  local function table_move(delta)
    local index = math.max(1, math.min(#s.tables, s.index + delta))
    if index == s.index then return end
    s.index, s.page, s.column = index, 0, 1
    load()
  end
  local function page_move(delta)
    if s.loading then return end
    if delta > 0 and (s.error or not s.has_next) or delta < 0 and s.page == 0 then return end
    s.page = s.page + delta
    load()
  end
  local function move(dx, dy)
    if session ~= s or not s.grid or #s.rows == 0 then return end
    s.row = math.max(1, math.min(#s.rows, (s.row or 1) + dy * vim.v.count1))
    s.column = math.max(1, math.min(#s.grid.columns, (s.column or 1) + dx * vim.v.count1))
    select_cell()
  end
  require('pathfinder.viewport').bind(buf, function()
    local ranges = s.grid and s.grid.cells[(s.row or 1) + 1]
    local range = ranges and ranges[s.column or 1]
    require('pathfinder.viewport').center(win, range and (range.left + range.right - 1) / 2)
    sync_header(s)
  end)
  for key, action in pairs({ q = M.close, ['<Esc>'] = M.close, v = M.close, D = M.close, ['<C-p>'] = M.close,
    h = function() move(-1, 0) end, l = function() move(1, 0) end,
    j = function() move(0, 1) end, k = function() move(0, -1) end,
    ['<Left>'] = function() move(-1, 0) end, ['<Right>'] = function() move(1, 0) end,
    ['<Down>'] = function() move(0, 1) end, ['<Up>'] = function() move(0, -1) end,
    ['<C-d>'] = function() move(0, math.max(1, math.floor(api.nvim_win_get_height(s.win) / 2))) end,
    ['<C-u>'] = function() move(0, -math.max(1, math.floor(api.nvim_win_get_height(s.win) / 2))) end,
    ['<ScrollWheelDown>'] = function() move(0, 3) end,
    ['<ScrollWheelUp>'] = function() move(0, -3) end,
    ['<Tab>'] = function() table_move(1) end, ['<S-Tab>'] = function() table_move(-1) end,
    [']'] = function() page_move(1) end, ['['] = function() page_move(-1) end,
    t = function()
      vim.ui.select(s.tables, { prompt = 'Table / collection', format_item = function(tbl) return tbl.name end }, function(_, index)
        if session ~= s or not index then return end
        s.index, s.page, s.column = index, 0, 1
        load()
      end)
    end,
    ['<CR>'] = edit_record, ['<Space>'] = edit_record, e = edit_record, dd = delete_record, R = load, u = function() M.close(); require('pathfinder.database').prompt() end,
    c = function() M.close(); require('pathfinder.database').connections() end,
    a = function() end,
  }) do vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true }) end
  if s.connection.kind == 'redis' then
    local function back() M.close(); require('pathfinder.database').close() end
    for _, key in ipairs({ 'q', '<Esc>', 'D', '<C-p>', 'v' }) do
      vim.keymap.set('n', key, back, { buffer = buf, silent = true })
    end
    vim.keymap.set('n', '/', function()
      vim.ui.input({ prompt = 'Redis key pattern (* matches all): ', default = s.filter.pattern }, function(pattern)
        if session ~= s or pattern == nil then return end
        s.filter.pattern, s.page = pattern == '' and '*' or pattern, 0
        load()
      end)
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 't', function()
      vim.ui.select({ 'all', 'string', 'hash', 'list', 'set', 'zset', 'stream' }, { prompt = 'Redis value type' }, function(kind)
        if session ~= s or not kind then return end
        s.filter.kind, s.page = kind ~= 'all' and kind or nil, 0
        load()
      end)
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 'n', function()
      if s.writing then return end
      vim.ui.input({ prompt = 'New Redis string key: ' }, function(key)
        if session ~= s or not key or key == '' then return end
        vim.ui.input({ prompt = 'Value: ' }, function(value)
          if session ~= s or value == nil then return end
          redis_mutation(s, 'create', { key = key, value = value })
        end)
      end)
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 'a', vim.fn.maparg('n', 'n', false, true).callback, { buffer = buf, silent = true, desc = 'Create Redis string key' })
    vim.keymap.set('n', 'T', function()
      local original = not s.loading and s.rows[s.row or 1]
      if not original or s.writing then return end
      vim.ui.input({ prompt = 'TTL in seconds (-1 removes expiry): ', default = tostring(original.ttl) }, function(value)
        if session ~= s or value == nil then return end
        local ttl = tonumber(value)
        if not ttl or ttl ~= math.floor(ttl) or ttl < -1 or ttl == 0 then
          vim.notify('Pathfinder: Enter positive seconds or -1 for no expiry', vim.log.levels.ERROR)
          return
        end
        redis_mutation(s, 'write', { original = original, action = 'expiry', ttl = ttl })
      end)
    end, { buffer = buf, silent = true })
  end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if session == s and api.nvim_win_is_valid(win) then
      api.nvim_win_set_config(win, dimensions())
      api.nvim_win_set_config(s.header, header_layout())
      select_cell()
    end
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if session == s then
      session = nil
      if s.job then s.job:kill(15) end
      close_detail(s)
    end
  end })
  load()
end

return M
