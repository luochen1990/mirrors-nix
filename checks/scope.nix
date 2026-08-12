# checks 共享 scope: 为所有 check package.nix 注入共享的 eval/check 基础设施.
#
# 职责边界:
#   仅提供"如何 eval NixOS 配置"和"如何比对断言"的共享逻辑, 不关心具体场景.
#   每个场景 (checks/<name>/package.nix) 通过 callPackage 参数解构这些注入值.
#
# 设计要点:
#   - args (而非 scope): mkEvalCheck / boilerplate 等不是 pkgs 成员, 应通过 args 注入.
#     scope 保持默认 (= pkgs), args 作为 callPackage 的第二参数合并进来.
#   - mkEvalCheck 是纯函数 (无闭包依赖), 可安全放在 args 中.
#   - boilerplate 与 presets 是数据, 一次性求值, 各场景共享.
#   - assertHelpers (assertAbsent / mkSkip) 内联在此处,
#     避免独立 lib.nix 被 flake-fhs 的 checks 扫描误识别为一个 check 项.
#
# flake-fhs 约定:
#   scope.nix 签名: { pkgs, self, system, inputs, ... } -> { scope ? ..., args ? ... }
#   返回的 args 会与父级 args 合并, 传给本目录及子目录的所有 package.nix.
#   scope.nix 本身会被 flake-fhs 扫描器跳过 (不算 check 项).
{ pkgs
, self
, inputs
, ...
}:

let
  nixpkgs = inputs.nixpkgs;

  # nixosSystem 求值的最小 boot/fileSystems/system.stateVersion 配置.
  # 这些选项与 mirrors 模块无关, 但 nixosSystem 会被 base 模块强制要求;
  # 显式提供以避免缺值警告, 让 CI 输出干净 (与真实部署无关, 仅用于 checks eval).
  boilerplate = {
    boot.loader.grub.device = "nodev";
    fileSystems."/".fsType = "ext4";
    fileSystems."/".device = "/dev/null";
    system.stateVersion = "26.11";
  };

  # 内置 provider 预设 (派生式断言的 expected 数据源, 与 modules/mirrors/providers.nix SSOT 保持一致).
  builtinPresets = import "${self}/modules/mirrors/providers.nix";

  # 工厂: 给定 (场景名, 已求值的断言列表), 生成一个 runCommand derivation.
  # 调用方负责先 eval NixOS 配置并生成断言 (assertions 已是 [{label, expected, actual, status?}, ...] list).
  # 工厂只关注"如何比对断言", 不关心"如何求值" — 单一职责.
  #
  # 断言三态:
  #   status = "check" (默认): 正常比对 expected vs actual (不等则 fail)
  #   status = "skip": 前提不满足 (P=false), 断言不适用, 跳过比对 (不计入 passed 也不计入 failed)
  #   汇总: X passed, Y skipped, Z failed (failed > 0 时 exit 1)
  mkEvalCheck = name: assertions:
    let
      assertionJsonFiles = pkgs.lib.imap0
        (
          idx: a:
            pkgs.writeTextDir "${name}-assertion-${toString idx}.json"
              (builtins.toJSON {
                inherit (a) label expected actual;
                status = a.status or "check";
              })
        )
        assertions;

      allAssertions = pkgs.symlinkJoin {
        name = "${name}-assertions-json";
        paths = assertionJsonFiles;
      };
    in
    pkgs.runCommand "${name}-eval-check"
      {
        inherit allAssertions;
        nativeBuildInputs = [ pkgs.jq ];
      } ''
      set -euo pipefail
      total=0
      passed=0
      skipped=0
      failed=0
      for f in "$allAssertions"/*.json; do
        total=$((total + 1))
        label=$(jq -r .label "$f")
        status=$(jq -r .status "$f")
        if [ "$status" = "skip" ]; then
          skipped=$((skipped + 1))
          continue
        fi
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
      echo "${name}: $passed passed, $skipped skipped, $failed failed (total $total)"
      if [ "$failed" -ne 0 ]; then
        exit 1
      fi
      mkdir -p "$out"
      echo "$passed passed, $skipped skipped, $failed failed" > "$out/summary"
    '';

  # eval 一个 mirrors 场景: 传入额外 modules, 返回 NixOS config.
  # 所有场景共享 self.nixosModules.mirrors + boilerplate, 调用方只需传场景特有 modules.
  # 显式传 pkgs: 让 nixosSystem 从 pkgs.stdenv.hostPlatform 推断 system,
  # 避免显式传 system (已废弃) 也避免缺 platform 报错.
  evalMirrors = extraModules:
    (nixpkgs.lib.nixosSystem {
      pkgs = pkgs;
      modules = [ self.nixosModules.mirrors boilerplate ] ++ extraModules;
    }).config;

  # 共享断言辅助函数.
  # assertAbsent: 把"unexpectedly set" 等文案集中到工厂函数, 避免散落复制.
  # mkSkip: 三态断言的 skip 构造器 (前提不满足时使用).
  assertAbsent = prefix: container: key: {
    label = "${prefix} ${key} 未注入";
    expected = "false";
    actual =
      if container ? ${key} then
        "true (unexpectedly set)"
      else
        "false";
  };

  # skip 断言: 前提不满足 (P=false), 断言不适用.
  # 用于属性测试的 P ⟹ Q 编码: 当 P 为假时, 整条断言 skip 而非 pass.
  mkSkip = label: { inherit label; status = "skip"; expected = ""; actual = ""; };

  assertHelpers = {
    inherit assertAbsent mkSkip;
  };
in
{
  args = {
    inherit
      mkEvalCheck
      evalMirrors
      builtinPresets
      assertHelpers
      self
      ;
  };
}
