#!/usr/bin/env bash
# =====================================================================
#  COLMO 中控屏 —— 无线调试配对 + 持久化 5555 端口
#
#  用法: ./adb_pair.sh <配对IP:端口> <6位配对码> [连接IP:端口]
#    例: ./adb_pair.sh 192.168.1.100:37000 123456 192.168.1.100:5555
#
#  说明：
#    - COLMO 屏（Android 11）走「无线调试」配对，配对码在屏幕上的
#      「开发者选项 > 无线调试」里查看。
#    - 配对成功后，把 5555 端口持久化到 persist 属性，重启也能连。
#    - 若设备未 root，setprop 会失败，但不影响本次连接。
# =====================================================================
set -e
cd "$(dirname "$0")"

# 改成你本机 adb 的路径，或把 adb 加入 PATH 后直接写 "adb"
ADB="${ADB:-adb}"

PAIR_ADDR="$1"; CODE="$2"; CONN_ADDR="${3:-}"

if [ -z "$PAIR_ADDR" ] || [ -z "$CODE" ]; then
  echo "用法: $0 <配对IP:端口> <配对码> [连接IP:端口]"
  exit 1
fi
if [ -z "$CONN_ADDR" ]; then
  CONN_ADDR="${PAIR_ADDR%:*}:5555"
fi

echo "== 1/4 配对 $PAIR_ADDR (code=$CODE) =="
"$ADB" pair "$PAIR_ADDR" "$CODE" || true

echo "== 2/4 连接 $CONN_ADDR =="
"$ADB" connect "$CONN_ADDR" || true
sleep 2
"$ADB" devices

echo "== 3/4 持久化 5555 端口 =="
"$ADB" shell setprop persist.adb.tcp.port 5555 || echo "(setprop 失败，设备可能需要 root)"
"$ADB" shell getprop persist.adb.tcp.port

echo "== 4/4 顺带开 5555 内存端口 =="
"$ADB" tcpip 5555 || true
sleep 2
"$ADB" connect "$CONN_ADDR" || true
"$ADB" devices
echo "完成"
