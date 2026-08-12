# Property: entries 不变性
#
# 不变式:
#   forall software sw:
#     config.mirrors.${sw}.entries == resolveAll(effectiveProviders(sw), providerPresets, providerKey(sw))
#
# 即: entries 始终反映 preferred list 中所有匹配 provider 的完整列表 (未剪裁),
#     不受 mirrors.enable / mirrors.${sw}.enable 控制.
#
# 注: resolveAll 复用模块的实现 (modules/mirrors/lib.nix), 守护 default.nix 的 effProv+swEntries
#     组合是否正确, 而非复制算法做独立验证.
{ config
, lib
, self
, softwareSpec
, ...
}:

let
  inherit (softwareSpec) specs allSoftware;

  mlib = import "${self}/modules/mirrors/lib.nix" { inherit lib; };
  presets = config.mirrors.providerPresets;

  effProv = swCfg: if swCfg.providers != null then swCfg.providers else config.mirrors.providers;
in
lib.flatten (
  map
    (
      sw:
      let
        s = specs.${sw};
        entries = config.mirrors.${sw}.entries;
        expected = mlib.resolveAll (effProv config.mirrors.${sw}) presets s.providerKey;
        expectedUrls = map (e: e.url) expected;
        actualUrls = map (e: e.url) entries;
        urlsMatch = builtins.length expectedUrls == builtins.length actualUrls
          && builtins.all (u: builtins.elem u actualUrls) expectedUrls;
      in
      [
        {
          label = "entries-invariant/${sw}: entries 长度 == resolveAll 结果";
          expected = toString (builtins.length expected);
          actual = toString (builtins.length entries);
        }
        {
          label = "entries-invariant/${sw}: entries URLs ⊇ resolveAll URLs";
          expected = "true";
          actual = if urlsMatch then "true" else "false (expected ${toString expectedUrls}, got ${toString actualUrls})";
        }
      ]
    )
    allSoftware
)
