# enable-false-leak 断言: 总开关关闭时所有注入项应不存在
# 全量遍历所有可能被注入的键, 守护未来新增 software 时漏加 cfg.enable && 的回归.
{ config, assertHelpers, ... }:

let
  inherit (assertHelpers) assertAbsent;
  env = config.environment.variables;
  etc = config.environment.etc;
in
[
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
]
