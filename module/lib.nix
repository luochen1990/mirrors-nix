# 镜像 URL 解析辅助函数
# 根据 preferred provider list, 从 providerPresets 中解析出 provider entry (attrset 列表)
#
# 易出错点:
# - Nix `or` 仅在属性缺失时返回默认值; 属性存在但值为 null 时返回 null, 需额外判断
# - map/filter/attrByPath 中仅 map 是 builtin, 其余需从 lib 继承
{lib}: let
  inherit (lib) attrByPath filter;
in {
  # 返回所有非 null 的 provider entry (attrset 列表)
  # config.nix 的 entries 派生 + 直写下发均基于此函数
  resolveAll = providers: data: key:
    filter (x: x != null) (map (p: attrByPath [p key] null data) providers);
}
