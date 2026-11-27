vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local form = require('pathfinder.database_form')
for _, size in ipairs({ { 180, 45 }, { 100, 30 }, { 60, 24 }, { 40, 16 }, { 24, 12 } }) do
  for _, value in ipairs({ 'DATABASE_URL', 'postgresql://localhost/db?' .. string.rep('a', 280) }) do
    for _, err in ipairs({ false, 'Connection refused: ' .. string.rep('a very long server error ', 20) }) do
      local layout = form.layout(size[1], size[2], value, err or nil, false)
      local panel, field = layout.panel, layout.field
      assert(panel.row >= 0 and panel.col >= 0)
      assert(panel.col + panel.width + 2 <= size[1])
      assert(panel.row + panel.height + 2 <= size[2])
      assert(field.row >= 0 and field.col >= 0)
      assert(field.col + field.width + 2 <= panel.width)
      assert(field.row + field.height + 2 <= panel.height)
      assert(#layout.lines == panel.height)
      for row, line in ipairs(layout.lines) do
        assert(vim.fn.strdisplaywidth(line) <= panel.width)
        if row - 1 >= field.row and row - 1 < field.row + field.height + 2 then
          assert(line == '', 'Input must have reserved rows, independent of text wrapping')
        end
      end
      local status = table.concat(layout.lines, '\n')
      assert(status:find(err and 'ailed' or 'Ready', 1, true), status)
    end
  end
end
local db = require('pathfinder.database')
db.toggle({ root = vim.fn.getcwd() })
local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
local config = api.nvim_win_get_config(win)
local parent = config.win
assert(config.relative == 'win' and config.border ~= 'none')
assert(vim.wo[win].wrap and not vim.wo[win].cursorline)
assert(vim.wo[win].winblend == 0 and vim.wo[parent].winblend == 0)
local value = 'postgresql://localhost/db?' .. string.rep('x', 300)
api.nvim_buf_set_lines(buf, 0, -1, false, { value })
api.nvim_exec_autocmds('TextChangedI', { buffer = buf })
assert(api.nvim_win_get_height(win) == 5)
vim.o.columns, vim.o.lines = 50, 20
api.nvim_exec_autocmds('VimResized', {})
assert(api.nvim_buf_get_lines(buf, 0, 1, false)[1] == value)
config = api.nvim_win_get_config(win)
assert(config.win == parent and config.relative == 'win')
api.nvim_buf_set_lines(buf, 0, -1, false, { 'invalid://url' })
vim.notify = function() end
vim.fn.maparg('<CR>', 'i', false, true).callback()
assert(api.nvim_get_current_buf() == buf)
assert(table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(parent), 0, -1, false), '\n'):find('Connection failed', 1, true))
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(not api.nvim_win_is_valid(win) and not api.nvim_win_is_valid(parent))
db.close()
print('Connection form: layout containment, long URLs, errors, resize and cleanup passed')
vim.cmd('qa!')
