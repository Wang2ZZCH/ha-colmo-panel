# -*- coding: utf-8 -*-
"""
COLMO 中控屏面板构建器 —— 参考实现（已脱敏）

这是一个「如何用 Python 生成 HA picture-elements 面板」的最小可运行范例。
作者实际用的脚本在此基础上扩展了户型图、房间布局等，但核心 API 与坑点完全一致。

用法：
  1. 安装依赖：pip install pillow requests
  2. 把下面的示例值（TOKEN / BASE_URL / 实体 ID / 户型图路径）换成你自己的
  3. python build_panel.py  → 生成底图 panel_base.png + elements JSON

输出：
  - panel_base.png          底图（中文标签/按钮框都画在图上）
  - panel_elements.json     picture-elements 的 elements 数组
  - panel_image.json        上传底图后 HA 返回的 image id

关键坑（务必理解，详见 README「避坑清单」）：
  1. icon_el 的 x/y 是元素「中心」，不是左上角。
  2. conditional 不会把 entity 传给子元素，子元素必须自己写 entity。
  3. 图标名写错（如 mdi:curtains-open）会静默渲染为空，不报错。
"""
import json
import os
import uuid

from PIL import Image, ImageDraw, ImageFont, ImageOps

# ============ 改成你自己的 ============
TOKEN = open('.ha_token', encoding='utf-8').read().strip()   # HA 长期令牌
BASE_URL = 'http://192.168.1.100:8123'                       # 你的 HA 地址
SRC = 'floorplan.jpg'          # 你的户型图/酷家乐原图路径
FONT_PATH = 'msyh.ttc'         # 中文字体（Windows 用 msyh.ttc）
# ======================================

# 画布尺寸（COLMO 条屏）
CW, CH = 1920, 720

# 实体 ID —— 全部改成你自己的
LIGHTS = {
    'living_ceil': 'light.living_ceiling',
    'living_strip': 'light.living_strip',
    'dining': 'light.dining_lamp',
}
INDOOR_TEMP = 'sensor.indoor_temperature'
INDOOR_HUM = 'sensor.indoor_humidity'
OUTDOOR = 'weather.forecast_home'

# 配色（暗色底）
BG = (9, 10, 12)
CARD = (22, 24, 28)
CARD_EDGE = (36, 40, 47)
INK = (232, 236, 241)
INK2 = (186, 196, 209)
INK3 = (104, 113, 126)
AMBER = (251, 191, 36)
SKY = (56, 189, 248)
GREEN = (52, 211, 153)


def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except Exception:
        return ImageFont.load_default()


ELEMS = []  # 全局收集 picture-elements 元素


def pct(x, y):
    """把像素坐标转成 picture-elements 的百分比字符串。"""
    return '%.4f%%' % (x / CW * 100), '%.4f%%' % (y / CH * 100)


def round_card(canvas, box, radius=18, fill=CARD, edge=CARD_EDGE, width=1):
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(box, radius=radius, fill=fill + (255,), outline=edge + (255,), width=width)


def icon_el(icon, x, y, size, color, entity=None, tap='toggle'):
    """★ x/y 是元素中心，不是左上角！配合 width/height 让热区覆盖整卡。"""
    left, top = pct(x, y)
    e = {
        'type': 'icon', 'icon': icon,
        'style': {
            'top': '%s%%' % top, 'left': '%s%%' % left,
            '--mdc-icon-size': '%dpx' % size,
            'color': color, 'cursor': 'pointer',
            'transform': 'translate(-50%,-50%)',  # 居中定位
        },
        'tap_action': {'action': tap},
    }
    # ★ 关键：conditional 不会把 entity 传给子元素，子元素必须自己写 entity
    if entity:
        e['entity'] = entity
    return e


def state_label(ent, x, y, size_px, color, bold=True, suffix='', attribute=None, prefix=''):
    """在底图上画一个会实时刷新的数值标签。"""
    left, top = pct(x, y)
    e = {'type': 'state-label', 'entity': ent,
         'style': {'top': '%s%%' % top, 'left': '%s%%' % left,
                   'font-size': '%dpx' % size_px,
                   'font-weight': '700' if bold else '400',
                   'color': color, 'cursor': 'pointer', 'white-space': 'nowrap'}}
    if attribute:
        e['attribute'] = attribute
    if suffix:
        e['suffix'] = suffix
    if prefix:
        e['prefix'] = prefix
    e['tap_action'] = {'action': 'more-info'}
    return e


def fallback_label(mi_ent, sbc_ent, x, y, size_px, color):
    """温湿度兜底：米家优先，unavailable/unknown 时切到板载读数。"""
    def _sl(ent):
        return state_label(ent, x, y, size_px, color)
    ELEMS.append({'type': 'conditional',
                  'conditions': [{'entity': mi_ent, 'state_not': 'unavailable'},
                                 {'entity': mi_ent, 'state_not': 'unknown'}],
                  'elements': [_sl(mi_ent)]})
    for st in ('unavailable', 'unknown'):
        ELEMS.append({'type': 'conditional',
                      'conditions': [{'entity': mi_ent, 'state': st}],
                      'elements': [_sl(sbc_ent)]})


def build():
    canvas = Image.new('RGBA', (CW, CH), BG + (255,))
    d = ImageDraw.Draw(canvas)

    # ---- 示例：左上角画一个「客厅」卡片，放两个灯按钮 ----
    round_card(canvas, (20, 20, 400, 200))
    d.text((40, 40), '客厅', font=font(20), fill=INK + (255,))

    # 两个灯按钮（中文标签直接画在底图上，热区用 icon_el 叠加）
    d.text((60, 90), '吸顶灯', font=font(14), fill=INK2 + (255,))
    ELEMS.append(icon_el('mdi:ceiling-light', 100, 150, 40, AMBER,
                         entity=LIGHTS['living_ceil']))
    d.text((220, 90), '灯带', font=font(14), fill=INK2 + (255,))
    ELEMS.append(icon_el('mdi:led-strip-variant', 260, 150, 40, AMBER,
                         entity=LIGHTS['living_strip']))

    # ---- 示例：右侧画「室内环境」卡，显示温湿度 ----
    round_card(canvas, (1400, 20, 1900, 200))
    d.text((1420, 40), '室内环境', font=font(16), fill=INK3 + (255,))
    d.text((1480, 90), '温度', font=font(13), fill=INK3 + (255,), anchor='mm')
    ELEMS.append(state_label(INDOOR_TEMP, 1480, 120, 36, AMBER, suffix='°'))
    d.text((1700, 90), '湿度', font=font(13), fill=INK3 + (255,), anchor='mm')
    ELEMS.append(state_label(INDOOR_HUM, 1700, 120, 32, SKY, suffix='%'))

    canvas.convert('RGB').save('panel_base.png')
    json.dump(ELEMS, open('panel_elements.json', 'w'), ensure_ascii=False, indent=1)
    print('已生成 panel_base.png 与 panel_elements.json，元素数', len(ELEMS))


def upload():
    """把底图传到 HA，拿到 image id，供 picture-elements 的 image 字段用。"""
    import requests
    import hashlib
    data = open('panel_base.png', 'rb').read()
    md5 = hashlib.md5(data).hexdigest()
    # HA 上传图片的 multipart 字段名是 file
    r = requests.post(
        f'{BASE_URL}/api/image/upload',
        headers={'Authorization': f'Bearer {TOKEN}'},
        files={'file': ('panel_base.png', data, 'image/png')},
        timeout=30,
    )
    r.raise_for_status()
    info = r.json()
    json.dump(info, open('panel_image.json', 'w'), ensure_ascii=False, indent=1)
    print('已上传底图，image id =', info.get('id'))
    print('在 HA 面板里把 picture-elements 的 image 设为：')
    print(f'  /api/image/serve/{info.get("id")}/original')


if __name__ == '__main__':
    build()
    upload()
