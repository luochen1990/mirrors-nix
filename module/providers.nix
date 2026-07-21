# 镜像源提供商预设数据
# 每个 provider 只列它实际提供的镜像 (省略 = 不提供, lib.attrByPath 自动返回 null)
# 每个条目是 attrset (至少含 url), 支持未来扩展 (如 trusted-public-keys)
#
# URL 已逐个验证可用 (2026-07-21, 见 README 答谢区); 仅保留实测可用的镜像:
#   - goproxy 仅 aliyun 提供 (TUNA/USTC/SJTU/Tencent 公告中未提供或已下线)
#   - rustup 在 USTC/SJTU 的官方目录是 rust-static (语义等价于 TUNA/aliyun 的 rustup)
#   - docker 仅 daocloud 提供 (有限流); 传统镜像站 docker registry 已于 2024-06 关停
#   - npm 仅 aliyun npmmirror 提供 (USTC npm 已于 2026-06-12 关停)
#   - huggingface 仅 hf-mirror.com (独立服务, 非高校镜像站)
#
# 易出错点:
# - 省略 = 不提供 (attrByPath 自动返回 null); 不要写 = null
# - 若镜像需要额外配置 (如 nix trusted-public-keys), 在 entry attrset 中添加对应字段
# - URL 需定期验证可用性; 已关停的镜像不收录
#
# 用户可通过 mirrors.providerPresets 选项添加自定义 provider 或覆盖内置属性
# (NixOS module system 自动合并, 用户值优先级高于 default)
{
  # 清华大学 TUNA
  tuna = {
    nix = {url = "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store";};
    pypi = {url = "https://pypi.tuna.tsinghua.edu.cn/simple";};
    cargo = {url = "https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/";};
    rustup = {url = "https://mirrors.tuna.tsinghua.edu.cn/rustup";};
  };

  # 中科大 USTC
  ustc = {
    nix = {url = "https://mirrors.ustc.edu.cn/nix-channels/store";};
    pypi = {url = "https://pypi.mirrors.ustc.edu.cn/simple";};
    cargo = {url = "https://mirrors.ustc.edu.cn/crates.io-index/";};
    rustup = {url = "https://mirrors.ustc.edu.cn/rust-static";};
  };

  # 阿里云 (npmmirror 即阿里旗下服务)
  aliyun = {
    pypi = {url = "https://mirrors.aliyun.com/pypi/simple/";};
    npm = {url = "https://registry.npmmirror.com";};
    cargo = {url = "https://mirrors.aliyun.com/crates.io-index/";};
    rustup = {url = "https://mirrors.aliyun.com/rustup";};
    goproxy = {url = "https://mirrors.aliyun.com/goproxy/";};
  };

  # 腾讯云
  tencent = {
    pypi = {url = "https://mirrors.cloud.tencent.com/pypi/simple";};
  };

  # 北外 BFSU
  bfsu = {
    nix = {url = "https://mirrors.bfsu.edu.cn/nix-channels/store";};
    pypi = {url = "https://mirrors.bfsu.edu.cn/pypi/web/simple";};
    cargo = {url = "https://mirrors.bfsu.edu.cn/crates.io-index/";};
  };

  # 上海交大 SJTU
  sjtu = {
    nix = {url = "https://mirror.sjtu.edu.cn/nix-channels/store";};
    pypi = {url = "https://mirror.sjtu.edu.cn/pypi/web/simple";};
    cargo = {url = "https://mirror.sjtu.edu.cn/crates.io-index/";};
    rustup = {url = "https://mirror.sjtu.edu.cn/rust-static";};
  };

  # DaoCloud (仅 docker registry; 有限流: 1Mi/s, 20r/m, 白名单机制)
  daocloud = {
    docker = {url = "https://docker.m.daocloud.io";};
  };

  # hf-mirror (仅 huggingface; 独立服务, 非镜像站)
  hf-mirror = {
    huggingface = {url = "https://hf-mirror.com";};
  };
}
