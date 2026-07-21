# mirrors-nix — 仓库维护者入口

本文档是仓库维护者与 AI 助手的项目入口, 描述项目整体规则与开发流程。
模块内部的设计与实现细节在 [`module/AGENTS.md`](module/AGENTS.md), 本文不复制。

## 项目定位

`mirrors-nix` 是一个 NixOS flake 模块, 把"镜像站 (provider)"和"软件 (software)"正交分离,
统一配置国内常用镜像源 (tuna / ustc / aliyun / ...)。
本项目从 `~/ws/nixos` 私有 dotfiles 抽取为独立 flake, 以便复用与社区分享。

## 目录结构

```
mirrors-nix/
├── module/             # 核心模块代码 (内部设计见 module/AGENTS.md)
│   ├── default.nix     # 模块入口, 仅做 imports 聚合
│   ├── options.nix     # 选项定义 (mirrors.* 系列)
│   ├── config.nix      # 配置应用 (生成 nix.settings / environment.* 等)
│   ├── providers.nix   # 内置 provider 预设数据 (镜像 URL SSOT)
│   └── lib.nix         # URL 解析辅助函数 (resolveAll / resolveFirst / getUrl)
├── checks/             # 模块 eval-time 断言数据 (供 flake.nix checks 使用)
├── scripts/            # 辅助脚本
│   └── verify_mirrors.py  # 镜像 URL 巡检 (可达性 + mirrorz 数据一致性)
├── example/            # 用户示例 (minimal.nix / advanced.nix)
├── flake.nix           # flake 入口 (inputs/outputs/devShell/formatter)
├── justfile            # 开发任务 (just check / just fmt / just update / just verify-mirrors)
├── treefmt.nix         # treefmt 配置 (多语言格式化聚合)
├── treefmt.toml        # treefmt v2 实际生效配置 (treefmt.nix 仅作 1.x 兼容)
├── statix.toml         # statix 规则 (无点前缀, 见 statix.toml 头注释)
├── pyproject.toml      # Python ruff (lint + format) 配置, 作用于 scripts/
├── README.md           # 对外 README (动机/特性/答谢/快速上手)
├── CHANGELOG.md        # 版本变更日志 (Keep a Changelog)
├── AGENTS.md           # 本文件 (项目整体规则入口)
└── .taskmaster/        # Task Master 任务规划数据
```

## 如何本地开发

```bash
nix develop       # 进入 devShell (含 nixpkgs-fmt / deadnix / statix / nil / just / python3 / ruff / nix)
just check        # 一键验证: lint (deadnix + statix + ruff) + nix flake check (含模块 eval 断言)
just fmt          # 格式化 (nixpkgs-fmt + ruff format)
just update       # 更新 flake inputs (nix flake update)
just verify-mirrors  # 巡检 module/providers.nix 中所有镜像 URL 的可达性 + mirrorz 数据一致性
```

devShell 的工具链是 SSOT, 新增/移除工具只改 `flake.nix` 的 `devTools` 一处, `devShell` 自动跟随。

## 关键设计

核心设计是 **provider 抽象 + preferred list + 两层覆盖**:

- 每个 provider 只列它实际提供的镜像, `null` = 不提供
- 用户用有序 `providers` list 声明偏好, 模块按"逐软件 > 全局"两层覆盖解析出实际 URL
- 多镜像策略因软件而异 (nix/docker/goproxy 收集所有匹配, 其他取第一个)

完整设计文档 (覆盖矩阵 / 多镜像策略 / 自定义 provider 合并机制 / TODO 路线图)
见 [`module/AGENTS.md`](module/AGENTS.md), 本文件不复制。

## 提交规范

- **原则**: SSOT (单一事实来源) / DRY / 函数式风格 (不可变数据 + attrset 抽象)
- **commit message**: 中文简洁, 以 **what** 为主, 避免 **how** 的冗长小作文
- **清理陈旧代码**: commit message 必须含完整关键词 (如被删的文件名/模块名), 便于日后 `git log` 搜索找回
- **类型严格**: 即便 Nix 是动态语言, 也用 attrset 结构与 `lib.mkOption` 类型约束保证数据形状正确
- **集中式预处理**: 默认值/异常值处理集中在 `options.nix` 的 `default` 字段, 核心逻辑假设数据合规

## License 状态

本项目当前 License: TBD (All Rights Reserved)。
在 License 确定前, 请勿复制或分发本项目代码; 后续确定后会在单独 commit 中补 LICENSE 文件,
并同步更新 `README.md` 末尾的 License 标注。
