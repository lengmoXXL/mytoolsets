# configs

## 文件内容

```
configs/
├── .gitignore
├── .nvim.lua
├── AGENTS.md -> README.md
├── README.md
├── setup.sh                    # 一键初始化: 默认 --init 基础配置，--nvim 等场景需先 --init
├── sync.sh                     # 遍历 install/ 以 --update 更新已安装的工具与配置（含 # sync: skip 的除外）
├── install/
│   ├── agent-prompts.sh
│   ├── clash-for-linux.sh
│   ├── clashctl.sh
│   ├── cmake.sh
│   ├── codex.sh               # Codex CLI（固定版本）+ config.toml 默认键 + refine skill
│   ├── doc-research.sh         # doc-research CLI（固定 commit）+ doc-research-init
│   ├── fd.sh
│   ├── fonts.sh
│   ├── fzf.sh
│   ├── gh.sh
│   ├── ghostty-config.sh
│   ├── ghostty-terminfo.sh
│   ├── git-prune-merged.sh
│   ├── herdr.sh               # Herdr + 配置（configs/herdr/config.toml）
│   ├── nvim.sh                # Neovim + 配置（configs/nvim）
│   ├── nvim-ft.sh
│   ├── ossutil.sh
│   ├── perf-to-profile.sh
│   ├── pi.sh                  # Pi CLI（npm 固定版本）+ 配置与自研 extensions
│   ├── pi-auth.py             # auth.json 合并式更新（sync: skip，手动执行）
│   ├── pj.sh
│   ├── playwright.sh
│   ├── pnpm.sh                # pnpm（npm 固定版本）
│   ├── prd.sh
│   ├── ripgrep.sh
│   ├── starship.sh             # Starship 提示符 + pure 预设配置；接管 shell 托管块，检测到 Oh My Zsh / Oh My Bash 先卸载
│   ├── style-check.sh
│   ├── tldr.sh
│   ├── tmux.sh                # tmux + 配置（~/.tmux.conf、TPM）
│   ├── tree-sitter.sh
│   ├── uv.sh
│   ├── wangcai-config.sh      # 旺财配置（init.ts 同步；local.ts 机器相关，缺失才生成）
│   ├── compiler/               # 语言编译器/运行时
│   │   ├── clang.sh
│   │   ├── go.sh
│   │   ├── node.sh
│   │   ├── python.sh
│   │   ├── rust.sh
│   │   └── zig.sh
│   ├── lsp/
│   │   ├── bash-lsp.sh
│   │   ├── clice.sh
│   │   ├── lua-lsp.sh
│   │   ├── markdown-oxide.sh
│   │   ├── pyright-lsp.sh
│   │   ├── rust-analyzer-lsp.sh
│   │   ├── starpls-lsp.sh
│   │   ├── typescript-lsp.sh
│   │   └── typos-lsp.sh
│   └── skill/                  # skill 安装
│       ├── archify.sh          # 画图 skill（固定 commit）+ ~/.agents/skills/archify
│       ├── code-report.sh
│       ├── code-style.sh
│       ├── neovim-skill.sh
│       └── product-style.sh    # 体验评审 skill + ~/.agents/skills/product-style
├── configs/
│   ├── agents/
│   │   ├── editing-constraints.md
│   │   ├── file-links.md
│   │   ├── git-safety.md
│   │   ├── inline-functions.md
│   │   └── response-style.md
│   ├── codex/
│   │   └── skills/
│   │       └── refine/
│   │           └── SKILL.md
│   ├── ghostty/
│   │   └── config
│   ├── herdr/
│   │   └── config.toml
│   ├── nvim/
│   │   ├── init.lua
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
│   │   ├── settings.json
│   │   ├── models.json
│   │   ├── pi-plan-mode.json
│   │   ├── zentui.json
│   │   ├── agents/
│   │   │   ├── refine-checker.md
│   │   │   └── worker.md
│   │   ├── extensions/
│   │   │   ├── flat-editor.ts.disabled
│   │   │   ├── herdr-agent-state.ts  # herdr 状态上报集成（herdr 管理，升级时从 herdr integration install pi 重新同步）
│   │   │   ├── link-pi-types.sh
│   │   │   ├── refine.ts
│   │   │   ├── test/
│   │   │   │   └── refine.test.mjs
│   │   │   └── tsconfig.json
│   │   └── themes/
│   │       ├── gray.json
│   │       └── gray-light.json
│   ├── starship/
│   │   └── starship.toml
│   ├── tmux/
│   │   └── tmux.conf
│   └── wangcai/
│       ├── init.ts
│       └── local.ts
├── skills/
│   ├── code-report/
│   │   └── ...
│   ├── code-style/
│   │   └── ...
│   └── product-style/
│       └── ...
└── tools/
    ├── build-perf-to-profile.sh
    ├── common.sh                # install 脚本共享函数（confirm_update / managed block / write-if-changed）
    ├── doc-research-init.sh      # 初始化文献调研项目（raw/tr/dist + 工作流 README）
    ├── git-prune-merged.sh
    ├── latest-version.sh        # 查询工具的上游最新版本（--all 列出全部）
    ├── nvim_ft.py               # 按 git URL 管理 Neovim filetype
    ├── pj/                      # 仓库命令工具
    │   └── ...
    ├── prd/                     # 本机文件 HTTP 预览工具
    │   ├── src/preview_server.ts
    │   └── ...
    ├── secrets.sh               # 同步 provider API keys
    ├── style-check.sh
    └── tcc-reset.sh             # 清除 App 的 TCC 授权记录并引导重加（adhoc 签名重建后 csreq 失配时用）
```

## install 脚本约束

新增 `install/` 脚本须遵守以下协议，才能接入 `setup.sh` / `sync.sh`：

- **一件事**：一个脚本只装一个工具；缺依赖时报错并指引对应脚本，不自动安装
- **固定版本**：版本/commit/tag 写成脚本常量，不查最新版；无版本输出的写入 `~/.local/share/configs-setup/versions/` 比对；升级前用 `tools/latest-version.sh` 查上游版本
- **CN=1**：走国内代理/镜像，读取处直接 `[[ "${CN:-}" == "1" ]]`，不加 `-cn` 参数
- **--update**：未安装则跳过；已安装且不一致时先 `confirm_update` 再执行
- **--remove**：卸载该脚本安装的文件/目录/托管块，先 `confirm_remove` 再执行；删除用 `remove_file` / `remove_dir` / `remove_managed_block`（`tools/common.sh`）
- **文本修改**：文件内片段用 `write_managed_block`，整文件用 `write_file_if_changed`，目录用 `rsync -ai --delete`（先 dry-run 列差异再确认）；函数在 `tools/common.sh`，脚本开头 `source`
- **sync 豁免**：构建型/交互型脚本在头部加 `# sync: skip`
- **bash 3.2**（macOS 自带）：`$VAR` 后紧贴多字节字符写 `${VAR}`；`set -u` 下空数组展开前用 `${#arr[@]}` 守卫
