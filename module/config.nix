# mirrors 模块配置应用
# 将 providerPresets 中的镜像配置应用到各软件的 NixOS 配置项
#
# 两层开关: 总开关 mirrors.enable 是第一道闸; 逐软件 enable 是第二道 (二者必须都为 true 才生效)
# 两层覆盖: 逐软件 providers > 全局 providers
# providerPresets: 内置预设 (providers.nix) 注入到 config (而非 option default), 用户可任意覆盖
#
# entries (派生 option): 每个 software 的 entries 是 readOnly, 值为 resolveAll 后的完整 entry 列表
#   (未剪裁, 应用方自行决定 select one / select all). 不受 enable 控制, 始终可读.
#   计算所需数据 (providers + providerPresets) 都在 let 中求值, entries 写入是字面量路径, 不触发递归.
#
# 直写下发 (nix.settings / environment.variables / environment.etc): 保持改造前逻辑不变 (字面量路径).
#   消费者若不想用直写下发 (如 selector4nix 代理接管 nix binary cache), 设 mirrors.<sw>.enable = false 即可,
#   entries 仍可读 (不受 enable 控制).
#
# 多镜像策略:
# - nix (substituters): 收集所有匹配的 provider, 提取 url + trusted-public-keys
# - docker (registry-mirrors): 收集所有匹配的 provider, 提取 url
# - goproxy (GOPROXY): 收集所有匹配的 provider, 提取 url, 逗号拼接 + direct 兜底
#   (各 provider 的实际覆盖情况见 module/providers.nix 头注释)
# - pip/npm/rustup/huggingface: 取第一个匹配的 provider, 提取 url (单镜像)
# - cargo: 取第一个匹配的 provider, 通过环境变量设置 (cargo 不读 /etc/ 配置)
#
# 易出错点:
# - 总开关 cfg.enable 必须参与每个 mkIf 条件; 否则 mirrors.enable=false 时仍会写入配置 (历史 bug)
# - 新增软件前先确认其配置文件搜索路径 (不是所有软件都读 /etc/, 如 cargo 只读 $CARGO_HOME)
# - 环境变量在无可用镜像时应不设置, 让软件用官方默认值; 不能用空值或 "direct" 覆盖
# - Nix `or` 仅在属性缺失时返回默认值; 属性存在但值为 null 时返回 null, 需额外判断
# - 参考镜像站文档时确认完整配置项, 勿遗漏配套变量 (如 rustup 需同时设 DIST_SERVER + UPDATE_ROOT)
#   (USTC/SJTU 用 rust-static 目录名, 语义等价; 详见 module/providers.nix 头注释)
{
  config,
  lib,
  ...
}: let
  # 内置 provider 预设 (SSOT). 在 config 块中作为模块自身的 definition 注入,
  # 与用户定义的 providerPresets 一起走 NixOS module system 标准合并 (用户值可覆盖内置字段).
  # 不能在 options.nix 用 mkOption.default 设默认值 — 那样用户整段定义会替换 default, 内置预设全丢.
  builtinPresets = import ./providers.nix;

  cfg = config.mirrors;
  providerPresets = cfg.providerPresets;
  mlib = import ./lib.nix {inherit lib;};

  # 解析生效的 provider 列表: 逐软件 providers 覆盖 > 全局 providers
  effProv = swCfg: if swCfg.providers != null then swCfg.providers else cfg.providers;

  # option 名 → providerPresets 中的 software key (不一致时在此映射, 当前仅 pip option 对应 pypi key)
  swProviderKey = {
    nix = "nix";
    docker = "docker";
    pip = "pypi";
    npm = "npm";
    cargo = "cargo";
    rustup = "rustup";
    huggingface = "huggingface";
    goproxy = "goproxy";
  };

  # 各 software 的完整 entries (未剪裁, resolveAll 收集所有匹配 provider).
  # 从 swProviderKey 派生 (key 集合 SSOT), 新增 software 只改 swProviderKey + options.nix 即可.
  # 同时用于: (1) 写入 readOnly entries option 供消费者读 (2) 直写下发的数据源
  swEntries = swName: mlib.resolveAll (effProv cfg.${swName}) providerPresets swProviderKey.${swName};
  allEntries = lib.mapAttrs (name: _: swEntries name) swProviderKey;

  # --- 直写下发用的派生数据 (从 entries 提取) ---
  nixUrls = map (e: e.url) allEntries.nix;
  nixKeys = lib.flatten (map (e: let k = e.trusted-public-keys or []; in if k == null then [] else k) allEntries.nix);

  dockerRegistries = map (e: e.url) allEntries.docker;

  goproxyValue = lib.concatStringsSep "," ((map (e: e.url) allEntries.goproxy) ++ ["direct"]);

  # 单镜像: 从 entries 取首项 url (entries 为空时返回 null)
  firstUrl = es: if es == [] then null else (builtins.head es).url or null;
  pipUrl = firstUrl allEntries.pip;
  npmUrl = firstUrl allEntries.npm;
  cargoUrl = firstUrl allEntries.cargo;
  rustupUrl = firstUrl allEntries.rustup;
  hfUrl = firstUrl allEntries.huggingface;
in {
  # === 注入内置 provider 预设 + 派生 entries ===
  # providerPresets: 内置预设作为模块 definition 注入 (与用户定义走 module system 合并)
  # entries: resolveAll 后的完整列表 (readOnly, 不受 enable 控制), 从 allEntries 派生
  # 用 mapAttrs 从 allEntries 自动派生 entries 写入, 新增 software 时此处零修改
  mirrors =
    (lib.mapAttrs (_: es: {entries = es;}) allEntries)
    // {providerPresets = builtinPresets;};

  # === 拼写检查: 所有 mirrors.providers / mirrors.<software>.providers 引用的 provider 名 ===
  # 必须存在于 providerPresets. 拼错的 provider 名原本会静默返回 null (镜像缺失),
  # 通过 NixOS 标准 assertions 机制给用户明确告警, 避免难以排查的"镜像链突然少一项"问题.
  #
  # software 列表是本模块 SSOT — 必须与 options.nix 中注册的 software 一致.
  # 拼写错误会通过 cfg.${name}.enable 直接 eval 失败 (fail-fast), 不会被静默吞掉.
  assertions = let
    softwareNames = builtins.attrNames swProviderKey;
    # 对每个 software, 求其生效 provider 列表中不在 providerPresets 的项 (仅当该 software 启用时)
    flagged = builtins.filter (x: x.invalid != []) (
      map (
        sname: {
          name = sname;
          # 仅检查启用的 software; 关闭的 software 的 providers 列表无意义
          invalid =
            if !(cfg.enable && cfg.${sname}.enable)
            then []
            else builtins.filter (p: !providerPresets ? ${p}) (effProv cfg.${sname});
        }
      ) softwareNames
    );
  in
    map (
      x: {
        assertion = false;
        message = "mirrors: ${x.name} 的 provider 列表引用了未在 providerPresets 中定义的项: ${toString x.invalid}";
      }
    ) flagged;

  # === Nix binary cache (多镜像, mkBefore 提高优先级) ===
  nix.settings.substituters = lib.mkIf (cfg.enable && cfg.nix.enable && nixUrls != []) (lib.mkBefore nixUrls);
  nix.settings.trusted-public-keys = lib.mkIf (cfg.enable && cfg.nix.enable && nixKeys != []) nixKeys;

  # === Docker registry mirror (多镜像, 默认关闭) ===
  virtualisation.docker.daemon.settings = lib.mkIf (cfg.enable && cfg.docker.enable && dockerRegistries != []) {
    registry-mirrors = dockerRegistries;
  };

  # === 环境变量 ===
  environment.variables = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.pip.enable && pipUrl != null) {PIP_INDEX_URL = pipUrl;})
    (lib.mkIf (cfg.enable && cfg.rustup.enable && rustupUrl != null) {
      RUSTUP_DIST_SERVER = rustupUrl;
      RUSTUP_UPDATE_ROOT = "${rustupUrl}/rustup";
    })
    # cargo 不读 /etc/cargo/config.toml, 通过环境变量设置镜像
    (lib.mkIf (cfg.enable && cfg.cargo.enable && cargoUrl != null) {
      CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
      CARGO_REGISTRIES_CRATES_IO_INDEX = cargoUrl;
    })
    (lib.mkIf (cfg.enable && cfg.goproxy.enable && allEntries.goproxy != []) {GOPROXY = goproxyValue;})
    (lib.mkIf (cfg.enable && cfg.huggingface.enable && hfUrl != null) {HF_ENDPOINT = hfUrl;})
  ];

  # === 配置文件 (pip / npm) ===
  environment.etc = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.pip.enable && pipUrl != null) {
      "pip.conf".text = ''
        [global]
        index-url = ${pipUrl}
      '';
    })

    (lib.mkIf (cfg.enable && cfg.npm.enable && npmUrl != null) {
      "npmrc".text = ''
        registry=${npmUrl}
      '';
    })
  ];
}
