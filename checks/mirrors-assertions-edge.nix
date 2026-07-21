# mirrors 模块 eval-time 断言数据 - 特殊场景 (供 flake.nix#checks 使用)
#
# 职责边界:
#   与 mirrors-assertions.nix 同样是声明式断言数据, 但聚焦"非默认配置"场景的回归守护.
#   每个场景需要独立的 NixOS eval 配置, 因此本文件导出一个 attrset, 每个字段是:
#     { modules = [...]; assertions = config: [{label, expected, actual}]; }
#   flake.nix 遍历每个场景, 用其 modules 求值, 再调用 assertions 函数生成断言.
#
# 守护的历史 bug:
#   - enable-false-leak:      总开关失效, mirrors.enable=false 时仍注入配置
#   - custom-provider-merge:   用户加自定义 provider 时内置 10 个 provider 全丢失
#   - builtin-override:        用户覆盖内置字段时其他字段是否保持不变
#   - per-software-disable:    逐软件 enable=false 是否只关停该软件
#   - substituter-order:       用户自定义 substituters 是否排在镜像之后 (mkBefore)
#
# 修复时对应的断言必须加上, 以防回归.
#
# 实现约束:
#   断言函数签名统一为 config -> [assertion], 不引入 lib 依赖 (保持 deadnix 0 告警).
#   需要"在 list 中查找元素索引"时用内嵌 findIndex, 避免 lambda 参数未使用告警.
let
  # 内嵌 list 索引查找 (避免依赖 nixpkgs.lib, 让断言函数只需 config 一个参数)
  # 返回目标元素在 list 中的索引, 找不到返回 -1
  findIndex = list: target: let
    go = i: l:
      if l == []
      then -1
      else if builtins.head l == target
      then i
      else go (i + 1) (builtins.tail l);
  in go 0 list;

  # 断言工厂: 断言某 attrset **不包含**指定 key (用于 enable=false / per-disable 场景)
  # 把"unexpectedly set" 等提示文案集中到此处, 避免在每个断言里复制粘贴
  assertAbsent = prefix: container: key: {
    label = "${prefix} ${key} 未注入";
    expected = "false";
    actual =
      if container ? ${key}
      then "true (unexpectedly set)"
      else "false";
  };

  # 断言工厂: 断言某 attrset **包含**指定 key (用于"其他软件不受影响"的对照检查)
  assertPresent = prefix: container: key: {
    label = "${prefix} ${key} 已注入";
    expected = "true";
    actual =
      if container ? ${key}
      then "true"
      else "false";
  };
in {
  # 场景 1: 总开关关闭, 整套模块应零副作用
  # 全量遍历所有可能被注入的键, 守护未来新增 software 时漏加 cfg.enable && 的回归
  enable-false-leak = {
    modules = [
      {mirrors.enable = false;}
    ];
    assertions = config: let
      env = config.environment.variables;
      etc = config.environment.etc;
    in [
      {
        label = "[enable=false] nix.settings.substituters 仅含 NixOS 默认 cache.nixos.org";
        expected = "1";
        actual = toString (builtins.length config.nix.settings.substituters);
      }
      {
        label = "[enable=false] nix.settings.trusted-public-keys 仅含 NixOS 默认 key";
        expected = "1";
        actual = toString (builtins.length config.nix.settings.trusted-public-keys);
      }
      # 全量遍历所有 environment.variables 注入项
      (assertAbsent "[enable=false]" env "PIP_INDEX_URL")
      (assertAbsent "[enable=false]" env "GOPROXY")
      (assertAbsent "[enable=false]" env "HF_ENDPOINT")
      (assertAbsent "[enable=false]" env "RUSTUP_DIST_SERVER")
      (assertAbsent "[enable=false]" env "RUSTUP_UPDATE_ROOT")
      (assertAbsent "[enable=false]" env "CARGO_REGISTRIES_CRATES_IO_PROTOCOL")
      (assertAbsent "[enable=false]" env "CARGO_REGISTRIES_CRATES_IO_INDEX")
      # 全量遍历所有 environment.etc 注入项
      (assertAbsent "[enable=false]" etc "pip.conf")
      (assertAbsent "[enable=false]" etc "npmrc")
      # docker registry-mirrors 应不存在
      (assertAbsent "[enable=false]" config.virtualisation.docker.daemon.settings "registry-mirrors")
    ];
  };

  # 场景 2: 添加自定义 provider, 内置 10 个 provider 必须全部保留
  custom-provider-merge = {
    modules = [
      {
        mirrors = {
          enable = true;
          providerPresets.my-cache.nix = {
            url = "https://my-cache.example.com";
            trusted-public-keys = ["my-cache-1:abc"];
          };
          nix.providers = ["my-cache" "tuna"];
        };
      }
    ];
    assertions = config: let
      presets = config.mirrors.providerPresets;
      # 内置 provider SSOT: 从 module/providers.nix 派生 (而非本地硬编码 list), 避免双重维护
      builtin = builtins.attrNames (import ../module/providers.nix);
      # 内置 provider 是否全部保留: 用 attrNames 集合运算替代 builtins.all lambda (避免 deadnix 误报)
      presetNames = builtins.attrNames presets;
      allPresent = builtins.all (n: builtins.elem n presetNames) builtin;
    in [
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
          if config.nix.settings.substituters != []
          then builtins.head config.nix.settings.substituters
          else "<empty>";
      }
    ];
  };

  # 场景 3: 覆盖内置 provider 的具体字段, 其他字段应保持不变
  builtin-override = {
    modules = [
      {
        mirrors = {
          enable = true;
          providerPresets.tuna.pypi = {url = "https://new-pypi.example.com/simple";};
        };
      }
    ];
    assertions = config: let
      tuna = config.mirrors.providerPresets.tuna;
    in [
      {
        label = "[override] tuna.pypi 已被用户值替换";
        expected = "https://new-pypi.example.com/simple";
        actual = tuna.pypi.url or "<missing>";
      }
      {
        label = "[override] tuna.nix 保持内置值不变";
        expected = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store";
        actual = tuna.nix.url or "<missing>";
      }
      {
        label = "[override] tuna.rustup 保持内置值不变";
        expected = "https://mirrors.tuna.tsinghua.edu.cn/rustup";
        actual = tuna.rustup.url or "<missing>";
      }
      {
        label = "[override] 生效的 PIP_INDEX_URL 是覆盖后的值";
        expected = "https://new-pypi.example.com/simple";
        actual = config.environment.variables.PIP_INDEX_URL or "<missing>";
      }
    ];
  };

  # 场景 4: 逐软件 enable=false 只关停该软件, 其他软件仍正常注入
  per-software-disable = {
    modules = [
      {
        mirrors = {
          enable = true;
          pip.enable = false;
          cargo.enable = false;
        };
      }
    ];
    assertions = config: let
      env = config.environment.variables;
      etc = config.environment.etc;
    in [
      # 关闭的软件: 相关变量 / 配置文件不应存在
      (assertAbsent "[per-disable]" env "PIP_INDEX_URL")
      (assertAbsent "[per-disable]" env "CARGO_REGISTRIES_CRATES_IO_INDEX")
      (assertAbsent "[per-disable]" env "CARGO_REGISTRIES_CRATES_IO_PROTOCOL")
      (assertAbsent "[per-disable]" etc "pip.conf")
      # 对照组: 其他软件应仍正常注入 (证明只是"逐软件关停", 而非整套失效)
      (assertPresent "[per-disable]" env "HF_ENDPOINT")
      (assertPresent "[per-disable]" env "GOPROXY")
      (assertPresent "[per-disable]" env "RUSTUP_DIST_SERVER")
      (assertPresent "[per-disable]" etc "npmrc")
    ];
  };

  # 场景 5: 用户自定义的 nix.settings.substituters 应排在镜像之后 (mkBefore 行为)
  # (镜像用 mkBefore 提高优先级, 因此镜像在前, 用户值在后; 这是合理的: 国内镜像优先于 cache.nixos.org)
  substituter-order = {
    modules = [
      {
        mirrors.enable = true;
        nix.settings.substituters = ["https://my-custom.example.com"];
      }
    ];
    assertions = config: let
      subs = config.nix.settings.substituters;
      userVal = "https://my-custom.example.com";
      userIdx = findIndex subs userVal;
    in [
      {
        label = "[order] 镜像 substituters 排在用户自定义之前 (mkBefore 生效)";
        expected = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store";
        actual = if subs != [] then builtins.head subs else "<empty>";
      }
      {
        label = "[order] 用户自定义 substituter 排在镜像之后";
        expected = "true";
        actual =
          if userIdx > 0
          then "true"
          else "false (userIdx=${toString userIdx}, subs=${toString subs})";
      }
    ];
  };
}
