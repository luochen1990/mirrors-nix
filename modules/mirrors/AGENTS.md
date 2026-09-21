# mirrors 模块维护文档

横向统一配置各软件的镜像源, 类似 catppuccin/nix 横向配置配色。

## 本文档维护约定

- 单条知识单行 `- ` bullet; 标注 (登记) 的小节按 key 字母序插入, 标注 (叙事) 的小节追加至本节末尾
- 新增软件支持时: 只在 "支持的软件" 与 "Provider 覆盖矩阵" 各插入所属字母序位置的一条, 并在 TODO 划掉对应条目, 不动其他行

## 文件结构 (登记: 按路径字母序插入)

- `config.cfg.nix` — 受 mirrors.enable 控制的直写下发 (flake-fhs 自动用 mkIf 包裹)
- `default.nix` — 模块入口: options 定义 + 无条件 config (providerPresets 注入 / entries 派生 / 拼写检查)
- `lib.nix` — URL 解析辅助函数 (resolveAll)
- `providers.nix` — 内置 provider 预设数据 (镜像 URL SSOT)

## 设计理念 (叙事: 追加至本节末尾)

- **provider 预设**: 每个 provider (tuna/ustc/aliyun/...) 只列它实际提供的镜像; `null` = 不提供; 数据为 attrset (至少含 `url`), 支持未来扩展 `trusted-public-keys` 等字段
- **preferred list**: 有序 provider 列表, 每个 software 的 entries 收集列表中所有匹配的 provider
- **entries (派生 option)**: 每个 software 有 readOnly 的 `entries` option, 值为 resolveAll 后的完整 entry 列表 (未剪裁), 不受 enable 控制始终可读 — 消费者 (如 selector4nix 代理) 读 `mirrors.<sw>.entries` 即可拿到解析数据, 无需自己 import lib + resolveAll
- **两层开关**: 总开关 `mirrors.enable` 是第一道闸; 逐软件 `enable` 是第二道 (二者必须都为 true 才生效, 仅控制直写下发, 不影响 entries 计算)
- **两层覆盖**: 逐软件 `providers` > 全局 `providers`
- **内置预设注入**: 内置 provider 预设在 `default.nix` 中以模块自身 definition 注入 (`mirrors.providerPresets = builtinPresets`), 让模块自身与用户定义一起走标准 module 合并; **不能放在 `option.default`** — 那样用户的整段定义会替换 default, 内置预设会全部丢失
- **自定义 provider**: 通过 `mirrors.providerPresets` 添加自定义 provider 或覆盖内置属性 (NixOS module system 自动合并)
- **拼写守护**: `mirrors.providers` 中拼错的 provider 名会通过 NixOS 标准 assertions 给出明确告警 (而非静默失败)
- **自定义 URL**: 不在模块内提供; 需要时直接用 NixOS 原生选项 (`environment.variables` / `nix.settings` 等)

## 支持的软件 (登记: 按软件名字母序插入)

每条一个软件: 直写位置 (直写下发到的原生选项); 多镜像策略; 默认启用与否; entries option。

- **cabal**: `CABAL_CONFIG` 环境变量 + `/etc/cabal/config` (repository 块); 单镜像; **默认关闭** (原因见下方子条目); `mirrors.cabal.entries`
  - 默认关闭原因: cabal 只读单一 config 文件, 无级联/include 机制 (发现顺序, cabal-install 3.16 实测: `--config-file` > `$CABAL_CONFIG` > `$CABAL_DIR/config` > `~/.config/cabal/config` (XDG) > `~/.cabal/config` (legacy), XDG 与 legacy 并存时警告并取 XDG); 系统级下发 `CABAL_CONFIG=/etc/cabal/config` 会**整文件遮蔽**用户自己的 cabal 配置 (jobs/profiling 等所有定制全部失效) — 需要的用户显式开启, 有用户级 cabal 配置的应保持关闭并自行引用 entries
  - repository 块不写 root-keys: Hackage 官方 root key 已轮换 (root.json v8, 2026-08 验证), 镜像站文档的旧 key 列表 pin 进去会验签失败; 省略 root-keys 是 cabal 允许的 bootstrap 模式 (首次 update 不验签 root.json, 之后 TUF 全程验证, 镜像走 HTTPS)
- **cargo**: `CARGO_REGISTRIES_CRATES_IO_PROTOCOL` + `CARGO_REGISTRIES_CRATES_IO_INDEX` 环境变量; 单镜像; 默认启用; `mirrors.cargo.entries`
- **docker**: `virtualisation.docker.daemon.settings.registry-mirrors`; 多镜像; 默认关闭 (国内镜像大多已关停); `mirrors.docker.entries`
- **goproxy**: `GOPROXY` 环境变量 (逗号拼接 + direct); 多镜像; 默认启用; `mirrors.goproxy.entries`
- **huggingface**: `HF_ENDPOINT` 环境变量; 单镜像; 默认启用; `mirrors.huggingface.entries`
- **nix**: `nix.settings.substituters` + `trusted-public-keys` (mkBefore, 额外字段 `trusted-public-keys`); 多镜像; 默认启用; `mirrors.nix.entries`
- **npm**: `/etc/npmrc` (registry=); 单镜像; 默认启用; `mirrors.npm.entries`
- **pip**: `PIP_INDEX_URL` 环境变量 + `/etc/pip.conf`; 单镜像; 默认启用; `mirrors.pip.entries`
- **rustup**: `RUSTUP_DIST_SERVER` 环境变量; 单镜像; 默认启用; `mirrors.rustup.entries`

## Provider 覆盖矩阵 (登记: 按软件名字母序插入)

> 实测于 2026-08-15; 仅保留逐个验证可用的镜像 (URL 见 `providers.nix`)

- **cargo**: tuna / ustc / aliyun / bfsu / sjtu
- **docker**: daocloud (有限流; 传统镜像站 2024-06 关停)
- **goproxy**: goproxy-cn / goproxy-io (仅专用服务商提供 — goproxy.cn 七牛运营 / goproxy.io 开源社区项目, 国内主流镜像站未提供)
- **hackage**: tuna / ustc / tencent / bfsu (bfsu 是 302 重定向到 tuna, 同源内容; sjtu/aliyun 无此镜像)
- **huggingface**: hf-mirror
- **nix**: tuna / ustc / bfsu / sjtu
- **npm**: aliyun (npmmirror 提供; ustc npm 于 2026-06-12 关停)
- **pypi**: tuna / ustc / aliyun / tencent / bfsu / sjtu
- **rustup**: tuna / aliyun (`/rustup`, 只镜像 rustup 子目录) + ustc / sjtu (`/rust-static`, 镜像 static.rust-lang.org 全站) — 各站命名/形态有差异, 不能假设统一前缀

## 用法示例

```nix
# 最简: 启用全部默认镜像 (tuna 优先, 逐级回退)
mirrors.enable = true;

# 自定义全局 provider 偏好顺序 (示例: 省略 daocloud / hf-mirror / goproxy-cn / goproxy-io)
mirrors.providers = ["ustc" "tuna" "aliyun" "tencent" "bfsu" "sjtu"];

# 逐软件覆盖 provider 偏好 (不影响其他软件)
mirrors.pip.providers = ["aliyun" "tuna"];  # pip 优先用阿里云

# 添加自定义 provider (与内置预设自动合并)
mirrors.providerPresets.my-cache = {
  nix = {
    url = "https://my-cache.example.com";
    trusted-public-keys = ["my-cache-1:abc123..."];
  };
  pypi = { url = "https://my-cache.example.com/pypi/simple"; };
};
mirrors.providers = ["my-cache" "tuna" "ustc"];  # 自定义 provider 优先

# 覆盖内置 provider 的属性
mirrors.providerPresets.tuna.pypi = { url = "https://new-pypi-url.com/simple"; };

# 启用 docker (默认关闭)
mirrors.docker.enable = true;

# 启用 cabal (默认关闭, 原因: CABAL_CONFIG 会整文件遮蔽用户自己的 cabal 配置)
mirrors.cabal.enable = true;

# 关闭某软件
mirrors.goproxy.enable = false;
```

### 消费者: 读 entries 自行组装 config (如 selector4nix 代理)

```nix
# 消费者模块 (如自定义代理模块) 读 entries, 关闭直写下发, 自行组装 config
{config, lib, ...}: {
  # 关闭 mirrors 的 nix 直写下发 (避免双写 nix.settings.substituters)
  mirrors.nix.enable = false;

  # 读 entries 拿到解析后的完整 provider 列表 (未剪裁, 自行决定 select one / select all)
  services.my-proxy.substituters = map (e: e.url) config.mirrors.nix.entries;
  nix.settings.trusted-public-keys =
    lib.flatten (map (e: e.trusted-public-keys or []) config.mirrors.nix.entries);
}
```

## TODO (登记: 按条目名字母序插入)

- [ ] HM 模块: 支持 per-user 镜像配置 (当前仅 NixOS 系统级)
- [ ] composer (PHP) — 环境变量
- [ ] flathub (Flatpak) — `services.flatpak.remotes`
- [ ] homebrew (darwin) — 环境变量
- [ ] maven (Java) — `~/.m2/settings.xml`
- [ ] rubygems (Ruby) — `~/.gemrc`
