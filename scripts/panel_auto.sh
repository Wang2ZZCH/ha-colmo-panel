#!/system/bin/sh
# =====================================================================
#  COLMO 中控屏 —— 一体化自动管家：雷达人感 + 三档调光
#
#  ★ 为什么必须「一体化」而不是拆成两段轮询（用户实测：拆开黑屏到亮屏要 5 秒+）：
#    旧架构是「radar_wake 检测后写时间戳文件 → saver_dim 轮询该文件」，延迟逐层叠加：
#      · radar：dd 读 60 字节 @85B/s ≈ 0.7~1.2s，再 sleep 1 → 检测周期 ~2s
#      · saver：每轮 2 次 dumpsys + 1 次 date + sleep 3 → 调光周期 ~3.3s
#    最坏 ≈ 5.3s。合并后单循环 ≈ 0.3s，「检测到人」与「提亮」在同一循环内完成。
#
#  ★ 让亮屏「肉眼即时」的三个关键：
#    1) 提亮先写硬件背光 /sys/class/backlight/.../brightness（~22ms，Write 即生效），
#       再补 settings put（~79ms）——顺序反了会白等多近 0.1s。
#    2) 热循环不调用外部 date（每次 51ms）→ 改用 mksh 内置的 $SECONDS 计时。
#    3) dumpsys power 是热循环里最贵的调用，节流为每 DUMPSYS_EVERY 轮一次。
#
#  ★ 关于「光线感应」（已彻底排查，勿重复找）：
#    本机光感硬件不可用 —— android.sensor.light 事件停在虚拟值且早已停更；
#    I2C 光感芯片无应答(空焊)；daylight-sic433 只有空的 input 节点；
#    HA 侧也没有任何 illuminance 实体。
#    → 改用 HA 的 sun.sun（日出日落）作为环境明暗代理，白天/夜间两档，随季节自动变化；
#      查不到网络时降级为本地时段判断（07:00-21:00 算白天）。
#
#  策略（可按需改参数）：
#    有人操作        → 正常亮度（白天 DAY_LEVEL / 夜间 NIGHT_LEVEL）
#    无人 60s        → 微暗 20
#    再无人到 180s   → 纯黑 0（必须写硬件背光，settings 的 0 会被钳到 10）
#    纯黑 + 有人     → 立即亮到 20（夜里不刺眼）
#    微暗 + 手动操作 → 回到正常亮度
#
#  日志：/data/local/tmp/panel_auto.log
# =====================================================================

# ========== 按你的环境修改这里 ==========
EV=/dev/ttyACM0                          # USB 毫米波雷达串口（人感真源）
BL=/sys/class/backlight/backlight/brightness   # 硬件背光节点
LOG=/data/local/tmp/panel_auto.log
HA_HOST=192.168.1.100                    # ← 改成你的 HA 地址
HA_PORT=8123
TOKEN_F=/data/local/tmp/.ha_token        # HA 长期令牌文件（先 adb push 进去）
SUN_CACHE=/data/local/tmp/.sun_state
SUN_TTL=600          # 日出日落查询结果缓存 10 分钟
# ========================================

DAY_LEVEL=160        # 白天（地平线以上）正常亮度
NIGHT_LEVEL=90       # 夜间正常亮度
DIM=20               # 微暗档
DIM_AFTER=60         # 无人多少秒 → 微暗
DARK_AFTER=180       # 无人多少秒 → 纯黑
ACTIVE_IDLE=5        # idle 小于此值视为"正在操作"
PRESENT_GRACE=12     # 雷达最后报"有人"后宽限多少秒仍算在场

CHUNK=15             # 雷达单次采样字节数（15B ≈ 0.18s @85B/s，约 1 帧）
GRACE_LOOPS=35       # 连续多少次采样无人才判定离场（≈12s）
DUMPSYS_EVERY=3      # 每几轮做一次 dumpsys power（节流降 CPU）
MODECHECK_EVERY=60   # 每多少轮复查一次「自动亮度」开关是否被打开（约 25 秒）

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> $LOG; }

# 白天/夜间：优先问 HA 的 sun.sun，失败降级到本地时段
sun_state() {
  NOW=$(date +%s)
  if [ -f "$SUN_CACHE" ]; then
    read TS ST < "$SUN_CACHE" 2>/dev/null
    if [ -n "$ST" ] && [ $((NOW - TS)) -lt "$SUN_TTL" ]; then
      echo "$ST"; return
    fi
  fi
  R=""
  if [ -f "$TOKEN_F" ]; then
    TOK=$(tr -d '\r\n' < "$TOKEN_F" 2>/dev/null)
    R=$(printf 'GET /api/states/sun.sun HTTP/1.0\r\nHost: %s\r\nAuthorization: Bearer %s\r\n\r\n' \
        "$HA_HOST" "$TOK" | busybox nc -w 4 $HA_HOST $HA_PORT 2>/dev/null \
        | sed -n 's/.*"state":"\([a-z_]*\)".*/\1/p' | head -1)
  fi
  if [ -z "$R" ]; then
    H=$((10#$(date +%H)))
    if [ "$H" -ge 7 ] && [ "$H" -lt 21 ]; then R=above_horizon; else R=below_horizon; fi
    log "sun.sun 查询失败，降级时段判定 → $R"
  fi
  echo "$NOW $R" > "$SUN_CACHE"
  echo "$R"
}

level_now() {
  if [ "$(sun_state)" = "above_horizon" ]; then echo $DAY_LEVEL; else echo $NIGHT_LEVEL; fi
}

# ★ 先写硬件背光（肉眼即时），再同步 settings（保持一致但慢）
apply() {
  echo $1 > $BL 2>/dev/null
  settings put system screen_brightness $1 >/dev/null 2>&1
}

# ---- 启动稳态设置：手动亮度模式 + 永不真熄屏 ----
settings put system screen_brightness_mode 0 >/dev/null 2>&1
settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
svc power stayon true >/dev/null 2>&1

# ---- 初始状态推断（脚本重启不丢上下文）----
CUR_BL=$(cat $BL 2>/dev/null)
CUR_SET=$(settings get system screen_brightness 2>/dev/null)
if [ "$CUR_BL" = "0" ]; then cur=dark
elif [ "$CUR_SET" -le 25 ] 2>/dev/null; then cur=dim
else cur=normal; fi

log "=== 一体化管家启动 === 初始=$cur (DAY=$DAY_LEVEL NIGHT=$NIGHT_LEVEL DIM=$DIM@${DIM_AFTER}s DARK@${DARK_AFTER}s CHUNK=$CHUNK) ==="

SECONDS=0
pres=0
last_pres=0
mtick=0
# ★ 必须让第一轮就做 dumpsys：否则 IMS 还是 0，会把 S 算成 ~0 秒，
#   被当成「用户正在操作」→ 启动时先闪一下正常亮度再跳回纯黑。
tick=$DUMPSYS_EVERY
IMS=0
IMS_AT=0
W=Awake

while true; do

  # ---------- 1. 雷达采样 ----------
  # ★ 必须逐字节精确匹配（od -w1 每行一个字节），不能对拼接串做 grep，
  #   否则 "d0"+"1x" 相邻会拼出 "01" 造成误判。
  HIT=$(timeout 4 dd if=$EV bs=1 count=$CHUNK 2>/dev/null | od -An -tx1 -w1 | tr -d ' ' | grep -cx '01')
  if [ -n "$HIT" ] && [ "$HIT" -gt 0 ] 2>/dev/null; then
    if [ "$pres" = 0 ]; then
      pres=1
      log "雷达：检测到人"
    fi
    last_pres=$SECONDS
  else
    if [ "$pres" = 1 ] && [ $((SECONDS - last_pres)) -ge "$PRESENT_GRACE" ]; then
      pres=0
      log "雷达：人已离开"
    fi
  fi

  # ---------- 2. 电源状态（节流：每 DUMPSYS_EVERY 轮一次）----------
  tick=$((tick + 1))
  if [ "$tick" -ge "$DUMPSYS_EVERY" ]; then
    tick=0
    PWR=$(dumpsys power 2>/dev/null | grep -E 'mWakefulness=|mLastUserActivityTime=' | tr -d '\r')
    W=$(printf '%s\n' "$PWR" | sed -n 's/^.*mWakefulness=\([A-Za-z]*\).*/\1/p' | head -1)
    I=$(printf '%s\n' "$PWR" | sed -n 's/^.*mLastUserActivityTime=[0-9]* (\([0-9]*\) ms ago).*/\1/p' | head -1)
    if [ -n "$I" ]; then IMS=$I; IMS_AT=$SECONDS; fi
    [ -z "$W" ] && W=Awake
  fi
  S=$(( IMS/1000 + SECONDS - IMS_AT ))

  # ---------- 3. 守住「手动亮度」模式 ----------
  # 系统的「自动调节屏幕亮度」开关依赖光感，而本机无光照硬件（见顶部说明）。
  # 打开后系统只认最后一次缓存值并据此回写背光，会把纯黑重新点亮。
  # 用户可能在设置里手动打开它，这里定期复位为手动模式。
  mtick=$((mtick + 1))
  if [ "$mtick" -ge "$MODECHECK_EVERY" ]; then
    mtick=0
    M=$(settings get system screen_brightness_mode 2>/dev/null)
    if [ "$M" != "0" ]; then
      settings put system screen_brightness_mode 0 >/dev/null 2>&1
      log "「自动亮度」被开启($M) → 已复位为手动（本机无光照硬件，开着会冲掉纯黑）"
    fi
  fi

  # ---------- 4. 意外熄屏 → 拉回 HA ----------
  # ★ 把包名换成你装的 HA Companion 变体（本机无 GMS，用 minimal 版）
  if [ "$W" != "Awake" ]; then
    am start -a android.intent.action.VIEW \
       -d "homeassistant://navigate/zhong-kong" \
       io.homeassistant.companion.android.minimal >/dev/null 2>&1
    apply $(level_now)
    input keyevent 224 >/dev/null 2>&1
    log "非 Awake($W) → 唤醒回 HA"
    cur=normal
    W=Awake
    IMS=0; IMS_AT=$SECONDS
    sleep 2
    continue
  fi

  # ---------- 5. 状态机（带滞回，避免雷达在场时来回抖动）----------
  next=$cur
  case $cur in
    normal)
      [ "$S" -ge "$DIM_AFTER" ] && next=dim
      ;;
    dim)
      if   [ "$S" -lt "$ACTIVE_IDLE" ]; then next=normal
      elif [ "$S" -ge "$DARK_AFTER" ] && [ "$pres" = 0 ]; then next=dark
      fi
      ;;
    dark)
      if   [ "$S" -lt "$ACTIVE_IDLE" ]; then next=normal
      elif [ "$pres" = 1 ]; then next=dim
      fi
      ;;
  esac

  if [ "$next" != "$cur" ]; then
    case $next in
      normal) LV=$(level_now); apply $LV; log "空闲${S}s 在场=$pres → $cur ⇒ 正常($LV)";;
      dim)                     apply $DIM; log "空闲${S}s 在场=$pres → $cur ⇒ 微暗($DIM)";;
      dark)                    apply 0;    log "空闲${S}s 在场=$pres → $cur ⇒ 纯黑(硬件背光0)";;
    esac
    cur=$next
  else
    # 纯黑档兜底：防止系统把背光写回来
    if [ "$cur" = dark ] && [ "$(cat $BL 2>/dev/null)" != "0" ]; then
      echo 0 > $BL 2>/dev/null
    fi
  fi

done
