# treefmt 配置 (多语言格式化聚合器)
#
# ⚠️ 重要: treefmt v2 (2024+) 已切换为 TOML 配置 (treefmt.toml), 不再读取 .nix 配置文件.
#    本文件仅为兼容 treefmt 1.x 与历史编辑器集成而保留; 真正生效的配置请见 ./treefmt.toml.
#
# 主要为编辑器集成服务 (VSCode/Neovim), 命令行格式化请直接用 `just fmt` (= nix fmt = nixpkgs-fmt).
# 本仓库 devShell 使用 nixpkgs-fmt (T1 决策), 因此 treefmt 也用 nixpkgs-fmt 而非 nixfmt, 保持一致.
#
# 历史: 主仓 ~/ws/nixos/treefmt.nix 仍用 nix 配置, 是因其 pin 在 treefmt 1.x;
#       本仓库跟随 nixos-unstable 使用 treefmt 2.x, 故用 toml.
{
  projectRootFile = "flake.nix";
  programs.nixpkgs-fmt.enable = true;
}
