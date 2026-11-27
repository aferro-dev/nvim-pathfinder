local M = {}
local api = vim.api
local session
local tables, connection, project_root, active_connection
local projects, profiles, selected_profile = {}, {}, nil
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
  if url:match('^rediss?://') then
    if not url:match('^rediss?://[^/]+') then return nil, 'Redis URLs must include a host' end
    return { kind = 'redis', url = url }
  end
  if url:match('^mongodb://') or url:match('^mongodb%+srv://') then
    if not url:match('^mongodb[^:]*://[^/]+/[^?]+') then
      return nil, 'MongoDB URLs must include a database name: mongodb://host/database'
    end
    local database = url:match('^mongodb[^:]*://[^/]+/([^?]+)')
    database = database:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end)
    return { kind = 'mongo', url = url, database = database }
  end
  -- Driver-qualified URLs follow SQLAlchemy: three slashes introduce a
  -- relative path, four an absolute path. Keep existing plain sqlite URLs.
  local driver = url:match('^sqlite%+([^:]+):')
  local path
  if driver then
    if driver ~= 'aiosqlite' and driver ~= 'pysqlite' then return nil, 'Unsupported SQLite driver: ' .. clean(driver) end
    path = url:match('^sqlite%+[^:]+:///(.+)$')
    if not path then return nil, 'Use sqlite+' .. driver .. ':///relative.db or sqlite+' .. driver .. ':////absolute/path.db' end
  else
    path = url:match('^sqlite://(.+)$') or url:match('^sqlite:(.+)$')
  end
  if path then
    if path:find('[?#]') then return nil, 'SQLite URLs accept a file path without query parameters' end
    path = path:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end)
    if path:find('%z') or path == ':memory:' then return nil, 'Use an existing SQLite database file' end
    path = vim.fn.expand(path)
    if path:sub(1, 1) ~= '/' then path = vim.fs.joinpath(root or vim.fn.getcwd(), path) end
    return { kind = 'sqlite', path = vim.fs.normalize(path) }
  end
  return nil, 'Use sqlite:///absolute/path.db, sqlite://relative/path.db, postgres://, postgresql://, mongodb://, mongodb+srv://, redis:// or rediss://'
end

function M.connection_error(result, url)
  if result.code == 124 then return 'Database connection timed out' end
  local detail = result.stderr or ''
  local function redact(value)
    if value and value ~= '' then detail = detail:gsub(value:gsub('([^%w])', '%%%1'), '[redacted]') end
  end
  redact(url)
  local password = url:match('^[%w+]+://[^/@]-:([^@]*)@')
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

local function endpoint(parsed)
  local label = parsed.path or parsed.url:match('^[%w+]+://(.*)$') or parsed.kind
  label = label:gsub('^.*@', ''):gsub('[?#].*$', '')
  if parsed.kind == 'mongo' and parsed.database then label = label:gsub('/.*$', '') .. '/' .. parsed.database end
  return parsed.kind .. ' · ' .. clean(label)
end

local function render()
  local s = session
  if not s or not api.nvim_buf_is_valid(s.buf) then return end
  local lines, marks
  s.visible = {}
  for _, tbl in ipairs(tables or {}) do if not s.hidden[tbl.name] then s.visible[#s.visible + 1] = tbl end end
  s.index = math.min(s.index or 1, math.max(1, #s.visible))
  view = { expanded = s.expanded, hidden = s.hidden, index = s.index }
  if selected_profile then selected_profile.view = view end
  local label = selected_profile and ((selected_profile.custom_name and selected_profile.name .. ' · ' or '') .. endpoint(selected_profile.parsed)) or 'No connection'
  local limit = math.max(8, math.min(30, math.floor(api.nvim_win_get_width(s.win) / 4)))
  if vim.fn.strdisplaywidth(label) > limit then label = vim.fn.strcharpart(label, 0, limit - 1) .. '…' end
  vim.wo[s.win].winbar = ' ' .. label:gsub('%%', '%%%%') .. '  ·  c connections  ·  u edit  ·  R refresh  ·  Enter detail  ·  v data  ·  D files'

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
  if input.panel and api.nvim_win_is_valid(input.panel) then api.nvim_win_close(input.panel, true) end
  if api.nvim_win_is_valid(input.win) then api.nvim_win_close(input.win, true) end
  if api.nvim_win_is_valid(s.win) then api.nvim_set_current_win(s.win) end
end

function M.close()
  local s = session
  if not s then return end
  session = nil
  require('pathfinder.mongo_browser').close()
  require('pathfinder.database_data').close()
  dismiss_input(s)
  if s.job then s.job:kill(15) end
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_win_is_valid(s.origin) then
    if s.hidden_origin then api.nvim_win_set_config(s.origin, { hide = false }) end
    api.nvim_set_current_win(s.origin)
  end
end

local function open_browser()
  if active_connection and active_connection.kind == 'redis' then
    require('pathfinder.database_data').open({ connection = active_connection, tables = tables,
      index = 1, label = selected_profile and selected_profile.name })
  elseif active_connection and active_connection.kind == 'mongo' then
    require('pathfinder.mongo_browser').open({ connection = active_connection, changed = function()
      if selected_profile and not selected_profile.custom_name then selected_profile.name = endpoint(active_connection) end
      render()
    end })
  end
end

local function connect(value)
  local s = session
  local target = s.input and s.input.profile or selected_profile
  if s.input and s.input.new then target = nil end
  local function fail(message)
    s.loading = false
    s.error = message
    render()
    if s.input and s.input.refresh then s.input.refresh() end
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
  elseif parsed.kind == 'redis' then
    if vim.fn.executable('python3') ~= 1 then fail('Redis support requires python3'); return end
    command = { 'python3', vim.fs.joinpath(scripts, 'redis_data.py'), 'schema' }
    opts.stdin = vim.json.encode({ url = parsed.url })
  elseif parsed.kind == 'mongo' then
    if vim.fn.executable('mongosh') ~= 1 then fail('MongoDB support requires mongosh on PATH'); return end
    command = { 'mongosh', '--quiet', '--norc', parsed.url, '--eval',
      'print(JSON.stringify(db.getCollectionNames().filter(n => !n.startsWith("system.")).sort().map(name => ({name,columns:[],foreign_keys:[]}))));' }
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
  if s.input and s.input.refresh then s.input.refresh() end
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
      if not target then
        for _, profile in ipairs(profiles) do if profile.value == value then target = profile; break end end
      end
      if not target then
        target = { name = endpoint(parsed), view = { expanded = {}, hidden = {}, index = 1 } }
        profiles[#profiles + 1] = target
      end
      if target.value ~= value then target.view = { expanded = {}, hidden = {}, index = 1 } end
      if not target.custom_name then target.name = endpoint(parsed) end
      target.value, target.parsed, target.tables, target.draft = value, parsed, schema, value
      s.draft, s.new_draft = nil, nil
      selected_profile = target
      projects[s.root].active = target
      s.expanded, s.hidden, s.index = target.view.expanded, target.view.hidden, target.view.index
      tables, connection, active_connection = schema, value, parsed
      dismiss_input(s)
      render()
      open_browser()
    end)
  end)
  if ok then s.job = job else s.loading = false; fail('Could not start the database client') end
end

function M.prompt(opts)
  opts = opts or {}
  require('pathfinder.mongo_browser').close()
  require('pathfinder.database_data').close()
  local s = session
  if not s or not api.nvim_win_is_valid(s.win) then return end
  if s.input and api.nvim_win_is_valid(s.input.win) then
    api.nvim_set_current_win(s.input.win)
    return
  end
  if opts.new then s.error = nil end
  local form = require('pathfinder.database_form')
  local value
  if opts.new then value = s.new_draft else value = (selected_profile and selected_profile.draft) or s.draft or connection end
  local kind = (value and form.detect(value)) or (not opts.new and selected_profile and selected_profile.parsed.kind) or 'postgres'
  value = value or form.type(kind).default
  local drafts = {}
  local buf, panel_buf = api.nvim_create_buf(false, true), api.nvim_create_buf(false, true)
  for _, target in ipairs({ buf, panel_buf }) do
    vim.bo[target].bufhidden, vim.bo[target].swapfile = 'wipe', false
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, { value })
  local function layout()
    local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '')
    return form.layout(vim.o.columns, vim.o.lines - vim.o.cmdheight, text, s.error, s.loading, kind)
  end
  local geometry = layout()
  geometry.panel.title = opts.new and ' Add connection ' or selected_profile and ' Edit connection ' or ' Connect database '
  local panel = api.nvim_open_win(panel_buf, false, geometry.panel)
  geometry.field.win = panel
  local win = api.nvim_open_win(buf, true, geometry.field)
  local ns = api.nvim_create_namespace('pathfinder_database_form')
  local function refresh()
    if not api.nvim_win_is_valid(panel) or not api.nvim_win_is_valid(win) then return end
    local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '')
    kind = form.detect(text) or kind
    local updated = layout()
    updated.panel.title = geometry.panel.title
    updated.field.win = panel
    api.nvim_win_set_config(panel, updated.panel)
    api.nvim_win_set_config(win, updated.field)
    vim.bo[panel_buf].modifiable = true
    api.nvim_buf_set_lines(panel_buf, 0, -1, false, updated.lines)
    vim.bo[panel_buf].modifiable = false
    api.nvim_buf_clear_namespace(panel_buf, ns, 0, -1)
    for _, mark in ipairs(updated.marks) do
      api.nvim_buf_set_extmark(panel_buf, ns, mark[1], 0, mark[3] and { end_col = mark[4], hl_group = mark[2], priority = 150 } or { line_hl_group = mark[2] })
    end
    vim.wo[win].winhighlight = 'Normal:PathfinderInput,NormalFloat:PathfinderInput,FloatBorder:'
      .. (s.error and 'PathfinderInputError' or 'PathfinderInputBorder') .. ',FloatTitle:PathfinderInputLabel'
  end
  s.input = { buf = buf, win = win, panel = panel, refresh = refresh, profile = selected_profile, new = opts.new }
  for _, target in ipairs({ win, panel }) do
    vim.wo[target].winblend = 0
    vim.wo[target].winbar = ''
    vim.wo[target].cursorline = false
    vim.wo[target].signcolumn = 'no'
    vim.wo[target].number, vim.wo[target].relativenumber = false, false
    vim.wo[target].foldcolumn = '0'
  end
  vim.wo[panel].wrap = false
  vim.wo[panel].winhighlight = 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,FloatBorder:PathfinderDialogBorder,FloatTitle:PathfinderInputLabel,FloatFooter:PathfinderMuted'
  vim.wo[win].wrap, vim.wo[win].linebreak = true, false
  vim.wo[win].showbreak = '↪ '
  vim.wo[win].sidescrolloff = 0
  refresh()
  local function choose(next_kind)
    if s.loading then return end
    drafts[kind] = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '')
    kind = next_kind
    local next_value = drafts[kind] or form.type(kind).default
    api.nvim_buf_set_lines(buf, 0, -1, false, { next_value })
    s.error = nil
    refresh()
    api.nvim_set_current_win(win)
    api.nvim_win_set_cursor(win, { 1, #next_value })
    vim.cmd('startinsert!')
  end
  local function cycle(delta)
    local _, index = form.type(kind)
    choose(form.types[(index - 1 + delta) % #form.types + 1].kind)
  end
  for _, target in ipairs({ buf, panel_buf }) do
    vim.keymap.set({ 'n', 'i' }, '<Tab>', function() cycle(1) end, { buffer = target, silent = true })
    vim.keymap.set({ 'n', 'i' }, '<S-Tab>', function() cycle(-1) end, { buffer = target, silent = true })
  end
  local function click_type()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= panel then
      api.nvim_feedkeys(api.nvim_replace_termcodes('<LeftMouse>', true, false, true), 'n', false)
      return
    end
    if mouse.line == 1 then
      local choices = layout().choices
      if #choices == 0 then cycle(1); return end
      for _, choice in ipairs(choices) do
        if mouse.column - 1 >= choice.start and mouse.column - 1 < choice.finish then choose(choice.kind); return end
      end
    end
    api.nvim_set_current_win(win)
    vim.cmd('startinsert!')
  end
  for _, target in ipairs({ buf, panel_buf }) do
    vim.keymap.set({ 'n', 'i' }, '<LeftMouse>', click_type, { buffer = target, silent = true })
  end
  local function cancel(stay)
    if session ~= s then return end
    local draft = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '')
    if not opts.new and selected_profile then selected_profile.draft = draft elseif opts.new then s.new_draft = draft else s.draft = draft end
    s.request = (s.request or 0) + 1
    if s.job then s.job:kill(15); s.job = nil end
    s.loading = false
    dismiss_input(s)
    render()
    if not stay then open_browser() end
  end
  local function submit()
    if session ~= s or not s.input or s.input.buf ~= buf or s.loading then return end
    local value = vim.trim(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), ''))
    if not opts.new and selected_profile then selected_profile.draft = value elseif opts.new then s.new_draft = value else s.draft = value end
    if value == '' then s.error = 'Enter a database URL or a .env variable'; refresh(); return end
    connect(value)
  end
  vim.keymap.set({ 'n', 'i' }, '<C-l>', function() cancel(true); M.connections() end, { buffer = buf, silent = true })
  vim.keymap.set({ 'n', 'i' }, '<CR>', submit, { buffer = buf, silent = true, desc = 'Connect to database' })
  for _, key in ipairs({ '<Esc>', '<C-c>' }) do
    vim.keymap.set({ 'n', 'i' }, key, cancel, { buffer = buf, silent = true, nowait = true, desc = 'Cancel database connection' })
  end
  vim.keymap.set('n', '<Esc>', cancel, { buffer = panel_buf, silent = true })
  vim.keymap.set('n', '<CR>', submit, { buffer = panel_buf, silent = true })
  api.nvim_create_autocmd({ 'VimResized', 'TextChanged', 'TextChangedI' }, { buffer = buf, callback = function()
    if session == s and s.input and s.input.buf == buf then refresh() end
  end })
  api.nvim_create_autocmd('WinLeave', { buffer = buf, callback = function()
    vim.schedule(function()
      if session == s and s.input and s.input.buf == buf and api.nvim_get_current_win() ~= win and api.nvim_get_current_win() ~= panel then cancel(true) end
    end)
  end })
  api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    if s.input and s.input.buf == buf then s.input = nil end
  end })
  api.nvim_win_set_cursor(win, { 1, #value })
  vim.cmd('startinsert!')
end

function M.connections()
  require('pathfinder.mongo_browser').close()
  require('pathfinder.database_data').close()
  vim.cmd.stopinsert()
  local s = session
  if not s or not api.nvim_win_is_valid(s.win) then return end
  if s.loading then
    s.request = (s.request or 0) + 1
    if s.job then s.job:kill(15); s.job = nil end
    s.loading = false
  end
  dismiss_input(s)
  render()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'wipe', false
  local function layout()
    local width = math.max(1, math.min(90, vim.o.columns - 4))
    local height = math.max(1, math.min(math.max(6, #profiles + 4), vim.o.lines - vim.o.cmdheight - 4))
    return { relative = 'editor', row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)), width = width, height = height,
      style = 'minimal', border = 'rounded', zindex = 70,
      title = ' Connections · current Neovim session ', title_pos = 'center',
      footer = ' Enter switch · a add · u edit · r rename · dd remove · Esc back ' }
  end
  local win = api.nvim_open_win(buf, true, layout())
  s.input = { buf = buf, win = win }
  vim.wo[win].wrap, vim.wo[win].cursorline = false, true
  vim.wo[win].winblend, vim.wo[win].winbar = 0, ''
  vim.wo[win].winhighlight = 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,FloatBorder:PathfinderDialogBorder,FloatTitle:PathfinderInputLabel,FloatFooter:PathfinderMuted'
  local function draw(index)
    local lines = { '  PROJECT CONNECTIONS', '' }
    for _, profile in ipairs(profiles) do
      lines[#lines + 1] = (profile == selected_profile and '  ● ' or '    ') .. clean(profile.name) .. (profile.custom_name and ' · ' .. endpoint(profile.parsed) or '')
    end
    if #profiles == 0 then lines[3] = '  No connections yet. Press a to add one.' end
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_win_set_cursor(win, { math.min(#lines, math.max(3, (index or 1) + 2)), 0 })
  end
  local function current() return profiles[api.nvim_win_get_cursor(win)[1] - 2] end
  local function activate(profile, editing)
    if not profile then return end
    require('pathfinder.database_data').close()
    selected_profile, projects[s.root].active = profile, profile
    tables, connection, active_connection = profile.tables, profile.value, profile.parsed
    view = profile.view
    s.expanded, s.hidden, s.index = view.expanded, view.hidden, view.index
    s.error, s.draft = nil, nil
    dismiss_input(s)
    render()
    if not editing then open_browser() end
  end
  local function close() dismiss_input(s) end
  local actions = {
    ['<Esc>'] = function() close(); open_browser() end, q = function() close(); open_browser() end,
    ['<CR>'] = function() activate(current()) end,
    a = function() close(); M.prompt({ new = true }) end,
    u = function() local profile = current(); if profile then activate(profile, true); M.prompt() end end,
    r = function()
      local profile = current()
      if not profile then return end
      vim.ui.input({ prompt = 'Connection name: ', default = profile.name }, function(name)
        if session ~= s or not api.nvim_buf_is_valid(buf) then return end
        if name and vim.trim(name) ~= '' then profile.name = clean(vim.trim(name)); profile.custom_name = true; draw() end
      end)
    end,
    dd = function()
      local index = api.nvim_win_get_cursor(win)[1] - 2
      local profile = profiles[index]
      if not profile then return end
      table.remove(profiles, index)
      if profile == selected_profile then
        selected_profile, projects[s.root].active = nil, nil
        tables, connection, active_connection = nil, nil, nil
        s.expanded, s.hidden, s.index, s.error, s.draft = {}, {}, 1, nil, nil
        render()
      end
      draw(index)
    end,
  }
  for key, action in pairs(actions) do vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true }) end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function()
    if api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, layout()) end
  end })
  api.nvim_create_autocmd('WinClosed', { pattern = tostring(win), once = true, callback = function()
    if s.input and s.input.buf == buf then s.input = nil end
  end })
  draw()
end

function M.toggle(opts)
  vim.cmd.stopinsert()
  opts = opts or {}
  if session and api.nvim_win_is_valid(session.win) then M.close(); return end
  local root = opts.root or vim.fs.root(api.nvim_buf_get_name(0) ~= '' and api.nvim_buf_get_name(0) or vim.fn.getcwd(), { '.git', '.env' }) or vim.fn.getcwd()
  root = vim.fs.normalize(root)
  if project_root ~= root then
    project_root = root
    projects[root] = projects[root] or { entries = {} }
    profiles, selected_profile = projects[root].entries, projects[root].active
    tables = selected_profile and selected_profile.tables
    connection = selected_profile and selected_profile.value
    active_connection = selected_profile and selected_profile.parsed
    view = selected_profile and selected_profile.view or { expanded = {}, hidden = {}, index = 1 }
  end
  require('pathfinder.theme').setup()
  local origin = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, dimensions())
  session = { buf = buf, win = win, origin = origin, root = root, expanded = view.expanded, hidden = view.hidden, index = view.index }
  if vim.bo[api.nvim_win_get_buf(origin)].filetype == 'pathfinder' then
    session.hidden_origin = true
    api.nvim_win_set_config(origin, { hide = true })
  end
  vim.wo[win].winblend = 0
  vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = 'wipe', false, 'pathfinder_database'
  vim.wo[win].wrap, vim.wo[win].signcolumn = false, 'no'
  api.nvim_set_option_value('winbar', ' Database  ·  hjkl move  ·  Enter detail  ·  v data  ·  Space toggle  ·  zR/zM all  ·  H hide/I restore  ·  u URL  ·  R refresh  ·  D files', { win = win, scope = 'local' })
  api.nvim_set_option_value('winhighlight', 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,FloatBorder:PathfinderDialogBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderDialog,WinBarNC:PathfinderDialog', { win = win, scope = 'local' })
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
    local lines = require('pathfinder.database_graph').details(tbl, tables or {}, active_connection and active_connection.kind)
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
        title = ' ' .. clean(tbl.name) .. ' ', title_pos = 'center', footer = ' Esc/q: back · v: data · hjkl: scroll ', footer_pos = 'center' }
    end
    local detail_win = api.nvim_open_win(detail, true, layout())
    s.input = { buf = detail, win = detail_win }
    local detail_ns = api.nvim_create_namespace('pathfinder_database_detail')
    for row, line in ipairs(lines) do
      local group = row == 1 and 'Title' or row == 3 and 'Title' or (line:find('REFERENC', 1, true) or line == '  FIELDS / BSON TYPES' or line == '  INDEXES') and 'DiagnosticInfo'
      if group then api.nvim_buf_set_extmark(detail, detail_ns, row - 1, 0, { end_col = #line, hl_group = group }) end
      if row > 4 and line:find('  ', 1, true) == 1 and (line:find('PK', 1, true) == 3 or line:find('FK', 1, true) == 3) then
        api.nvim_buf_set_extmark(detail, detail_ns, row - 1, 2, { end_col = 7, hl_group = 'DiagnosticInfo' })
      end
    end
    vim.wo[detail_win].wrap = false
    require('pathfinder.viewport').bind(detail)
    vim.wo[detail_win].linebreak = true
    vim.wo[detail_win].breakindent = true
    api.nvim_set_option_value('winhighlight', 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,FloatBorder:PathfinderBorder,FloatTitle:Title,FloatFooter:Comment,WinBar:PathfinderNormal,WinBarNC:PathfinderNormal', { win = detail_win, scope = 'local' })
    for _, key in ipairs({ '<Esc>', 'q', '<CR>', '<BS>', '-' }) do
      vim.keymap.set('n', key, function() dismiss_input(s) end, { buffer = detail, silent = true })
    end
    vim.keymap.set('n', 'v', function()
      dismiss_input(s)
      if active_connection then
        require('pathfinder.database_data').open({ connection = active_connection, tables = s.visible, index = s.index })
      end
    end, { buffer = detail, silent = true })
    api.nvim_create_autocmd('VimResized', { buffer = detail, callback = function()
      if api.nvim_win_is_valid(detail_win) then api.nvim_win_set_config(detail_win, layout()) end
    end })
    api.nvim_create_autocmd('WinLeave', { buffer = detail, once = true, callback = function()
      vim.schedule(function() if s.input and s.input.buf == detail then dismiss_input(s) end end)
    end })
  end
  local function data()
    if not active_connection or session.loading then return end
    require('pathfinder.database_data').open({ connection = active_connection, tables = session.visible, index = session.index })
  end
  require('pathfinder.viewport').bind(buf, function()
    local pos = session and session.positions[session.index]
    if pos then require('pathfinder.viewport').center(win, pos.col - 2 + (pos.width - 1) / 2) end
  end)
  for key, action in pairs({ v = data, D = M.close, q = M.close, ['<Esc>'] = M.close, ['<C-p>'] = M.close,
    u = M.prompt, c = M.connections, a = function() end, R = function() if connection then connect(connection) else M.prompt() end end,
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
      require('pathfinder.mongo_browser').close()
      require('pathfinder.database_data').close()
      dismiss_input(session)
      if session.job then session.job:kill(15) end
      local closing = session
      session = nil
      if closing.hidden_origin and api.nvim_win_is_valid(closing.origin) then api.nvim_win_set_config(closing.origin, { hide = false }) end
    end
  end })
  render()
  if not connection then M.prompt() else open_browser() end
end

return M
