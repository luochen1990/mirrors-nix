# devShell 默认环境
# 集中放置 lint / format / lsp / build 工具链.
#
# 职责边界:
#   仅声明 devShell 内容 (packages). 由 flake-fhs 自动装配成 devShells.<system>.default.
#
# 关键设计:
#   工具列表是 SSOT, 新增/移除工具只改这一处, CI 自动跟随 (CI 通过 `nix develop -c just check`).
#   不再需要 flake.nix 的 devTools 绑定 (改造前 devTools 在 flake.nix 内, 迁移后下沉到此).
{ pkgs
, ...
}:

pkgs.mkShellNoCC {
  packages = with pkgs; [
    nixpkgs-fmt # formatter (与 treefmt.toml 中配置的底层 formatter 保持一致)
    deadnix # 静态检查: 未使用代码
    statix # 静态检查: 反模式建议
    nil # LSP (nix language server)
    just # 任务运行器 (justfile)
    nix # 包管理器自身, 保证 devShell 内 nix 版本可控
    treefmt # 多语言格式化聚合器 (flake-fhs 在 treefmt.toml 存在时选它作为 formatter)
    python3 # 巡检脚本 scripts/verify_mirrors.py 的运行时
    ruff # Python lint + format (巡检脚本代码质量)
  ];
}
