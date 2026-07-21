# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/),
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
### Changed
- goproxy: 由 aliyun 内置改为专用服务商 goproxy.cn (七牛) / goproxy.io (开源社区)
- 巡检脚本语言由 bash 改为 python3, 以增强可维护性并整合两类检测
- `just check` 的 lint 链追加 ruff (Python lint)
- `just fmt` 追加 `ruff format` (Python 格式化)

### Added
- 新增 `scripts/verify_mirrors.py` 镜像 URL 巡检脚本 (Python3, 替换原 bash 版):
  - 可达性检测: 从 `providers.nix` (SSOT) 提取 URL, 并发 HEAD/Range-GET 探测
  - 一致性检测: 对比 `mirrorz-json-legacy` 数据, 捕捉悄默路径变更
  - 子命令: `--reach` / `--consistency` / `--quiet`
- 新增 `pyproject.toml` (ruff lint + format 配置, 作用于 `scripts/`)
- 新增 `just verify-mirrors-{reach,consistency,quiet}` 子命令
- devShell 增补 python3 / ruff, 替换 jq / curl

### Removed
- 移除 `scripts/verify-mirrors.sh` (已被 Python 版本完全替代)

## [0.1.0] - 2026-07-21
### Added
- Initial public release: 从 `~/ws/nixos` 抽取为独立 flake 项目
- 8 个内置 provider: tuna / ustc / aliyun / tencent / bfsu / sjtu / daocloud / hf-mirror
- 8 个软件支持: nix / docker / goproxy / pip / npm / cargo / rustup / huggingface
- provider 抽象 + preferred list + 两层覆盖设计
- devShell (nixpkgs-fmt / deadnix / statix / nil / just / nix)
- `nixosModules.{default, mirrors}` 输出
- example/minimal.nix 与 example/advanced.nix

### License
- TBD (All Rights Reserved)
