#!/system/bin/sh
# =====================================================================
#  COLMO 中控屏 —— 板载空气质量传感器(sgp40)上报 HA
#
#  数据源：/sys/bus/iio/devices/iio:device1  (name=sgp40)
#    - in_concentration_input        VOC 指数 (0-500 IAQ 空气质量指标)
#    - out_temp_raw                  温度 ×1000  (28.235 -> 28235)
#    - out_humidityrelative_raw      相对湿度 ×1000 (45.947 -> 45947)
#    - in_resistance_raw             VOC 气敏电阻(算法内部用,一并上报)
#
#  上报目标：HA REST API  /api/states/<entity>   （无需 MQTT）
#     sensor.sbc_temp       中控屏板载温度   device_class=temperature
#     sensor.sbc_humidity   中控屏板载湿度   device_class=humidity
#     sensor.sbc_voc        中控屏空气质量   VOC 指数
#
#  ★ 中控屏无 curl/wget，只能用 nc (toybox netcat)：
#    printf 'POST ...\r\n...' | nc -w 5 <host> <port>
#    （busybox wget 不支持自定义 header，之前已踩过）
#
#  周期：每 60 秒一轮。由 panel_guard.sh 纳入 watchdog 守护。
#  用法：adb shell sh /data/local/tmp/sbc_sensor.sh
# =====================================================================

DIR=/data/local/tmp
LOG=$DIR/sbc_sensor.log
HOST=192.168.1.100        # ← 改成你的 HA 地址
PORT=8123
TOKEN=$(cat $DIR/.ha_token 2>/dev/null)
IIO=/sys/bus/iio/devices/iio:device1

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; }

# 读 sgp40，返回 "temp hum voc res"（纯数字）
read_sgp() {
  local t h v r
  t=$(cat $IIO/out_temp_raw 2>/dev/null)
  h=$(cat $IIO/out_humidityrelative_raw 2>/dev/null)
  v=$(cat $IIO/in_concentration_input 2>/dev/null)
  r=$(cat $IIO/in_resistance_raw 2>/dev/null)
  echo "$t $h $v $r"
}

# post <entity> <state> <json属性串(不含外层大括号)>
#   用 nc 发 HTTP POST；成功与否只看有没有回包（HA 返回 200/201）
post() {
  local ent=$1 state=$2 attrs=$3
  local body len
  if [ -n "$attrs" ]; then
    body="{\"state\":\"$state\",\"attributes\":{$attrs}}"
  else
    body="{\"state\":\"$state\"}"
  fi
  len=${#body}
  printf 'POST /api/states/%s HTTP/1.1\r\nHost: %s\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
    "$ent" "$HOST" "$TOKEN" "$len" "$body" | nc -w 5 "$HOST" "$PORT" 2>/dev/null | head -1
}

if [ -z "$TOKEN" ]; then
  log "FATAL: $DIR/.ha_token 不存在，无法鉴权"
  exit 1
fi

if [ ! -d "$IIO" ]; then
  log "FATAL: $IIO 不存在（sgp40 未挂载）"
  exit 1
fi

log "=== sbc_sensor 启动 (sgp40 -> HA) ==="

while true; do
  read t h v r <<EOF
$(read_sgp)
EOF
  # 偶发读到 999999（无效值），跳过本轮
  if [ -z "$t" ] || [ "$t" = "999999" ] || [ "$h" = "999999" ]; then
    log "skip: 无效采样 t=$t h=$h"
    sleep 60
    continue
  fi
  tC="$((t/1000)).$((t%1000))"
  hP="$((h/1000)).$((h%1000))"
  # VOC 取整（原始如 71.000000 → 71），避免面板显示 6 位小数
  vi="${v%%.*}"

  # 温湿度：保留板载读数，作为「米家温湿度计」的兜底备用（米家无数据时由 HA 侧 conditional 切换）
  r1=$(post "sensor.sbc_temp" "$tC" "\"unit_of_measurement\":\"°C\",\"device_class\":\"temperature\",\"friendly_name\":\"中控屏板载温度\"")
  r2=$(post "sensor.sbc_humidity" "$hP" "\"unit_of_measurement\":\"%\",\"device_class\":\"humidity\",\"friendly_name\":\"中控屏板载湿度\"")
  # VOC：主要上报项
  r3=$(post "sensor.sbc_voc" "$vi" "\"friendly_name\":\"中控屏空气质量\",\"unit_of_measurement\":\"VOC\"")
  r4=$(post "sensor.sbc_voc_resistance" "$r" "\"friendly_name\":\"中控屏VOC电阻\",\"unit_of_measurement\":\"Ω\"")

  log "temp=$tC hum=$hP voc=$v res=$r | $r1 / $r2 / $r3 / $r4"
  sleep 60
done
