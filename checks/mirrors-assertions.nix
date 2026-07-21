# mirrors 模块 eval-time 断言数据 (供 flake.nix#checks 使用)
#
# 职责边界:
#   本文件只描述 "应该断言什么" (声明式数据), 不负责如何运行断言.
#   flake.nix 读取这些 (label, expected, actual) 元组, 在 runCommand 中比对.
#
# 设计要点:
# - 每个断言是 { label; expected; actual; } 三元组, label 用于失败时定位
# - 期望值与实际值都强制成字符串 (builtins.toString), 用 bash 字符串比较即可
# - expected 优先派生自 module/providers.nix (SSOT), 避免硬编码 URL 导致双重维护
#   例: tuna nix substituter URL 直接读 presets.tuna.nix.url, 改 URL 时断言自动跟随
# - 派生式断言还能守护 config.nix 的解析逻辑 (resolveFirst/resolveAll/mkBefore 顺序等)
#
# 参数 (由 flake.nix 传入):
#   config: 经 nixosSystem 求值后的 NixOS config attrset
#   lib:    nixpkgs.lib (仅用于 splitString / hasSuffix 等 list/字符串工具)
#   presets: 内置 provider 预设 (import ./module/providers.nix), 用于派生 expected
#
# 易出错点:
# - 派生 expected 时用 or null 兜底, 避免 providers.nix 漏字段导致 eval 失败
# - environment.etc.<name>.text 是 multiline string, 用 toString 后会保留换行, bash 字符串比较仍可用
# - nix.settings.substituters 是 list, 断言只校验 "首项" 以保持弹性和可读性
{
  config,
  lib,
  presets,
}: let
  inherit (config) environment;
  inherit (config.nix.settings) substituters trusted-public-keys;

  # 从 environment.variables 安全取值 (避免缺键报错)
  env = environment.variables;

  # 派生: 默认全局 providers 列表的第一个 (tuna)
  tunaNixUrl = presets.tuna.nix.url or null;
  tunaPypiUrl = presets.tuna.pypi.url or null;
  tunaCargoUrl = presets.tuna.cargo.url or null;
  tunaRustupUrl = presets.tuna.rustup.url or null;
  aliyunNpmUrl = presets.aliyun.npm.url or null;
  hfUrl = presets.hf-mirror.huggingface.url or null;
  firstGoproxyUrl = presets.goproxy-cn.goproxy.url or null;

  # GOPROXY 逗号拼接, 校验 "包含 direct 兜底" 且 "首项是 goproxy.cn"
  goproxy = env.GOPROXY or "";
  goproxyParts = lib.splitString "," goproxy;

  # docker 默认 enable=false, 故 registry-mirrors 不应被设置
  dockerSettings = config.virtualisation.docker.daemon.settings or {};
  dockerHasMirrors = dockerSettings ? "registry-mirrors";
in
  # 派生式断言: expected 从 presets 读取, 修改 providers.nix 时自动跟随
  [
    # --- pip (派生自 providers.nix) ---
    {
      label = "PIP_INDEX_URL set to tuna pypi (derived from providers.nix)";
      expected = toString tunaPypiUrl;
      actual = env.PIP_INDEX_URL or "<missing>";
    }
    {
      label = "/etc/pip.conf contains tuna pypi index-url (derived from providers.nix)";
      expected = "[global]\nindex-url = ${toString tunaPypiUrl}\n";
      actual = environment.etc."pip.conf".text or "<missing>";
    }

    # --- npm (派生自 providers.nix) ---
    {
      label = "/etc/npmrc contains aliyun npmmirror registry (derived from providers.nix)";
      expected = "registry=${toString aliyunNpmUrl}\n";
      actual = environment.etc."npmrc".text or "<missing>";
    }

    # --- nix binary cache (派生自 providers.nix) ---
    {
      label = "nix.settings.substituters has tuna as first entry (derived from providers.nix)";
      expected = toString tunaNixUrl;
      actual =
        if (substituters != [])
        then builtins.head substituters
        else "<empty>";
    }
    {
      label = "nix.settings.substituters contains tuna/ustc/bfsu/sjtu (>=4 mirror entries)";
      expected = "true";
      actual =
        if (builtins.length substituters) >= 4
        then "true"
        else "false (got ${toString (builtins.length substituters)})";
    }
    {
      label = "nix.settings.trusted-public-keys is non-empty";
      expected = "true";
      actual =
        if (trusted-public-keys != [])
        then "true"
        else "false";
    }

    # --- huggingface (派生自 providers.nix) ---
    {
      label = "HF_ENDPOINT set to hf-mirror.com (derived from providers.nix)";
      expected = toString hfUrl;
      actual = env.HF_ENDPOINT or "<missing>";
    }

    # --- cargo (派生自 providers.nix) ---
    {
      label = "CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse";
      expected = "sparse";
      actual = env.CARGO_REGISTRIES_CRATES_IO_PROTOCOL or "<missing>";
    }
    {
      label = "CARGO_REGISTRIES_CRATES_IO_INDEX set to tuna cargo index (derived from providers.nix)";
      expected = toString tunaCargoUrl;
      actual = env.CARGO_REGISTRIES_CRATES_IO_INDEX or "<missing>";
    }

    # --- rustup (派生自 providers.nix) ---
    {
      label = "RUSTUP_DIST_SERVER set to tuna rustup (derived from providers.nix)";
      expected = toString tunaRustupUrl;
      actual = env.RUSTUP_DIST_SERVER or "<missing>";
    }
    {
      label = "RUSTUP_UPDATE_ROOT derived from tuna rustup URL (derived from providers.nix)";
      expected = "${toString tunaRustupUrl}/rustup";
      actual = env.RUSTUP_UPDATE_ROOT or "<missing>";
    }

    # --- goproxy: 多镜像逗号拼接 + direct 兜底 ---
    {
      label = "GOPROXY ends with 'direct' fallback (real URL + direct)";
      expected = "true";
      actual =
        # 至少一个真实 URL + direct 兜底; 未来若新增 goproxy provider, 段数会增加
        if (builtins.length goproxyParts) >= 2 && lib.hasSuffix "direct" goproxy
        then "true"
        else "false (got '${goproxy}')";
    }
    {
      label = "GOPROXY starts with goproxy.cn (derived from providers.nix)";
      expected = toString firstGoproxyUrl;
      actual =
        if goproxyParts != []
        then builtins.head goproxyParts
        else "<missing>";
    }

    # --- docker 默认 enable=false, 故不应有 registry-mirrors ---
    {
      label = "docker registry-mirrors NOT set when docker.enable=false (default)";
      expected = "false";
      actual =
        if dockerHasMirrors
        then "true (unexpectedly set)"
        else "false";
    }
  ]
  # 非派生守护: providers.nix 关键字段的存在性检查.
  # 派生式断言会跟随 providers.nix 变化, 但无法检测"某字段被误删导致 expected/actual 都变 null 同时通过"的情况.
  # 这里固定检查关键字段存在, 与派生断言互补, 双重守护.
  ++ [
    {
      label = "[non-derived] providers.nix 内置 provider 数量 = 10 (防字段误删)";
      expected = "10";
      actual = toString (builtins.length (builtins.attrNames presets));
    }
    {
      label = "[non-derived] providers.nix tuna.nix.url 存在 (防字段误删)";
      expected = "true";
      actual =
        if presets ? "tuna" && presets.tuna ? "nix" && presets.tuna.nix ? "url"
        then "true"
        else "false";
    }
    {
      label = "[non-derived] providers.nix aliyun.npm.url 存在 (防字段误删)";
      expected = "true";
      actual =
        if presets ? "aliyun" && presets.aliyun ? "npm" && presets.aliyun.npm ? "url"
        then "true"
        else "false";
    }
  ]
