# mirrors-nix — 仓库维护者入口

本文档是仓库维护者与 AI 助手的项目入口, 描述项目整体规则与开发流程。
模块内部的设计与实现细节在 [`modules/mirrors/AGENTS.md`](modules/mirrors/AGENTS.md), 本文不复制。

## 项目定位

`mirrors-nix` 是一个 NixOS flake 模块, 把"镜像站 (provider)"和"软件 (software)"正交分离,
统一配置国内常用镜像源 (tuna / ustc / aliyun / ...)。
本项目从 `~/ws/nixos` 私有 dotfiles 抽取为独立 flake, 以便复用与社区分享。

## 目录结构

```
mirrors-nix/
├── modules/            # flake-fhs 自动扫描 → nixosModules.<name>
│   └── mirrors/        # mirrors 模块 (内部设计见 modules/mirrors/AGENTS.md)
│       ├── default.nix       # 模块入口: options 定义 + 无条件 config (providerPresets 注入 / entries 派生 / 拼写检查)
│       ├── config.cfg.nix    # 受 mirrors.enable 控制的直写下发 (nix.settings / environment.* / docker)
│       ├── providers.nix     # 内置 provider 预设数据 (镜像 URL SSOT)
│       └── lib.nix           # URL 解析辅助函数 (resolveAll)
├── checks/             # 模块 eval-time 断言 (属性测试, flake-fhs 扫描 → checks.<system>.all)
│   ├── scope.nix       # 共享 eval/check 基础设施 (mkEvalCheck 三态 / evalMirrors / builtinPresets / assertHelpers)
│   └── all/            # 唯一 check 入口 (package.nix 触发封装, properties/ 不被扫描)
│       ├── package.nix       # driver: test-configs × properties 笛卡尔积, 拼接断言, 生成 1 个 drv
│       ├── software-spec.nix # SSOT: software 名 / provider key / 注入键 (含文件指针型) (properties forall 遍历的数据源)
│       └── properties/        # 属性文件: forall software 的不变式 (P ⟹ Q, 三态 skip/check)
│           ├── no-leak.nix            # 开关精确性: software 关闭 ⟹ 注入项 absent
│           ├── entries-invariant.nix  # entries 不变性: entries == resolveAll(...) 不受 enable 控制
│           └── inject-correctness.nix # 直写值正确性: 注入值 ∈ provider URLs 或 == 文件指针 (/etc/...)
├── shells/             # devShell 定义 (flake-fhs 自动扫描 → devShells.<system>.<name>)
│   └── default.nix     # 默认 devShell (lint / format / lsp / build 工具链 SSOT)
├── scripts/            # 辅助脚本
│   └── verify_mirrors.py  # 镜像 URL 巡检 (可达性 + mirrorz 数据一致性, 见 scripts/verify_mirrors.py 头注释)
├── .github/workflows/  # CI / 定期巡检
│   ├── ci.yml              # PR / push 跑 just check
│   └── verify-mirrors.yml  # 每周一 09:00 (UTC+8) 跑 verify-mirrors, 夹效开 issue
├── example/            # 用户示例 (configuration.nix)
├── flake.nix           # flake 入口 (调用 flake-fhs mkFlake 生成全部 outputs)
├── justfile            # 开发任务 (just check / just fmt / just update / just verify-mirrors)
├── treefmt.nix         # treefmt 1.x 兼容配置 (仅编辑器集成用, 真正生效见 treefmt.toml)
├── treefmt.toml        # treefmt v2 实际生效配置 (nixpkgs-fmt + ruff, 被 flake-fhs 选为 formatter)
├── statix.toml         # statix 规则 (无点前缀, 见 statix.toml 头注释)
├── pyproject.toml      # Python ruff (lint + format) 配置, 作用于 scripts/verify_mirrors.py
├── README.md           # 对外 README (动机/特性/答谢/快速上手)
├── CHANGELOG.md        # 版本变更日志 (Keep a Changelog)
├── LICENSE             # MIT License
├── AGENTS.md           # 本文件 (项目整体规则入口)
└── .taskmaster/        # Task Master 任务规划数据
```

## 如何本地开发

```bash
nix develop       # 进入 devShell (含 nixpkgs-fmt / deadnix / statix / nil / just / treefmt / python3 / ruff / nix)
just check        # 一键验证: lint (deadnix + statix + ruff) + nix flake check (含模块 eval 断言)
just fmt          # 格式化 (treefmt: nixpkgs-fmt + ruff format, 一次性覆盖 .nix 和 .py)
just update       # 更新 flake inputs (nix flake update)
just verify-mirrors  # 巡检 modules/mirrors/providers.nix 中所有镜像 URL 的可达性 + mirrorz 数据一致性
```

devShell 的工具链是 SSOT, 新增/移除工具只改 `shells/default.nix` 一处, devShell 自动跟随。

## flake-fhs 集成

本项目使用 [flake-fhs](https://github.com/luochen1990/flake-fhs) (Flake Filesystem Hierarchy Standard)
按目录约定自动生成 flake outputs, 消除手写 outputs 样板代码。

- `modules/mirrors/` → `nixosModules.mirrors` (目录模块, default.nix + config.cfg.nix)
- `checks/` → `checks.<system>.<name>` (走 callPackage, scope 由 `checks/scope.nix` 注入)
- `shells/` → `devShells.<system>.<name>` (走 import, 传入 evalContext)
- `treefmt.toml` 存在时 → `formatter.<system> = pkgs.treefmt`

mirrors 模块遵循 flake-fhs 目录模块约定:
- `default.nix`: options 定义 + 无条件 config (始终生效). `mirrors.enable` 在此声明,
  flake-fhs 的 injectEnable 检测到已存在便不再重复注入.
- `config.cfg.nix`: 受 enable-chain (`mkIf config.mirrors.enable`) 控制的直写下发.

## 关键设计

核心设计是 **provider 抽象 + preferred list + 两层覆盖**:

- 每个 provider 只列它实际提供的镜像, `null` = 不提供
- 用户用有序 `providers` list 声明偏好, 模块按"逐软件 > 全局"两层覆盖解析出实际 URL
- 多镜像策略因软件而异 (nix/docker/goproxy 收集所有匹配, 其他取第一个)

完整设计文档 (覆盖矩阵 / 多镜像策略 / 自定义 provider 合并机制 / TODO 路线图)
见 [`modules/mirrors/AGENTS.md`](modules/mirrors/AGENTS.md), 本文件不复制。

## 提交规范

- **原则**: SSOT (单一事实来源) / DRY / 函数式风格 (不可变数据 + attrset 抽象)
- **commit message**: 中文简洁, 以 **what** 为主, 避免 **how** 的冗长小作文
- **清理陈旧代码**: commit message 必须含完整关键词 (如被删的文件名/模块名), 便于日后 `git log` 搜索找回
- **类型严格**: 即便 Nix 是动态语言, 也用 attrset 结构与 `lib.mkOption` 类型约束保证数据形状正确
- **集中式预处理**: 默认值/异常值处理集中在 options 的 `default` 字段, 核心逻辑假设数据合规

## License 状态

本项目采用 MIT License, 见根目录 [LICENSE](LICENSE) 文件。
