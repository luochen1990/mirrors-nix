# Property: 开关精确性 (no-leak)
#
# 不变式 (P ⟹ Q):
#   forall software sw, forall 注入键 k (env / etc):
#     P: sw 被关闭 (总开关关 OR 逐软件关)
#     Q: k 不存在于 config 中
#
# 三态编码:
#   P=true  (sw 关闭): 正常检查 Q (assertAbsent)
#   P=false (sw 启用): skip
{ config
, lib
, assertHelpers
, softwareSpec
, ...
}:

let
  inherit (assertHelpers) assertAbsent mkSkip;
  inherit (softwareSpec) specs allSoftware;

  env = config.environment.variables;
  etc = config.environment.etc;

  # P: software sw 是否被关闭
  isDisabled = sw: !config.mirrors.enable || !config.mirrors.${sw}.enable;
in
lib.flatten (
  map
    (
      sw:
      let
        s = specs.${sw};
        disabled = isDisabled sw;

        # P ⟹ Q: 如果 sw 关闭, 检查注入项 absent; 否则 skip
        checkKey = container: k:
          if disabled then
            assertAbsent "no-leak/${sw}" container k
          else
            mkSkip "no-leak/${sw}/${k} (sw enabled)";
      in
      (map (checkKey env) s.envKeys)
      ++ (map (checkKey etc) s.etcKeys)
    )
    allSoftware
)
