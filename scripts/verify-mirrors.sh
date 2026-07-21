#!/usr/bin/env bash
# 镜像 URL 可用性巡检
#
# 职责边界:
#   从 module/providers.nix (SSOT) 提取所有 provider.software.url 三元组,
#   对每个 url 做 HTTP HEAD 探测, 报告失效项.
#   本脚本不硬编码任何 URL.
#
# 用法:
#   scripts/verify-mirrors.sh            # 彩色输出 (tty)
#   scripts/verify-mirrors.sh --quiet    # 只输出失效项 (适合 CI / 管道)
#
# 退出码: 0=全部可达, 1=有失效项, 2=脚本/数据错误
# 依赖: nix, curl, jq
set -euo pipefail
cd "$(readlink -f "$(dirname "$0")/..")"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
export QUIET

# tty / quiet 决定是否启用颜色 (CI 日志友好)
if [ -t 1 ] && [ "$QUIET" -ne 1 ]; then
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
else
  GREEN=""
  RED=""
  RESET=""
fi
export GREEN RED RESET

# --- 单个 URL 检测函数 ---
# 判定标准: 2xx/3xx/401/403 视为可达
# (401/403 表示端点存在, 仅权限受限, 如 USTC nix-channels/store/ 列目录被禁;
#  真正失效是 404/5xx/连接错误)
check_one() {
  local provider="$1" software="$2" url="$3" code
  # 第一轮: HEAD
  code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' -I "$url" 2>/dev/null) || code="ERR"
  # 第二轮: 范围 GET 回退 (某些 S3-like 后端对 HEAD 异常)
  case "$code" in
    000|ERR|"")
      code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' -r 0-0 "$url" 2>/dev/null) || code="ERR"
      ;;
  esac
  case "$code" in
    [23]*|401|403)
      [ "$QUIET" -ne 1 ] && printf "  [${GREEN}%s${RESET}] %s/%s  %s\n" "$code" "$provider" "$software" "$url"
      ;;
    *)
      printf "  [${RED}%s${RESET}] %s/%s  %s\n" "$code" "$provider" "$software" "$url"
      echo "FAIL $provider/$software $url (code=$code)" >> "$RESULT_FILE"
      ;;
  esac
  # 显式 return 0 避免 set -e + wait 误判
  return 0
}
export -f check_one

# --- 从 providers.nix (SSOT) 提取所有 url ---
# nix eval 输出: [{"provider":"tuna","software":"nix","url":"https://..."}, ...]
# entry 可能为 null (类型允许), 用守卫跳过
ENTRIES_FILE=$(mktemp)
RESULT_FILE=$(mktemp)
export RESULT_FILE
trap 'rm -f "$ENTRIES_FILE" "$RESULT_FILE"' EXIT

nix eval --impure --json --expr '
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
' \
  | jq -r '.[] | [.provider, .software, .url] | @tsv' > "$ENTRIES_FILE"

TOTAL=$(wc -l < "$ENTRIES_FILE")
if [ "$TOTAL" -eq 0 ]; then
  echo "!! 未从 module/providers.nix 提取到任何 URL" >&2
  exit 2
fi

[ "$QUIET" -ne 1 ] && { echo "巡检 $TOTAL 个 URL (来自 module/providers.nix)..."; echo; }

# --- 并发巡检 (后台子shell + wait, 并发度 8) ---
MAX_JOBS=8
while IFS=$'\t' read -r provider software url; do
  while [ "$(jobs -r | wc -l)" -ge "$MAX_JOBS" ]; do
    wait -n 2>/dev/null || sleep 0.1
  done
  check_one "$provider" "$software" "$url" &
done < "$ENTRIES_FILE"
wait 2>/dev/null || true

# --- 汇总 ---
FAILED_LINES=$(wc -l < "$RESULT_FILE")
if [ "$QUIET" -ne 1 ]; then
  echo
  if [ "$FAILED_LINES" -eq 0 ]; then
    echo "✓ 全部 $TOTAL 个 URL 可达"
  else
    echo "✗ $FAILED_LINES / $TOTAL 个 URL 失效 (见上方标红项)"
  fi
fi

if [ "$FAILED_LINES" -gt 0 ]; then
  exit 1
fi
exit 0
