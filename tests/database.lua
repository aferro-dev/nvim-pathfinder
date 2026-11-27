vim.opt.runtimepath:prepend(vim.fn.getcwd())
local db = require('pathfinder.database')
assert(db.parse_url('sqlite:///tmp/example.db').path == '/tmp/example.db')
assert(db.parse_url('postgres://user:secret@localhost/db').kind == 'postgres')
assert(db.parse_url('postgresql://localhost/db').kind == 'postgres')
assert(not db.parse_url('mysql://localhost/db'))
assert(not db.parse_url('sqlite://:memory:'))
local message = db.connection_error({ code = 2, stderr = 'connection postgres://user:secret@localhost/db failed; password secret' }, 'postgres://user:secret@localhost/db')
assert(not message:find('secret', 1, true))
assert(message:find('failed', 1, true))
assert(db.connection_error({ code = 124 }, ''):find('timed out', 1, true))
local large = {}
for i = 1, 30 do large[i] = { name = 'public.table_' .. i, columns = { { name = 'id', type = 'uuid', pk = true } }, foreign_keys = {} } end
local overview, locations = db.diagram(large, 120)
assert(#locations == 30)
assert(#overview <= 120)
for _, node in ipairs(locations) do assert(node.bottom - node.top == 2) end

local narrow = db.diagram(large, 25)
assert(#narrow > 0)
local connected = {
  { name = 'public.parents', columns = { { name = 'id', type = 'uuid', pk = true } }, foreign_keys = {} },
  { name = 'public.children', columns = { { name = 'parent_id', type = 'uuid' } }, foreign_keys = {
    { column = 'parent_id', target_table = 'public.parents', target_column = 'id' },
    { column = 'other_parent', target_table = 'public.parents', target_column = 'id' },
    { column = 'previous', target_table = 'public.children', target_column = 'id' },
  } },
}
local graph, nodes, marks = db.diagram(connected, 100, {}, 2)
local graph_text = table.concat(graph, '\n')
assert(#nodes == 2 and (graph_text:find('▶', 1, true) or graph_text:find('◀', 1, true)))
assert(graph_text:find('▲', 1, true)) -- self-reference remains connected
assert(not graph_text:find('parent_id', 1, true)) -- collapsed fields retain the table edges
local active = false
for _, mark in ipairs(marks) do if mark[4] == 'DiagnosticInfo' then active = true end end
assert(active)
local detail = table.concat(require('pathfinder.database_graph').details(connected[2], connected), '\n')
assert(detail:find('REFERENCES', 1, true) and detail:find('REFERENCED BY', 1, true))
assert(detail:find('parent_id → parents.id', 1, true))
local mongo_detail = table.concat(require('pathfinder.database_graph').details({
  name = 'meal', columns = { { name = '_id', type = 'objectId' }, { name = 'amount', type = 'double | int' } },
  foreign_keys = {}, sample_size = 12,
  indexes = { { name = '_id_', unique = true, keys = '_id: 1' } },
}, {}, 'mongo'), '\n')
assert(mongo_detail:find('12 documents', 1, true))
assert(mongo_detail:find('double | int', 1, true))
assert(mongo_detail:find('_id_ [unique]', 1, true))
assert(not mongo_detail:find('REFERENCES', 1, true))
assert(not mongo_detail:find('NULL', 1, true))
local empty_mongo = table.concat(require('pathfinder.database_graph').details({ name = 'empty', columns = {} }, {}, 'mongo'), '\n')
assert(empty_mongo:find('No fields observed', 1, true))
local expanded_graph = table.concat(db.diagram(connected, 100, { ['public.children'] = true }, 2), '\n')
assert(expanded_graph:find('FK parent_id', 1, true))
assert(expanded_graph:find('▲', 1, true))
local distributed, spread_nodes = db.diagram(large, 200, {}, 1, 160)
assert(#distributed >= 130 and #distributed <= 160)
for i = 2, #spread_nodes do assert(spread_nodes[i].top > spread_nodes[i - 1].bottom) end
local wide_graph, wide_nodes = db.diagram(connected, 200, {}, 2, 80)
assert(math.abs(wide_nodes[1].col - wide_nodes[2].col) > 120)
for _, line in ipairs(wide_graph) do assert(vim.fn.strdisplaywidth(line) <= 200) end
local small_graph = db.diagram(large, 40, {}, 1, 12)
assert(#small_graph == #overview) -- no added vertical spacing when the graph overflows
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local path = root .. '/schema with spaces.db'
local create = [[import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.executescript('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL); CREATE TABLE posts (id INTEGER PRIMARY KEY, author_id INTEGER REFERENCES users, title TEXT); ')
c.close()
]]
assert(vim.system({ 'python3', '-c', create, path }):wait().code == 0)
local original_notify = vim.notify
local notices = {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.fn.writefile({ '# project connection', 'export DATABASE_URL="sqlite://' .. path .. '" # local', "OTHER='postgres://user:pass@localhost/db'", 'LITERAL=$(touch /tmp/should-never-run)' }, root .. '/.env')
assert(db.resolve_url('DATABASE_URL', root) == 'sqlite://' .. path)
assert(db.resolve_url('$DATABASE_URL', root) == 'sqlite://' .. path)
assert(db.resolve_url('${DATABASE_URL}', root) == 'sqlite://' .. path)
assert(db.resolve_url('OTHER', root) == 'postgres://user:pass@localhost/db')
assert(db.resolve_url('LITERAL', root) == '$(touch /tmp/should-never-run)')
assert(not db.resolve_url('MISSING', root))
assert(db.parse_url('sqlite://relative.db', root).path == root .. '/relative.db')
local function submit(value)
  local config = vim.api.nvim_win_get_config(0)
  assert(config.relative == 'win' and config.zindex == 70)
  assert(vim.api.nvim_buf_line_count(0) == 1)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { value })
  vim.fn.maparg('<CR>', 'i', false, true).callback()
end
local p = require('pathfinder')
p.open({ root = root })
local tree = vim.api.nvim_get_current_buf()
local tree_content = vim.api.nvim_buf_get_lines(tree, 0, -1, false)
local function content() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
db.toggle({ root = root })
submit('DATABASE_URL')
assert(vim.wait(5000, function() return content():find('› posts', 1, true) ~= nil end))
assert(vim.api.nvim_win_get_config(0).border == 'none')
assert(not content():find('author_id', 1, true))
local function key(name) vim.fn.maparg(name, 'n', false, true).callback() end
key('<CR>')
assert(content():find('author_id → users.id', 1, true))
assert(content():find('COLUMN', 1, true))
assert(content():find('INTEGER', 1, true))
key('<Esc>')
key('zR')
assert(content():find('FK author_id: INTEGER', 1, true))
key('zM')
assert(not content():find('author_id', 1, true))
key('H')
assert(not content():find('› posts', 1, true))
key('I')
assert(content():find('› posts', 1, true))
local tab = vim.fn.maparg('<Tab>', 'n', false, true)
tab.callback()
assert(vim.api.nvim_win_get_cursor(0)[2] > 0)
vim.o.columns = 100
vim.api.nvim_exec_autocmds('VimResized', {})
assert(vim.api.nvim_win_get_width(0) == 100)
local centered = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local first, last
for row, line in ipairs(centered) do
  if line:find('%S') then first, last = first or row, row end
end
local height = vim.api.nvim_win_get_height(0)
assert(first and math.abs((first - 1) - (height - last)) <= 1)
assert(vim.fn.line('w0') == 1)

db.close()
assert(vim.api.nvim_get_current_buf() == tree)
assert(vim.deep_equal(tree_content, vim.api.nvim_buf_get_lines(tree, 0, -1, false)))
db.toggle({ root = root })
assert(content():find('posts', 1, true))
notices = {}
db.prompt()
submit('sqlite://' .. root .. '/missing.db')
assert(vim.wait(5000, function() return table.concat(notices):find('Database connection failed', 1, true) ~= nil end))
assert(not vim.uv.fs_stat(root .. '/missing.db'))
assert(content() == 'sqlite://' .. root .. '/missing.db') -- failed input stays editable
assert(vim.wo.wrap and vim.api.nvim_win_get_height(0) >= 3)
local failed_buf = vim.api.nvim_get_current_buf()
submit('mysql://invalid/db') -- validation errors also allow another attempt
assert(vim.api.nvim_get_current_buf() == failed_buf)
submit('DATABASE_URL')
assert(vim.wait(5000, function() return content():find('› posts', 1, true) ~= nil end))
-- Reopening retains the last submitted value.
db.prompt()
assert(content() == 'DATABASE_URL')
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(content():find('posts', 1, true))
-- PostgreSQL URLs must be supplied as dbname so libpq expands all connection parameters.
local original_system, original_executable = vim.system, vim.fn.executable
local pending, killed
vim.fn.executable = function(name) if name == 'psql' then return 1 end; return original_executable(name) end
vim.system = function(command, opts, callback)
  assert(command[1] == 'psql')
  assert(command[2] == '--dbname')
  assert(command[3] == 'postgresql://user:secret@localhost/db?sslmode=disable')
  assert(not opts.env.PGDATABASE)
  assert(opts.timeout == 15000)
  assert(vim.fn.filereadable(command[#command]) == 1)
  pending = callback
  return { kill = function() killed = true end }
end
db.prompt()
submit('postgresql://user:secret@localhost/db?sslmode=disable')
pending({ code = 0, stdout = vim.json.encode({ { name = 'public.accounts', columns = { { name = 'id', type = 'uuid', pk = true, nullable = false } }, foreign_keys = {} } }) })
assert(vim.wait(1000, function() return content():find('› accounts', 1, true) ~= nil end))
db.prompt()
submit('postgresql://user:secret@localhost/db?sslmode=disable')
local cancelled = pending
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(killed)
cancelled({ code = 0, stdout = '[]' })
vim.wait(30, function() return false end)
assert(content():find('› accounts', 1, true)) -- cancelled responses cannot replace the schema
killed = false
db.prompt()
submit('postgresql://user:secret@localhost/db?sslmode=disable')
db.close()
assert(killed)
pending({ code = 0, stdout = '[]' })
vim.wait(30, function() return false end)
assert(vim.api.nvim_get_current_buf() == tree)
vim.system, vim.fn.executable = original_system, original_executable
db.toggle({ root = root })
local schema_buf = vim.api.nvim_get_current_buf()
db.prompt()
local input_buf = vim.api.nvim_get_current_buf()
db.prompt() -- opening again focuses the existing modal
assert(vim.api.nvim_get_current_buf() == input_buf)
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(vim.api.nvim_get_current_buf() == schema_buf)
assert(not vim.api.nvim_buf_is_valid(input_buf))
db.prompt()
input_buf = vim.api.nvim_get_current_buf()
db.close()
assert(not vim.api.nvim_buf_is_valid(input_buf))
p.close()
vim.notify = original_notify
vim.fn.delete(root, 'rf')
print('Database SQLite integration, .env, UML, switching, errors and PostgreSQL process contract passed')
vim.cmd('qa!')
