# SPDX-FileCopyrightText: 2026 luochen1990
# SPDX-License-Identifier: TBD
#
# mirrors-nix — cross-distribution mirror-source configuration module for NixOS.
#
# 职责边界:
#   本 flake 仅作为项目的对外入口, 声明 inputs 与 outputs.
#   - inputs: 跟随 `nixos-unstable` 通道 (nixpkgs 自身镜像同步机制决定了这是镜像源模块最合适的基线);
#     flake-utils 仅用于简化 per-system 输出.
#   - outputs:
#       * nixosModules.{default, mirrors}  NixOS 模块 (不依赖 system, 单独导出; mirrors 为 default 别名).
#       * checks.<system>.mirrors-module-eval  对模块求值并断言关键配置项生效 (回归测试).
#       * devShells.<system>.default        开发环境, 集中放置 lint / format / lsp / build 工具链.
#       * formatter.<system>                项目默认 formatter 为 nixpkgs-fmt (见 devShell 说明).
#
# 关键设计:
#   - formatter 选择 nixpkgs-fmt (社区成熟稳定, 真正可逆, AST 级格式化).
#     备选 nixfmt-rfc-style 是 nixpkgs 官方迁移目标, 但生态工具 (nil / 编辑器集成) 仍以 nixpkgs-fmt 为主,
#     经评估仍保留 nixpkgs-fmt; 待 nil 等周边工具全面支持 RFC-style 后再切换.
#   - nixosModules 不通过 eachDefaultSystem 包装, 因为模块本身与 system 无关;
#     只把 devShells / formatter / checks 这种本质上 per-system 的输出交给 flake-utils.
#   - checks.mirrors-module-eval: 求值最小 NixOS 配置并断言关键配置项生效 (不跑 VM test).
#     实现细节与选型理由见下方 mirrorsModuleEval 内联注释.
#   - 工具列表集中在一处 (devTools) 以便 SSOT; nixosModules 不依赖 system, 单独导出.
{
  description = "mirrors-nix — cross-distribution mirror-source configuration module for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:

    # nixosModules 与 system 无关, 单独导出, 不走 eachDefaultSystem.
    # default = 真实模块入口 (./module); mirrors = 别名, 兼容不同引用习惯.
    {
      nixosModules = {
        default = import ./module;
        mirrors = self.nixosModules.default;
      };
    }

    # devShells / formatter / checks 本质上 per-system, 用 flake-utils 合并到顶层 outputs.
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # SSOT: 开发工具链. formatter / lint / lsp / 任务运行器 / 包管理器自身.
        # 新增/移除工具只改这一处, devShell 自动跟随.
        devTools = with pkgs; [
          nixpkgs-fmt # formatter (与 `formatter.<system>` 保持一致)
          deadnix     # 静态检查: 未使用代码
          statix      # 静态检查: 反模式建议
          nil         # LSP (nix language server)
          just        # 任务运行器 (justfile)
          nix         # 包管理器自身, 保证 devShell 内 nix 版本可控
          python3     # 巡检脚本 scripts/verify_mirrors.py 的运行时
          ruff        # Python lint + format (巡检脚本代码质量)
        ];

        # === checks.mirrors-module-eval ===
        # 对模块求值并断言关键配置项生效. 见 checks/mirrors-assertions.nix 与 flake.nix 头部注释.
        # 用 nixosSystem (而非裸 lib.evalModules), 因为 baseModules 已提供 environment.*/nix.settings 等选项,
        # 无需手工补缺值, 表达更贴近真实使用场景.
        mirrorsModuleEval = let
          # 关闭 system.stateVersion 警告, 关闭 boot/fileSystems 缺值警告 (我们只关心 mirrors.* 派生项)
          evalConfig = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                # 启用 mirrors, 其余保持默认
                mirrors.enable = true;

                # 提供最小必需的 boot/fileSystems 值, 避免 nixosSystem 求值时缺值报错
                # (这些选项与 mirrors 模块无关, 但 nixosSystem 会被 base 模块强制要求)
                boot.loader.grub.device = "nodev";
                fileSystems."/".fsType = "ext4";
                fileSystems."/".device = "/dev/null";
              }
            ];
          };

          # 断言列表: [{label, expected, actual}, ...]
          assertions = import ./checks/mirrors-assertions.nix {
            inherit (evalConfig) config;
            inherit (nixpkgs) lib;
          };

          # 把每个断言落盘成一个 .json 文件 (expected/actual 原样保留, 不转义, 避免值含换行/特殊字符)
          # 用 imap0 给每个文件起稳定序号, 方便失败定位.
          assertionJsonFiles = pkgs.lib.imap0 (
            idx: a:
              pkgs.writeTextDir "assertion-${toString idx}.json"
                (builtins.toJSON {inherit (a) label expected actual;})
          ) assertions;

          # 所有断言 JSON 汇总到一个 store path, runCommand 用 jq 逐项校验
          allAssertions = pkgs.symlinkJoin {
            name = "mirrors-assertions-json";
            paths = assertionJsonFiles;
          };
        in
          pkgs.runCommand "mirrors-module-eval-check" {
            # 把所有 assertion json 作为 build input
            inherit allAssertions;
            nativeBuildInputs = [pkgs.jq];
          } ''
            set -euo pipefail
            total=0
            passed=0
            failed=0
            for f in "$allAssertions"/assertion-*.json; do
              total=$((total + 1))
              label=$(jq -r .label "$f")
              expected=$(jq -r .expected "$f")
              actual=$(jq -r .actual "$f")
              if [ "$expected" = "$actual" ]; then
                passed=$((passed + 1))
              else
                failed=$((failed + 1))
                echo "FAIL: $label"
                echo "  expected: $expected"
                echo "  actual:   $actual"
              fi
            done
            echo "mirrors-module-eval: $passed/$total assertions passed, $failed failed"
            if [ "$failed" -ne 0 ]; then
              exit 1
            fi
            mkdir -p "$out"
            echo "$passed/$total assertions passed" > "$out/summary"
          '';
      in
      {
        devShells.default = pkgs.mkShellNoCC {
          packages = devTools;
        };

        formatter = pkgs.nixpkgs-fmt;

        # nix flake check 会构建每个 check 项; mirrors-module-eval 仅在 eval 时求值模块 + 构建时比对断言,
        # 不跑任何 VM, 通常在秒级完成.
        checks.mirrors-module-eval = mirrorsModuleEval;
      });
}
