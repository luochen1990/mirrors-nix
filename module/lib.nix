# 镜像 URL 解析辅助函数
# 根据 preferred provider list, 从 providerPresets 中解析出 provider entry (attrset)
# 各软件的 config 按需从 entry 中提取字段 (url / trusted-public-keys 等)
#
# 易出错点:
# - Nix `or` 仅在属性缺失时返回默认值; 属性存在但值为 null 时返回 null, 需额外判断
# - map/filter/findFirst/attrByPath 中仅 map 是 builtin, 其余需从 lib 继承
{lib}: let
  inherit (lib) attrByPath filter findFirst;
in {
  # 多镜像解析: 返回所有非 null 的 provider entry (attrset 列表)
  # 用于支持多镜像的软件 (nix / docker / goproxy)
  resolveAll = providers: data: key:
    filter (x: x != null) (map (p: attrByPath [p key] null data) providers);

  # 单镜像解析: 返回第一个非 null 的 provider entry (attrset 或 null)
  # 用于仅支持单镜像的软件 (pip / npm / cargo / rustup / huggingface)
  resolveFirst = providers: data: key:
    findFirst (x: x != null) null (map (p: attrByPath [p key] null data) providers);

  # 从 entry 中提取 url (entry 为 null 或缺少 url 字段时返回 null)
  getUrl = entry: if entry != null then (entry.url or null) else null;
}
