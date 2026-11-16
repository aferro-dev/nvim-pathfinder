vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local db = require('pathfinder.database')
local data = require('pathfinder.database_data')
local client = require('pathfinder.database_client')
local function content() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
local function key(name) vim.fn.maparg(name, 'n', false, true).callback() end
local function wait_for(text) assert(vim.wait(5000, function() return content():find(text, 1, true) ~= nil end), content()) end
assert(db.parse_url('mongodb://user:secret@localhost/catalog').kind == 'mongo')
assert(db.parse_url('mongodb+srv://host/catalog?retryWrites=true').kind == 'mongo')
assert(not db.parse_url('mongodb://localhost'))
local err = db.connection_error({ code = 1, stderr = 'secret p@ss mongodb://user:p%40ss@host/db' }, 'mongodb://user:p%40ss@host/db')
assert(not err:find('p@ss', 1, true) and not err:find('p%%40ss'))
local nested = { escaped = '"hello\\world', nested = { id = { ['$oid'] = 'abc' } }, null = vim.NIL }
assert(vim.deep_equal(vim.json.decode(table.concat(data.pretty(nested), '\n')), nested))
local grid = table.concat(data.grid({ columns = {} }, { { a = vim.NIL, text = 'hello\nworld' }, { b = 42 } }), '\n')
assert(grid:find('null', 1, true) and grid:find('—', 1, true) and grid:find('hello world', 1, true))

-- Exercise real SQLite reads, pagination, detail, selection, and lifecycle.
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local path = root .. '/data.db'
assert(vim.system({ 'python3', '-c', [[import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute('CREATE TABLE records(id INTEGER PRIMARY KEY, value TEXT, optional TEXT)')
c.executemany('INSERT INTO records VALUES(?, ?, NULL)', [(i, 'value '+str(i)) for i in range(1, 56)])
c.execute('CREATE TABLE empty(id INTEGER PRIMARY KEY)')
c.commit()
c.close()
]], path }):wait().code == 0)
local tables = { { name = 'records', columns = { { name = 'id', pk = true }, { name = 'value' }, { name = 'optional' } } },
  { name = 'empty', columns = { { name = 'id', pk = true } } } }
local origin = api.nvim_get_current_win()
data.open({ connection = { kind = 'sqlite', path = path }, tables = tables })
wait_for('value 1')
assert(content():find('50 records', 1, true) and content():find('null', 1, true))
local function cursor() return api.nvim_win_get_cursor(0) end
local selection_ns = api.nvim_get_namespaces().pathfinder_database_data_selection
local function highlighted(group, row)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(0, selection_ns, 0, -1, { details = true })) do
    if mark[2] == row and (mark[4].hl_group == group or mark[4].line_hl_group == group) then return mark end
  end
end
assert(cursor()[1] == 5 and cursor()[2] == 2)
assert(highlighted('PathfinderDataRow', 4) and highlighted('PathfinderDataCell', 4))
local first_header = assert(highlighted('PathfinderDataHeader', 2))
key('<Right>')
assert(cursor()[1] == 5 and cursor()[2] > 2)
local value_col = cursor()[2]
assert(api.nvim_get_current_line():sub(value_col + 1):find('value 1', 1, true) == 1)
assert(highlighted('PathfinderDataHeader', 2)[3] > first_header[3])
key('<Down>')
assert(cursor()[1] == 6 and cursor()[2] == value_col)
assert(highlighted('PathfinderDataCell', 5) and highlighted('PathfinderDataColumn', 4))
assert(highlighted('PathfinderDataRow', 5) and not highlighted('PathfinderDataRow', 4))
key('<CR>')
assert(content():find('value 2', 1, true)) -- detail follows the selected record
key('q')
key('l'); local last_col = cursor()[2]; key('l')
assert(cursor()[2] == last_col) -- stop at the final column
key('h'); key('<Left>'); key('h')
assert(cursor()[2] == 2 and cursor()[1] == 6)
key('k'); key('<Up>')
assert(cursor()[1] == 5) -- headers cannot be selected
vim.cmd('normal 3j')
assert(cursor()[1] == 8)
for _ = 1, 60 do key('j') end
assert(cursor()[1] == 54 and vim.fn.line('w0') > 1)
for _ = 1, 60 do key('k') end
assert(cursor()[1] == 5)
key('<CR>')
assert(vim.bo.filetype == 'json' and content():find('value 1', 1, true))
key('<Esc>')
key(']')
wait_for('value 51')
assert(content():find('5 records', 1, true) and content():find('Page 2', 1, true))
key(']') -- last page stays selected
assert(content():find('Page 2', 1, true))
key('['); wait_for('value 1')
key('<Tab>'); wait_for('No records')
assert(content():find('empty', 1, true) and content():find('Page 1', 1, true))
key('j'); key('l') -- empty tables do not attempt to select nonexistent cells
assert(#api.nvim_buf_get_extmarks(0, selection_ns, 0, -1, {}) == 0)
key('<S-Tab>'); wait_for('value 1')
local data_win = api.nvim_get_current_win()
vim.o.columns = 85
api.nvim_exec_autocmds('VimResized', {})
assert(api.nvim_win_get_width(data_win) == 85)
key('v')
assert(api.nvim_get_current_win() == origin and not api.nvim_win_is_valid(data_win))

-- Multibyte cells use byte offsets for the cursor and display widths for scrolling.
vim.o.columns = 24
data.open({ connection = { kind = 'sqlite', path = path }, tables = tables })
wait_for('value 1')
key('l'); key('l')
local narrow_col = cursor()[2]
assert(api.nvim_get_current_line():sub(narrow_col + 1):find('null', 1, true) == 1)
local leftcol = api.nvim_win_call(0, function() return vim.fn.winsaveview().leftcol end)
assert(leftcol > 0)
key('h'); key('h')
assert(cursor()[2] == 2)
data.close()
local unicode_lines, unicode_grid = data.grid({ columns = { { name = '名前' }, { name = 'emoji' } } },
  { { ['名前'] = '日本語', emoji = '🙂' } })
local second_cell = unicode_grid.cells[2][2]
assert(unicode_lines[3]:sub(second_cell.start + 1):find('🙂', 1, true) == 1)
assert(second_cell.start > second_cell.left)
vim.o.columns = 85

-- PostgreSQL and MongoDB process contracts, quoting, cancellation and stale responses.
local system, executable = vim.system, vim.fn.executable
vim.fn.executable = function(name) if name == 'psql' or name == 'mongosh' then return 1 end; return executable(name) end
local command, opts = client.data_command({ kind = 'postgres', url = 'postgres://host/db' },
  { name = 'odd.schema.table', schema = 'odd.schema', table = 'table";drop table x;--', columns = { { name = 'key"id', pk = true } } }, 2)
local sql = command[#command]
assert(sql:find('BEGIN READ ONLY', 1, true) and sql:find('ROLLBACK', 1, true))
assert(sql:find('"odd.schema"."table"";drop table x;--"', 1, true))
assert(sql:find('ORDER BY "key""id"', 1, true) and sql:find('LIMIT 51 OFFSET 100', 1, true))
assert(command[2] == '--dbname' and opts.timeout == 15000 and opts.env.PGCONNECT_TIMEOUT == '8')
local callbacks, killed, commands = {}, 0, {}
vim.system = function(cmd, options, callback)
  commands[#commands + 1] = cmd
  callbacks[#callbacks + 1] = callback
  assert(options.timeout == 15000)
  return { kill = function() killed = killed + 1 end }
end
local mongo = { kind = 'mongo', url = 'mongodb://user:secret@host/db' }
data.open({ connection = mongo, tables = { { name = 'one"\\collection', columns = {} }, { name = 'two', columns = {} } } })
assert(commands[1][1] == 'mongosh' and commands[1][3] == '--norc' and commands[1][4] == mongo.url)
assert(commands[1][6]:find(vim.json.encode('one"\\collection'), 1, true))
assert(commands[1][6]:find('.sort({_id:1}).skip(0).limit(51).maxTimeMS(10000)', 1, true))
assert(commands[1][6]:find('relaxed:false', 1, true))
key('<Tab>')
assert(killed == 1)
callbacks[1]({ code = 0, stdout = '[{"stale":"must not appear"}]' })
callbacks[2]({ code = 0, stdout = '[{"_id":{"$oid":"abc"},"nested":{"ok":true}}]' })
wait_for('$oid')
assert(not content():find('must not appear', 1, true))
key('<CR>'); assert(content():find('"nested"', 1, true)); key('q')
key('R')
callbacks[3]({ code = 124 })
wait_for('timed out')
key('R')
callbacks[4]({ code = 1, stderr = 'secret' })
wait_for('redacted')
assert(not content():find('secret', 1, true))
key('R'); data.close()
callbacks[5]({ code = 0, stdout = '[{"late":true}]' })
vim.wait(20, function() return false end)
assert(api.nvim_get_current_win() == origin)

-- Connect MongoDB through the existing database modal, then switch views.
db.toggle({ root = root })
api.nvim_buf_set_lines(0, 0, -1, false, { mongo.url })
vim.fn.maparg('<CR>', 'i', false, true).callback()
assert(commands[#commands][1] == 'mongosh')
callbacks[#callbacks]({ code = 0, stdout = '[{"name":"collection","columns":[],"foreign_keys":[]}]' })
wait_for('collection')
local schema_win = api.nvim_get_current_win()
key('v')
callbacks[#callbacks]({ code = 0, stdout = '[{"hello":"mongo"}]' })
wait_for('hello')
key('v')
assert(api.nvim_get_current_win() == schema_win)
key('v')
db.close() -- also cancels and closes the dependent data view
assert(api.nvim_get_current_win() == origin)
vim.system, vim.fn.executable = system, executable
vim.fn.delete(root, 'rf')
print('Database data: SQLite integration and PostgreSQL/MongoDB client contracts passed')
vim.cmd('qa!')
