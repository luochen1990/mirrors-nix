# SPDX-FileCopyrightText: 2026 luochen1990
# SPDX-License-Identifier: MIT
#
# mirrors-nix — cross-distribution mirror-source configuration module for NixOS.
#
# 职责边界:
#   本 flake 仅作为项目的对外入口, 声明 inputs 与 outputs.
#   - inputs: 跟随 `nixos-unstable` 通道 (nixpkgs 自身镜像同步机制决定了这是镜像源模块最合适的基线);
#     flake-utils 仅用于简化 per-system 输出.
#   - outputs:
#       * nixosModules.{default, mirrors}  NixOS 模块 (不依赖 system, 单独导出; mirrors 为 default 别名).
#       * checks.<system>.*  对模块在多场景下求值并断言关键配置项生效 (回归测试):
#           - mirrors-module-eval       默认场景 (mirrors.enable=true)
#           - enable-false-leak         总开关关闭时零副作用
#           - custom-provider-merge     用户加自定义 provider 时内置 provider 不丢失
#           - builtin-override          覆盖内置 provider 的字段时其他字段保持不变
#           - per-software-disable      逐软件 enable=false 只关停该软件
#           - substituter-order         mkBefore 让镜像 substituter 排在用户值之前
#       * devShells.<system>.default        开发环境, 集中放置 lint / format / lsp / build 工具链.
#       * formatter.<system>                项目默认 formatter 为 nixpkgs-fmt (见 devShell 说明).
#
# 关键设计:
#   - formatter 选择 nixpkgs-fmt (社区成熟稳定, 真正可逆, AST 级格式化).
#     备选 nixfmt-rfc-style 是 nixpkgs 官方迁移目标, 但生态工具 (nil / 编辑器集成) 仍以 nixpkgs-fmt 为主,
#     经评估仍保留 nixpkgs-fmt; 待 nil 等周边工具全面支持 RFC-style 后再切换.
#   - nixosModules 不通过 eachDefaultSystem 包装, 因为模块本身与 system 无关;
#     只把 devShells / formatter / checks 这种本质上 per-system 的输出交给 flake-utils.
#   - checks: 默认场景 + 多个边缘场景共享同一份"求值 + 跑断言"基础设施 (mkEvalCheck 工厂).
#     断言数据集中放在 checks/ (声明式), 工厂在 flake.nix 中. 实现细节见下方 mkEvalCheck 注释.
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
        #
        # 架构: 默认场景 + 多个边缘场景, 共享同一份"求值 + 跑断言"基础设施 (mkEvalCheck 工厂).
        #   - 默认场景: mirrors.enable=true, 跑 mirrors-assertions.nix, 守护默认行为
        #   - 边缘场景: 跑 checks/mirrors-assertions-edge.nix 中每个场景, 守护历史 bug 修复
        # 工厂返回一个 derivation, nix flake check 时为每个场景构建一次.

        # nixosSystem 求值的最小 boot/fileSystems/system.stateVersion 配置
        # 这些选项与 mirrors 模块无关, 但 nixosSystem 会被 base 模块强制要求;
        # 显式提供以避免缺值警告, 让 CI 输出干净 (与真实部署无关, 仅用于 checks eval)
        boilerplate = {
          boot.loader.grub.device = "nodev";
          fileSystems."/".fsType = "ext4";
          fileSystems."/".device = "/dev/null";
          system.stateVersion = "26.11";
        };

        # 内置 provider 预设 (派生式断言的 expected 数据源, 与 module/providers.nix SSOT 保持一致)
        builtinPresets = import ./module/providers.nix;

        # 工厂: 给定 (场景名, 已求值的断言列表), 生成一个 runCommand derivation.
        # 调用方负责先 eval NixOS 配置并生成断言 (assertions 已是 [{label, expected, actual}, ...] list).
        # 工厂只关注"如何比对断言", 不关心"如何求值" — 单一职责.
        mkEvalCheck = name: assertions:
          let
            # 把每个断言落盘成一个 .json 文件 (expected/actual 原样保留, 不转义, 避免值含换行/特殊字符)
            # 用 imap0 给每个文件起稳定序号, 方便失败定位.
            assertionJsonFiles = pkgs.lib.imap0 (
              idx: a:
                pkgs.writeTextDir "${name}-assertion-${toString idx}.json"
                (builtins.toJSON {inherit (a) label expected actual;})
            ) assertions;

            allAssertions = pkgs.symlinkJoin {
              name = "${name}-assertions-json";
              paths = assertionJsonFiles;
            };
          in
            pkgs.runCommand "${name}-eval-check" {
              inherit allAssertions;
              nativeBuildInputs = [pkgs.jq];
            } ''
              set -euo pipefail
              total=0
              passed=0
              failed=0
              for f in "$allAssertions"/*.json; do
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
              echo "${name}: $passed/$total assertions passed, $failed failed"
              if [ "$failed" -ne 0 ]; then
                exit 1
              fi
              mkdir -p "$out"
              echo "$passed/$total assertions passed" > "$out/summary"
            '';

        # 默认场景的断言 (派生自 providers.nix 的 expected)
        defaultEvalCfg = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [self.nixosModules.default boilerplate {mirrors.enable = true;}];
        };
        defaultAssertions = import ./checks/mirrors-assertions.nix {
          inherit (nixpkgs) lib;
          presets = builtinPresets;
          config = defaultEvalCfg.config;
        };

        # 边缘场景: 每个场景独立 eval + 独立断言
        # edge 文件返回 { <name> = { modules, assertions = config: [...] }; }, 此处对每个场景求值并组装 derivation
        # 用 let 绑定求值结果而非内联 (expr).config, 因为 statix 对 (f x).attr 形式会误报 useless_parens
        edgeScenarios = import ./checks/mirrors-assertions-edge.nix;
        edgeChecks = builtins.mapAttrs (
          name: sc: let
            evalCfg = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [self.nixosModules.default boilerplate] ++ sc.modules;
            };
          in
            mkEvalCheck name (sc.assertions evalCfg.config)
        ) edgeScenarios;
      in {
        devShells.default = pkgs.mkShellNoCC {
          packages = devTools;
        };

        formatter = pkgs.nixpkgs-fmt;

        # nix flake check 会构建每个 check 项; 所有 check 仅在 eval 时求值模块 + 构建时比对断言,
        # 不跑任何 VM, 通常在秒级完成.
        checks =
          {
            # 默认场景: mirrors.enable=true 的全套默认行为
            mirrors-module-eval = mkEvalCheck "default" defaultAssertions;
          }
          // edgeChecks;
      });
}
