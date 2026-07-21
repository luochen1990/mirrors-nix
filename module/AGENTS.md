# mirrors-nix 模块

横向统一配置各软件的镜像源, 类似 catppuccin/nix 横向配置配色。

## 文件结构

```
module/
├── default.nix   # 模块入口, 仅做 imports 聚合
├── options.nix   # 选项定义 (mirrors.* 系列)
├── config.nix    # 配置应用 (根据选项生成 nix.settings / environment.* 等)
├── providers.nix # 内置 provider 预设数据 (tuna/ustc/aliyun/...)
└── lib.nix       # URL 解析辅助函数 (resolveAll / resolveFirst / getUrl)
```


## 设计理念

- **provider 预设**: 每个 provider (tuna/ustc/aliyun/...) 只列它实际提供的镜像; `null` = 不提供; 数据为 attrset (至少含 `url`), 支持未来扩展 `trusted-public-keys` 等字段
- **preferred list**: 有序 provider 列表, 每个软件取列表中第一个/所有提供该镜像的 provider
- **多镜像策略**: 不同软件对多镜像的支持不同, 解析策略也不同
  - 支持多镜像 (nix / docker / goproxy): 收集 preferred list 中**所有**匹配的 provider
  - 仅支持单镜像 (pip / npm / cargo / rustup / huggingface): 取 preferred list 中**第一个**匹配的 provider
- **两层覆盖**: 逐软件 `providers` > 全局 `providers`
- **自定义 provider**: 通过 `mirrors.providerPresets` 添加自定义 provider 或覆盖内置属性 (NixOS module system 自动合并)
- **自定义 URL**: 不在模块内提供; 需要时直接用 NixOS 原生选项 (`environment.variables` / `nix.settings` 等)

## 支持的软件

| 软件 | 配置方式 | 多镜像? | 默认启用? | 额外字段 |
| - | - | - | - | - |
| nix | `nix.settings.substituters` + `trusted-public-keys` (mkBefore) | 是 | 是 | `trusted-public-keys` |
| docker | `virtualisation.docker.daemon.settings.registry-mirrors` | 是 | 否 (国内镜像大多已关停) | - |
| goproxy | `GOPROXY` 环境变量 (逗号拼接 + direct) | 是 | 是 | - |
| pip | `PIP_INDEX_URL` 环境变量 + `/etc/pip.conf` | 否 | 是 | - |
| npm | `/etc/npmrc` (registry=) | 否 | 是 | - |
| cargo | `CARGO_REGISTRIES_CRATES_IO_PROTOCOL` + `CARGO_REGISTRIES_CRATES_IO_INDEX` 环境变量 | 否 | 是 | - |
| rustup | `RUSTUP_DIST_SERVER` 环境变量 | 否 | 是 | - |
| huggingface | `HF_ENDPOINT` 环境变量 | 否 | 是 | - |

## Provider 覆盖矩阵

> 实测于 2026-07-21; 仅保留逐个验证可用的镜像 (URL 见 `providers.nix`)

| 软件 \ Provider | tuna | ustc | aliyun | tencent | bfsu | sjtu | daocloud | hf-mirror | goproxy-cn | goproxy-io |
| - | - | - | - | - | - | - | - | - | - | - |
| nix | Y | Y | - | - | Y | Y | - | - | - | - |
| pypi | Y | Y | Y | Y | Y | Y | - | - | - | - |
| npm | - | - | Y | - | - | - | - | - | - | - |
| cargo | Y | Y | Y | - | Y | Y | - | - | - | - |
| rustup | Y | Y* | Y | - | - | Y* | - | - | - | - |
| goproxy | - | - | - | - | - | - | - | - | Y | Y |
| docker | - | - | - | - | - | - | Y | - | - | - |
| huggingface | - | - | - | - | - | - | - | Y | - | - |

> `Y*` rustup URL 各站命名不一: USTC/SJTU 叫 `/rust-static` (镜像 static.rust-lang.org 全站),
> TUNA/aliyun 叫 `/rustup` (只镜像 rustup 子目录); 不能假设统一前缀
>
> npm 镜像由阿里云 npmmirror 提供; USTC npm 于 2026-06-12 关停
>
> goproxy 仅由专用服务商提供 (goproxy.cn 七牛运营 / goproxy.io 开源社区项目);
> 国内主流镜像站未提供
>
> docker 镜像仅 DaoCloud 可用 (有限流); 传统镜像站于 2024-06 关停

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

# 关闭某软件
mirrors.goproxy.enable = false;
```

## TODO

- [ ] maven (Java) — `~/.m2/settings.xml`
- [ ] composer (PHP) — 环境变量
- [ ] rubygems (Ruby) — `~/.gemrc`
- [ ] flathub (Flatpak) — `services.flatpak.remotes`
- [ ] homebrew (darwin) — 环境变量
- [ ] HM 模块: 支持 per-user 镜像配置 (当前仅 NixOS 系统级)
