#!/bin/bash
# setclock-http — 通过 HTTPS Date 头校正本机时间
# 适用于 NTP UDP/123 被防火墙封禁、只能访问特定白名单 CDN 的环境
# 主源: https://www.baidu.com
#
# 退出码:
#   0  同步成功（含偏差过小不需要调整的情况）
#   1  同步失败（已记录日志）

set -u

LOG_TAG="setclock-http"
LOCK="/var/lock/setclock-http.lock"
MAX_OFFSET_SEC=3600   # 偏差超过 1 小时拒绝自动设置（防止上游被劫持/异常）
MIN_INTERVAL=10       # 两次同步之间最少间隔 10 秒

mkdir -p /var/log
exec 9>"$LOCK"
flock -n 9 || { logger -t "$LOG_TAG" "另一实例正在运行,跳过"; exit 0; }

# 上次同步时间戳
LAST_FILE="/var/lib/misc/setclock-http.last"
mkdir -p "$(dirname "$LAST_FILE")" 2>/dev/null || true
NOW=$(date +%s)
if [[ -f "$LAST_FILE" ]]; then
  LAST=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
  if (( NOW - LAST < MIN_INTERVAL )); then
    exit 0
  fi
fi

# 当前本地时间（用于估算请求往返延迟）
LOCAL_BEFORE=$(date +%s)

# 时间源,按顺序尝试
declare -a SOURCES=(
  "https://www.baidu.com"
  "https://www.ntsc.ac.cn"
)
declare -a FALLBACK=(
  "http://www.ntsc.ac.cn"
)

GOT_TIME=""
SOURCE_USED=""

for url in "${SOURCES[@]}" "${FALLBACK[@]}"; do
  HDR=$(curl -sI --max-time 6 "$url" 2>/dev/null | grep -i "^date:" | head -1 | tr -d '\r')
  if [[ -n "$HDR" ]]; then
    TS=$(echo "$HDR" | sed -E 's/^[^:]+:[[:space:]]*//')
    EPOCH=$(date -u -d "$TS" +%s 2>/dev/null)
    if [[ -n "$EPOCH" && "$EPOCH" =~ ^[0-9]+$ ]]; then
      GOT_TIME=$EPOCH
      SOURCE_USED=$url
      break
    fi
  fi
done

if [[ -z "$GOT_TIME" ]]; then
  logger -t "$LOG_TAG" "ERROR 所有时间源均不可达"
  exit 1
fi

LOCAL_AFTER=$(date +%s)
RTT=$(( LOCAL_AFTER - LOCAL_BEFORE ))
SERVER_NOW=$(( GOT_TIME + RTT / 2 ))
LOCAL_NOW=$(date +%s)
OFFSET=$(( SERVER_NOW - LOCAL_NOW ))

# 偏差过大:拒绝
if (( OFFSET < -MAX_OFFSET_SEC || OFFSET > MAX_OFFSET_SEC )); then
  logger -t "$LOG_TAG" "ALERT 偏差 ${OFFSET}s 超过 ${MAX_OFFSET_SEC}s 阈值,拒绝同步 (源=$SOURCE_USED)"
  exit 1
fi

# 偏差小:记日志,不写硬件时钟
if (( OFFSET >= -2 && OFFSET <= 2 )); then
  logger -t "$LOG_TAG" "OK 偏差 ${OFFSET}s,无需调整 (源=$SOURCE_USED)"
  echo "$NOW" > "$LAST_FILE"
  exit 0
fi

# 调整本地时间
if date -u -s "@$SERVER_NOW" 2>/dev/null; then
  logger -t "$LOG_TAG" "FIX 调整 ${OFFSET}s (源=$SOURCE_USED,新时间=$(date -u -d "@$SERVER_NOW" '+%F %T'))"
  hwclock -w 2>/dev/null
  echo "$NOW" > "$LAST_FILE"
  exit 0
else
  logger -t "$LOG_TAG" "ERROR date 命令失败"
  exit 1
fi
