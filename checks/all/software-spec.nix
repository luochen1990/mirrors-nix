# mirrors 模块的软件规格 (SSOT for properties).
#
# 职责边界:
#   定义所有 software 的 provider key、注入键 (环境变量/配置文件/special 设置).
#   properties/*.nix 通过 forall 遍历此规格生成断言.
#
# 数据来源:
#   - provider key: 从 modules/mirrors/default.nix#swProviderKey 派生
#   - 注入键: 从 modules/mirrors/config.cfg.nix 的下发逻辑提取
#
# ⚠️ 同步点:
#   新增 software 或改下发逻辑时, 需同步更新此文件.
#   验证一致性: grep -E 'environment\.(variables|etc)|nix\.settings|virtualisation' modules/mirrors/config.cfg.nix
#   (后续 PR 可考虑把此映射提取到模块层, 让模块和 properties 共享同一 SSOT)
let
  # 每个 software 的规格集中在一处 (缺省键视为 []), 避免分散在多张平行表中
  specs = {
    nix = {
      providerKey = "nix";
      # nix 走 nix.settings, 不是 env/etc
      specialKeys = [ "substituters" "trusted-public-keys" ];
    };
    docker = {
      providerKey = "docker";
      # docker 走 virtualisation.docker.daemon.settings
      specialKeys = [ "registry-mirrors" ];
    };
    pip = {
      providerKey = "pypi";
      envKeys = [ "PIP_INDEX_URL" ];
      etcKeys = [ "pip.conf" ];
    };
    npm = {
      providerKey = "npm";
      etcKeys = [ "npmrc" ];
    };
    cargo = {
      providerKey = "cargo";
      envKeys = [ "CARGO_REGISTRIES_CRATES_IO_PROTOCOL" "CARGO_REGISTRIES_CRATES_IO_INDEX" ];
      # PROTOCOL=sparse 是协议标识, 不是 URL, inject-correctness 不适用
      nonUrlEnvKeys = [ "CARGO_REGISTRIES_CRATES_IO_PROTOCOL" ];
    };
    rustup = {
      providerKey = "rustup";
      envKeys = [ "RUSTUP_DIST_SERVER" "RUSTUP_UPDATE_ROOT" ];
    };
    huggingface = {
      providerKey = "huggingface";
      envKeys = [ "HF_ENDPOINT" ];
    };
    goproxy = {
      providerKey = "goproxy";
      envKeys = [ "GOPROXY" ];
    };
  };

  fillDefault = s: {
    providerKey = s.providerKey or "";
    envKeys = s.envKeys or [ ];
    etcKeys = s.etcKeys or [ ];
    specialKeys = s.specialKeys or [ ];
    nonUrlEnvKeys = s.nonUrlEnvKeys or [ ];
  };
in
{
  specs = builtins.mapAttrs (_: fillDefault) specs;
  allSoftware = builtins.attrNames specs;
}
