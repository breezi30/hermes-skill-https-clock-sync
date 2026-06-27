#!/bin/bash
# preflight-check.sh — 在部署 setclock-http 之前跑一遍这个
# 确认：NTP 是否真的不通 + HTTPS 时间源是否可达 + 当前时钟漂移量
#
# 用法：sudo ./preflight-check.sh
# 退出码：0 = 可以部署，1 = 部署前需要先解决前置问题

set -u

RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "${GRN}[OK]${NC}    $*"; }
warn() { echo -e "${YEL}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

echo "=== 1. NTP/UDP-123 连通性 ==="
for host in time1.aliyun.com time.cloudflare.com pool.ntp.org; do
  if timeout 4 nc -uvz "$host" 123 2>&1 | grep -qi "open\|succeeded"; then
    warn "$host:123 可达 —— 不需要这个方案，请直接用 systemd-timesyncd 或 chrony"
  else
    ok "$host:123 不可达 (符合预期)"
  fi
done

echo
echo "=== 2. HTTPS 时间源连通性 ==="
SOURCES=(
  "https://www.baidu.com"
  "https://www.ntsc.ac.cn"
  "https://www.cloudflare.com"
)
REACHABLE=0
for url in "${SOURCES[@]}"; do
  HDR=$(curl -sI --max-time 6 "$url" 2>/dev/null | grep -i "^date:" | head -1 | tr -d '\r')
  if [[ -n "$HDR" ]]; then
    TS=$(echo "$HDR" | sed -E 's/^[^:]+:[[:space:]]*//')
    EPOCH=$(date -u -d "$TS" +%s 2>/dev/null || echo "")
    if [[ -n "$EPOCH" ]]; then
      ok "$url -> $TS"
      REACHABLE=$((REACHABLE + 1))
    else
      fail "$url 返回了 Date 头但解析失败: $HDR"
    fi
  else
    fail "$url 拿不到 Date 头"
  fi
done

if (( REACHABLE == 0 )); then
  fail "所有 HTTPS 源都不可达 —— 修网络再说"
  exit 1
fi
ok "至少 $REACHABLE 个 HTTPS 源可用"

echo
echo "=== 3. 当前时钟漂移估算 ==="
for url in "${SOURCES[@]}"; do
  BEFORE=$(date +%s)
  HDR=$(curl -sI --max-time 6 "$url" 2>/dev/null | grep -i "^date:" | head -1 | tr -d '\r')
  AFTER=$(date +%s)
  if [[ -n "$HDR" ]]; then
    TS=$(echo "$HDR" | sed -E 's/^[^:]+:[[:space:]]*//')
    UPSTREAM=$(date -u -d "$TS" +%s 2>/dev/null || echo 0)
    if (( UPSTREAM > 0 )); then
      LOCAL=$(date +%s)
      OFFSET=$(( UPSTREAM + (AFTER - BEFORE) / 2 - LOCAL ))
      if (( OFFSET < -2 || OFFSET > 2 )); then
        warn "本地时钟偏移约 ${OFFSET}s（源: $url）—— 部署后会自动校准"
      else
        ok "本地时钟偏移 ${OFFSET}s（源: $url）—— 在 ±2s 容差内"
      fi
      break
    fi
  fi
done

echo
echo "=== 4. 部署前置检查 ==="
command -v curl >/dev/null && ok "curl 已装" || { fail "缺 curl"; exit 1; }
command -v date >/dev/null && ok "date 可用" || { fail "缺 date"; exit 1; }
command -v hwclock >/dev/null && ok "hwclock 可用" || warn "hwclock 不可用 — RTC 不会同步，但系统时间仍会校准"
command -v logger >/dev/null && ok "logger 可用" || warn "logger 不可用 — 日志会丢失"
[ -d /run/systemd/system ] && ok "systemd 目录存在" || { fail "不是 systemd 系统，这个方案不适用"; exit 1; }

echo
if (( REACHABLE >= 1 )); then
  ok "可以部署 setclock-http"
  exit 0
else
  fail "前置条件不满足"
  exit 1
fi
