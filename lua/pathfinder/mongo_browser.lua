local M = {}
local api = vim.api
local session
local source = debug.getinfo(1, 'S').source:sub(2)
local script = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))), 'scripts', 'mongo_meta.js')
local function clean(value) return tostring(value):gsub('%c', ' ') end

function M.command(connection, action, payload)
  payload = vim.tbl_extend('force', payload or {}, { action = action, database = connection.database })
  return { 'mongosh', '--quiet', '--norc', connection.url, '--eval', table.concat(vim.fn.readfile(script), '\n') },
    { text = true, timeout = 15000, stdin = vim.json.encode(payload) }
end

local function dimensions()
  return { relative = 'editor', row = 0, col = 0, width = math.max(1, vim.o.columns),
    height = math.max(1, vim.o.lines - vim.o.cmdheight), style = 'minimal', border = 'none', zindex = 64 }
end
local function render(s)
  if session ~= s or not api.nvim_win_is_valid(s.win) then return end
  local lines = { '  MongoDB / ' .. clean(s.connection.database or 'test'), '',
    s.layer == 'databases' and '  DATABASES  ·  Enter opens collections' or '  COLLECTIONS  ·  Enter opens documents', '' }
  if s.loading then lines[5] = '  Loading…'
  elseif #s.items == 0 then lines[5] = s.layer == 'databases' and '  No accessible databases.' or '  No collections. Press n to create one.'
  else
    for _, item in ipairs(s.items) do lines[#lines + 1] = '  › ' .. clean(item.name) .. (item.type and '  [' .. clean(item.type) .. ']' or '') end
  end
  if s.error then lines[#lines + 1] = ''; lines[#lines + 1] = '  ' .. s.error end
  vim.bo[s.buf].modifiable = true
  api.nvim_buf_set_lines(s.buf, 0, -1, false, lines)
  vim.bo[s.buf].modifiable = false
  s.index = math.max(1, math.min(s.index, #s.items))
  api.nvim_win_set_cursor(s.win, { math.min(#lines, s.index + 4), 0 })
  vim.wo[s.win].winbar = ' MongoDB · b databases · l collections · Enter documents · n create · r rename · dd drop · i indexes · R refresh · c connections · q files'
end
local function request(s, action, payload, done)
  if session ~= s or s.loading then return end
  s.loading, s.error = true, nil
  render(s)
  local command, opts = M.command(s.connection, action, payload)
  local ok, job = pcall(vim.system, command, opts, function(result)
    vim.schedule(function()
      if session ~= s then return end
      s.loading, s.job = false, nil
      if result.code ~= 0 then
        s.error = require('pathfinder.database').connection_error(result, s.connection.url)
      else
        local decoded, value = pcall(vim.json.decode, result.stdout or '')
        if not decoded then s.error = 'Invalid MongoDB metadata response' else done(value) end
      end
      render(s)
    end)
  end)
  if ok then s.job = job else s.loading = false; s.error = 'Cannot start mongosh'; render(s) end
end
local function load(s)
  request(s, s.layer, {}, function(items)
    if type(items) ~= 'table' or not vim.islist(items) then s.error = 'Invalid MongoDB list'; return end
    s.items = items
  end)
end
function M.close()
  local s = session
  if not s then return end
  session = nil
  require('pathfinder.database_data').close()
  if s.detail and api.nvim_win_is_valid(s.detail) then api.nvim_win_close(s.detail, true) end
  if s.job then s.job:kill(15) end
  if api.nvim_win_is_valid(s.win) then api.nvim_win_close(s.win, true) end
  if api.nvim_win_is_valid(s.origin) then
    if s.hidden_origin then api.nvim_win_set_config(s.origin, { hide = false }) end
    api.nvim_set_current_win(s.origin)
  end
end
function M.open(opts)
  M.close()
  vim.cmd.stopinsert()
  local origin = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, dimensions())
  local s = { buf = buf, win = win, origin = origin, connection = opts.connection, changed = opts.changed,
    layer = 'collections', items = {}, index = 1 }
  session = s
  if api.nvim_win_get_config(origin).relative ~= '' then
    s.hidden_origin = true
    api.nvim_win_set_config(origin, { hide = true })
  end
  vim.bo[buf].bufhidden, vim.bo[buf].filetype = 'wipe', 'pathfinder_mongo'
  vim.wo[win].winblend, vim.wo[win].wrap, vim.wo[win].cursorline = 0, false, true
  vim.wo[win].winhighlight = 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,WinBar:PathfinderDialog,WinBarNC:PathfinderDialog'
  local function selected() return not s.loading and s.items[s.index] end
  local function move(delta) s.index = math.max(1, math.min(#s.items, s.index + delta)); render(s) end
  local function layer(name)
    if s.loading then return end
    s.layer, s.items, s.index = name, {}, 1
    load(s)
  end
  local function documents()
    local item = selected()
    if not item then return end
    if s.layer == 'databases' then
      s.connection.database = item.name
      if s.changed then s.changed() end
      layer('collections')
    else
      require('pathfinder.database_data').open({ connection = s.connection, tables = s.items, index = s.index })
    end
  end
  local function back() M.close(); require('pathfinder.database').close() end
  local actions = {
    j = function() move(1) end, k = function() move(-1) end,
    ['<Down>'] = function() move(1) end, ['<Up>'] = function() move(-1) end,
    ['<CR>'] = documents, v = documents, b = function() layer('databases') end, l = function() layer('collections') end,
    R = function() load(s) end, q = back, ['<Esc>'] = back, D = back,
    c = function() M.close(); require('pathfinder.database').connections() end,
    u = function() M.close(); require('pathfinder.database').prompt() end,
    a = function() end,
    n = function()
      if s.layer ~= 'collections' or s.loading then return end
      vim.ui.input({ prompt = 'New collection in ' .. s.connection.database .. ': ' }, function(name)
        if session == s and name and vim.trim(name) ~= '' then
          request(s, 'create', { name = name }, function() vim.schedule(function() if session == s then load(s) end end) end)
        end
      end)
    end,
    r = function()
      local item = selected()
      if not item or s.layer ~= 'collections' then return end
      vim.ui.input({ prompt = 'Rename collection: ', default = item.name }, function(name)
        if session == s and name and vim.trim(name) ~= '' and name ~= item.name then
          request(s, 'rename', { name = item.name, replacement = name }, function() vim.schedule(function() if session == s then load(s) end end) end)
        end
      end)
    end,
    dd = function()
      local item = selected()
      if not item or s.layer ~= 'collections' then return end
      if vim.fn.confirm('Drop collection ' .. s.connection.database .. '.' .. item.name .. ' and all its documents?', '&Drop\n&Cancel', 2) == 1 and session == s then
        request(s, 'drop', { name = item.name }, function() vim.schedule(function() if session == s then load(s) end end) end)
      end
    end,
    i = function()
      local item = selected()
      if not item or s.layer ~= 'collections' then return end
      request(s, 'info', { name = item.name }, function(info)
        vim.schedule(function()
          if session ~= s then return end
          local detail = api.nvim_create_buf(false, true)
          api.nvim_buf_set_lines(detail, 0, -1, false, require('pathfinder.database_data').pretty(info))
          vim.bo[detail].bufhidden, vim.bo[detail].filetype, vim.bo[detail].modifiable = 'wipe', 'json', false
          local w, h = math.max(1, math.min(90, vim.o.columns - 6)), math.max(1, math.min(22, vim.o.lines - 6))
          local popup = api.nvim_open_win(detail, true, { relative = 'editor', row = 2, col = math.max(0, math.floor((vim.o.columns - w) / 2)),
            width = w, height = h, style = 'minimal', border = 'rounded', zindex = 75, title = ' Collection indexes ' })
          s.detail = popup
          vim.wo[popup].winblend = 0
          vim.wo[popup].winhighlight = 'Normal:PathfinderDialog,NormalFloat:PathfinderDialog,FloatBorder:PathfinderDialogBorder'
          for _, key in ipairs({ 'q', '<Esc>' }) do vim.keymap.set('n', key, function() api.nvim_win_close(popup, true) end, { buffer = detail }) end
        end)
      end)
    end,
  }
  for key, action in pairs(actions) do vim.keymap.set('n', key, action, { buffer = buf, silent = true, nowait = true }) end
  api.nvim_create_autocmd('VimResized', { buffer = buf, callback = function() if session == s then api.nvim_win_set_config(win, dimensions()) end end })
  api.nvim_create_autocmd('WinClosed', { pattern = tostring(win), once = true, callback = function() if session == s then M.close() end end })
  load(s)
end
return M
