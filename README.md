# mirrors-nix

> 横向统一配置各软件镜像源的 NixOS flake 模块 (tuna / ustc / aliyun / tencent / bfsu / sjtu / daocloud / hf-mirror)。

## 动机

国内 NixOS 用户配置镜像源一直很碎片化: 每份 dotfiles 都在 `environment.variables` / `nix.settings` 里
自己拼一遍 `GOPROXY` / `PIP_INDEX_URL` / `HF_ENDPOINT` 等字符串, 散乱、重复、互相抄。
社区现有方案 (如 `nix-china`) 把镜像 URL 直接硬编码进模块, 缺少 provider 抽象,
新增一个镜像站或切换偏好顺序都要改源码, 难以扩展和维护。

`mirrors-nix` 把"镜像站" (provider) 与"软件" (software) 正交分离, 借鉴
[catppuccin/nix](https://github.com/catppuccin/nix) 的横向配置思路:
内置一组 provider 预设数据, 用户只声明偏好顺序 (`mirrors.providers`),
模块自动按"逐软件 > 全局"两层覆盖解析出每个软件实际应使用的镜像 URL。

## 关键特性

- **8 个内置 provider**: tuna / ustc / aliyun / tencent / bfsu / sjtu / daocloud / hf-mirror
- **8 个软件支持**: nix / docker / goproxy / pip / npm / cargo / rustup / huggingface
- **多镜像策略**: `nix` / `docker` / `goproxy` 收集所有匹配 provider; 其余软件取第一个匹配
- **两层覆盖**: 逐软件 `mirrors.<software>.providers` > 全局 `mirrors.providers`
- **可扩展**: 通过 `mirrors.providerPresets` 用 NixOS module system 自动合并自定义 provider
- **零外部依赖**: 仅依赖 `nixpkgs.lib`, 不引入额外 flake input

## 快速上手

把本 flake 加为 input, 并在 NixOS 配置的 `modules` 数组里引用默认模块:

```nix
# flake.nix
inputs.mirrors-nix.url = "github:luochen1990/mirrors-nix";

# configuration.nix (modules 数组里)
inputs.mirrors-nix.nixosModules.default
```

然后一行启用所有默认镜像 (按 `tuna` > `ustc` > `aliyun` > ... 顺序优先匹配):

```nix
mirrors.enable = true;
```

## 更多示例

- [`example/minimal.nix`](example/minimal.nix) — 最简用法
- [`example/advanced.nix`](example/advanced.nix) — 自定义 provider / 逐软件覆盖

想了解 provider 抽象与内部设计, 见 [`module/AGENTS.md`](module/AGENTS.md)。

## 答谢

本项目的横向配置思路受 [catppuccin/nix](https://github.com/catppuccin/nix) 启发。

镜像数据来自以下镜像站的开源服务 (见 `providers.nix`):

- 清华大学 TUNA 协会 — <https://tuna.tsinghua.edu.cn>
- 中国科学技术大学 USTC — <https://ustc.edu.cn>
- 阿里云 (含 npmmirror) — <https://aliyun.com>
- 腾讯云 — <https://cloud.tencent.com>
- 北京外国语大学 BFSU — <https://bfsu.edu.cn>
- 上海交通大学 SJTU — <https://sjtu.edu.cn>
- DaoCloud — <https://daocloud.io>
- hf-mirror.com — <https://hf-mirror.com>

**没有这些镜像站长期提供的开源服务, 本项目毫无意义。** 请在享受便利时, 也关注各镜像站的运营状况与公告。

## License

License: MIT
