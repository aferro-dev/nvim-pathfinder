local M = {}

-- Link to the user's highlights; only rounded caps need derived colors.
function M.apply()
  local links = {
    PathfinderNormal = 'Normal',
    PathfinderDirectory = 'Directory',
    PathfinderAncestor = 'CursorLine',
    PathfinderSelected = 'Visual',
    PathfinderBadge = 'Title',
    PathfinderConnector = 'NonText',
    PathfinderBorder = 'WinSeparator',
    PathfinderMuted = 'Comment',
    PathfinderKey = 'Special',
    PathfinderDataRow = 'CursorLine',
    PathfinderDataId = 'Comment',
    PathfinderDataDate = 'Special',
    PathfinderDataNumber = 'Number',
    PathfinderDataBoolean = 'Boolean',
    PathfinderDataNull = 'Comment',
    PathfinderDataObject = 'Type',
    PathfinderDataBorder = 'NonText',
  }
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { default = true, link = target })
  end
  for name, target in pairs({ PathfinderDatabaseTitle = 'Title', PathfinderDatabaseSelected = 'PathfinderSelected' }) do
    local hl = vim.api.nvim_get_hl(0, { name = target, link = false })
    hl.bold = true
    hl.default = true
    vim.api.nvim_set_hl(0, name, hl)
  end
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  local canvas = vim.api.nvim_get_hl(0, { name = 'PathfinderNormal', link = false })
  local function blend(a, b, weight)
    local result = 0
    for _, shift in ipairs({ 16, 8, 0 }) do
      local channel = math.floor(bit.band(bit.rshift(a, shift), 255) * (1 - weight)
        + bit.band(bit.rshift(b, shift), 255) * weight + 0.5)
      result = result + bit.lshift(channel, shift)
    end
    return result
  end
  local bg, fg = canvas.bg or normal.bg or 0x151820, canvas.fg or normal.fg or 0xd8dee9
  local info = vim.api.nvim_get_hl(0, { name = 'DiagnosticInfo', link = false })
  local accent = info.fg or 0x61afef
  for name, hl in pairs({
    PathfinderDataText = { fg = fg },
    PathfinderDataStripe = { bg = blend(bg, fg, 0.035), ctermbg = 235 },
    PathfinderDataRow = { bg = blend(bg, accent, 0.13), ctermbg = 236 },
    PathfinderDataColumn = { bg = blend(bg, accent, 0.10), ctermbg = 235 },
    PathfinderDataHeading = { fg = accent, bg = blend(bg, accent, 0.08), bold = true, ctermfg = 81, ctermbg = 235 },
    PathfinderDataHeader = { fg = accent, bg = blend(bg, accent, 0.22), bold = true, underline = false, ctermfg = 81, ctermbg = 24 },
    PathfinderDataCell = { fg = 0xffffff, bg = 0x315b86, bold = true, underline = false,
      reverse = false, standout = false, ctermfg = 231, ctermbg = 24, cterm = { bold = true } },
  }) do
    vim.api.nvim_set_hl(0, name, hl)
  end
  for name, surface in pairs({
    PathfinderDirectoryEdge = 'PathfinderDirectory',
    PathfinderAncestorEdge = 'PathfinderAncestor',
    PathfinderSelectedEdge = 'PathfinderSelected',
    PathfinderKeyEdge = 'PathfinderKey',
  }) do
    local hl = vim.api.nvim_get_hl(0, { name = surface, link = false })
    vim.api.nvim_set_hl(0, name, {
      fg = hl.bg or canvas.bg or normal.bg,
      bg = canvas.bg or normal.bg,
      ctermfg = hl.ctermbg or canvas.ctermbg or normal.ctermbg,
      ctermbg = canvas.ctermbg or normal.ctermbg,
    })
  end
end

function M.setup()
  M.apply()
  local group = vim.api.nvim_create_augroup('PathfinderTheme', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply })
end

return M
