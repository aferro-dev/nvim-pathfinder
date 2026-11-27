vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local db = require('pathfinder.database')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local function key(name, mode) vim.fn.maparg(name, mode or 'n', false, true).callback() end
local function content() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
local function submit(value)
  api.nvim_buf_set_lines(0, 0, -1, false, { value })
  key('<CR>', 'i')
end
local function wait(text) assert(vim.wait(5000, function() return content():find(text, 1, true) ~= nil end), content()) end
for _, name in ipairs({ 'first', 'second' }) do
  assert(vim.system({ 'python3', '-c', 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE ' .. name .. ' (id INTEGER PRIMARY KEY)"); c.close()', root .. '/' .. name .. '.db' }):wait().code == 0)
end
db.toggle({ root = root })
submit('sqlite://' .. root .. '/first.db')
wait('› first')
key('zR')
assert(content():find('PK id', 1, true))
key('a')
submit('sqlite://' .. root .. '/second.db')
wait('› second')
assert(not content():find('first', 1, true))
key('c')
assert(content():find('first.db', 1, true) and content():find('second.db', 1, true))
assert(not content():find('sqlite://', 1, true))
api.nvim_win_set_cursor(0, { 3, 0 })
key('<CR>')
assert(content():find('PK id', 1, true)) -- per-connection expansion state
key('c')
local input = vim.ui.input
vim.ui.input = function(_, callback) callback('Primary database') end
key('r')
vim.ui.input = input
assert(content():find('Primary database', 1, true))
key('<CR>')
assert(vim.wo.winbar:find('Primary database', 1, true))
key('c')
api.nvim_win_set_cursor(0, { 4, 0 })
key('dd')
assert(not content():find('second.db', 1, true))
key('<Esc>')
db.close()
local other = vim.fn.tempname()
vim.fn.mkdir(other, 'p')
db.toggle({ root = other })
key('<Esc>', 'i')
key('c')
assert(content():find('No connections yet', 1, true))
db.close()
db.toggle({ root = root })
assert(content():find('PK id', 1, true)) -- project isolation and session retention
assert(vim.wo.winbar:find('Primary database', 1, true))
key('c')
key('dd') -- removing active entry clears stale data
key('<Esc>')
assert(not content():find('PK id', 1, true))
key('a')
submit('sqlite://' .. root .. '/second.db')
wait('› second')
-- Redis schema and key browser share the same connection manager.
if vim.env.REDIS_TEST_URL then
  key('a')
  submit(vim.env.REDIS_TEST_URL)
  wait('ttl')
  assert(vim.bo.filetype == 'pathfinder_database_data') -- Redis opens directly, without a UML card
  assert(vim.wo.winbar:find('Redis', 1, true))
  local ui_input, ui_select = vim.ui.input, vim.ui.select
  vim.ui.input = function(_, callback) callback('pathfinder-test:*') end
  key('/')
  wait('ttl')
  assert(content():find('Match: pathfinder-test:*', 1, true))
  vim.ui.select = function(_, _, callback) callback('string') end
  key('t')
  wait('ttl')
  assert(content():find('Type: string', 1, true))
  vim.ui.input, vim.ui.select = ui_input, ui_select
  key('<CR>')
  -- Non-string and truncated records are protected; complete strings are editable.
  local record = vim.json.decode(table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n'))
  assert(vim.bo.modifiable == (record.type == 'string' and not record.truncated))
  assert(vim.bo.filetype == 'json')
  vim.cmd('q')
  local found
  for _ = 1, 3 do
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    for row, line in ipairs(lines) do
      if row >= 5 and line:find('pathfinder-test:string', 1, true) then found = row; break end
    end
    if found then break end
    key(']')
    assert(vim.wait(5000, function() return content():find('ttl', 1, true) ~= nil end))
  end
  assert(found, 'Redis string fixture missing')
  for _ = 1, found - 5 do key('j') end
  key('e')
  local value = vim.json.decode(table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n'))
  assert(value.type == 'string' and value.key == 'pathfinder-test:string')
  value.value = 'saved in Neovim'
  api.nvim_buf_set_lines(0, 0, -1, false, require('pathfinder.database_data').pretty(value))
  vim.cmd('write')
  assert(not vim.bo.modified)
  vim.cmd('q')
  vim.ui.input = function(_, callback) callback('pathfinder-test:ui-new') end
  key('/')
  wait('No records on this page')
  local answers = { 'pathfinder-test:ui-new', 'created from UI' }
  vim.ui.input = function(_, callback) callback(table.remove(answers, 1)) end
  key('n')
  wait('created from UI')
  vim.ui.input = function(_, callback) callback('120') end
  key('T')
  wait('120')
  vim.ui.input = ui_input
  key('c')
  assert(content():find('second.db', 1, true) and content():find('redis', 1, true))
  assert(not content():find('pathfinder-test', 1, true))
  key('<Esc>')
  wait('ttl')
  assert(vim.bo.filetype == 'pathfinder_database_data')
  db.close()
  db.toggle({ root = root })
  wait('ttl')
  assert(vim.bo.filetype == 'pathfinder_database_data') -- cached Redis also opens the browser
  key('q')
  assert(vim.bo.filetype ~= 'pathfinder_database_data')
end
db.close()
vim.fn.delete(root, 'rf')
vim.fn.delete(other, 'rf')
print('Multiple connections: add, switch, rename, remove, per-project state and Redis browser passed')
vim.cmd('qa!')
