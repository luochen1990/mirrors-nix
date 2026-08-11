# checks 唯一入口: 求值 7 个场景, 拼接所有断言, 生成 1 个 derivation.
#
# flake-fhs 封装语义: package.nix 存在时, 当前目录 (all/) 及子目录 (scenarios/) 不被扫描.
# scenarios/ 里的 7 个文件是纯断言数据 (函数: config -> [assertion]), 由本文件逐个 import.
#
# 1-drv 设计:
#   每个场景用各自的 eval 配置求值出 config, 再调用对应的断言函数提取断言 list,
#   最后把所有场景的断言拼接成 1 个 list, 喂给同一个 mkEvalCheck.
#   失败定位粒度不变 (断言的 label 含场景前缀, 如 "[enable=false] PIP_INDEX_URL 未注入").
#
# 数据驱动: 场景名 → extraModules 的 attrset 是场景清单 SSOT, 新增/删除场景只改这一处.
# 所有 scenario 文件统一传 { config, builtinPresets, assertHelpers, lib }, lambda 自动忽略未声明的参数.
{ lib
, mkEvalCheck
, evalMirrors
, builtinPresets
, assertHelpers
, ...
}:

let
  # 场景名 → extraModules. 新增/删除场景只改这一处 + 新建 scenario 文件.
  scenarioModules = {
    # 默认行为: mirrors.enable=true 全套默认镜像
    default = [{ mirrors.enable = true; }];

    # 总开关关闭, 整套模块应零副作用
    enable-false-leak = [{ mirrors.enable = false; }];

    # 添加自定义 provider, 内置 provider 必须全部保留
    custom-provider-merge = [
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
  };

  # 所有 scenario 文件的统一参数 (lambda 自动忽略未声明的, 故无需改 scenario 文件)
  argsFor = config: {
    inherit config builtinPresets assertHelpers lib;
  };
in
mkEvalCheck "all" (
  lib.concatLists (
    lib.mapAttrsToList
      (
        name: extraModules:
        import ./scenarios/${name}.nix (argsFor (evalMirrors extraModules))
      )
      scenarioModules
  )
)
