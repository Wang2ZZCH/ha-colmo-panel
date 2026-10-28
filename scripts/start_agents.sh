#!/system/bin/sh
# =====================================================================
#  COLMO 中控屏 —— 一键拉起常驻（panel_auto / panel_guard / sbc_sensor）
#
#  用法：adb shell sh /data/local/tmp/start_agents.sh
#
#  要点：
#   1. 屏幕永不熄屏（stayon + screen_off_timeout 拉满），靠背光归零做伪黑屏，
#      这样 HA 与 WebView 始终在前台，不会被 LMK 回收 → 唤醒无需重建。
#   2. panel_auto.sh 单进程同时负责雷达采样与调光（不建议拆成两段轮询，
#      两段交接会拖慢「人走近 → 亮屏」到 5 秒以上）。
#   3. 常驻写入 oom_score_adj=-1000，禁止 LMK 杀掉（设备仅 2GB 内存）。
#   4. panel_guard 作为 watchdog，每 10 秒巡检并拉起意外死亡的常驻。
#
#  ★★ 进程匹配必须用 list_pid()，不要用 ps | grep "[$N].sh"：
#     "$N" 展开后变成 [panel_auto].sh，方括号被当作「字符类」，
#     会把内核线程 [kdmflush] 里的 "lush" 误判命中 → 误杀整条进程树。
# =====================================================================

DIR=/data/local/tmp
ADJ=-1000

# ★★ 进程匹配：单次 ps + awk 按字段取 PID。
#    不能写 ps | grep "[$N].sh"（原因见顶部注释）。
#    也不能逐个 cat /proc/<pid>/cmdline（约 400 次 fork，慢到卡死）。
#    这里要求 $2=="sh" 且 $3 正则匹配 "<名>\.sh$"，
#    adb 的一次性 shell ($3=="-c") 自然被排除。
list_pid() {
  ps -A -o PID,ARGS 2>/dev/null | awk -v n="$1" '
    BEGIN { pat = n "\\.sh$" }
    $2 == "sh" && $3 ~ pat { print $1 }
  '
}

echo "--- 清理旧进程 ---"
for N in panel_auto panel_guard; do
  for P in $(list_pid $N); do
    kill -9 $P 2>/dev/null && echo "killed $N ($P)"
  done
done
sleep 2
rm -f $DIR/.radar_present

echo "--- 防止系统熄屏（屏幕常亮，靠背光归零实现伪黑屏）---"
svc power stayon true
settings put system screen_off_timeout 2147483647
settings put secure screensaver_enabled 0
settings put secure screensaver_activate_on_sleep 0
settings put system screen_brightness_mode 0
echo "screen_off_timeout=$(settings get system screen_off_timeout)"

echo "--- 启动常驻 ---"
start_one() {
  S=$1
  nohup sh $DIR/$S </dev/null >>$DIR/${S%.*}.log 2>&1 &
  sleep 3
  for P in $(list_pid ${S%.*}); do
    echo $ADJ > /proc/$P/oom_score_adj 2>/dev/null
    echo "$S 已启动 PID=$P oom_adj=$(cat /proc/$P/oom_score_adj 2>/dev/null)"
  done
}
start_one panel_auto.sh
start_one panel_guard.sh
start_one sbc_sensor.sh

echo "--- 降低动画开销，提升面板流畅度 ---"
settings put global animator_duration_scale 0
settings put global transition_animation_scale 0
settings put global window_animation_scale 0

echo "--- 当前状态 ---"
for N in panel_auto panel_guard; do
  echo "$N: $(list_pid $N)"
done
echo "wakefulness=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=')"
echo "brightness=$(settings get system screen_brightness)"
echo "OK"
