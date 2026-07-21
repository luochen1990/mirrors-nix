# mirrors-nix 高级用法: 展示完整的 provider 覆盖能力
#
# 与 module/AGENTS.md 用法示例呼应, 演示 4 个场景:
#   1. 自定义全局 providers 顺序 (ustc 优先于 tuna)
#   2. 逐软件覆盖 (仅 pip 用 aliyun, 不影响其他软件)
#   3. 添加自定义 provider (公司内部 cache, 含 nix trusted-public-keys)
#   4. 启用非默认软件 (docker), 关闭某软件 (cargo)
#
# 放置位置: 把此文件内容放入 configuration.nix 的 imports 数组里
# (前提: flake.nix 已添加 mirrors-nix.nixosModules.default 到 modules 数组)
_: {
  mirrors = {
    # 总开关: 即便做了下面的细粒度定制, 仍需 enable 才会真正写入系统配置
    enable = true;

    # --- 场景 1: 自定义全局 provider 偏好顺序 ---
    # 默认是 ["tuna" "ustc" "aliyun" ... "goproxy-cn" "goproxy-io" ...], 这里改为 ustc 优先, tuna 回退
    # 若引入了自定义 provider (见场景 3), 通常把它放到列表最前
    providers = ["my-cache" "ustc" "tuna" "aliyun" "tencent" "bfsu" "sjtu" "goproxy-cn" "goproxy-io" "daocloud" "hf-mirror"];

    # --- 场景 2: 逐软件覆盖 ---
    # 仅 pip 的偏好顺序被覆盖, 其他软件仍继承全局 mirrors.providers
    # 两层覆盖: 逐软件 providers > 全局 providers
    pip.providers = ["aliyun" "tuna"];

    # --- 场景 3: 添加自定义 provider ---
    # 公司内部 cache, 通过 NixOS module system 与内置预设自动合并
    # provider 名 ("my-cache") 必须出现在 providers 列表里才会被使用
    providerPresets = {
      my-cache = {
        # nix 支持 trusted-public-keys 等额外字段
        nix = {
          url = "https://my-cache.example.com";
          trusted-public-keys = ["my-cache-1:abc123def456..."];
        };
        # pip 走公司内部 PyPI 简单仓库
        pypi = {url = "https://my-cache.example.com/pypi/simple";};
      };
    };

    # --- 场景 4: 启用非默认软件 / 关闭某软件 ---
    docker.enable = true;   # docker 默认关闭 (国内免费镜像大多已关停, 仅 DaoCloud 仍可用)
    cargo.enable = false;   # cargo 默认启用, 这里关闭 (例如走公司内部源 / 直连)
  };
}
