# mirrors 模块 eval-time 断言数据 (供 flake.nix#checks.mirrors-module-eval 使用)
#
# 职责边界:
#   本文件只描述 "应该断言什么" (声明式数据), 不负责如何运行断言.
#   flake.nix 读取这些 (label, expected, actual) 元组, 在 runCommand 中比对.
#
# 设计要点:
# - 每个断言是 { label; expected; actual; } 三元组, label 用于失败时定位
# - 期望值与实际值都强制成字符串 (builtins.toString), 用 bash 字符串比较即可
# - 这里的 expected 默认应与 module/providers.nix 中 URL 保持一致; 修改 URL 时需同步本文件
#   (作为契约, 故意让二者显式呼应而非自动派生, 以便回归测试能捕捉到非预期改动)
#
# 参数 (由 flake.nix 传入):
#   config: 经 nixosSystem 求值后的 NixOS config attrset
#   lib:    nixpkgs.lib (用于 splitString / hasSuffix 等字符串工具)
#
# 易出错点:
# - 修改 module/providers.nix 中某 URL 后, 须同步更新此处的 expected (这正是回归测试的目的)
# - environment.etc.<name>.text 是 multiline string, 用 toString 后会保留换行, bash 字符串比较仍可用
# - nix.settings.substituters 是 list, 这里只断言 "首项为 tuna nix url" 以保持弹性和可读性
{
  config,
  lib,
}: let
  inherit (config) environment;
  inherit (config.nix.settings) substituters trusted-public-keys;

  # 从 environment.variables 安全取值 (避免缺键报错)
  env = environment.variables;

  # GOPROXY 逗号拼接, 这里校验 "包含 direct 兜底" 且 "包含多个 URL (含逗号)"
  goproxy = env.GOPROXY or "";
  goproxyParts = lib.splitString "," goproxy;

  # docker 默认 enable=false, 故 registry-mirrors 不应被设置 (settings attrset 内不含此键)
  # 注意 docker.daemon.settings 整个 attrset 默认是 {}, 我们用 or {} 兜底
  dockerSettings = config.virtualisation.docker.daemon.settings or {};
  dockerHasMirrors = dockerSettings ? "registry-mirrors";
in [
  # --- pip ---
  {
    label = "PIP_INDEX_URL set to tuna pypi";
    expected = "https://pypi.tuna.tsinghua.edu.cn/simple";
    actual = env.PIP_INDEX_URL or "<missing>";
  }
  {
    label = "/etc/pip.conf contains tuna pypi index-url";
    expected = "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple\n";
    actual = environment.etc."pip.conf".text or "<missing>";
  }

  # --- npm ---
  {
    label = "/etc/npmrc contains npmmirror registry";
    expected = "registry=https://registry.npmmirror.com\n";
    actual = environment.etc."npmrc".text or "<missing>";
  }

  # --- nix binary cache ---
  {
    label = "nix.settings.substituters has tuna as first entry";
    expected = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store";
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

  # --- huggingface ---
  {
    label = "HF_ENDPOINT set to hf-mirror.com";
    expected = "https://hf-mirror.com";
    actual = env.HF_ENDPOINT or "<missing>";
  }

  # --- cargo ---
  {
    label = "CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse";
    expected = "sparse";
    actual = env.CARGO_REGISTRIES_CRATES_IO_PROTOCOL or "<missing>";
  }
  {
    label = "CARGO_REGISTRIES_CRATES_IO_INDEX set to tuna cargo index";
    expected = "https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/";
    actual = env.CARGO_REGISTRIES_CRATES_IO_INDEX or "<missing>";
  }

  # --- rustup ---
  {
    label = "RUSTUP_DIST_SERVER set to tuna rustup";
    expected = "https://mirrors.tuna.tsinghua.edu.cn/rustup";
    actual = env.RUSTUP_DIST_SERVER or "<missing>";
  }
  {
    label = "RUSTUP_UPDATE_ROOT derived from RUSTUP_DIST_SERVER";
    expected = "https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup";
    actual = env.RUSTUP_UPDATE_ROOT or "<missing>";
  }

  # --- goproxy: 多镜像逗号拼接 + direct 兜底 ---
  {
    label = "GOPROXY contains 'direct' fallback at the end";
    expected = "true";
    actual =
      if goproxy != "" && lib.hasSuffix "direct" goproxy
      then "true"
      else "false (got '${goproxy}')";
  }
  {
    label = "GOPROXY contains multiple comma-separated URLs";
    expected = "true";
    actual =
      if (builtins.length goproxyParts) > 1
      then "true"
      else "false (got '${goproxy}')";
  }
  {
    label = "GOPROXY starts with tuna goproxy";
    expected = "https://mirrors.tuna.tsinghua.edu.cn/goproxy";
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
