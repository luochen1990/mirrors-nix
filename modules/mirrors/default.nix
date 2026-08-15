# mirrors 模块入口 (flake-fhs 目录模块)
# 横向统一配置各软件的镜像源, 类似 catppuccin/nix 横向配置配色
# 设计要点与覆盖矩阵见 modules/mirrors/AGENTS.md; 选项语义见本文件 options 段
#
# flake-fhs 目录模块约定:
#   - default.nix: options 定义 + 无条件 config (始终生效, 不受 enable 控制)
#   - config.cfg.nix: 受 enable-chain 控制的 config (flake-fhs 自动用 mkIf config.mirrors.enable 包裹)
#
# 本文件职责:
#   1. 声明 mirrors.* 系列 options (含 mirrors.enable, 让 flake-fhs 的 injectEnable 检测到已存在而不重复注入)
#   2. 无条件注入内置 providerPresets (让 entries-readable 场景在 enable=false 时仍能读 entries)
#   3. 派生各 software 的 entries (readOnly, 不受 enable 控制)
#   4. 拼写检查 (providers 列表中的 provider 名必须存在于 providerPresets)
#
# 受 mirrors.enable 控制的直写下发 (nix.settings / environment.* / docker) 放在 config.cfg.nix.
{ config, lib, ... }:
let
  # 逐软件 provider 偏好列表类型 (null = 继承全局 mirrors.providers)
  # 为每个软件生成完整选项 (enable + providers + entries)
  mkSoftwareOpts =
    { displayName
    , defaultEnable ? true
    , enableDescription ? "启用 ${displayName} 镜像源"
    }: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = defaultEnable;
        description = enableDescription;
      };
      providers = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = ''
          ${displayName} 专用 provider 偏好列表.
          null = 继承全局 mirrors.providers.
          设为列表则仅对此软件覆盖全局偏好顺序.
        '';
      };
      entries = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        readOnly = true;
        description = ''
          ${displayName} 解析后的完整 entry 列表 (preferred list 中所有匹配 provider, 未剪裁).
          不受 enable 控制, 始终可读. 应用方 (如 selector4nix 代理) 可直接读此 option 拿到解析数据,
          自行决定 select one / select all 策略.
          每个 entry 至少含 `url`, 可能携带 `trusted-public-keys` 等扩展字段.
        '';
      };
    };

  # 内置 provider 预设 (SSOT). 在 config 块中作为模块自身的 definition 注入,
  # 与用户定义的 providerPresets 一起走 NixOS module system 标准合并 (用户值可覆盖内置字段).
  # 不能用 mkOption.default 设默认值 — 那样用户整段定义会替换 default, 内置预设全丢.
  builtinPresets = import ./providers.nix;

  cfg = config.mirrors;
  providerPresets = cfg.providerPresets;
  mlib = import ./lib.nix { inherit lib; };

  # 解析生效的 provider 列表: 逐软件 providers 覆盖 > 全局 providers
  effProv = swCfg: if swCfg.providers != null then swCfg.providers else cfg.providers;

  # option 名 → providerPresets 中的 software key (不一致时在此映射: pip→pypi, cabal→hackage)
  swProviderKey = {
    nix = "nix";
    docker = "docker";
    pip = "pypi";
    npm = "npm";
    cargo = "cargo";
    rustup = "rustup";
    huggingface = "huggingface";
    goproxy = "goproxy";
    cabal = "hackage";
  };

  # 各 software 的完整 entries (未剪裁, resolveAll 收集所有匹配 provider).
  # 从 swProviderKey 派生 (key 集合 SSOT), 新增 software 只改 swProviderKey + 上方 options 段即可.
  swEntries = swName: mlib.resolveAll (effProv cfg.${swName}) providerPresets swProviderKey.${swName};
  allEntries = lib.mapAttrs (name: _: swEntries name) swProviderKey;
in
{
  # === Options ===
  options.mirrors = {
    enable = lib.mkEnableOption "统一镜像源配置";

    providers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tuna" "ustc" "aliyun" "tencent" "bfsu" "sjtu" "goproxy-cn" "goproxy-io" "daocloud" "hf-mirror" ];
      description = ''
        有序的镜像源提供商偏好列表 (preferred provider list).
        对每个软件, entries option 收集列表中所有提供该镜像的 provider entry.
        顺序即优先级. 列表中的 provider 名须存在于 providerPresets (内置预设或用户自定义).
      '';
    };

    # Provider 预设数据 (内置预设在下方 config 中注入, 不在此处设 default;
    # 否则用户定义会替换 default 导致内置预设丢失)
    #
    # 类型说明 (重要):
    #   不用 nullOr attrs 而是 attrsOf attrs, 因为 nullOr 在多定义场景下会冲突
    #   (内置预设 {url=...} 与用户 null 在 module system 合并时报 "defined both null and not null").
    #   "provider 不提供某软件" 用 attrset 中**字段缺失**表达, 而非显式 null.
    #   resolveAll 用 attrByPath 自动处理缺失 (= null), 语义等价.
    providerPresets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.attrs);
      default = { };
      description = ''
        Provider 预设数据. 内置预设 (tuna / ustc / aliyun / ...) 由模块自动注入, 用户可任意添加或覆盖:
        - 添加自定义 provider: `mirrors.providerPresets.my-cache.nix = { url = "https://..."; trusted-public-keys = ["key1"]; };`
        - 覆盖内置字段: `mirrors.providerPresets.tuna.pypi = { url = "https://new-url.com"; };`
        每个 entry 为 attrset (至少含 `url`), 可扩展 `trusted-public-keys` 等字段.
        **"provider 不提供某软件"用 attrset 中省略字段表达 (不要写 null)**, 解析层 (lib.nix#attrByPath) 会自动当作 null.
      '';
    };

    # --- 各 software ---
    # 注: pip/cabal 的 option 名与 provider key 不一致 (pypi/hackage, 映射见 swProviderKey); 其余一致
    nix = mkSoftwareOpts {
      displayName = "Nix binary cache";
      enableDescription = "启用 Nix binary cache 镜像 (substituters + trusted-public-keys), 使用 mkBefore 提高优先级";
    };
    docker = mkSoftwareOpts {
      displayName = "Docker registry mirror";
      defaultEnable = false;
      enableDescription = ''
        启用 Docker Hub registry 镜像加速.
        默认关闭: 国内免费 registry 镜像大多已关停 (2024-06), 仅 DaoCloud 仍可用但有限流.
      '';
    };
    pip = mkSoftwareOpts { displayName = "pip (Python PyPI)"; };
    npm = mkSoftwareOpts { displayName = "npm (Node.js)"; };
    cargo = mkSoftwareOpts { displayName = "cargo (Rust crates.io)"; };
    rustup = mkSoftwareOpts { displayName = "rustup (Rust 工具链)"; };
    huggingface = mkSoftwareOpts { displayName = "HuggingFace (HF_ENDPOINT)"; };
    goproxy = mkSoftwareOpts { displayName = "Go module proxy (GOPROXY)"; };
    cabal = mkSoftwareOpts {
      displayName = "cabal (Haskell Hackage)";
      defaultEnable = false;
      enableDescription = ''
        启用 Hackage 镜像 (cabal).
        默认关闭: cabal 无级联配置, 本模块通过 CABAL_CONFIG=/etc/cabal/config 下发,
        会**整文件遮蔽**用户自己的 ~/.cabal/config 或 ~/.config/cabal/config
        (用户级 cabal 定制全部失效, 不止 repository 段).
        若你有用户级 cabal 配置, 建议保持关闭并自行在用户配置中引用 mirrors.cabal.entries.
      '';
    };
  };

  # === 无条件 config (始终生效, 不受 mirrors.enable 控制) ===
  # providerPresets: 内置预设作为模块 definition 注入 (与用户定义走 module system 合并)
  # entries: resolveAll 后的完整列表 (readOnly, 不受 enable 控制), 从 allEntries 派生
  config.mirrors =
    (lib.mapAttrs (_: es: { entries = es; }) allEntries)
    // { providerPresets = builtinPresets; };

  # 拼写检查: providers 列表中的 provider 名必须存在于 providerPresets.
  # 拼错的 provider 名原本会静默返回 null (镜像缺失), 通过 assertions 给用户明确告警.
  config.assertions =
    let
      softwareNames = builtins.attrNames swProviderKey;
      flagged = builtins.filter (x: x.invalid != [ ]) (
        map
          (
            sname: {
              name = sname;
              invalid =
                if !(cfg.enable && cfg.${sname}.enable)
                then [ ]
                else builtins.filter (p: !providerPresets ? ${p}) (effProv cfg.${sname});
            }
          )
          softwareNames
      );
    in
    map
      (
        x: {
          assertion = false;
          message = "mirrors: ${x.name} 的 provider 列表引用了未在 providerPresets 中定义的项: ${lib.concatStringsSep ", " x.invalid}";
        }
      )
      flagged;
}
