# treefmt 配置 (多语言格式化聚合器)
#
# ⚠️ 重要: treefmt v2 (2024+) 已切换为 TOML 配置 (treefmt.toml), 不再读取 .nix 配置文件.
#    本文件仅为兼容 treefmt 1.x 与历史编辑器集成而保留; 真正生效的配置请见 ./treefmt.toml.
#
# 引入 flake-fhs 后, formatter 由 flake-fhs 自动生成 (= pkgs.treefmt, 因 treefmt.toml 存在).
# treefmt 内部按 ./treefmt.toml 分发: nixpkgs-fmt (Nix) + ruff format (Python).
#
# 主要为编辑器集成服务 (VSCode/Neovim), 命令行格式化请直接用 `just fmt` (= nix fmt = treefmt).
# 本仓库 devShell 使用 nixpkgs-fmt (底层 formatter), treefmt 作为外层 wrapper 保持一致.
{
  projectRootFile = "flake.nix";
  programs.nixpkgs-fmt.enable = true;
}
