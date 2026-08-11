# SPDX-FileCopyrightText: 2026 luochen1990
# SPDX-License-Identifier: MIT
#
# mirrors-nix — cross-distribution mirror-source configuration module for NixOS.
#
# 职责边界:
#   本 flake 仅作为项目的对外入口, 声明 inputs 与调用 flake-fhs 生成 outputs.
#   所有 outputs (nixosModules / checks / devShells / formatter) 均由 flake-fhs 按目录约定自动生成.
#
# 目录约定 (flake-fhs):
#   modules/mirrors/ → nixosModules.mirrors (default.nix: options + 无条件 config; config.cfg.nix: 受 enable 控制的直写下发)
#   checks/          → checks.<system>.<name> (走 callPackage, scope 由 checks/scope.nix 注入)
#   shells/          → devShells.<system>.<name> (走 import, 传入 evalContext)
#   treefmt.toml     → formatter.<system> = pkgs.treefmt
{
  description = "mirrors-nix — cross-distribution mirror-source configuration module for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-fhs.url = "github:luochen1990/flake-fhs";
    flake-fhs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, flake-fhs, ... }:
    flake-fhs.lib.mkFlake { inherit inputs self; } {
      # 仅 x86_64-linux: 本模块是 NixOS 系统级配置, 无需跨平台
      systems = [ "x86_64-linux" ];
    };
}
