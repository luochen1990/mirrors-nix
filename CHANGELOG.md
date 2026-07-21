# Changelog

All notable changes to this project will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/),
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
### Changed
- goproxy: 由 aliyun 内置改为专用服务商 goproxy.cn (七牛) / goproxy.io (开源社区)

### Added
- 新增 `scripts/verify-mirrors.sh` 镜像 URL 巡检脚本 (从 `providers.nix` SSOT 提取并 HEAD 探测)
- 新增 `just verify-mirrors` / `just verify-mirrors-quiet` 任务
- devShell 增补 jq / curl (巡检脚本依赖)

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
