local M = {}
M.types = {
  { kind = 'postgres', name = 'PostgreSQL', default = 'postgresql://localhost:5432/postgres' },
  { kind = 'mongo', name = 'MongoDB', default = 'mongodb://localhost:27017/mydb' },
  { kind = 'sqlite', name = 'SQLite', default = 'sqlite://./knowledge.db' },
  { kind = 'redis', name = 'Redis', default = 'redis://localhost:6379/0' },
}
function M.detect(value)
  if value:match('^postgres[^:]*://') then return 'postgres' end
  if value:match('^mongodb[^:]*://') then return 'mongo' end
  if value:match('^sqlite[^:]*:') then return 'sqlite' end
  if value:match('^rediss?://') then return 'redis' end
end
function M.type(kind)
  for i, entry in ipairs(M.types) do if entry.kind == kind then return entry, i end end
  return M.types[1], 1
end

local function truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local length = vim.fn.strchars(text)
  while length > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, length) .. '…') > width do length = length - 1 end
  return vim.fn.strcharpart(text, 0, length) .. '…'
end

local function wrap(text, width)
  local lines, line = {}, ''
  for word in text:gmatch('%S+') do
    local candidate = line == '' and word or line .. ' ' .. word
    if vim.fn.strdisplaywidth(candidate) > width and line ~= '' then lines[#lines + 1], line = line, '' end
    while vim.fn.strdisplaywidth(word) > width do
      local count = vim.fn.strchars(word)
      while count > 1 and vim.fn.strdisplaywidth(vim.fn.strcharpart(word, 0, count)) > width do count = count - 1 end
      lines[#lines + 1], word = vim.fn.strcharpart(word, 0, count), vim.fn.strcharpart(word, count)
    end
    line = line == '' and word or line .. ' ' .. word
  end
  if line ~= '' then lines[#lines + 1] = line end
  return lines
end

-- One layout calculation owns both surfaces, including status and input wrapping.
function M.layout(columns, rows, value, error, loading, kind)
  local width = math.max(12, math.min(76, columns - 6))
  width = math.min(width, math.max(1, columns - 2))
  local inner = math.max(1, width - 6)
  local available = math.max(1, rows - 4)
  local compact = available < 12 or width < 42
  local field_row = math.min(compact and 1 or 3, math.max(0, available - 3))
  local field_height = math.min(5, math.max(3, math.ceil(vim.fn.strdisplaywidth(value) / math.max(1, inner - 2))))
  field_height = math.max(1, math.min(field_height, available - field_row - 5))
  local status_row = field_row + field_height + 4
  local detail = error and wrap(error, math.max(1, width - 4)) or {}
  local height = math.min(available, status_row + math.max(1, math.min(4, #detail)) + 1)
  local lines, marks = {}, {}
  for i = 1, height do lines[i] = '' end
  local function put(row, text, group)
    if row < 0 or row >= height then return end
    lines[row + 1] = '  ' .. truncate(text, math.max(1, width - 4))
    marks[#marks + 1] = { row, group }
  end
  local selected = M.type(kind)
  local choices = {}
  if not compact then
    local tabs = ''
    for _, entry in ipairs(M.types) do
      local label = entry.kind == selected.kind and '[ ' .. entry.name .. ' ]' or '  ' .. entry.name .. '  '
      local start = #tabs + 2
      tabs = tabs .. label .. ' '
      choices[#choices + 1] = { start = start, finish = start + #label, kind = entry.kind }
    end
    put(0, tabs, 'PathfinderMuted')
    for _, choice in ipairs(choices) do
      if choice.kind == selected.kind then marks[#marks + 1] = { 0, 'PathfinderInputLabel', choice.start, choice.finish } end
    end
    put(1, 'Tab / Shift-Tab: database type   ·   Click a type to select', 'PathfinderMuted')
  else
    put(0, selected.name .. ' · Tab: type', 'PathfinderInputLabel')
  end
  put(field_row + field_height + 2, compact and '.env: DATABASE_URL' or '.env example: DATABASE_URL', 'PathfinderMuted')
  local status = error and (compact and '● Failed — retry' or '● Connection failed — correct the URL and retry')
    or loading and '◌ Connecting…' or (compact and '● Ready' or '● Ready to connect')
  put(status_row - 1, status,
    error and 'DiagnosticError' or loading and 'DiagnosticInfo' or 'DiagnosticOk')
  for i = 1, math.min(#detail, height - status_row) do
    local text = detail[i]
    if i == height - status_row and i < #detail then text = truncate(text, math.max(1, width - 5)) .. '…' end
    put(status_row + i - 1, text, 'PathfinderMuted')
  end
  local footer = width >= 62 and ' Enter  Connect   Esc  Back   Ctrl-L  Connections '
    or width >= 38 and ' Enter Connect · Esc Back · ^L List ' or ' Enter OK · Esc Back '
  return {
    panel = { relative = 'editor', row = math.max(0, math.floor((rows - height - 2) / 2)),
      col = math.max(0, math.floor((columns - width - 2) / 2)), width = width, height = height,
      style = 'minimal', border = 'rounded', zindex = 69, focusable = true,
      title = ' Connection ', title_pos = 'left', footer = footer, footer_pos = 'center' },
    field = { relative = 'win', row = field_row, col = math.min(2, math.max(0, width - 3)),
      width = inner, height = field_height, style = 'minimal', border = 'rounded', zindex = 70,
      title = width >= 30 and ' URL / .env variable ' or ' URL ', title_pos = 'left' },
    lines = lines, marks = marks, choices = choices,
  }
end

return M
