# mirrors-nix 模块入口
# 横向统一配置各软件的镜像源, 类似 catppuccin/nix 横向配置配色
# 设计要点与覆盖矩阵见 module/AGENTS.md; 选项语义见 options.nix 头注释
#
# 用法: imports = [mirrors-nix.nixosModules.default]; mirrors.enable = true;
_: {
  imports = [./options.nix ./config.nix];
}
