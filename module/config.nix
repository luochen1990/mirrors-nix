# mirrors 模块配置应用
# 将 providerPresets 中的镜像配置应用到各软件的 NixOS 配置项
#
# 两层覆盖: 逐软件 providers > 全局 providers
# providerPresets: 内置预设 (providers.nix) 为 default, 用户可通过 mirrors.providerPresets 添加/覆盖
# 多镜像策略:
# - nix (substituters): 收集所有匹配的 provider, 提取 url + trusted-public-keys
# - docker (registry-mirrors): 收集所有匹配的 provider, 提取 url
# - goproxy (GOPROXY): 收集所有匹配的 provider, 提取 url, 逗号拼接 + direct 兜底
#   (各 provider 的实际覆盖情况见 module/providers.nix 头注释)
# - pip/npm/rustup/huggingface: 取第一个匹配的 provider, 提取 url (单镜像)
# - cargo: 取第一个匹配的 provider, 通过环境变量设置 (cargo 不读 /etc/ 配置)
#
# 易出错点:
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
  cfg = config.mirrors;
  providerPresets = cfg.providerPresets;
  mlib = import ./lib.nix {inherit lib;};

  # 解析生效的 provider 列表: 逐软件 providers 覆盖 > 全局 providers
  effProv = swCfg: if swCfg.providers != null then swCfg.providers else cfg.providers;

  # --- nix: 多镜像, 提取 url + trusted-public-keys ---
  nixEntries = mlib.resolveAll (effProv cfg.nix) providerPresets "nix";
  nixUrls = map (e: e.url) nixEntries;
  # or 仅在属性缺失时返回默认值; 显式 null 需单独处理
  nixKeys = lib.flatten (map (e: let k = e.trusted-public-keys or []; in if k == null then [] else k) nixEntries);

  # --- docker: 多镜像, 提取 url ---
  dockerEntries = mlib.resolveAll (effProv cfg.docker) providerPresets "docker";
  dockerRegistries = map (e: e.url) dockerEntries;

  # --- goproxy: 多镜像逗号拼接 + direct 兜底 ---
  goproxyEntries = mlib.resolveAll (effProv cfg.goproxy) providerPresets "goproxy";
  goproxyValue = lib.concatStringsSep "," ((map (e: e.url) goproxyEntries) ++ ["direct"]);

  # --- 单镜像: 取第一个匹配的 entry, 提取 url ---
  pipUrl = mlib.getUrl (mlib.resolveFirst (effProv cfg.pip) providerPresets "pypi");
  npmUrl = mlib.getUrl (mlib.resolveFirst (effProv cfg.npm) providerPresets "npm");
  cargoUrl = mlib.getUrl (mlib.resolveFirst (effProv cfg.cargo) providerPresets "cargo");
  rustupUrl = mlib.getUrl (mlib.resolveFirst (effProv cfg.rustup) providerPresets "rustup");
  hfUrl = mlib.getUrl (mlib.resolveFirst (effProv cfg.huggingface) providerPresets "huggingface");
in {
  # === Nix binary cache (多镜像, mkBefore 提高优先级) ===
  nix.settings.substituters = lib.mkIf (cfg.nix.enable && nixUrls != []) (lib.mkBefore nixUrls);
  nix.settings.trusted-public-keys = lib.mkIf (cfg.nix.enable && nixKeys != []) nixKeys;

  # === Docker registry mirror (多镜像, 默认关闭) ===
  virtualisation.docker.daemon.settings = lib.mkIf (cfg.docker.enable && dockerRegistries != []) {
    registry-mirrors = dockerRegistries;
  };

  # === 环境变量 ===
  environment.variables = lib.mkMerge [
    (lib.mkIf (cfg.pip.enable && pipUrl != null) {PIP_INDEX_URL = pipUrl;})
    (lib.mkIf (cfg.rustup.enable && rustupUrl != null) {
      RUSTUP_DIST_SERVER = rustupUrl;
      RUSTUP_UPDATE_ROOT = "${rustupUrl}/rustup";
    })
    # cargo 不读 /etc/cargo/config.toml, 通过环境变量设置镜像
    (lib.mkIf (cfg.cargo.enable && cargoUrl != null) {
      CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
      CARGO_REGISTRIES_CRATES_IO_INDEX = cargoUrl;
    })
    (lib.mkIf (cfg.goproxy.enable && goproxyEntries != []) {GOPROXY = goproxyValue;})
    (lib.mkIf (cfg.huggingface.enable && hfUrl != null) {HF_ENDPOINT = hfUrl;})
  ];

  # === 配置文件 (pip / npm) ===
  environment.etc = lib.mkMerge [
    (lib.mkIf (cfg.pip.enable && pipUrl != null) {
      "pip.conf".text = ''
        [global]
        index-url = ${pipUrl}
      '';
    })

    (lib.mkIf (cfg.npm.enable && npmUrl != null) {
      "npmrc".text = ''
        registry=${npmUrl}
      '';
    })
  ];
}
