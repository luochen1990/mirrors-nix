# mirrors 模块选项定义
# 横向统一配置各软件的镜像源, 类似 catppuccin/nix 横向配置配色
#
# 设计要点:
# - provider 预设: 每个 provider 只列它实际提供的镜像 (省略 = 不提供); 数据为 attrset, 支持扩展
# - preferred list: 有序 provider 列表, 每个 software 取列表中所有匹配的 provider entry
# - providerPresets: 内置预设通过 config 注入 (见 config.nix), 与用户值走标准 module system 递归合并
# - entries (派生 option): 每个 software 有 readOnly 的 entries option, 值为 resolveAll 后的完整 entry 列表
#   (未剪裁, 应用方自行决定 select one / select all). entries 不受 enable 控制, 始终可读.
#
# 易出错点:
# - providerPresets 的默认值不能放在 mkOption.default — 那样用户的整段定义会替换 default, 内置预设会丢失
#   正确做法: 内置预设写在 config.nix 的 config.mirrors.providerPresets = import ./providers.nix;
#   这样模块自身作为一个 definition, 与用户定义参与合并 (lib.mkMerge 语义)
# - providers 类型用 listOf str 而非 enum, 以支持用户自定义 provider 名 (但须存在于 providerPresets, 否则静默返回 null)
# - option 名与 providerPresets 中的 software key 可能不一致 (如 pip option 对应 pypi provider key);
#   config.nix 中的 swProviderKey 映射表是此不一致的 SSOT
{lib, ...}: let
  # 逐软件 provider 偏好列表类型 (null = 继承全局 mirrors.providers)
  providerListType = lib.types.nullOr (lib.types.listOf lib.types.str);

  # 为每个软件生成完整选项 (enable + providers + entries)
  # 参数:
  #   displayName: 人类可读的软件名 (用于 description)
  #   defaultEnable: 默认是否启用 (docker 等场景设 false)
  #   enableDescription: enable option 的自定义描述 (默认 "启用 ${displayName} 镜像源")
  mkSoftwareOpts = {
    displayName,
    defaultEnable ? true,
    enableDescription ? "启用 ${displayName} 镜像源",
  }: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = defaultEnable;
      description = enableDescription;
    };
    providers = lib.mkOption {
      type = providerListType;
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
in {
  options.mirrors = {
    enable = lib.mkEnableOption "统一镜像源配置";

    providers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["tuna" "ustc" "aliyun" "tencent" "bfsu" "sjtu" "goproxy-cn" "goproxy-io" "daocloud" "hf-mirror"];
      description = ''
        有序的镜像源提供商偏好列表 (preferred provider list).
        对每个软件, entries option 收集列表中所有提供该镜像的 provider entry.
        顺序即优先级. 列表中的 provider 名须存在于 providerPresets (内置预设或用户自定义).
      '';
    };

    # Provider 预设数据 (内置预设在 config.nix 中通过 config 注入, 不在此处设 default;
    # 否则用户定义会替换 default 导致内置预设丢失)
    #
    # 类型说明 (重要):
    #   不用 nullOr attrs 而是 attrsOf attrs, 因为 nullOr 在多定义场景下会冲突
    #   (内置预设 {url=...} 与用户 null 在 module system 合并时报 "defined both null and not null").
    #   "provider 不提供某软件" 用 attrset 中**字段缺失**表达, 而非显式 null.
    #   resolveAll 用 attrByPath 自动处理缺失 (= null), 语义等价.
    providerPresets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.attrs);
      default = {};
      description = ''
        Provider 预设数据. 内置预设 (tuna / ustc / aliyun / ...) 由模块自动注入, 用户可任意添加或覆盖:
        - 添加自定义 provider: `mirrors.providerPresets.my-cache.nix = { url = "https://..."; trusted-public-keys = ["key1"]; };`
        - 覆盖内置字段: `mirrors.providerPresets.tuna.pypi = { url = "https://new-url.com"; };`
        每个 entry 为 attrset (至少含 `url`), 可扩展 `trusted-public-keys` 等字段.
        **"provider 不提供某软件"用 attrset 中省略字段表达 (不要写 null)**, 解析层 (lib.nix#attrByPath) 会自动当作 null.
      '';
    };

    # --- 各 software ---
    # 注: pip option 对应 pypi provider key; 其余 option 名与 provider key 一致 (映射见 config.nix swProviderKey)
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
    pip = mkSoftwareOpts {displayName = "pip (Python PyPI)";};
    npm = mkSoftwareOpts {displayName = "npm (Node.js)";};
    cargo = mkSoftwareOpts {displayName = "cargo (Rust crates.io)";};
    rustup = mkSoftwareOpts {displayName = "rustup (Rust 工具链)";};
    huggingface = mkSoftwareOpts {displayName = "HuggingFace (HF_ENDPOINT)";};
    goproxy = mkSoftwareOpts {displayName = "Go module proxy (GOPROXY)";};
  };
}
