# custom-provider-merge 断言: 自定义 provider 注入后内置 provider 全部保留
{ config, builtinPresets, ... }:

let
  presets = config.mirrors.providerPresets;
  # 内置 provider SSOT: 从 modules/mirrors/providers.nix 派生 (而非本地硬编码 list), 避免双重维护
  builtin = builtins.attrNames builtinPresets;
  # 检查内置 provider 是否全部保留 (用户加自定义 provider 时不应丢失内置项)
  presetNames = builtins.attrNames presets;
  allPresent = builtins.all (n: builtins.elem n presetNames) builtin;
in
[
  {
    label = "[custom-provider] 内置 10 个 provider 全部保留";
    expected = "true";
    actual = if allPresent then "true" else "false (got ${toString (builtins.length (builtins.attrNames presets))} presets)";
  }
  {
    label = "[custom-provider] 用户自定义 provider my-cache 已注入";
    expected = "true";
    actual = if presets ? "my-cache" then "true" else "false";
  }
  {
    label = "[custom-provider] my-cache 的 nix substituter 排在镜像链首位";
    expected = "https://my-cache.example.com";
    actual =
      if config.nix.settings.substituters != [ ] then
        builtins.head config.nix.settings.substituters
      else
        "<empty>";
  }
]
