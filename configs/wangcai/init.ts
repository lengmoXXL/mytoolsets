// 旺财的启动入口：启动时由 app 直接加载，只放配置与插件注册。
// 可配字段（就这些，其它字段会被忽略）：
//   theme   { background, foreground, cursor, selection, surface, overlay, border, muted, accent,
//             black, red, green, yellow, blue, magenta, cyan, white, brightBlack, brightRed,
//             brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite }
//           界面与终端配色，值写 '#rrggbb'；终端调色板是 black 到 brightWhite
//   network { proxy, mirror }  出网方式：proxy 写 http://host:port、https://host:port 或 socks5://host:port
//           （不写 scheme 当 http://，socks:// 当 socks5://；插件的 clone 与构建也走它），mirror 是 GitHub
//           加速前缀（像 https://ghfast.top/），https://github.com/ 开头的链接都从这里出去；两个都不写就用直连
//   workspaces [{ id, repo, commit, directory, config }]  工作区插件：窗口从这里取工作区列表，以及菜单里能开什么
//   tabs       [{ id, repo, commit, directory, config }]  侧栏标签页插件：它导出的视图出现在侧栏菜单里
// 插件条目的字段：
//   id        插件 id，也就是插件目录名
//   repo      插件仓库：不写就用官方仓库 https://github.com/lengmoXXL/WangCai-<id>；写了就 clone 并构建
//             （app 自带 node 与 npm；出网方式见 network）
//   commit    写哪个 commit 或分支就 checkout 到它（换一个就重新 checkout 并重建）；不写就只在更新时
//             跟仓库的分支走，启动时用的是已经构建好的那份
//   directory 插件放在哪个目录：clone 到这里，也直接读这里的 main.cjs；不写时用数据目录（默认为
//             ~/.local/share/wangcai）下的 plugins/<id>/；只写 directory 就是用那里的现成插件
//   config    这个插件自己的配置，能写哪些字段由插件说了算（schema 在插件的 main.cjs 里），不写的用插件给的默认值
// 插件就是一个目录，里面是编译好的 main.cjs（主进程）和可选的 ui.js / ui.css（界面文件）。
// 配置字段的完整说明：/Users/lzy/.local/share/wangcai/src/README.md
// 删掉本文件会重新生成这份默认配置。
import type { Config, KeyContext, Machine } from 'wangcai.api';
// network 与 machines 随机器不同，放在同目录 local.ts：install 脚本缺失时生成、存在则不覆盖。
import local from './local.ts';

// 插件字体：DejaVuSansM Nerd Font 需要安装（install/fonts.sh 的 dejavu）；插件代码默认是 macOS 自带的 Menlo。
const font = { family: '"DejaVuSansM Nerd Font Mono", monospace' };

// 当前工作区的机器与终端所在目录；没有工作区在前、或终端还没进过目录时给 undefined。
async function front({ machine, request }: KeyContext) {
  const m = machine();
  const { workspaces, active } = await request('terminal-agent', 'config') as {
    workspaces: { id: string; cwd?: string }[]; active?: string;
  };
  const cwd = workspaces.find((w) => w.id === active)?.cwd;
  return m && cwd ? { machine: m, cwd } : undefined;
}

export default {
  network: local.network,
  workspaces: [
    { id: 'terminal-agent',
      repo: 'https://github.com/lengmoXXL/WangCai-terminal-agent',
      commit: '645261a',
      // codex 工作区默认 yolo：命令都在远端 VM 里跑，本机不执行。
      config: { font, machines: local.machines, codex: { enabled: true, args: ['--dangerously-bypass-approvals-and-sandbox'] } },
    },
  ],
  tabs: [
    // 目录遍历归它：点一个文件就发 onclick，由 editor 接住。
    { id: 'files', repo: 'https://github.com/lengmoXXL/WangCai-files', config: { font } },
    // 一次读一个文件：语言服务、vim 键，点页头的「预览」把文件交给 preview。
    { id: 'editor', repo: 'https://github.com/lengmoXXL/WangCai-editor',
      config: { font, fontSizes: { markdown: 13 }, lsp: {
        c: { command: ['clice', 'serve'] },
        cpp: { command: ['clice', 'serve'] },
      } },
    },
    // 图片、Markdown 与 HTML 由它渲染。
    { id: 'preview', repo: 'https://github.com/lengmoXXL/WangCai-preview', config: { font } },
    { id: 'git', repo: 'https://github.com/lengmoXXL/WangCai-git', config: { font } },
    { id: 'terminal', repo: 'https://github.com/lengmoXXL/WangCai-terminal', config: { font } },
  ],
  keys: {
    '<leader>bf': { command: 'worktree.fork', desc: ['worktree', 'fork'], global: true },
    '<leader>bd': { command: 'worktree.remove', desc: ['worktree', '删除'], global: true },
    '<leader>gj': { command: 'report.jump', desc: ['goto', '跳到引用的代码'], global: true },
  },
  commands: {
    // 输入分支名，在仓库旁边建 worktree：目录是 仓库名-分支名，分支里的 / 换成 -，不会多出目录层级。
    // 分支已存在就检出它，不存在就从当前 HEAD 建。
    'worktree.fork': async (ctx) => {
      const at = await front(ctx);
      if (!at) return ctx.notify('前面没有工作区');
      const git = (...args: string[]) => ctx.exec(at.machine, 'git', args, { cwd: at.cwd });
      const top = await git('rev-parse', '--show-toplevel');
      if (top.code !== 0) return ctx.notify('当前目录不在 git 仓库里');
      const branch = (await ctx.input({ title: 'fork：分支名', placeholder: 'feat/xxx' }))?.trim();
      if (!branch) return;
      const dir = `${top.stdout.trim()}-${branch.replace(/\//g, '-')}`;
      const exists = (await git('rev-parse', '--verify', '--quiet', `refs/heads/${branch}`)).code === 0;
      const added = exists ? await git('worktree', 'add', dir, branch) : await git('worktree', 'add', '-b', branch, dir);
      if (added.code !== 0) return ctx.notify(added.stderr.trim());
      await ctx.request('terminal-agent', 'workspace-create', { key: at.machine.id, cwd: dir });
      ctx.notify(`已创建 ${dir}（分支 ${branch}），工作区已打开`);
    },
    // 选一个 worktree，连目录带分支一起删；有未提交改动导致移除失败时，再问一次要不要强制。
    'worktree.remove': async (ctx) => {
      const at = await front(ctx);
      if (!at) return ctx.notify('前面没有工作区');
      const git = (cwd: string, ...args: string[]) => ctx.exec(at.machine, 'git', args, { cwd });
      const list = await git(at.cwd, 'worktree', 'list', '--porcelain');
      if (list.code !== 0) return ctx.notify('当前目录不在 git 仓库里');
      const [main, ...rest] = list.stdout.trim().split('\n\n').map((block) => {
        const lines = block.split('\n');
        return {
          path: lines[0].slice('worktree '.length),
          branch: lines.find((l) => l.startsWith('branch refs/heads/'))?.slice('branch refs/heads/'.length),
        };
      });
      if (rest.length === 0) return ctx.notify('没有可删的 worktree');
      const items = rest.map((w) => `${w.branch ?? '(detached)'}  ${w.path}`);
      const chosen = await ctx.pick({ title: '删除哪个 worktree（连同分支）', items });
      if (chosen === undefined) return;
      const target = rest[items.indexOf(chosen)];
      // 从主 worktree 里跑，删的正好是终端当前目录也不受影响。
      let removed = await git(main.path, 'worktree', 'remove', target.path);
      if (removed.code !== 0) {
        const force = await ctx.pick({ title: '移除失败（可能有未提交改动），强制删除？', items: ['强制删除', '取消'] });
        if (force !== '强制删除') return;
        removed = await git(main.path, 'worktree', 'remove', '--force', target.path);
        if (removed.code !== 0) return ctx.notify(removed.stderr.trim());
      }
      // worktree 已删：关掉同机器上 cwd 落在其中的 workspace
      const { workspaces } = await ctx.request('terminal-agent', 'config') as { workspaces: { id: string; machineId: string; cwd?: string }[] };
      for (const w of workspaces) {
        if (w.machineId === at.machine.id && w.cwd && (w.cwd === target.path || w.cwd.startsWith(`${target.path}/`))) {
          await ctx.request('terminal-agent', 'workspace-close', { id: w.id });
        }
      }
      if (target.branch) {
        const dropped = await git(main.path, 'branch', '-D', target.branch);
        if (dropped.code !== 0) return ctx.notify(dropped.stderr.trim());
      }
      ctx.notify(`已删除 ${target.path}${target.branch ? `（分支 ${target.branch}）` : ''}`);
    },
    // code-report 的 caption 跳转，与 nvim caption_jump.lua 同逻辑：caption 在代码块下方（`> path:start-end`），
    // 光标在 caption 行或块内时跳到引用处（块内第 N 行 -> start+N-1），路径相对报告所在目录。
    'report.jump': async (ctx) => {
      const at = await ctx.request('editor', 'cursor') as { machine: Machine; path: string; line: number } | undefined;
      if (!at) return ctx.notify('编辑器里没有打开的文件');
      try {
        const text = await ctx.request('editor', 'read', { machine: at.machine, path: at.path }) as string;
        const lines = text.split('\n');
        const parse = (s: string) => {
          const t = /^\s*>\s*(.*?)\s*$/.exec(s)?.[1];
          if (!t) return undefined;
          const m = /^(.*):(\d+)-(\d+)$/.exec(t) ?? /^(.*):(\d+)$/.exec(t);
          return m && m[1] ? { path: m[1], start: +m[2], end: +(m[3] ?? m[2]) } : undefined;
        };
        let cap = parse(lines[at.line - 1] ?? '');
        if (!cap) {
          let open = at.line;
          while (open > 1 && !/^\s*```/.test(lines[open - 1])) open--;
          let close = at.line + 1;
          while (close <= lines.length && !/^\s*```/.test(lines[close - 1])) close++;
          if (/^\s*```/.test(lines[open - 1] ?? '') && close <= lines.length && close > open) {
            let c = close + 1;
            while (c <= lines.length && /^\s*$/.test(lines[c - 1])) c++;
            cap = parse(lines[c - 1] ?? '');
            if (cap && at.line > open) cap.start = Math.min(cap.start + at.line - open - 1, cap.end);
          }
        }
        if (!cap) return ctx.notify('光标不在引用块里');
        const base = at.path.slice(0, at.path.lastIndexOf('/')) || '/';
        const target = await ctx.request('editor', 'resolve', { machine: at.machine, path: cap.path, base }) as { path: string };
        await ctx.publish('onclick', { type: 'file', machine: at.machine, path: target.path, line: cap.start });
      } catch (e) {
        ctx.notify(e instanceof Error ? e.message : String(e));
      }
    },
  },
} satisfies Config;
