vim.opt.runtimepath:prepend(vim.fn.getcwd())
local client = require('pathfinder.database_client')
local data = require('pathfinder.database_data')
local api = vim.api
local path = vim.fn.tempname() .. '.db'
assert(vim.system({ 'python3', '-c', [[import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE records(id INTEGER PRIMARY KEY, value TEXT)'); c.execute("INSERT INTO records VALUES(1, 'before')"); c.commit(); c.close()
]], path }):wait().code == 0)
local connection = { kind = 'sqlite', path = path }
local tbl = { name = 'records', columns = { { name = 'id', pk = true }, { name = 'value' } } }
local function key(name) vim.fn.maparg(name, 'n', false, true).callback() end
local function content() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
local function wait_for(value) assert(vim.wait(5000, function() return content():find(value, 1, true) ~= nil end), content()) end
local notices, notify = {}, vim.notify
vim.notify = function(message) notices[#notices + 1] = message end
data.open({ connection = connection, tables = { tbl } })
wait_for('before')
key('e')
assert(vim.bo.modifiable and vim.bo.filetype == 'json')
api.nvim_buf_set_lines(0, 0, -1, false, { '{"id":1,"value":"after"}' })
key('<C-s>')
assert(vim.wait(5000, function() return table.concat(notices):find('Record saved', 1, true) ~= nil end), table.concat(notices, '\n'))
wait_for('after')
assert(not vim.bo.modifiable)
local command, opts = client.write_command(connection, tbl, { id = 1, value = 'before' }, nil)
assert(vim.system(command, opts):wait().code ~= 0) -- stale delete must roll back
assert(not client.write_command(connection, tbl, { id = 1, value = 'after' }, { id = 2, value = 'after' }))
assert(not client.write_command(connection, { name = 'records', columns = {} }, { id = 1 }, nil))
local select = vim.ui.select
vim.ui.select = function(items, _, callback) callback(items[1]) end
key('dd')
assert(content():find('after', 1, true))
vim.ui.select = function(items, _, callback) callback(items[2]) end
key('dd')
wait_for('No records')
vim.ui.select = select
data.close()
local pg = { kind = 'postgres', url = 'postgres://host/db' }
local pgcmd, pgopts = client.write_command(pg, { name = 'public.records', columns = tbl.columns }, { id = 1, value = 'old' }, { id = 1, value = "O'Reilly\\text" })
assert(pgcmd[1] == 'psql' and pgopts.stdin:find('ROW_COUNT', 1, true))
assert(pgopts.stdin:find('to_jsonb(t)', 1, true) and pgopts.stdin:find('COMMIT', 1, true))
local mongo = { kind = 'mongo', url = 'mongodb://host/db' }
local original = { _id = { ['$oid'] = '0123456789abcdef01234567' }, value = { ['$numberLong'] = '99' } }
local cmd, options = client.write_command(mongo, { name = 'records' }, original, original)
assert(cmd[1] == 'mongosh' and cmd[#cmd]:find('replaceOne', 1, true))
assert(vim.deep_equal(vim.json.decode(options.stdin).replacement, original))
vim.notify = notify
vim.fn.delete(path)
print('Database writes: SQLite editing, delete, cancellation, conflict and client contracts passed')
vim.cmd('qa!')
