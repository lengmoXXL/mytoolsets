return {
  'esmuellert/codediff.nvim',
  cmd = { 'CodeDiff' },
  keys = {
    {
      '<leader>gw',
      function()
        local ok, lifecycle = pcall(require, 'codediff.ui.lifecycle')
        if ok then
          for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
            local panel = lifecycle.get_panel(tabpage)
            local explorer = lifecycle.get_panel_view(tabpage)
            if
              panel
              and panel.name == 'explorer'
              and explorer
              and not explorer.base_revision
              and not explorer.target_revision
              and not explorer.dir1
              and not explorer.dir2
            then
              vim.api.nvim_set_current_tabpage(tabpage)
              return
            end
          end
        end

        vim.cmd('CodeDiff')
      end,
      desc = 'CodeDiff Workspace',
    },
  },
  opts = {
    explorer = {
      focus_on_select = true,
    },
    keymaps = {
      view = {
        focus_explorer = '<leader>ge',
      },
    },
  },
  -- neogit 上游集成仍写旧的 session_config（mode/explorer_data/original_path），
  -- codediff 2.67.9+ 已改为 panel/original/modified（Path 对象），见 NeogitOrg/neogit#2008。
  -- 运行时翻译旧结构，避免改插件工作区（本地改动会让 lazy 更新 neogit 报错）。
  config = function(_, opts)
    require('codediff').setup(opts)

    local path = require('codediff.core.path')
    local view = require('codediff.ui.view')
    local create = view.create
    view.create = function(session_config, filetype, on_ready)
      if session_config.panel == nil then
        if session_config.mode == 'explorer' then
          session_config.panel = { name = 'explorer', data = session_config.explorer_data or {} }
          session_config.original = session_config.original or path.empty()
          session_config.modified = session_config.modified or path.empty()
        elseif session_config.original_path ~= nil then
          session_config.original = session_config.original
            or path.make_ref(session_config.original_path, session_config.git_root)
          session_config.modified = session_config.modified
            or path.make_ref(session_config.modified_path or session_config.original_path, session_config.git_root)
        end
      end
      return create(session_config, filetype, on_ready)
    end
  end,
}
