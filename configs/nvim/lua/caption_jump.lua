-- markdown 代码块 caption 跳转：代码块下方一行是 caption（`> path:start-end`，
-- 路径相对当前文件所在目录）。块内 gd 跳到对应行（块内第 N 行 -> start+N-1），
-- caption 行上 gd 跳到 start；无 caption 时回落到 LSP 定义。
local M = {}

local function parse_caption(text)
  local t = text:match('^%s*>%s*(.-)%s*$')
  if not t then return end
  local path, s, e = t:match('^(.-):(%d+)%-(%d+)$')
  if path and path ~= '' then
    return path, tonumber(s), tonumber(e)
  end
  path, s = t:match('^(.-):(%d+)$')
  if path and path ~= '' then
    return path, tonumber(s), tonumber(s)
  end
end

function M.jump()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]

  local path, start_l, end_l = parse_caption(lines[row] or '')
  if not path then
    local open = row
    while open > 1 and not lines[open]:match('^%s*```') do
      open = open - 1
    end
    local close = row + 1
    while close <= #lines and not lines[close]:match('^%s*```') do
      close = close + 1
    end
    if lines[open] and lines[open]:match('^%s*```') and close <= #lines and close > open then
      local cap = close + 1
      while cap <= #lines and lines[cap]:match('^%s*$') do
        cap = cap + 1
      end
      path, start_l, end_l = parse_caption(lines[cap] or '')
      if path and row > open then
        start_l = math.min(start_l + row - open - 1, end_l)
      end
    end
  end

  if not path then
    require('snacks').picker.lsp_definitions()
    return
  end

  local full = vim.fn.expand('%:p:h') .. '/' .. path
  if vim.fn.filereadable(full) ~= 1 then
    vim.notify('[caption-jump] 引用文件不存在: ' .. path, vim.log.levels.WARN)
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(full))
  vim.api.nvim_win_set_cursor(0, { start_l, 0 })
  vim.cmd('normal! zz')
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('UserCaptionJump', { clear = true }),
    pattern = 'markdown',
    callback = function(args)
      vim.keymap.set('n', 'gd', M.jump, {
        buffer = args.buf,
        desc = 'Jump to cited code, fallback LSP definition',
      })
    end,
  })
end

return M
