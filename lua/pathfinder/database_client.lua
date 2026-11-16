local M = {}
local source = debug.getinfo(1, 'S').source:sub(2)
local scripts = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source))), 'scripts')
M.page_size = 50

local function identifier(value) return '"' .. value:gsub('"', '""') .. '"' end

function M.data_command(connection, tbl, page)
  local offset = math.max(0, math.floor(page or 0)) * M.page_size
  local opts = { text = true, timeout = 15000 }
  if connection.kind == 'postgres' then
    if vim.fn.executable('psql') ~= 1 then return nil, 'PostgreSQL support requires psql on PATH' end
    local schema, name = tbl.schema, tbl.table
    if not schema then schema, name = tbl.name:match('^([^.]+)%.(.+)$') end
    if not schema or not name then return nil, 'Missing PostgreSQL schema or table name' end
    local order = {}
    for _, column in ipairs(tbl.columns or {}) do
      if column.pk then order[#order + 1] = identifier(column.name) end
    end
    -- ctid gives heap tables without a primary key a repeatable order between writes.
    if #order == 0 then order = { 'tableoid', 'ctid' } end
    local sql = "BEGIN READ ONLY; SET LOCAL statement_timeout = '10s'; "
      .. "SELECT coalesce(json_agg(row_to_json(page)), '[]'::json) FROM (SELECT * FROM "
      .. identifier(schema) .. '.' .. identifier(name) .. ' ORDER BY ' .. table.concat(order, ', ')
      .. ' LIMIT ' .. (M.page_size + 1) .. ' OFFSET ' .. offset .. ') page; ROLLBACK;'
    opts.env = { PGCONNECT_TIMEOUT = '8', PGAPPNAME = 'nvim-pathfinder', PSQL_HISTORY = '/dev/null' }
    return { 'psql', '--dbname', connection.url, '-X', '-w', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-c', sql }, opts
  elseif connection.kind == 'mongo' then
    if vim.fn.executable('mongosh') ~= 1 then return nil, 'MongoDB support requires mongosh on PATH' end
    local js = 'print(EJSON.stringify(db.getCollection(' .. vim.json.encode(tbl.name)
      .. ').find({}).sort({_id:1}).skip(' .. offset .. ').limit(' .. (M.page_size + 1)
      .. ').maxTimeMS(10000).toArray(), null, 0, {relaxed:false}));'
    return { 'mongosh', '--quiet', '--norc', connection.url, '--eval', js }, opts
  elseif connection.kind == 'sqlite' then
    if vim.fn.executable('python3') ~= 1 then return nil, 'SQLite support requires python3' end
    return { 'python3', vim.fs.joinpath(scripts, 'sqlite_data.py'), connection.path, tbl.name,
      tostring(M.page_size + 1), tostring(offset) }, opts
  end
  return nil, 'Unsupported database'
end

return M
