# Property: 直写值正确性 (inject-correctness)
#
# 不变式 (P ⟹ Q):
#   forall software sw, forall 注入键 k (env / etc / special):
#     P: sw 启用且存在匹配 provider
#     Q: 注入的值"派生自"某个 entry URL (包含 entry URL 作为子串)
#
# 涵盖:
#   - env 键: 环境变量值包含某个 entry URL (兼容 goproxy 逗号拼接、rustup 后缀)
#   - etc 键: 配置文件 text 包含某个 entry URL
#   - special 键 (nix substituters / docker registry-mirrors): 每个 URL ∈ entry URLs
#   - 文件指针型 env 键: 值 == "/etc/" + 指定的 etc 文件路径 (如 CABAL_CONFIG → /etc/cabal/config)
# 非 URL 的注入值从 spec 的 nonUrlEnvKeys 跳过; 文件指针型键由 filePointerEnvKeys 精确断言.
#
# 三态编码:
#   P=true  (sw 启用且有 entries): 正常检查 Q
#   P=false (sw 关闭或无 entries): skip
{ config
, lib
, assertHelpers
, softwareSpec
, ...
}:

let
  inherit (assertHelpers) mkSkip;
  inherit (softwareSpec) specs allSoftware;

  env = config.environment.variables;
  etc = config.environment.etc;

  entryUrls = sw: map (e: e.url) config.mirrors.${sw}.entries;

  isEnabled = sw: config.mirrors.enable && config.mirrors.${sw}.enable && config.mirrors.${sw}.entries != [ ];

  # 检查字符串值是否包含某个 entry URL 作为子串
  containsUrl = sw: value:
    let urls = entryUrls sw; in
    builtins.any (u: lib.hasInfix u value) urls;

  # env 键检查: 值包含 entry URL (文件指针型键精确断言; 其余非 URL 值跳过)
  checkEnv = sw: k:
    let
      s = specs.${sw};
      actual = env.${k} or null;
      # 文件指针型: 值必须精确等于 /etc/<etcKey> (配对一致性, 防止 env 指向不存在的文件)
      pointerTarget = s.filePointerEnvKeys.${k} or null;
      pointerValue = "/etc/${pointerTarget}";
    in
    if pointerTarget != null then
      {
        label = "inject/${sw}/${k}: env 值 == ${pointerValue}";
        expected = pointerValue;
        actual =
          if actual == null then
            "false (key not set)"
          else if actual == pointerValue then
            actual
          else
            "false (got ${actual})";
      }
    else if builtins.elem k s.nonUrlEnvKeys then
      mkSkip "inject/${sw}/${k} (non-URL value)"
    else
      {
        label = "inject/${sw}/${k}: env 值包含某个 provider URL";
        expected = "true";
        actual =
          if actual == null then
            "false (key not set)"
          else if containsUrl sw actual then
            "true"
          else
            "false (got ${actual})";
      };

  # etc 键检查: text 包含 entry URL
  checkEtc = sw: k:
    let
      actual = etc.${k}.text or null;
    in
    {
      label = "inject/${sw}/${k}: etc 文件包含某个 provider URL";
      expected = "true";
      actual =
        if actual == null then
          "false (file not set)"
        else if containsUrl sw actual then
          "true"
        else
          "false (got ${actual})";
    };

  # special 键检查: nix substituters / docker registry-mirrors
  checkSpecial = sw: k:
    if sw == "nix" && k == "substituters" then
      let
        actuals = config.nix.settings.substituters;
        urls = entryUrls sw;
        # 性质: 所有 entry URL 都出现在 substituters 中 (substituters 可含系统默认值如 cache.nixos.org)
        allPresent = builtins.all (u: builtins.elem u actuals) urls;
      in
      {
        label = "inject/${sw}/${k}: 所有 provider URL ∈ substituters";
        expected = "true";
        actual = if allPresent then "true" else "false (missing some of ${toString urls} in ${toString actuals})";
      }
    else if sw == "nix" && k == "trusted-public-keys" then
      let
        # 从 entries 派生期望的 keys (模块应注入这些)
        expectedKeys = lib.flatten (map (e: e.trusted-public-keys or [ ]) (config.mirrors.${sw}.entries));
        actuals = config.nix.settings.trusted-public-keys;
        allPresent = builtins.all (key: builtins.elem key actuals) expectedKeys;
        result = if expectedKeys == [ ] then "true" else if allPresent then "true" else "false: missing some of ${toString expectedKeys}";
      in
      {
        label = "inject/${sw}/${k}: 所有 provider trusted-public-keys 已注入";
        expected = "true";
        actual = result;
      }
    else if sw == "docker" && k == "registry-mirrors" then
      let
        settings = config.virtualisation.docker.daemon.settings or { };
        actuals = settings."registry-mirrors" or [ ];
        urls = entryUrls sw;
        # docker registry-mirrors 无系统默认值, 模块完全决定其内容
        exactMatch = builtins.length actuals == builtins.length urls
          && builtins.all (u: builtins.elem u actuals) urls
          && builtins.all (a: builtins.elem a urls) actuals;
      in
      {
        label = "inject/${sw}/${k}: registry-mirrors == entry URLs";
        expected = "true";
        actual =
          if actuals == [ ] && urls == [ ] then
            "true (both empty)"
          else if exactMatch then
            "true"
          else
            "false (actuals ${toString actuals}, expected ${toString urls})";
      }
    else
      mkSkip "inject/${sw}/${k} (unknown special key)";
in
lib.flatten (
  map
    (
      sw:
      let
        s = specs.${sw};
        enabled = isEnabled sw;
        guard = fn: k:
          if enabled then fn sw k else mkSkip "inject/${sw}/${k} (sw disabled or no entries)";
      in
      (map (guard checkEnv) s.envKeys)
      ++ (map (guard checkEtc) s.etcKeys)
      ++ (map (guard checkSpecial) s.specialKeys)
    )
    allSoftware
)
