# substituter-order 断言: 镜像 substituters 排在用户自定义之前 (mkBefore 生效)
{ config, builtinPresets, assertHelpers, ... }:

let
  inherit (assertHelpers) findIndex;
  subs = config.nix.settings.substituters;
  # 派生: 期望值从 builtinPresets (SSOT) 读取, 修改 providers.nix 时自动跟随
  expectedFirst = toString (builtinPresets.tuna.nix.url or null);
  userVal = "https://my-custom.example.com";
  userIdx = findIndex subs userVal;
in
[
  {
    label = "[order] 镜像 substituters 排在用户自定义之前 (mkBefore 生效, derived from providers.nix)";
    expected = expectedFirst;
    actual = if subs != [ ] then builtins.head subs else "<empty>";
  }
  {
    label = "[order] 用户自定义 substituter 排在镜像之后";
    expected = "true";
    actual =
      if userIdx > 0 then
        "true"
      else
        "false (userIdx=${toString userIdx}, subs=${toString subs})";
  }
]
