local M = {}
local api = vim.api
local win, buf

function M.width()
  return math.min(math.max(1, vim.o.columns - 1), math.max(20, math.floor(vim.o.columns * 0.32)))
end

function M.close()
  if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  if buf and api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
  win, buf = nil, nil
end

local function contents(node)
  if node.dir then return { 'Select a file to preview' } end
  -- Prefer unsaved text already loaded in the editor.
  local existing = vim.fn.bufnr(node.path)
  if existing >= 0 and api.nvim_buf_is_loaded(existing) then
    return api.nvim_buf_get_lines(existing, 0, 200, false)
  end
  local stat = vim.uv.fs_stat(node.path)
  if not stat or stat.type ~= 'file' then return { 'Preview unavailable' } end
  local fd = vim.uv.fs_open(node.path, 'r', 0)
  if not fd then return { 'Cannot read file' } end
  local data = vim.uv.fs_read(fd, math.min(stat.size, 65536), 0)
  vim.uv.fs_close(fd)
  if not data then return { 'Cannot read file' } end
  if data:find('%z') then return { 'Binary file' } end
  local lines = vim.split(data, '\n', { plain = true })
  while #lines > 200 do table.remove(lines) end
  for i, line in ipairs(lines) do lines[i] = line:gsub('\r$', '') end
  if stat.size > #data or select(2, data:gsub('\n', '')) >= 200 then
    lines[#lines + 1] = '… preview truncated …'
  end
  return lines
end

function M.show(node)
  if not buf or not api.nvim_buf_is_valid(buf) then
    buf = api.nvim_create_buf(false, true)
    vim.bo[buf].swapfile = false
  end
  local width = M.width()
  local layout = { relative = 'editor', row = 0, col = vim.o.columns - width,
    width = width, height = math.max(1, vim.o.lines - vim.o.cmdheight),
    style = 'minimal', border = 'none', focusable = false, zindex = 51 }
  if win and api.nvim_win_is_valid(win) then api.nvim_win_set_config(win, layout)
  else win = api.nvim_open_win(buf, false, layout) end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, contents(node))
  vim.bo[buf].modifiable = false
  local ft = not node.dir and vim.filetype.match({ filename = node.path }) or ''
  vim.bo[buf].filetype = ft or ''
  vim.bo[buf].syntax = ft or ''
  vim.wo[win].winbar = '%#PathfinderMuted# Preview · ' .. node.name:gsub('%c', ' '):gsub('%%', '%%%%')
  vim.wo[win].winhighlight = 'Normal:PathfinderNormal,NormalFloat:PathfinderNormal,WinBar:PathfinderNormal'
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].fillchars = 'eob: '
  api.nvim_win_set_cursor(win, { 1, 0 })
  api.nvim_win_call(win, function() vim.fn.winrestview({ topline = 1, leftcol = 0 }) end)
end

return M
