#!/usr/bin/env python3
"""镜像 URL 可用性 + mirrorz 数据一致性巡检.

职责边界:
  1. 从 module/providers.nix (SSOT) 提取所有 provider.software.url 三元组
  2. 可达性检测: 对每个 URL 做 HTTP HEAD 探测 (某些 S3-like 后端用 Range-GET 回退)
  3. 一致性检测: 对在 mirrorz 数据库中的 provider, 比对 URL 与 mirrorz 自报路径,
     捕捉悄默路径变更. mirrorz 数据来自 mirrorz-json-legacy (每日 CI 抓取的 git 快照).

数据流:
  providers.nix ──> nix eval --json ──> entries [{provider, software, url}, ...]
                                              │
                              ┌───────────────┴───────────────┐
                              ▼                               ▼
                  可达性检测 (HEAD/Range-GET)        一致性检测 (对比 mirrorz)
                              │                               │
                              └───────────────┬───────────────┘
                                              ▼
                                         报告 + 退出码

一致性检测的 provider 覆盖:
  - 仅对 mirrorz 数据库收录的传统镜像站生效 (tuna/ustc/bfsu/sjtu)
  - 商业服务商 (aliyun/tencent) 和专用服务商 (daocloud/hf-mirror/goproxy-*) 不参与,
    因为 mirrorz 不收录这些 provider

用法:
  python3 scripts/verify_mirrors.py                # 默认: 两检测都做, 彩色输出
  python3 scripts/verify_mirrors.py --reach        # 只做可达性检测
  python3 scripts/verify_mirrors.py --consistency  # 只做一致性检测
  python3 scripts/verify_mirrors.py --quiet        # 静默模式 (仅输出问题, CI 友好)

退出码:
  0 = 全部通过 (可达性无失效 + 一致性无 ERROR)
  1 = 有 ERROR (URL 失效 或 一致性检测发现路径已变更)
  2 = 脚本/数据错误 (providers.nix 解析失败 / mirrorz 数据获取失败)

依赖:
  标准库 (urllib.request / json / concurrent.futures / argparse / subprocess)
  外部命令: nix (eval --json)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request
from collections import Counter
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar

# === 配置常量 (本脚本 SSOT, 与外部数据解耦) ===

# 每个 URL 探测的超时 (秒). 兼顾速度与对镜像站的礼貌.
HTTP_TIMEOUT = 10

# 可达性检测的并发数. 兼顾巡检速度与镜像站压力.
REACHABILITY_CONCURRENCY = 8

# mirrorz-json-legacy 数据源 (每日 CI 抓取的 git 快照, 通过 raw.githubusercontent 取单文件)
MIRRORZ_LEGACY_BASE = (
    "https://raw.githubusercontent.com/mirrorz-org/mirrorz-json-legacy/master/data"
)

# provider 名 → mirrorz site 缩写 (仅列不一致的; 未列入视为同名)
# 例如 sjtu 实际指向 mirror.sjtu.edu.cn, 在 mirrorz 数据库里代号是 siyuan.
# 仅对传统镜像站生效; 商业/专用服务商不入此表 (mirrorz 不收录).
PROVIDER_SITE_ALIAS: dict[str, str] = {
    "sjtu": "siyuan",
}

# 我们的 software 名 → mirrorz 标准 cname 候选列表 (顺序即优先级)
# 多候选理由: 不同站点对同一被镜像对象的命名存在差异
#   - nix: 多数站叫 nix-channels, 但 bfsu 只报了 nix (实际路径仍是 /nix-channels)
#   - cargo: 多数站叫 crates.io-index, 但 sjtu 只报 crates.io
# 数据源: https://github.com/mirrorz-org/mirrorz-config/blob/master/cname.json
# 未列入的 software (pypi/rustup) 视为单候选 (同名)
SOFTWARE_CNAME_CANDIDATES: dict[str, list[str]] = {
    "nix": ["nix-channels", "nix"],
    "cargo": ["crates.io-index", "crates.io"],
}

# mirrorz URL 到"实际服务入口"的派生规则
# mirrorz 的 url 字段只是镜像目录根, 而各软件的协议要求不同的子路径或独立子域名.
# providers.nix 中的 URL 是"实际服务入口", 不能与 mirrorz url 字面比对, 需要先派生.
#
# 每条规则: software → 派生函数 (site, mirror_url) -> list[str]
# site 参数是 mirrorz 站点缩写 (如 "tuna", "siyuan"), 用于站点特例 (如 pypi 独立子域).
# 返回多个候选入口 (因为同一 software 在不同站点的入口形式可能不同, 如 pypi 有独立子域 / 同站子路径).
# 比对逻辑: providers URL 只要匹配任一候选入口 (前缀比对) 即视为一致.
# 未列入的 software (rustup) 视为镜像目录根 == 实际服务入口, 单候选直接比对.


def _nix_service_urls(_site: str, mirror_url: str) -> list[str]:
    """nix binary cache 入口: mirrorz nix-channels 目录 + /store."""
    return [mirror_url.rstrip("/") + "/store"]


def _pypi_service_urls(site: str, _mirror_url: str) -> list[str]:
    """pypi: tuna/ustc 独立子域特例 (mirrorz url 字段无法表达跨子域)."""
    independent = {
        "tuna": "https://pypi.tuna.tsinghua.edu.cn/simple",
        "ustc": "https://pypi.mirrors.ustc.edu.cn/simple",
    }
    return [independent[site]] if site in independent else []


SOFTWARE_URL_DERIVATION: dict[str, Callable[[str, str], list[str]]] = {
    "nix": _nix_service_urls,
    "pypi": _pypi_service_urls,
}


# 不参与一致性检测的 software
# 理由: mirrorz 不收录 (goproxy/docker/huggingface 是专用服务商领域)
#       或各站命名歧义 (npm 镜像站镜像的是 nodejs-release 而非 npm registry)
SOFTWARE_NO_CONSISTENCY: set[str] = {"goproxy", "npm", "docker", "huggingface"}

# 不参与一致性检测的 provider
# 理由: mirrorz 数据库不收录 (商业/专用服务商)
PROVIDER_NO_CONSISTENCY: set[str] = {
    "aliyun",
    "tencent",
    "daocloud",
    "hf-mirror",
    "goproxy-cn",
    "goproxy-io",
}


# === 数据结构 ===


@dataclass(frozen=True)
class Entry:
    """providers.nix 中的一条镜像 entry."""

    provider: str
    software: str
    url: str


@dataclass(frozen=True)
class ReachResult:
    """可达性检测结果."""

    entry: Entry
    status: str  # HTTP 状态码字符串 ("200", "404", "ERR:TimeoutError" 等)
    reachable: bool


@dataclass(frozen=True)
class ConsistencyResult:
    """一致性检测结果.

    level:
      "OK"        = URL 与 mirrorz 自报路径一致
      "WARN"      = mirrorz 数据中未找到对应 cname, 或找到但路径语义不匹配
                    (mirrorz 数据滞后或站点命名差异; 需人工判断, 不影响退出码)
      "ERROR"     = mirrorz 自报路径与 providers.nix 中的 URL 不一致 (路径可能已变更)
      "SKIP"      = 该 entry 不参与一致性检测 (mirrorz 不覆盖)
      "FETCH_ERR" = mirrorz 数据获取失败 (网络问题, 不影响退出码)
    """

    entry: Entry
    level: str
    message: str
    detail: dict[str, Any] | None = None


# === ANSI 颜色 (根据 tty / --quiet 切换) ===


@dataclass(frozen=True)
class Colors:
    """ANSI 颜色码; 非 tty 或 --quiet 时所有属性为空字符串."""

    green: str
    red: str
    yellow: str
    cyan: str
    magenta: str
    bold: str
    reset: str

    _ANSI: ClassVar[dict[str, str]] = {
        "green": "\033[32m",
        "red": "\033[31m",
        "yellow": "\033[33m",
        "cyan": "\033[36m",
        "magenta": "\033[35m",
        "bold": "\033[1m",
        "reset": "\033[0m",
    }

    @classmethod
    def for_output(cls, enabled: bool) -> Colors:
        return cls(**{k: v if enabled else "" for k, v in cls._ANSI.items()})


# === Step 1: 从 providers.nix 提取所有 entry ===


def extract_entries_from_providers(project_root: Path) -> list[Entry]:
    """调用 nix eval --json 从 module/providers.nix 提取所有 entry.

    providers.nix 是 URL 的 SSOT; 本函数零硬编码, 全部数据由 nix eval 派生.
    entry 可能为 null (类型允许), nix 表达式里加守卫跳过.
    """
    nix_expr = """
      let presets = import ./module/providers.nix; in
      builtins.concatLists (
        builtins.attrValues (
          builtins.mapAttrs (provider: swMap:
            builtins.attrValues (
              builtins.mapAttrs (software: entry:
                if entry == null then null
                else { provider = provider; software = software; url = entry.url; }
              ) swMap
            )
          ) presets
        )
      )
    """
    try:
        result = subprocess.run(
            ["nix", "eval", "--impure", "--json", "--expr", nix_expr],
            capture_output=True,
            text=True,
            check=True,
            cwd=project_root,
        )
    except subprocess.CalledProcessError as e:
        print(
            f"!! nix eval 失败, 检查 module/providers.nix 语法\n{e.stderr}",
            file=sys.stderr,
        )
        sys.exit(2)

    data = json.loads(result.stdout)
    return [Entry(item["provider"], item["software"], item["url"]) for item in data]


# === Step 2: 可达性检测 ===


def _probe_url(url: str) -> str:
    """探测 URL 返回 HTTP 状态码字符串.

    返回值:
      - 成功: 数字字符串 ("200", "301", "404")
      - 网络错误: "ERR:<异常类型名>" (如 "ERR:TimeoutError"), 便于诊断
    """
    # 第一轮: HEAD 请求
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return str(resp.status)
    except urllib.error.HTTPError as e:
        # HTTP 错误 (如 404) 仍返回状态码, 这是有效信号
        return str(e.code)
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
        head_err = type(e).__name__
    else:
        head_err = None

    # 第二轮: Range-GET 回退 (某些 S3-like 后端对 HEAD 异常)
    try:
        req = urllib.request.Request(url)
        req.add_header("Range", "bytes=0-0")
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return str(resp.status)
    except urllib.error.HTTPError as e:
        return str(e.code)
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
        # 两轮都失败, 优先报告 HEAD 的错误类型 (更接近"这个 URL 死了"的语义)
        return f"ERR:{head_err or type(e).__name__}"


def _is_reachable(status: str) -> bool:
    """判定状态码是否视为可达.

    2xx/3xx/401/403 都视为可达. 401/403 表示端点存在, 仅权限受限
    (如 USTC nix-channels/store/ 列目录被禁).
    ERR:* 一律视为不可达.
    """
    if status.startswith("ERR") or status == "":
        return False
    try:
        code = int(status)
    except ValueError:
        return False
    return code < 400 or code in {401, 403}


def check_reachability(entries: list[Entry]) -> list[ReachResult]:
    """并发探测所有 entry 的 URL 可达性."""
    results: list[ReachResult] = []
    with ThreadPoolExecutor(max_workers=REACHABILITY_CONCURRENCY) as pool:
        future_to_entry = {pool.submit(_probe_url, e.url): e for e in entries}
        for future in as_completed(future_to_entry):
            entry = future_to_entry[future]
            # 兜底: _probe_url 内已捕获常见网络异常, 但仍防御未来改动引入的意外异常
            try:
                status = future.result()
            except Exception as e:  # noqa: BLE001
                status = f"ERR:{type(e).__name__}"
            results.append(ReachResult(entry, status, _is_reachable(status)))
    # 按原始顺序排序, 让输出稳定
    order = {e: i for i, e in enumerate(entries)}
    results.sort(key=lambda r: order[r.entry])
    return results


# === Step 3: 一致性检测 ===


def _fetch_mirrorz_site(site: str) -> dict[str, Any] | None:
    """从 mirrorz-json-legacy 拉取指定站点的 mirrorz.json 数据.

    返回 None 表示获取失败 (404 / 网络错误). 调用方决定如何处理.
    """
    url = f"{MIRRORZ_LEGACY_BASE}/{site}.json"
    try:
        with urllib.request.urlopen(url, timeout=HTTP_TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except (
        urllib.error.URLError,
        TimeoutError,
        ConnectionError,
        OSError,
        json.JSONDecodeError,
    ):
        return None


def _normalize_url(url: str) -> str:
    """规范化 URL 用于一致性比对.

    去尾斜杠 + 整体小写化 (URL 路径部分对大小写不敏感, host 显然不敏感).
    scheme/host/path 在现实镜像 URL 中均为小写, 小写化不会引入假阳性.
    """
    return url.rstrip("/").lower()


def _skip_reason(entry: Entry) -> str | None:
    """判断 entry 是否应跳过一致性检测, 返回原因或 None."""
    if entry.provider in PROVIDER_NO_CONSISTENCY:
        return f"provider {entry.provider} 不在 mirrorz 数据库"
    if entry.software in SOFTWARE_NO_CONSISTENCY:
        return f"software {entry.software} mirrorz 数据不可靠"
    return None


def check_consistency(entry: Entry) -> ConsistencyResult:
    """对单条 entry 比对其 URL 与 mirrorz 自报路径.

    比对规则:
      1. 取 software 的所有 cname 候选 (SOFTWARE_CNAME_CANDIDATES, 默认 [software 本身])
      2. 在 mirrorz 数据中查找任一候选 cname, 收集所有匹配的 mirror 记录
      3. 对每个匹配记录, 派生"实际服务入口"候选列表 (SOFTWARE_URL_DERIVATION, 默认 [mirror_url])
      4. 双向前缀匹配: providers URL 与任一候选满足"互为前缀"即视为一致
         (双向前缀用于处理 pypi 独立子域 vs 同站子路径的差异)
    """
    # 1. 跳过判定
    skip_reason = _skip_reason(entry)
    if skip_reason is not None:
        return ConsistencyResult(entry, "SKIP", skip_reason)

    # 2. 派生 mirrorz 查询键
    site = PROVIDER_SITE_ALIAS.get(entry.provider, entry.provider)
    cname_candidates = SOFTWARE_CNAME_CANDIDATES.get(entry.software, [entry.software])

    # 3. 抓取 mirrorz 数据
    data = _fetch_mirrorz_site(site)
    if data is None:
        return ConsistencyResult(
            entry,
            "FETCH_ERR",
            f"无法获取 mirrorz 数据 data/{site}.json",
        )

    # 防御 mirrorz 数据格式异常 (url 字段非 str 等)
    raw_site_url = data.get("site", {}).get("url", "")
    site_url = raw_site_url.rstrip("/") if isinstance(raw_site_url, str) else ""

    # 4. 在 mirrorz mirrors 列表中找匹配的 cname (多候选, 收集所有命中)
    matched_mirrors: list[tuple[str, str]] = []  # [(cname, mirror_url), ...]
    for mirror in data.get("mirrors", []):
        cname = mirror.get("cname", "")
        if cname not in cname_candidates:
            continue
        raw_mirror_url = mirror.get("url", "")
        if not isinstance(raw_mirror_url, str):
            continue
        if raw_mirror_url.startswith("/"):
            mirror_url = site_url + raw_mirror_url
        else:
            mirror_url = raw_mirror_url
        matched_mirrors.append((cname, mirror_url))

    if not matched_mirrors:
        return ConsistencyResult(
            entry,
            "WARN",
            f"mirrorz {site} 数据中未找到任一 cname 候选: {cname_candidates}",
            detail={"site": site, "cname_candidates": cname_candidates},
        )

    # 5. 收集所有候选入口: mirror_url 自身 + derive 函数追加的额外入口
    derive = SOFTWARE_URL_DERIVATION.get(entry.software)
    all_candidates: list[str] = []
    for _cname, mirror_url in matched_mirrors:
        all_candidates.append(mirror_url)
        if derive is not None:
            all_candidates.extend(derive(site, mirror_url))

    # 6. 双向前缀匹配任一候选即视为一致
    for candidate in all_candidates:
        if _urls_consistent(entry.url, candidate):
            return ConsistencyResult(
                entry,
                "OK",
                f"一致 (mirrorz {site})",
            )

    # 7. 所有候选都不匹配
    # 多候选 cname: 命名歧义 → WARN; 单候选: 路径真变更 → ERROR.
    level = "WARN" if len(cname_candidates) > 1 else "ERROR"
    return ConsistencyResult(
        entry,
        level,
        f"路径不一致: providers.nix={entry.url} 不匹配 mirrorz 任一候选 {all_candidates}",
        detail={
            "providers_nix_url": entry.url,
            "mirrorz_candidates": all_candidates,
            "site": site,
            "cname_candidates": cname_candidates,
        },
    )


def _urls_consistent(a: str, b: str) -> bool:
    """双向前缀匹配: a 以 b 为前缀, 或 b 以 a 为前缀, 或两者规范化后相等."""
    na = _normalize_url(a)
    nb = _normalize_url(b)
    if na == nb:
        return True
    if na.startswith(nb.rstrip("/") + "/"):
        return True
    if nb.startswith(na.rstrip("/") + "/"):
        return True
    return False


# === 报告 ===


def report_reachability(results: list[ReachResult], colors: Colors, quiet: bool) -> int:
    """打印可达性报告, 返回失败数."""
    failures = [r for r in results if not r.reachable]
    items = failures if quiet else results
    for r in items:
        color = colors.green if r.reachable else colors.red
        print(
            f"  [{color}{r.status}{colors.reset}] "
            f"{r.entry.provider}/{r.entry.software}  {r.entry.url}"
        )
    if quiet:
        return len(failures)

    total = len(results)
    print()
    if failures:
        print(f"{colors.red}✗ 可达性: {len(failures)} / {total} 失效{colors.reset}")
    else:
        print(f"{colors.green}✓ 可达性: 全部 {total} 个 URL 可达{colors.reset}")
    return len(failures)


def report_consistency(
    results: list[ConsistencyResult], colors: Colors, quiet: bool
) -> tuple[int, int, int]:
    """打印一致性报告.

    返回 (error 数, warn 数, fetch_err 数).
    FETCH_ERR 单独计档, 不计入退出码 (mirrorz 数据获取失败不代表 providers.nix 有问题).
    """
    counts: Counter[str] = Counter(r.level for r in results)

    level_color = {
        "OK": colors.green,
        "ERROR": colors.red,
        "WARN": colors.yellow,
        "FETCH_ERR": colors.magenta,
        "SKIP": colors.cyan,
    }

    if quiet:
        # quiet 模式: 只输出 ERROR (真正影响退出码的问题)
        for r in results:
            if r.level == "ERROR":
                print(
                    f"  [{colors.red}{r.level}{colors.reset}] "
                    f"{r.entry.provider}/{r.entry.software}  {r.message}"
                )
        return counts["ERROR"], counts["WARN"], counts["FETCH_ERR"]

    # 非 quiet 模式: 完整报告
    for r in results:
        color = level_color.get(r.level, "")
        print(
            f"  [{color}{r.level:9s}{colors.reset}] "
            f"{r.entry.provider}/{r.entry.software}  {r.message}"
        )

    total = len(results)
    print()
    summary_parts = [
        f"{colors.green}OK={counts['OK']}{colors.reset}",
        f"{colors.cyan}SKIP={counts['SKIP']}{colors.reset}",
        f"{colors.yellow}WARN={counts['WARN']}{colors.reset}",
        f"{colors.magenta}FETCH_ERR={counts['FETCH_ERR']}{colors.reset}",
        f"{colors.red}ERROR={counts['ERROR']}{colors.reset}",
    ]
    print(f"一致性: {' | '.join(summary_parts)}  (总计 {total})")
    return counts["ERROR"], counts["WARN"], counts["FETCH_ERR"]


# === 主入口 ===


def main() -> int:
    parser = argparse.ArgumentParser(
        description="镜像 URL 可用性 + mirrorz 数据一致性巡检",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--reach", action="store_true", help="只做可达性检测")
    mode.add_argument(
        "--consistency", action="store_true", help="只做一致性检测 (对比 mirrorz 数据)"
    )
    parser.add_argument(
        "--quiet", action="store_true", help="静默模式 (仅输出问题, CI 友好)"
    )
    args = parser.parse_args()

    do_reach = not args.consistency
    do_consistency = not args.reach

    # tty 与 --quiet 决定是否启用颜色
    color_enabled = sys.stdout.isatty() and not args.quiet
    colors = Colors.for_output(color_enabled)

    project_root = Path(__file__).resolve().parent.parent
    entries = extract_entries_from_providers(project_root)
    if not entries:
        print("!! 未从 module/providers.nix 提取到任何 URL", file=sys.stderr)
        return 2

    if not args.quiet:
        print(
            f"{colors.bold}巡检 {len(entries)} 个 entry (来自 module/providers.nix){colors.reset}"
        )
        print()

    total_errors = 0

    if do_reach:
        if not args.quiet:
            print(f"{colors.bold}== 可达性检测 (HEAD / Range-GET)=={colors.reset}")
        reach_results = check_reachability(entries)
        reach_failures = report_reachability(reach_results, colors, args.quiet)
        total_errors += reach_failures
        if not args.quiet:
            print()

    if do_consistency:
        if not args.quiet:
            print(
                f"{colors.bold}== 一致性检测 (对比 mirrorz-json-legacy 数据)=={colors.reset}"
            )
        consistency_results = [check_consistency(e) for e in entries]
        # 按 entry 原始顺序排序
        order = {e: i for i, e in enumerate(entries)}
        consistency_results.sort(key=lambda r: order[r.entry])
        consistency_errors, _warns, _fetch_errs = report_consistency(
            consistency_results, colors, args.quiet
        )
        # FETCH_ERR 不计入退出码 (mirrorz 数据获取失败不代表 providers.nix 有问题)
        total_errors += consistency_errors

    if not args.quiet:
        print()
        if total_errors == 0:
            print(f"{colors.green}{colors.bold}✓ 巡检通过{colors.reset}")
        else:
            print(
                f"{colors.red}{colors.bold}✗ 巡检发现 {total_errors} 个问题{colors.reset}"
            )

    return 1 if total_errors > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
