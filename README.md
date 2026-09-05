# configs

## 文件内容

```
configs/
├── .gitignore
├── .nvim.lua
├── AGENTS.md -> README.md
├── README.md
├── setup.sh                    # 一键初始化: 默认 --init 基础配置，--nvim 等场景需先 --init
├── sync.sh                     # UPDATE=1 遍历 install/ 更新已安装的工具与配置（含 # sync: skip 的除外）
├── install/
│   ├── agent-prompts.sh
│   ├── clash-for-linux.sh
│   ├── clashctl.sh
│   ├── cmake.sh
│   ├── codex.sh
│   ├── codex-batch.sh
│   ├── doc-research.sh         # doc-research CLI（固定 commit，对比远端提示更新）
│   ├── doc-research-init.sh
│   ├── fd.sh
│   ├── fonts.sh
│   ├── fzf.sh
│   ├── gh.sh
│   ├── ghostty-config.sh
│   ├── ghostty-terminfo.sh
│   ├── git-prune-merged.sh
│   ├── herdr.sh
│   ├── herdr-config.sh
│   ├── kimi.sh
│   ├── kimi-config.sh
│   ├── nvim.sh
│   ├── nvim-config.sh
│   ├── nvim-ft.sh
│   ├── oh-my-bash.sh           # Linux: Oh My Bash + ~/.bashrc（env.d 加载、PATH）
│   ├── oh-my-zsh.sh            # macOS: Oh My Zsh + ~/.zshrc（env.d 加载、PATH）
│   ├── opencode-auth.sh        # auth.json 合并式更新（sync: skip，手动执行）
│   ├── opencode-config.sh
│   ├── opencode.sh
│   ├── ossutil.sh
│   ├── perf-to-profile.sh
│   ├── pi-agent.sh
│   ├── pi-auth.py             # auth.json 合并式更新（sync: skip，手动执行）
│   ├── pi-config.sh           # 配置 + 自研 extensions
│   ├── pj.sh
│   ├── playwright.sh
│   ├── prd.sh
│   ├── ripgrep.sh
│   ├── style-check.sh
│   ├── tldr.sh
│   ├── tmux.sh
│   ├── tmux-config.sh
│   ├── tree-sitter.sh
│   ├── uv.sh
│   ├── compiler/               # 语言编译器/运行时
│   │   ├── clang.sh
│   │   ├── go.sh
│   │   ├── node.sh
│   │   ├── python.sh
│   │   ├── rust.sh
│   │   └── zig.sh
│   ├── lsp/
│   │   ├── bash-lsp.sh
│   │   ├── lua-lsp.sh
│   │   ├── markdown-oxide.sh
│   │   ├── pyright-lsp.sh
│   │   ├── rust-analyzer-lsp.sh
│   │   ├── starpls-lsp.sh
│   │   ├── typescript-lsp.sh
│   │   └── typos-lsp.sh
│   └── skill/                  # skill 安装
│       ├── code-report.sh
│       ├── code-style.sh
│       ├── frontend-draw.sh
│       └── neovim-skill.sh
├── configs/
│   ├── agents/
│   │   ├── editing-constraints.md
│   │   ├── git-safety.md
│   │   ├── inline-functions.md
│   │   └── response-style.md
│   ├── ghostty/
│   │   └── config
│   ├── herdr/
│   │   └── config.toml
│   ├── kimi/
│   │   └── themes/
│   │       └── gray.json
│   ├── nvim/
│   │   ├── init.lua
│   │   ├── patches/
│   │   │   └── neogit-codediff-session-config.patch  # neogit 集成适配 codediff 新 API，由 neogit.lua 的 build 钩子自动应用
│   │   └── lua/
│   │       ├── buffer_columns.lua
│   │       ├── caption_jump.lua
│   │       ├── project_filetypes.lua
│   │       ├── project_state.lua
│   │       ├── snacks_tab.lua
│   │       ├── snacks_terminal.lua
│   │       ├── plugins/
│   │       │   └── ...
│   │       └── themes/
│   │           └── ...
│   ├── pi/
│   │   ├── auth.json
│   │   ├── models.json
│   │   ├── settings.json
│   │   ├── pi-plan-mode.json
│   │   ├── zentui.json
│   │   ├── agents/
│   │   │   └── worker.md
│   │   ├── extensions/
│   │   │   ├── bash-highlight.ts
│   │   │   ├── flat-editor.ts.disabled
│   │   │   ├── herdr-agent-state.ts  # herdr 状态上报集成（herdr 管理，升级时从 herdr integration install pi 重新同步）
│   │   │   ├── link-pi-types.sh
│   │   │   ├── refine.ts
│   │   │   └── tsconfig.json
│   │   └── themes/
│   │       └── gray.json
│   └── tmux/
│       └── tmux.conf
├── skills/
│   ├── code-report/
│   │   └── ...
│   ├── code-style/
│   │   └── ...
│   ├── frontend-draw/
│   │   └── ...
│   └── publish-frontend-draw-assets.sh
└── tools/
    ├── build-perf-to-profile.sh
    ├── codex_batch.py
    ├── common.sh                # install 脚本共享函数（confirm_update / managed block / write-if-changed）
    ├── doc-research-init.sh      # 初始化文献调研项目（raw/tr/dist + 工作流 README）
    ├── github-release-latest.sh
    ├── git-prune-merged.sh
    ├── nvim_ft.py               # 按 git URL 管理 Neovim filetype
    ├── pj/                      # 仓库命令工具
    │   └── ...
    ├── prd/                     # 本机文件 HTTP 预览工具
    │   ├── src/preview_server.ts
    │   └── ...
    ├── secrets.sh               # 同步 provider API keys
    └── style-check.sh
```

## install 脚本约束

新增 `install/` 脚本须遵守以下协议，才能接入 `setup.sh` / `sync.sh`：

- **一件事**：一个脚本只装一个工具；缺依赖时报错并指引对应脚本，不自动安装
- **固定版本**：版本/commit/tag 写成脚本常量，不查最新版；无版本输出的写入 `~/.local/share/configs-setup/versions/` 比对
- **CN=1**：走国内代理/镜像，读取处直接 `[[ "${CN:-}" == "1" ]]`，不加 `-cn` 参数
- **UPDATE=1**：未安装则跳过；已安装且不一致时先 `confirm_update` 再执行
- **文本修改**：文件内片段用 `write_managed_block`，整文件用 `write_file_if_changed`，目录用 `rsync -ai --delete`（先 dry-run 列差异再确认）；函数在 `tools/common.sh`，脚本开头 `source`
- **sync 豁免**：构建型/交互型脚本在头部加 `# sync: skip`
- **bash 3.2**（macOS 自带）：`$VAR` 后紧贴多字节字符写 `${VAR}`；`set -u` 下空数组展开前用 `${#arr[@]}` 守卫
