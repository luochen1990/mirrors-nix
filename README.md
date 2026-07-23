# mirrors-nix

> 一个 NixOS flake 模块, 把"镜像站" (provider) 与"软件" (software) 正交分离, 一处声明偏好顺序, 统一配置 nix / pip / npm / cargo / rustup / goproxy / docker / huggingface 等常用镜像源。

## 为什么需要它

国内 NixOS 用户配置镜像源的方式相当碎片化: 在 `environment.variables` / `nix.settings` 里手写一遍 `GOPROXY` / `PIP_INDEX_URL` / `HF_ENDPOINT` 等字符串, 每份 dotfiles 都要重复一遍类似的工作。

`mirrors-nix` 内置了 10 个常用 provider 预设 (tuna / ustc / aliyun / tencent / bfsu / sjtu / daocloud / hf-mirror / goproxy.cn / goproxy.io), 你只需声明偏好顺序, 模块自动解析出每个软件实际该用哪个镜像, 并写入对应的 NixOS 原生配置 (`nix.settings` / 环境变量 / `pip.conf` / `npmrc` 等)。

## 快速上手

Flake 安装:

```nix
# flake.nix
inputs.mirrors-nix.url = "github:luochen1990/mirrors-nix";

# configuration.nix (modules 数组)
inputs.mirrors-nix.nixosModules.default
```

一行启用全部默认镜像:

```nix
mirrors.enable = true;
```

> **启用规则**: 对于支持指定多个镜像站的软件 (nix / docker / goproxy), mirrors-nix 会把已启用镜像站中所有兼容的条目都加入软件源列表; 对于只支持单镜像站的软件 (pip / npm / cargo / rustup / huggingface), 则取列表中首个兼容的镜像站。

需要更细粒度的控制时:

```nix
# 1. 只启用你信任的镜像站 (列表顺序即优先级, 不在列表内的内置 provider 不会被使用)
mirrors.providers = ["ustc" "tuna" "aliyun" "tencent" "bfsu" "sjtu"];

# 2. 禁用某个软件的镜像支持 (其余软件不受影响)
mirrors.cargo.enable = false;

# 3. 精确地为某个软件指定镜像站 (覆盖 mirrors.providers 全局设置, 不影响其他软件)
mirrors.pip.providers = ["aliyun" "tuna"];

# 4. 添加自定义镜像站 (与内置预设自动合并, 名字需出现在 mirrors.providers 中才会生效)
mirrors.providerPresets.my-cache.nix = {
  url = "https://my-cache.example.com";
  trusted-public-keys = ["my-cache-1:abc123..."];
};
mirrors.providers = ["my-cache" "ustc" "tuna"];
```

完整示例见 [`example/`](example/)。

## 答谢

本项目的横向配置思路受 [catppuccin/nix](https://github.com/catppuccin/nix) 启发。

镜像数据来自以下 provider 长期提供的开源服务 (URL 即 `providers.nix` 中引用的入口):

- 清华大学 TUNA — <https://mirrors.tuna.tsinghua.edu.cn>
- 中国科学技术大学 USTC — <https://mirrors.ustc.edu.cn>
- 阿里云 (含 npmmirror) — <https://mirrors.aliyun.com>
- 腾讯云 — <https://mirrors.cloud.tencent.com>
- 北京外国语大学 BFSU — <https://mirrors.bfsu.edu.cn>
- 上海交通大学 SJTU — <https://mirror.sjtu.edu.cn>
- DaoCloud — <https://docker.m.daocloud.io>
- hf-mirror.com — <https://hf-mirror.com>
- 七牛云 goproxy.cn — <https://goproxy.cn>
- goproxy.io — <https://goproxy.io>

各 provider 的镜像覆盖状况可通过 [mirrorz](https://mirrorz.org) 一站式查询; 本项目的 URL 巡检脚本 (`scripts/verify_mirrors.py`) 也以 mirrorz 数据为一致性基准。**没有这些镜像站长期提供的开源服务, 本项目毫无意义。**

> **docker 提示**: 国内免费 Docker Hub registry 镜像大多于 2024-06 关停, 目前仅 DaoCloud 仍可用且有限流 (1 MiB/s, 20 req/min), 故 `mirrors.docker.enable` 默认关闭。生产环境建议自建 registry 或使用云厂商付费服务。

## License

MIT
