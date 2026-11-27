vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local db = require('pathfinder.database')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local collections = { alpha = { users = true }, beta = { events = true }, corrected = {} }
local original_system, original_input, original_confirm = vim.system, vim.ui.input, vim.fn.confirm
local calls = {}
vim.system = function(command, opts, callback)
  assert(command[1] == 'mongosh')
  local payload = opts.stdin and vim.json.decode(opts.stdin)
  local result = {}
  if payload then
    calls[#calls + 1] = payload
    local target = collections[payload.database]
    if payload.action == 'databases' then
      result = { { name = 'alpha' }, { name = 'beta' } }
    elseif payload.action == 'collections' then
      for name in pairs(target) do result[#result + 1] = { name = name, type = 'collection', columns = {}, foreign_keys = {} } end
      table.sort(result, function(a, b) return a.name < b.name end)
    elseif payload.action == 'create' then target[payload.name] = true
    elseif payload.action == 'rename' then
      assert(not target[payload.replacement])
      target[payload.name], target[payload.replacement] = nil, true
    elseif payload.action == 'drop' then target[payload.name] = nil
    elseif payload.action == 'info' then result = { collection = payload.name, indexes = { { name = '_id_', key = { _id = 1 } } } }
    else error('Unexpected metadata operation') end
  elseif command[6]:find('.find({})', 1, true) then
    assert(command[6]:find('db.getSiblingDB("beta")', 1, true))
    result = { { _id = 1, value = 'document in beta' } }
  end
  vim.schedule(function() callback({ code = 0, stdout = vim.json.encode(result) }) end)
  return { kill = function() end }
end
local function key(name, mode) vim.fn.maparg(name, mode or 'n', false, true).callback() end
local function text() return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
local function wait(value) assert(vim.wait(1000, function() return text():find(value, 1, true) end), text()) end
local function submit(url)
  api.nvim_buf_set_lines(0, 0, -1, false, { url })
  key('<CR>', 'i')
end
db.toggle({ root = root })
submit('mongodb://localhost:27017/alpha')
wait('› users')
assert(vim.bo.filetype == 'pathfinder_mongo')
key('b')
wait('› beta')
key('j')
key('<CR>')
wait('› events')
assert(text():find('MongoDB / beta', 1, true))
key('<CR>')
wait('document in beta')
assert(text():find('beta / events', 1, true))
key('q')
assert(vim.bo.filetype == 'pathfinder_mongo')
local client = require('pathfinder.database_client')
local write = client.write_command({ kind = 'mongo', url = 'mongodb://localhost:27017/alpha?authSource=admin', database = 'beta' },
  { name = 'events' }, { _id = 1 }, { _id = 1, value = 'changed' })
assert(write[4] == 'mongodb://localhost:27017/alpha?authSource=admin')
assert(write[6]:find('db.getSiblingDB("beta")', 1, true))

vim.ui.input = function(_, callback) callback('new_collection') end
key('n')
wait('› new_collection')
key('j')
vim.ui.input = function(_, callback) callback('renamed') end
key('r')
wait('› renamed')
key('i')
wait('_id_')
key('q')
vim.fn.confirm = function() return 2 end
local count = #calls
key('dd')
assert(#calls == count and collections.beta.renamed)
vim.fn.confirm = function() return 1 end
key('dd')
assert(vim.wait(1000, function() return not collections.beta.renamed end))
assert(vim.wait(1000, function() return text():find('› events', 1, true) and not text():find('Loading', 1, true) end))
key('c')
assert(text():find('localhost:27017/beta', 1, true)) -- actual selected database in the connection label
key('u')
submit('mongodb://localhost:27017/corrected')
wait('No collections')
assert(text():find('MongoDB / corrected', 1, true))
key('c')
assert(text():find('localhost:27017/corrected', 1, true))
assert(not text():find('/alpha', 1, true) and not text():find('/beta', 1, true))
key('r') -- custom name survives endpoint changes
key('u')
submit('mongodb://localhost:27017/alpha')
wait('› users')
key('c')
assert(text():find('renamed', 1, true))
key('<Esc>')
wait('› users')
db.close()
vim.system, vim.ui.input, vim.fn.confirm = original_system, original_input, original_confirm
vim.fn.delete(root, 'rf')
print('MongoDB browser: databases, collections, documents, create, rename, drop confirmation, indexes and current endpoint passed')
vim.cmd('qa!')
