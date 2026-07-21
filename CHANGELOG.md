# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/),
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-07-21
### Fixed
- **总开关失效** (P0): `mirrors.enable = false` 不再注入任何 substituters / 环境变量 / 配置文件;
  此前所有 mkIf 只检查逐软件 `enable`, 总开关形同虚设
- **自定义 provider 丢失内置预设** (P0): 用户通过 `mirrors.providerPresets.my-cache.*`
  添加自定义 provider 时, 不再导致内置 10 个 provider (tuna/ustc/...) 全部丢失;
  根因是 option.default 在用户整段定义时会被替换, 改为 config 注入后走标准 module 合并
- **`providerPresets.X.Y = null` 类型冲突**: option 类型从 `nullOr attrs` 改为 `attrs`,
  "provider 不提供某软件" 用 attrset 中省略字段表达 (而非显式 null),
  避免用户 null 与内置 `{url=...}` 在 module system 合并时报 "defined both null and not null"
- **License 标注不一致**: README/flake.nix/CHANGELOG/AGENTS 中的 TBD 标注统一为 MIT, 补 LICENSE 文件

### Changed
- **断言改为派生式**: `checks/mirrors-assertions.nix` 的 expected 从硬编码 URL 改为
  从 `module/providers.nix` 派生, 修改 URL 时断言自动跟随, 避免双重维护;
  同时保留非派生守护断言检查关键字段存在性, 兼顾 DRY 与回归检测
- **providerPresets 默认值位置**: 从 `option.default` 移到 `config.mirrors.providerPresets`,
  让模块自身作为 definition 与用户定义参与合并 (详见 module/options.nix 头注释)
- **巡检脚本改用 python**: `scripts/verify-mirrors.sh` → `scripts/verify_mirrors.py`,
  新增 mirrorz 数据一致性检测 (与 mirrorz.org 各站上报数据交叉校验),
  devShell 中 jq/curl 替换为 python3/ruff

### Added
- **5 个边缘场景断言**: `checks/mirrors-assertions-edge.nix`, 守护历史 bug 不回归:
  - enable-false-leak: 总开关关闭时零副作用 (全量遍历所有可能被注入的键)
  - custom-provider-merge: 用户加自定义 provider 时内置 provider 不丢失
  - builtin-override: 覆盖内置 provider 字段时其他字段保持不变
  - per-software-disable: 逐软件 enable=false 只关停该软件
  - substituter-order: mkBefore 让镜像 substituter 排在用户值之前
- **provider 拼写检查**: 拼错的 provider 名通过 NixOS 标准 assertions 给出明确告警, 不再静默失败
- **CI workflow**: `.github/workflows/ci.yml` 在 PR / push 时跑 `just check`
- **镜像 URL 定期巡检**: `.github/workflows/verify-mirrors.yml` 每周一 09:00 UTC+8 跑
  `just verify-mirrors-quiet`, 失效时自动开 issue 通知维护者

## [0.1.0] - 2026-07-21
### Added
- Initial public release: 从 `~/ws/nixos` 抽取为独立 flake 项目
- 内置 provider 扩展为 10 个: tuna / ustc / aliyun / tencent / bfsu / sjtu / daocloud / hf-mirror / goproxy-cn / goproxy-io
- 8 个软件支持: nix / docker / goproxy / pip / npm / cargo / rustup / huggingface
- provider 抽象 + preferred list + 两层覆盖设计
- devShell (nixpkgs-fmt / deadnix / statix / nil / just / nix)
- `nixosModules.{default, mirrors}` 输出
- example/minimal.nix 与 example/advanced.nix

### License
- MIT (见 LICENSE 文件)
