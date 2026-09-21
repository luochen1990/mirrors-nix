# mirrors-nix — 仓库维护者入口

本文档是仓库维护者与 AI 助手的项目入口, 描述项目整体规则与开发流程。
模块内部的设计与实现细节在 [`modules/mirrors/AGENTS.md`](modules/mirrors/AGENTS.md), 本文不复制。

## 本文档维护约定

- 单条知识单行 `- ` bullet, 加入所属小节; 无合适小节时新建小节, 不往无关小节塞
- 登记类小节 (名称/路径为 key, 如目录清单) 按 key 字母序插入; 叙事类小节 (原则/决策) 追加至本节末尾
- 文件级职责以各文件头部注释为 SSOT, 本文不缓存 — 新增文件只写自己的头注, 不需要修改本文

## 项目定位

`mirrors-nix` 是一个 NixOS flake 模块, 把"镜像站 (provider)"和"软件 (software)"正交分离,
统一配置国内常用镜像源 (tuna / ustc / aliyun / ...)。
本项目从 `~/ws/nixos` 私有 dotfiles 抽取为独立 flake, 以便复用与社区分享。

## 目录结构 (登记: 按路径字母序插入)

目录级分工如下; 每个文件的职责见其头部注释。

- `.github/workflows/` — CI (PR/push 验证 + 每周定时巡检)
- `checks/` — 模块 eval-time 断言: 属性测试, test-configs × properties 笛卡尔积 (入口 `checks/all/package.nix`)
- `example/` — 用户示例 (`configuration.nix`)
- `modules/mirrors/` — mirrors 模块 (内部设计见 [`modules/mirrors/AGENTS.md`](modules/mirrors/AGENTS.md))
- `scripts/` — 辅助脚本 (`verify_mirrors.py`: 镜像 URL 可达性 + mirrorz 数据一致性巡检)
- `shells/` — devShell 定义

根级配置文件的坑: formatter 真正生效的是 `treefmt.toml` (treefmt v2), 同目录的 `treefmt.nix`
仅为 treefmt 1.x 编辑器集成兼容而保留 — 改格式化配置认准 `.toml`。

## 如何本地开发

`nix develop` 进入 devShell, 开发任务入口是 justfile (`just --list` 一览, 各命令注释自解释);
标准验证链是 `just check` = lint (deadnix + statix + ruff) + `nix flake check` (含模块 eval 断言)。
devShell 工具链是 SSOT: 新增/移除工具只改 `shells/default.nix` 一处, devShell 自动跟随。

## flake-fhs 集成

本项目使用 [flake-fhs](https://github.com/luochen1990/flake-fhs) (Flake Filesystem Hierarchy Standard)
按目录约定自动生成 flake outputs, 消除手写 outputs 样板代码:

- `modules/mirrors/` → `nixosModules.mirrors` (目录模块, default.nix + config.cfg.nix)
- `checks/` → `checks.<system>.<name>` (走 callPackage, scope 由 `checks/scope.nix` 注入)
- `shells/` → `devShells.<system>.<name>` (走 import, 传入 evalContext)
- `treefmt.toml` 存在时 → `formatter.<system> = pkgs.treefmt`

mirrors 模块遵循 flake-fhs 目录模块约定:

- `default.nix`: options 定义 + 无条件 config (始终生效); `mirrors.enable` 在此声明,
  flake-fhs 的 injectEnable 检测到已存在便不再重复注入
- `config.cfg.nix`: 受 enable-chain (`mkIf config.mirrors.enable`) 控制的直写下发

## 关键设计

核心设计是 **provider 抽象 + preferred list + 两层覆盖**:

- 每个 provider 只列它实际提供的镜像, `null` = 不提供
- 用户用有序 `providers` list 声明偏好, 模块按"逐软件 > 全局"两层覆盖解析出实际 URL
- 多镜像策略因软件而异 (nix/docker/goproxy 收集所有匹配, 其他取第一个)

完整设计文档 (覆盖矩阵 / 多镜像策略 / 自定义 provider 合并机制 / TODO 路线图)
见 [`modules/mirrors/AGENTS.md`](modules/mirrors/AGENTS.md), 本文件不复制。

## 提交规范 (叙事: 追加至本节末尾)

- **原则**: SSOT (单一事实来源) / DRY / 函数式风格 (不可变数据 + attrset 抽象)
- **commit message**: 中文简洁, 以 **what** 为主, 避免 **how** 的冗长小作文
- **清理陈旧代码**: commit message 必须含完整关键词 (如被删的文件名/模块名), 便于日后 `git log` 搜索找回
- **类型严格**: 即便 Nix 是动态语言, 也用 attrset 结构与 `lib.mkOption` 类型约束保证数据形状正确
- **集中式预处理**: 默认值/异常值处理集中在 options 的 `default` 字段, 核心逻辑假设数据合规

## License 状态

本项目采用 MIT License, 见根目录 [LICENSE](LICENSE) 文件。
