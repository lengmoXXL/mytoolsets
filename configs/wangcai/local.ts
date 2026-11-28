// 机器相关配置：出网方式 network 与 terminal-agent 的 machines 列表，随机器/环境不同。
// 由 install/wangcai-config.sh 在目标机器缺失时生成；已存在则不覆盖、不同步，改这里不影响别的机器。
// machines 每项 { name?, host, env? }，host 'local' 表示本机。
export default {
  network: { proxy: 'http://127.0.0.1:7897' },
  machines: [
    { name: '本机', host: 'local', env: {
      PATH: '$HOME/.local/bin:$PATH',
      RUSTUP_HOME: '$HOME/.local/rust/rustup',
      CARGO_HOME: '$HOME/.local/rust',
    } },
    // clashctl 的代理：VM 上的 codex app-server 出网要用。
    { name: 'VM149', host: 'vm149', env: {
      http_proxy: 'http://127.0.0.1:7890', https_proxy: 'http://127.0.0.1:7890',
      all_proxy: 'socks5h://127.0.0.1:7890', no_proxy: 'localhost,127.0.0.1,::1',
      HTTP_PROXY: 'http://127.0.0.1:7890', HTTPS_PROXY: 'http://127.0.0.1:7890',
      ALL_PROXY: 'socks5h://127.0.0.1:7890', NO_PROXY: 'localhost,127.0.0.1,::1',
    } },
  ],
};
