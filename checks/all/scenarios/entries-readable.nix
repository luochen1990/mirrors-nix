# entries-readable 断言: enable=false 时 entries 仍可读且返回完整未剪裁数据
{ config, builtinPresets, ... }:

let
  nixEntries = config.mirrors.nix.entries;
  entryUrls = map (e: e.url) nixEntries;
  # 派生: 期望值从 builtinPresets (SSOT) 读取, 修改 providers.nix 时自动跟随
  expectedTunaUrl = toString (builtinPresets.tuna.nix.url or null);
  expectedBfsuUrl = toString (builtinPresets.bfsu.nix.url or null);
in
[
  {
    label = "[entries] enable=false 时 nix.entries 仍非空";
    expected = "true";
    actual = if nixEntries != [ ] then "true" else "false (empty)";
  }
  {
    label = "[entries] nix.entries 包含 tuna 的 url (derived from providers.nix)";
    expected = expectedTunaUrl;
    actual =
      if builtins.elem expectedTunaUrl entryUrls then
        expectedTunaUrl
      else
        "<missing> (got ${toString entryUrls})";
  }
  {
    label = "[entries] nix.entries 包含 bfsu 的 url (derived from providers.nix)";
    expected = expectedBfsuUrl;
    actual =
      if builtins.elem expectedBfsuUrl entryUrls then
        expectedBfsuUrl
      else
        "<missing> (got ${toString entryUrls})";
  }
  {
    label = "[entries] 不提供 nix 的 provider (aliyun) 被正确过滤, entries 恰好 2 项";
    expected = "2";
    actual = toString (builtins.length nixEntries);
  }
]
