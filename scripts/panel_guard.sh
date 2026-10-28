#!/system/bin/sh
# =====================================================================
#  COLMO 中控屏 —— 常驻守护（watchdog）
#
#  职责：每 10 秒检查 panel_auto.sh（雷达+调光一体化）与 sbc_sensor.sh
#        （板载传感器上报）是否存活，死了就拉起。
#        设备只有 2GB 内存，LMK 随时可能回收后台进程，没有守护不可靠。
#
#  ★★ 进程匹配必须用 list_pid()，不要用 ps | grep "[$N].sh"：
#     "$N" 展开后变成 [panel_auto].sh，方括号被当作「字符类」而非取巧写法，
#     实际匹配的是任一类内字符 + 任意字符 + "sh"，于是内核线程 [kdmflush]
#     里的 "lush" 会被误判命中 → 实测导致脚本把自己所在进程树全杀掉。
#
#  日志：/data/local/tmp/panel_guard.log
# =====================================================================

DIR=/data/local/tmp
LOG=$DIR/panel_guard.log

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; }

# list_pid <脚本名>：单次 ps + awk，要求 $2=="sh" 且 $3 匹配 "<名>\.sh$"
list_pid() {
  ps -A -o PID,ARGS 2>/dev/null | awk -v n="$1" '
    BEGIN { pat = n "\\.sh$" }
    $2 == "sh" && $3 ~ pat { print $1 }
  '
}

start_one() {
  S=$1
  nohup sh $DIR/$S </dev/null >>$DIR/${S%.*}.log 2>&1 &
  sleep 3
  for P in $(list_pid ${S%.*}); do
    echo -1000 > /proc/$P/oom_score_adj 2>/dev/null
  done
}

log "=== 常驻守护启动（监管 panel_auto.sh / sbc_sensor.sh）==="

while true; do
  if [ -z "$(list_pid panel_auto)" ]; then
    log "panel_auto 已死 → 拉起"
    start_one panel_auto.sh
  fi
  if [ -z "$(list_pid sbc_sensor)" ]; then
    log "sbc_sensor 已死 → 拉起"
    start_one sbc_sensor.sh
  fi
  sleep 10
done
