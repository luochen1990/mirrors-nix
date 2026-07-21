# mirrors-nix 开发任务入口
# 常用:
#   just check   一键验证 (lint + nix flake check, 含模块 eval 断言)
#   just fmt     用 nix fmt (nixpkgs-fmt) 格式化所有 .nix 文件
#   just update  更新 flake inputs
#   just show    显示 flake outputs 结构

# 一键验证: lint (deadnix + statix) → nix flake check (含模块 eval 断言)
# 用法: just check
# 说明: 此目标对应 PR 前的标准验证流程; 在干净 checkout 上应一次通过.
#       若失败, 优先看 lint 输出和 mirrors-module-eval 的 FAIL 行.
check:
    just lint
    nix flake check

# 静态检查: deadnix (nix 死代码) + statix (nix 反模式)
# 用法: just lint
# 说明: 排除 .taskmaster/ (Task Master 数据, 不参与 lint).
#       deadnix --fail 在发现未使用绑定时返回非 0.
#       statix check . 按 statix.toml 配置的规则扫描全仓 (注意文件名无前导点, 见 statix.toml 头注释).
lint:
    @echo "Running deadnix..."
    find . -name '*.nix' -not -path './.taskmaster/*' -print -exec deadnix --fail {} +
    @echo "Running statix..."
    statix check .

# 格式化所有 .nix 文件
# 用法: just fmt
# 说明: 调用项目 formatter (flake.nix 中 formatter.<system> = nixpkgs-fmt).
#       nix fmt 会以 flake.nix 所在目录为根, 递归格式化所有 .nix 文件.
fmt:
    nix fmt

# 更新 flake inputs
# 用法: just update
# 说明: 执行 nix flake update, 重写 flake.lock 到最新 input commit.
#       更新后务必跑一次 just check 确认仍全绿.
update:
    nix flake update

# 显示 flake outputs 结构
# 用法: just show
# 说明: 列出所有 nixosModules / checks / devShells / formatter 等顶层输出.
show:
    nix flake show
