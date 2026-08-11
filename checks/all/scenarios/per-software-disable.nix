# per-software-disable 断言: 关闭的软件相关配置不存在, 其他软件仍正常注入
{ config, assertHelpers, ... }:

let
  inherit (assertHelpers) assertAbsent assertPresent;
  env = config.environment.variables;
  etc = config.environment.etc;
in
[
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
]
