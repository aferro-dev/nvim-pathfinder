local M = {}
local api = vim.api
local session
local tables, connection, project_root
local view = { expanded = {}, hidden = {}, index = 1 }
local source = debug.getinfo(1, 'S').source:sub(2)
local scripts = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))), 'scripts')

local function clean(value) return (tostring(value):gsub('%c', ' ')) end
local function notify(message) vim.notify('Pathfinder: ' .. message, vim.log.levels.ERROR) end

function M.resolve_url(value, root)
  value = vim.trim(value)
  local name = value:match('^%${([%a_][%w_]*)}$') or value:match('^%$([%a_][%w_]*)$')
    or value:match('^([%a_][%w_]*)$')
  if not name then return value end
  local path = vim.fs.joinpath(root, '.env')
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil, 'Cannot read the project .env file' end
  local found
  for _, line in ipairs(lines) do
    line = line:gsub('^%s*export%s+', '')
    local key, raw = line:match('^%s*([%a_][%w_]*)%s*=%s*(.-)%s*$')
    if key == name then
      local quote = raw:sub(1, 1)
      if quote == '"' or quote == "'" then
        local ending
        for i = 2, #raw do
          if raw:sub(i, i) == quote then
            local slashes, j = 0, i - 1
            while j > 0 and raw:sub(j, j) == string.char(92) do slashes = slashes + 1; j = j - 1 end
            if quote == "'" or slashes % 2 == 0 then ending = i; break end
          end
        end
        if not ending or not raw:sub(ending + 1):match('^%s*#') and vim.trim(raw:sub(ending + 1)) ~= '' then
          return nil, 'Invalid quoted value for ' .. name .. ' in .env'
        end
        found = raw:sub(2, ending - 1)
      else
        found = vim.trim((raw:gsub('%s+#.*$', '')))
      end
    end
  end
  if not found or found == '' then return nil, 'Variable ' .. name .. ' is missing or empty in the project .env' end
  return found
end

function M.parse_url(url, root)
  if type(url) ~= 'string' or url:find('%c') then return nil, 'Invalid database URL' end
  if url:match('^postgres://') or url:match('^postgresql://') then
    return { kind = 'postgres', url = url }
  end
  local path = url:match('^sqlite://(.+)$') or url:match('^sqlite:(.+)$')
  if path then
    if path:find('[?#]') then return nil, 'SQLite URLs accept a file path without query parameters' end
    path = path:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end)
    if path:find('%z') or path == ':memory:' then return nil, 'Use an existing SQLite database file' end
    path = vim.fn.expand(path)
    if path:sub(1, 1) ~= '/' then path = vim.fs.joinpath(root or vim.fn.getcwd(), path) end
    return { kind = 'sqlite', path = vim.fs.normalize(path) }
  end
  return nil, 'Use sqlite:///absolute/path.db, sqlite://relative/path.db, postgres:// or postgresql://'
end

function M.connection_error(result, url)
  if result.code == 124 then return 'Database connection timed out' end
  local detail = result.stderr or ''
  local function redact(value)
    if value and value ~= '' then detail = detail:gsub(value:gsub('([^%w])', '%%%1'), '[redacted]') end
  end
  redact(url)
  local password = url:match('^postgres[^:]*://[^/@]-:([^@]*)@')
  redact(password)
  if password then redact((password:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))) end
  detail = clean(detail):sub(1, 1500)
  return 'Database connection failed' .. (detail ~= '' and ': ' .. detail or ' (client exit ' .. result.code .. ')')
end

function M.diagram(schema, viewport, expanded, selected, height)
  return require('pathfinder.database_graph').render(schema, viewport, expanded, selected, height)
end

local function dimensions()
  return { relative = 'editor', row = 0, col = 0, width = math.max(1, vim.o.columns),
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 60 }
end

local function render()
  local s = session
  if not s or not api.nvim_buf_is_valid(s.buf) then return end
  local lines, marks
  s.visible = {}
  for _, tbl in ipairs(tables or {}) do if not s.hidden[tbl.name] then s.visible[#s.visible + 1] = tbl end end
  s.index = math.min(s.index or 1, math.max(1, #s.visible))
  view = { expanded = s.expanded, hidden = s.hidden, index = s.index }
  lines, s.positions, marks = M.diagram(s.visible, api.nvim_win_get_width(s.win), s.expanded, s.index, api.nvim_win_get_height(s.win) - (s.error and 2 or 0))
  if tables and #tables == 0 then lines = { 'No tables found in this database.' } end
  if not tables then
    lines = { s.error or 'Press u to enter a database URL or a project .env variable.' }
  elseif s.error then
    table.insert(lines, 1, s.error)
    table.insert(lines, 2, '')
    for _, mark in ipairs(marks) do mark[1] = mark[1] + 2 end
    for _, pos in ipairs(s.positions) do pos.row = pos.row + 2; pos.top = pos.top + 2; pos.bottom = pos.bottom + 2 end
  end
  if s.loading then lines = { 'Connecting…' }; s.positions, marks = {}, {} end
  local height = api.nvim_win_get_height(s.win)
  local fits = #lines <= height
  if #s.positions > 0 and fits then
    local padding = math.floor((height - #lines) / 2)
    local centered = {}
    for _ = 1, padding do centered[#centered + 1] = '' end
    vim.list_extend(centered, lines)
    lines = centered
    for _, mark in ipairs(marks) do mark[1] = mark[1] + padding end
    for _, pos in ipairs(s.positions) do
      pos.row, pos.top, pos.bottom = pos.row + padding, pos.top + padding, pos.bottom + padding
    end
  end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  local ns = api.nvim_create_namespace('pathfinder_database')
  api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
  for _, mark in ipairs(marks) do
    if mark[3] > mark[2] then
      api.nvim_buf_set_extmark(s.buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
    end
  end
  s.index = math.min(s.index or 1, math.max(1, #s.positions))
  local pos = s.positions[s.index]
  if pos then api.nvim_win_set_cursor(s.win, { pos.row, math.max(0, vim.fn.virtcol2col(s.win, pos.row, pos.col + 1) - 1) }) end
  if fits then api.nvim_win_call(s.win, function() vim.fn.winrestview({ topline = 1 }) end) end
end

local function dismiss_input(s)
  local input = s and s.input
  if not input then return end
  s.input = nil
  vim.cmd.stopinsert()
  if api.nvim_win_is_valid(input.win) then api.nvim_win_close(input.win, true) end
  if api.nvim_win_is_valid(s.win) then api.nvim_set_current_win(s.win) end
end

function M.close()
  local s = session
  if not s then return end
  session = nil
  dismiss_input(s)
  if s.job then s.job:kill(15) end
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_win_is_valid(s.origin) then api.nvim_set_current_win(s.origin) end
end

local function connect(value)
  local s = session
  local function fail(message)
    s.error = message
    render()
    notify(message)
  end
  local resolved, resolve_err = M.resolve_url(value, s.root)
  if not resolved then fail(resolve_err); return end
  local parsed, err = M.parse_url(resolved, s.root)
  if not parsed then fail(err); return end
  local command, opts = nil, { text = true, timeout = 15000 }
  if parsed.kind == 'sqlite' then
    if vim.fn.executable('python3') ~= 1 then fail('SQLite support requires python3'); return end
    command = { 'python3', vim.fs.joinpath(scripts, 'sqlite_schema.py'), parsed.path }
  else
    if vim.fn.executable('psql') ~= 1 then fail('PostgreSQL support requires psql on PATH. Restart Neovim from: nix shell nixpkgs#postgresql'); return end
    command = { 'psql', '--dbname', parsed.url, '-X', '-w', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-f', vim.fs.joinpath(scripts, 'postgres_schema.sql') }
    opts.env = { PGCONNECT_TIMEOUT = '8', PGAPPNAME = 'nvim-pathfinder', PSQL_HISTORY = '/dev/null' }
  end
  if s.job then s.job:kill(15) end
  s.request = (s.request or 0) + 1
  local request = s.request
  s.error = nil
  s.loading = true
  render()
  local ok, job = pcall(vim.system, command, opts, function(result)
    vim.schedule(function()
      if session ~= s or s.request ~= request then return end
      s.loading, s.job = false, nil
      if result.code ~= 0 then
        fail(M.connection_error(result, resolved))
        return
      end
      local decoded, schema = pcall(vim.json.decode, result.stdout or '')
      if not decoded or type(schema) ~= 'table' then fail('Invalid database schema response'); return end
      if connection ~= value then s.expanded, s.hidden, s.index = {}, {}, 1 end
      tables, connection = schema, value
      render()
    end)
  end)
  if ok then s.job = job else s.loading = false; fail('Could not start the database client') end
end

function M.prompt()
  local s = session
  if not s or not api.nvim_win_is_valid(s.win) then return end
  if s.input and api.nvim_win_is_valid(s.input.win) then
    api.nvim_set_current_win(s.input.win)
    return
  end
  local function input_dimensions()
    local width = math.max(1, math.min(68, vim.o.columns - 4))
    return { relative = 'editor', row = math.max(0, math.floor((vim.o.lines - 5) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)), width = width, height = 1,
      style = 'minimal', border = 'rounded', zindex = 70,
      title = ' Database URL / .env variable ', title_pos = 'center',
      footer = ' Enter: connect · Esc: cancel ', footer_pos = 'center' }
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'wipe', false
  api.nvim_buf_set_lines(buf, 0, -1, false, { 'DATABASE_URL' })
  local win = api.nvim_open_win(buf, true, input_dimensions())
  s.input = { buf = buf, win = win }
  vim.wo[win].wrap = false
  api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = win, scope = 'local' })
  local function cancel() if session == s then dismiss_input(s) end end
  local function submit()
    if session ~= s or not s.input or s.input.buf ~= buf then return end
    local value = vim.trim(api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '')
    if value == '' then return end
    dismiss_input(s)
    connect(value)
  end
  vim.keymap.set({ 'n', 'i' }, '<CR>', submit, { buffer = buf, silent = true, desc = 'Connect to database' })
  for _, key in ipairs({ '<Esc>', '<C-c>' }) do
    vim.keymap.set({ 'n', 'i' }, key, cancel, { buffer = buf, silent = true, nowait = true, desc = 'Cancel database connection' })
  end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if session == s and s.input and s.input.buf == buf and api.nvim_win_is_valid(win) then
      api.nvim_win_set_config(win, input_dimensions())
    end
  end })
  api.nvim_create_autocmd('WinLeave', { buffer = buf, once = true, callback = function()
    vim.schedule(function()
      if session == s and s.input and s.input.buf == buf then dismiss_input(s) end
    end)
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if s.input and s.input.buf == buf then s.input = nil end
  end })
  api.nvim_win_set_cursor(win, { 1, #'DATABASE_URL' })
  vim.cmd('startinsert!')
end

function M.toggle(opts)
  opts = opts or {}
  if session and api.nvim_win_is_valid(session.win) then M.close(); return end
  local root = opts.root or vim.fs.root(api.nvim_buf_get_name(0) ~= '' and api.nvim_buf_get_name(0) or vim.fn.getcwd(), { '.git', '.env' }) or vim.fn.getcwd()
  root = vim.fs.normalize(root)
  if project_root ~= root then
    tables, connection, project_root = nil, nil, root
    view = { expanded = {}, hidden = {}, index = 1 }
  end
  require('pathfinder.theme').setup()
  local origin = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, dimensions())
  session = { buf = buf, win = win, origin = origin, root = root, expanded = view.expanded, hidden = view.hidden, index = view.index }
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = 'wipe', false, 'pathfinder_database'
  vim.wo[win].wrap, vim.wo[win].signcolumn = false, 'no'
  api.nvim_set_option_value('winbar', ' Database  ·  hjkl move  ·  Enter detail  ·  Space toggle  ·  zR/zM all  ·  H hide/I restore  ·  u URL  ·  R refresh  ·  D files', { win = win, scope = 'local' })
  api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = win, scope = 'local' })
  local function move(delta)
    if #session.positions == 0 then return end
    session.index = math.max(1, math.min(#session.positions, session.index + delta * vim.v.count1))
    render()
  end
  local function spatial(dx, dy)
    local s = session
    local from = s.positions[s.index]
    if not from then return end
    for _ = 1, vim.v.count1 do
      from = s.positions[s.index]
      local target, distance
      for i, pos in ipairs(s.positions) do
        local x, y = pos.col - from.col, pos.row - from.row
        if (dx ~= 0 and x * dx > 0) or (dy ~= 0 and y * dy > 0) then
          local score = dx ~= 0 and math.abs(x) + math.abs(y) * 3 or math.abs(y) + math.abs(x) * 3
          if not distance or score < distance then target, distance = i, score end
        end
      end
      if not target then break end
      s.index = target
    end
    render()
  end
  local function expand(value, all)
    local s = session
    local tbl = s.visible[s.index]
    if all then
      for _, entry in ipairs(tables or {}) do s.expanded[entry.name] = value end
    elseif tbl then s.expanded[tbl.name] = value == nil and not s.expanded[tbl.name] or value end
    render()
  end
  local function details()
    local s = session
    local tbl = s.visible[s.index]
    if not tbl then return end
    local lines = require('pathfinder.database_graph').details(tbl, tables or {})
    local detail = api.nvim_create_buf(false, true)
    vim.bo[detail].bufhidden, vim.bo[detail].swapfile = 'wipe', false
    api.nvim_buf_set_lines(detail, 0, -1, false, lines)
    vim.bo[detail].modifiable = false
    local function layout()
      local content_width = 0
      for _, line in ipairs(lines) do content_width = math.max(content_width, vim.fn.strdisplaywidth(line)) end
      local w = math.max(1, math.min(math.max(58, content_width + 2), vim.o.columns - 8))
      local h = math.max(1, math.min(#lines, vim.o.lines - vim.o.cmdheight - 6))
      return { relative = 'editor', row = math.max(0, math.floor((vim.o.lines - h - 2) / 2)),
        col = math.max(0, math.floor((vim.o.columns - w - 2) / 2)), width = w, height = h,
        style = 'minimal', border = 'rounded', zindex = 70,
        title = ' ' .. clean(tbl.name) .. ' ', title_pos = 'center', footer = ' Esc/q: back · hjkl: scroll ', footer_pos = 'center' }
    end
    local detail_win = api.nvim_open_win(detail, true, layout())
    s.input = { buf = detail, win = detail_win }
    local detail_ns = api.nvim_create_namespace('pathfinder_database_detail')
    for row, line in ipairs(lines) do
      local group = row == 1 and 'Title' or row == 3 and 'Title' or line:find('REFERENC', 1, true) and 'DiagnosticInfo'
      if group then api.nvim_buf_set_extmark(detail, detail_ns, row - 1, 0, { end_col = #line, hl_group = group }) end
      if row > 4 and line:find('  ', 1, true) == 1 and (line:find('PK', 1, true) == 3 or line:find('FK', 1, true) == 3) then
        api.nvim_buf_set_extmark(detail, detail_ns, row - 1, 2, { end_col = 7, hl_group = 'DiagnosticInfo' })
      end
    end
    vim.wo[detail_win].wrap = true
    vim.wo[detail_win].linebreak = true
    vim.wo[detail_win].breakindent = true
    api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = detail_win, scope = 'local' })
    for _, key in ipairs({ '<Esc>', 'q', '<CR>', '<BS>', '-' }) do
      vim.keymap.set('n', key, function() dismiss_input(s) end, { buffer = detail, silent = true })
    end
    api.nvim_create_autocmd('VimResized', { buffer = detail, callback = function()
      if api.nvim_win_is_valid(detail_win) then api.nvim_win_set_config(detail_win, layout()) end
    end })
    api.nvim_create_autocmd('WinLeave', { buffer = detail, once = true, callback = function()
      vim.schedule(function() if s.input and s.input.buf == detail then dismiss_input(s) end end)
    end })
  end
  for key, action in pairs({ D = M.close, q = M.close, ['<Esc>'] = M.close, ['<C-p>'] = M.close,
    u = M.prompt, R = function() if connection then connect(connection) else M.prompt() end end,
    ['<Tab>'] = function() move(1) end, ['<S-Tab>'] = function() move(-1) end,
    h = function() spatial(-1, 0) end, l = function() spatial(1, 0) end,
    j = function() spatial(0, 1) end, k = function() spatial(0, -1) end,
    ['<Left>'] = function() spatial(-1, 0) end, ['<Right>'] = function() spatial(1, 0) end,
    ['<Down>'] = function() spatial(0, 1) end, ['<Up>'] = function() spatial(0, -1) end,
    ['<CR>'] = details, ['<Space>'] = function() expand() end,
    zo = function() expand(true) end, zc = function() expand(false) end,
    zR = function() expand(true, true) end, zM = function() expand(false, true) end,
    H = function() local tbl = session.visible[session.index]; if tbl then session.hidden[tbl.name] = true; render() end end,
    I = function() session.hidden = {}; render() end,
  }) do
    vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true })
  end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if session and session.buf == buf and api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, dimensions()); render() end
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if session and session.buf == buf then
      dismiss_input(session)
      if session.job then session.job:kill(15) end
      session = nil
    end
  end })
  render()
  if not connection then M.prompt() end
end

return M
