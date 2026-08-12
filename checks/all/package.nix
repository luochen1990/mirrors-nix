# checks 唯一入口: 对所有 test-config × 所有 properties 笛卡尔积执行, 1 个 drv.
#
# 属性测试架构 (三要素分离):
#   test-configs (退化生成器): 枚举具体 NixOS 配置 (modules list), 不含断言
#   properties (属性): forall 遍历 software 的不变式, 从 config 自行提取前提条件 (P ⟹ Q)
#   driver (本文件): 笛卡尔积 — 每个 config × 每个 property, 拼接所有断言
#
# 三态断言:
#   check (正常比对) / skip (前提不满足) / pass (比对通过)
#   skip 让"前提不满足"与"断言通过"区分开, 避免假绿
#
# flake-fhs 封装语义: package.nix 存在时, 子目录 (properties/ test-configs/) 不被扫描.
{ lib
, self
, mkEvalCheck
, evalMirrors
, builtinPresets
, assertHelpers
, ...
}:

let
  # 所有 software 的规格 (SSOT: software 名 / provider key / 注入键)
  softwareSpec = import ./software-spec.nix;

  # properties 的公共参数
  propArgs = {
    inherit lib builtinPresets assertHelpers softwareSpec self;
  };

  # 属性文件列表: 每个 config 都跑所有 properties
  properties = [
    (import ./properties/no-leak.nix)
    (import ./properties/entries-invariant.nix)
    (import ./properties/inject-correctness.nix)
  ];

  # 退化生成器: 枚举具体 NixOS 配置 (modules list)
  # 后续 PR 可增强为真正的生成器 (排列组合 / 随机采样)
  testConfigs = {
    # 默认行为: mirrors.enable=true 全套默认镜像
    default = [{ mirrors.enable = true; }];

    # 总开关关闭, 整套模块应零副作用
    enable-false = [{ mirrors.enable = false; }];

    # 添加自定义 provider, 内置 provider 必须全部保留
    custom-provider = [
      {
        mirrors = {
          enable = true;
          providerPresets.my-cache.nix = {
            url = "https://my-cache.example.com";
            trusted-public-keys = [ "my-cache-1:abc" ];
          };
          nix.providers = [ "my-cache" "tuna" ];
        };
      }
    ];

    # 覆盖内置 provider 字段, 其他字段保持不变
    builtin-override = [
      {
        mirrors = {
          enable = true;
          providerPresets.tuna.pypi = { url = "https://new-pypi.example.com/simple"; };
        };
      }
    ];

    # 逐软件 enable=false 只关停该软件
    per-software-disable = [
      {
        mirrors = {
          enable = true;
          pip.enable = false;
          cargo.enable = false;
        };
      }
    ];

    # mkBefore 让镜像 substituter 排在用户值之前
    substituter-order = [
      {
        mirrors.enable = true;
        nix.settings.substituters = [ "https://my-custom.example.com" ];
      }
    ];

    # entries option 在 enable=false 时仍可读且返回完整未剪裁数据
    entries-readable = [
      {
        mirrors = {
          enable = false;
          nix.enable = false;
          providers = [ "tuna" "bfsu" "aliyun" ];
        };
      }
    ];

    # docker 默认关闭, 显式启用以覆盖 docker registry-mirrors 注入
    docker-enabled = [
      {
        mirrors = {
          enable = true;
          docker.enable = true;
        };
      }
    ];
  };

  # 笛卡尔积: 每个 config × 每个 property → 断言 list → 拼接
  # property 断言的 label 里带上 cfgName, 方便失败时定位是哪个配置触发的
  tagProp = cfgName: assertions:
    map (a: a // { label = "[${cfgName}] ${a.label}"; }) assertions;

  allAssertions = lib.concatLists (
    lib.mapAttrsToList
      (
        cfgName: modules:
          let config = evalMirrors modules; in
          tagProp cfgName (lib.concatMap (prop: prop (propArgs // { inherit config; })) properties)
      )
      testConfigs
  );
in
mkEvalCheck "all" allAssertions
