return {
  'NeogitOrg/neogit',
  cmd = { 'Neogit', 'NeogitLogCurrent' },
  keys = {
    { '<leader>gg', '<cmd>Neogit<cr>', desc = 'Neogit' },
    { '<leader>gf', '<cmd>NeogitLogCurrent<cr>', desc = 'Neogit File History' },
    { '<leader>gl', '<cmd>Neogit log<cr>', desc = 'Neogit Log History' },
  },
  -- codediff 集成契约差异（大版本改 API）由 plugins/codediff.lua 的运行时 shim 兜住，见 NeogitOrg/neogit#2008
  opts = {
    integrations = {
      codediff = true,
    },
    diff_viewer = 'codediff',
  },
}
