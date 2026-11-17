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

function M.write_command(connection, tbl, original, replacement)
  local keys = {}
  if connection.kind == 'mongo' then
    if original._id == nil then return nil, 'Record has no _id' end
    keys = { '_id' }
  else
    for _, col in ipairs(tbl.columns or {}) do if col.pk then keys[#keys + 1] = col.name end end
    if #keys == 0 then return nil, 'Editing and deletion require a primary key' end
  end
  for _, key in ipairs(keys) do
    if original[key] == nil or original[key] == vim.NIL then return nil, 'Record has no usable primary key' end
    if replacement and not vim.deep_equal(original[key], replacement[key]) then return nil, 'Primary keys cannot be changed' end
  end
  if replacement and connection.kind ~= 'mongo' then
    for key in pairs(original) do if replacement[key] == nil then return nil, 'Keep every column; use null to clear a value' end end
    for key in pairs(replacement) do if original[key] == nil then return nil, 'Unknown column: ' .. key end end
  end
  local payload = { original = original, replacement = replacement, table = tbl.name, keys = keys }
  local opts = { text = true, timeout = 15000, stdin = vim.json.encode(payload) }
  if connection.kind == 'sqlite' then
    return { 'python3', vim.fs.joinpath(scripts, 'sqlite_write.py'), connection.path }, opts
  elseif connection.kind == 'mongo' then
    return { 'mongosh', '--quiet', '--norc', connection.url, '--eval', table.concat(vim.fn.readfile(vim.fs.joinpath(scripts, 'mongo_write.js')), '\n') }, opts
  elseif connection.kind == 'postgres' then
    local schema, name = tbl.schema, tbl.table
    if not schema then schema, name = tbl.name:match('^([^.]+)%.(.+)$') end
    if not schema or not name then return nil, 'Missing PostgreSQL schema or table name' end
    local function literal(value) return "E'" .. value:gsub('\\', '\\\\'):gsub("'", "''") .. "'" end
    local target = identifier(schema) .. '.' .. identifier(name)
    local old = literal(vim.json.encode(original)) .. '::jsonb'
    local where = { 'to_jsonb(t) = ' .. old }
    for _, key in ipairs(keys) do
      where[#where + 1] = 't.' .. identifier(key) .. ' IS NOT DISTINCT FROM (jsonb_populate_record(NULL::' .. target .. ', ' .. old .. ')).' .. identifier(key)
    end
    local mutation
    if replacement then
      local assignments = {}
      local record = 'jsonb_populate_record(NULL::' .. target .. ', ' .. literal(vim.json.encode(replacement)) .. '::jsonb)'
      for _, col in ipairs(tbl.columns) do
        if not vim.deep_equal(original[col.name], replacement[col.name]) then
          assignments[#assignments + 1] = identifier(col.name) .. ' = (' .. record .. ').' .. identifier(col.name)
        end
      end
      if #assignments == 0 then return nil, 'No changes to save' end
      mutation = 'UPDATE ' .. target .. ' AS t SET ' .. table.concat(assignments, ', ')
    else mutation = 'DELETE FROM ' .. target .. ' AS t' end
    local body = 'DECLARE affected integer; BEGIN ' .. mutation .. ' WHERE ' .. table.concat(where, ' AND ')
      .. "; GET DIAGNOSTICS affected = ROW_COUNT; IF affected <> 1 THEN RAISE EXCEPTION 'Record changed or disappeared; reload before retrying'; END IF; END;"
    opts.stdin = "BEGIN; SET LOCAL statement_timeout = '10s'; DO " .. literal(body) .. "; COMMIT;"
    opts.env = { PGCONNECT_TIMEOUT = '8', PGAPPNAME = 'nvim-pathfinder', PSQL_HISTORY = '/dev/null' }
    return { 'psql', '--dbname', connection.url, '-X', '-w', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1' }, opts
  end
  return nil, 'Unsupported database'
end

return M
