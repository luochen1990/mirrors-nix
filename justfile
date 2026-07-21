# mirrors-nix 开发任务入口
# 常用:
#   just check   一键验证 (lint + nix flake check, 含模块 eval 断言)
#   just fmt     格式化 (nixpkgs-fmt + ruff format)
#   just update  更新 flake inputs
#   just show    显示 flake outputs 结构
#   just verify-mirrors  巡检 providers.nix 中所有镜像 URL 的可达性与一致性

# 一键验证: lint (deadnix + statix + ruff) → nix flake check (含模块 eval 断言)
# 用法: just check
# 说明: 此目标对应 PR 前的标准验证流程; 在干净 checkout 上应一次通过.
#       若失败, 优先看 lint 输出和 mirrors-module-eval 的 FAIL 行.
check:
    just lint
    nix flake check

# 静态检查: deadnix (nix 死代码) + statix (nix 反模式) + ruff (python lint)
# 用法: just lint
# 说明: 排除 .taskmaster/ (Task Master 数据, 不参与 lint).
#       deadnix --fail 在发现未使用绑定时返回非 0.
#       statix check . 按 statix.toml 配置的规则扫描全仓 (注意文件名无前导点, 见 statix.toml 头注释).
#       ruff check 扫描 scripts/ 下的 Python 代码, 规则见 pyproject.toml.
lint:
    @echo "Running deadnix..."
    find . -name '*.nix' -not -path './.taskmaster/*' -print -exec deadnix --fail {} +
    @echo "Running statix..."
    statix check .
    @echo "Running ruff (python lint)..."
    ruff check .

# 格式化所有文件 (.nix + .py)
# 用法: just fmt
# 说明: nix fmt 格式化 .nix 文件; ruff format 格式化 scripts/ 下的 Python 代码.
fmt:
    nix fmt
    ruff format .

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

# 镜像 URL 可达性 + mirrorz 一致性巡检
# 用法: just verify-mirrors
# 说明: 从 module/providers.nix (SSOT) 提取所有 url, 执行两类检测:
#       1. 可达性: 并发 HEAD/Range-GET 探测每个 URL 是否返回 2xx/3xx/401/403
#       2. 一致性: 对比 mirrorz-json-legacy 数据, 捕捉悄默路径变更
#       退出码: 0=通过, 1=有 ERROR, 2=脚本/数据错误.
#       适合在更新 providers.nix 后跑一次确认 URL 仍可达且路径与 mirrorz 数据一致.
verify-mirrors:
    python3 scripts/verify_mirrors.py

# 镜像 URL 巡检 (静默模式, 只输出问题项)
# 用法: just verify-mirrors-quiet
# 说明: 同 verify-mirrors, 但只输出 ERROR / FETCH_ERR, 适合 CI 或管道下游消费.
verify-mirrors-quiet:
    python3 scripts/verify_mirrors.py --quiet

# 仅做可达性检测
# 用法: just verify-mirrors-reach
verify-mirrors-reach:
    python3 scripts/verify_mirrors.py --reach

# 仅做一致性检测 (对比 mirrorz 数据)
# 用法: just verify-mirrors-consistency
verify-mirrors-consistency:
    python3 scripts/verify_mirrors.py --consistency
