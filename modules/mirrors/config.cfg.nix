# mirrors 模块直写下发 (受 mirrors.enable 控制配置项)
#
# flake-fhs 约定: .cfg.nix 的内容会被 mkIf (enable-chain) 自动包裹.
# enable-chain = config.mirrors.enable (本模块是顶层目录模块, 无祖先).
# 因此本文件内每个 mkIf 只需检查逐软件 enable + 数据非空, 无需再检查 cfg.enable.
#
# 多镜像策略:
# - nix (substituters): 收集所有匹配的 provider, 提取 url + trusted-public-keys
# - docker (registry-mirrors): 收集所有匹配的 provider, 提取 url
# - goproxy (GOPROXY): 收集所有匹配的 provider, 提取 url, 逗号拼接 + direct 兜底
# - pip/npm/rustup/huggingface/cabal: 取第一个匹配的 provider, 提取 url (单镜像)
# - cargo: 取第一个匹配的 provider, 通过环境变量设置 (cargo 不读 /etc/ 配置)
#
# cabal 特殊性: CABAL_CONFIG 遮蔽式下发 (默认关闭) + repository 块不 pin root-keys;
# 完整原因与实测细节见 modules/mirrors/AGENTS.md "cabal 默认关闭的原因"
#
# 易出错点:
# - 新增软件前先确认其配置文件搜索路径 (不是所有软件都读 /etc/, 如 cargo 只读 $CARGO_HOME)
# - 环境变量在无可用镜像时应不设置, 让软件用官方默认值; 不能用空值或 "direct" 覆盖
# - Nix `or` 仅在属性缺失时返回默认值; 属性存在但值为 null 时返回 null, 需额外判断
# - 参考镜像站文档时确认完整配置项, 勿遗漏配套变量 (如 rustup 需同时设 DIST_SERVER + UPDATE_ROOT)
{ config, lib, ... }:
let
  cfg = config.mirrors;

  # --- 直写下发用的派生数据 (直接从 cfg.<sw>.entries 提取, entries 在 default.nix 派生) ---
  nixUrls = map (e: e.url) cfg.nix.entries;
  nixKeys = lib.flatten (map (e: let k = e.trusted-public-keys or [ ]; in if k == null then [ ] else k) cfg.nix.entries);

  dockerRegistries = map (e: e.url) cfg.docker.entries;

  goproxyValue = lib.concatStringsSep "," ((map (e: e.url) cfg.goproxy.entries) ++ [ "direct" ]);

  # 单镜像: 从 entries 取首项 url (entries 为空时返回 null)
  firstUrl = es: if es == [ ] then null else (builtins.head es).url or null;
  pipUrl = firstUrl cfg.pip.entries;
  npmUrl = firstUrl cfg.npm.entries;
  cargoUrl = firstUrl cfg.cargo.entries;
  rustupUrl = firstUrl cfg.rustup.entries;
  hfUrl = firstUrl cfg.huggingface.entries;
  cabalUrl = firstUrl cfg.cabal.entries;

  # cabal env 指针与 etc 下发路径的配对 SSOT (模块侧; checks 侧由 filePointerEnvKeys 守护)
  cabalConfigEtc = "cabal/config";
in
{
  # === Nix binary cache (多镜像, mkBefore 提高优先级) ===
  nix.settings.substituters = lib.mkIf (cfg.nix.enable && nixUrls != [ ]) (lib.mkBefore nixUrls);
  nix.settings.trusted-public-keys = lib.mkIf (cfg.nix.enable && nixKeys != [ ]) nixKeys;

  # === Docker registry mirror (多镜像, 默认关闭) ===
  virtualisation.docker.daemon.settings = lib.mkIf (cfg.docker.enable && dockerRegistries != [ ]) {
    registry-mirrors = dockerRegistries;
  };

  # === 环境变量 ===
  environment.variables = lib.mkMerge [
    (lib.mkIf (cfg.pip.enable && pipUrl != null) { PIP_INDEX_URL = pipUrl; })
    (lib.mkIf (cfg.rustup.enable && rustupUrl != null) {
      RUSTUP_DIST_SERVER = rustupUrl;
      RUSTUP_UPDATE_ROOT = "${rustupUrl}/rustup";
    })
    # cargo 不读 /etc/cargo/config.toml, 通过环境变量设置镜像
    (lib.mkIf (cfg.cargo.enable && cargoUrl != null) {
      CARGO_REGISTRIES_CRATES_IO_PROTOCOL = "sparse";
      CARGO_REGISTRIES_CRATES_IO_INDEX = cargoUrl;
    })
    (lib.mkIf (cfg.goproxy.enable && cfg.goproxy.entries != [ ]) { GOPROXY = goproxyValue; })
    (lib.mkIf (cfg.huggingface.enable && hfUrl != null) { HF_ENDPOINT = hfUrl; })
    # cabal: 遮蔽式下发, 默认关闭 (见文件头注释)
    (lib.mkIf (cfg.cabal.enable && cabalUrl != null) { CABAL_CONFIG = "/etc/${cabalConfigEtc}"; })
  ];

  # === 配置文件 (pip / npm / cabal) ===
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

    (lib.mkIf (cfg.cabal.enable && cabalUrl != null) {
      "${cabalConfigEtc}".text = ''
        repository mirror
          url: ${cabalUrl}
          secure: True
      '';
    })
  ];
}
