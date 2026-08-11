# builtin-override 断言: 覆盖内置 provider 字段时其他字段保持不变
{ config, builtinPresets, ... }:

let
  # 从 config 读合并后的 tuna (验证用户覆盖 + 内置保留)
  tuna = config.mirrors.providerPresets.tuna;
  # 从 builtinPresets 派生期望值 (SSOT: 原始内置值, 未被用户覆盖)
  expectedNixUrl = toString (builtinPresets.tuna.nix.url or null);
  expectedRustupUrl = toString (builtinPresets.tuna.rustup.url or null);
in
[
  {
    label = "[override] tuna.pypi 已被用户值替换";
    expected = "https://new-pypi.example.com/simple";
    actual = tuna.pypi.url or "<missing>";
  }
  {
    label = "[override] tuna.nix 保持内置值不变 (derived from providers.nix)";
    expected = expectedNixUrl;
    actual = tuna.nix.url or "<missing>";
  }
  {
    label = "[override] tuna.rustup 保持内置值不变 (derived from providers.nix)";
    expected = expectedRustupUrl;
    actual = tuna.rustup.url or "<missing>";
  }
  {
    label = "[override] 生效的 PIP_INDEX_URL 是覆盖后的值";
    expected = "https://new-pypi.example.com/simple";
    actual = config.environment.variables.PIP_INDEX_URL or "<missing>";
  }
]
