# mirrors-nix 最简用法
#
# 放置位置: 把此文件内容放入 configuration.nix 的 imports 数组里
# (前提: flake.nix 的 inputs 已添加 mirrors-nix,
#  modules 数组已添加 mirrors-nix.nixosModules.default)
_: {
  mirrors.enable = true;  # 启用全部默认镜像 (tuna 优先, 自动覆盖 nix/pip/npm/cargo/rustup/goproxy/huggingface)
}
