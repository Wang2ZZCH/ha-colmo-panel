#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成通用化样例面板图（脱敏）
用途：README 里作为「最终效果」的示例截图。

- 所有房间名使用通用名称：客厅 / 餐厅 / 厨房 / 主卧 / 卧室 / 儿童房 / 卫生间
- 设备名称使用通用名称：吸顶灯 / 空调 / 窗帘 / 筒射灯 等
- 数据均为示例值，不含任何真实账号 / IP / 实体 / 温度。
- 视觉风格与真实面板一致（深色底 + 三列布局）。
"""
from PIL import Image, ImageDraw, ImageFont

CW, CH = 1920, 720
BG = (9, 10, 12)
CARD = (18, 20, 25)
CARD_EDGE = (32, 36, 43)
CHIP = (22, 25, 31)
CHIP_EDGE = (38, 42, 50)
TXT = (232, 236, 241)
SUB = (120, 130, 145)
ACCENT = {  # 每类设备的图标色
    'light': (245, 158, 11),      # 橙
    'ac': (56, 189, 248),         # 蓝
    'curtain': (125, 211, 252),   # 浅蓝
    'strip': (251, 191, 36),      # 黄
    'spot': (148, 163, 184),      # 灰
    'fan': (52, 211, 153),        # 绿
}

FR = r'C:\Windows\Fonts\msyh.ttc'
FB = r'C:\Windows\Fonts\msyhbd.ttc'

def font(size, bold=False):
    return ImageFont.truetype(FB if bold else FR, size)

img = Image.new('RGB', (CW, CH), BG)
d = ImageDraw.Draw(img)

def rrect(draw, box, radius, fill, edge=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=edge, width=width)

# ============================================================ 左列：户型图
PLAN_X, PLAN_Y = 24, 24
PLAN_W, PLAN_H = 500, 672
rrect(d, (PLAN_X, PLAN_Y, PLAN_X + PLAN_W, PLAN_Y + PLAN_H), 20, CARD, CARD_EDGE)

# 简化户型：绘制几个房间的色块 + 墙体线
# 用比卡片略浅的色块表示房间
room_fill = (26, 30, 37)
wall = (52, 58, 70)

# 户型整体外框
plan_inner = (PLAN_X + 20, PLAN_Y + 20, PLAN_X + PLAN_W - 20, PLAN_Y + PLAN_H - 20)
d.rectangle(plan_inner, outline=wall, width=2)

# 划分房间：卧室(左上) / 儿童房(左中) / 主卧(左下) / 客厅(中下) / 餐厅(中上) / 厨房(右上) / 卫生间(右中)
lx, ly = plan_inner[0], plan_inner[1]
rx, by = plan_inner[2], plan_inner[3]
mx = lx + (rx - lx) * 0.45          # 左右分界
my_top = ly + (by - ly) * 0.40      # 上/中分界
my_bot = ly + (by - ly) * 0.72      # 中/下分界

# 房间矩形（画淡色填充，便于看出分区）
rooms = [
    # (x0, y0, x1, y1, 名称, 名称位置)
    (lx, ly, mx, my_top, '主卧', (lx + (mx-lx)*0.5, ly + (my_top-ly)*0.5)),
    (lx, my_top, mx, my_bot, '儿童房', (lx + (mx-lx)*0.5, my_top + (my_bot-my_top)*0.5)),
    (lx, my_bot, mx, by, '卧室', (lx + (mx-lx)*0.5, my_bot + (by-my_bot)*0.5)),
    (mx, ly, rx, my_top, '餐厅', (mx + (rx-mx)*0.5, ly + (my_top-ly)*0.5)),
    (mx, my_top, rx, my_bot, '厨房', (mx + (rx-mx)*0.5, my_top + (my_bot-my_top)*0.5)),
    (mx, my_bot, rx, by, '客厅', (mx + (rx-mx)*0.5, my_bot + (by-my_bot)*0.5)),
]
for (x0, y0, x1, y1, name, pos) in rooms:
    d.rectangle((x0, y0, x1, y1), fill=room_fill, outline=wall, width=1)
    d.text(pos, name, font=font(22, True), fill=(205, 216, 230), anchor='mm')

# 客厅内画两个设备小圆点（示意吸顶灯/空调），放在客厅格子右下角，避开标签
d.ellipse((rx - 90, by - 80, rx - 60, by - 50), fill=ACCENT['light'], outline=None)
d.ellipse((rx - 45, by - 80, rx - 15, by - 50), fill=ACCENT['ac'], outline=None)

# ============================================================ 中列：控制区
CTRL_X0 = PLAN_X + PLAN_W + 24
CTRL_W = 880
CTRL_X1 = CTRL_X0 + CTRL_W
row_y = [24, 24 + 190, 24 + 380]
CHIP_W = 128
CHIP_H = 150
GAP = 10

# 房间分组（通用名称）
groups = [
    ('客厅', ['吸顶灯', '筒射灯', '灯带', '空调', '窗帘']),
    ('餐厅', ['吊灯', '筒射灯', '空调']),
    ('厨房', ['主灯', '凉霸']),
    ('主卧', ['主灯', '床头灯带', '空调', '窗帘']),
    ('儿童房', ['吸顶灯', '空调']),
    ('卫生间', ['浴霸', '排气扇']),
]

# 简化：只画前 3 行（每行一个分组标题 + 若干 chip）
display_rows = [('客厅', ['吸顶灯', '筒射灯', '灯带', '空调', '窗帘']),
                ('餐厅', ['吊灯', '筒射灯', '空调']),
                ('主卧', ['主灯', '床头灯带', '空调', '窗帘']),
                ('儿童房', ['吸顶灯', '空调']),
                ('情景', ['观影', '离家', '睡眠'])]

# 实际画 4 个设备分组（2 行）+ 情景行
chip_rows = [
    ('客厅', ['吸顶灯', '筒射灯', '灯带', '空调', '窗帘']),
    ('餐厅 · 厨房 · 主卧 · 儿童房', ['吊灯', '主灯', '主灯', '床头灯带', '空调']),
]
y_cursor = 24
for grp_name, items in chip_rows:
    # 分组标题
    d.text((CTRL_X0 + 2, y_cursor + 6), grp_name, font=font(22, True), fill=(232, 236, 241), anchor='lm')
    y_cursor += 44
    # chips
    x = CTRL_X0
    for i, name in enumerate(items):
        box = (x, y_cursor, x + CHIP_W, y_cursor + CHIP_H)
        rrect(d, box, 14, CHIP, CHIP_EDGE)
        cx = x + CHIP_W // 2
        # 图标圆点
        color = list(ACCENT.values())[i % len(ACCENT)]
        d.ellipse((cx - 22, y_cursor + 40, cx + 22, y_cursor + 84), fill=color)
        d.text((cx, y_cursor + CHIP_H - 28), name, font=font(19, True), fill=(222, 228, 235), anchor='mm')
        x += CHIP_W + GAP
    y_cursor += CHIP_H + 18

# 情景行
d.text((CTRL_X0 + 2, y_cursor + 6), '情景', font=font(22, True), fill=(232, 236, 241), anchor='lm')
y_cursor += 44
scene = [('观影', '#f59e0b'), ('离家', '#34d399'), ('睡眠', '#a78bfa')]
sw = 190
for name, color in scene:
    box = (CTRL_X0 + (scene.index((name, color))) * (sw + 16), y_cursor, 
           CTRL_X0 + scene.index((name, color)) * (sw + 16) + sw, y_cursor + 150)
    rrect(d, box, 16, CHIP, CHIP_EDGE)
    cx = box[0] + sw // 2
    c = tuple(int(color[i:i+2], 16) for i in (1, 3, 5))
    d.ellipse((cx - 26, y_cursor + 34, cx + 26, y_cursor + 86), fill=c)
    d.text((cx, y_cursor + 122), name, font=font(21, True), fill=(232, 236, 241), anchor='mm')

# ============================================================ 右列：信息区
IX0 = CTRL_X1 + 24
IX1 = CW - 24
icx = (IX0 + IX1) // 2
# 时间卡
rrect(d, (IX0, 24, IX1, 150), 20, CARD, CARD_EDGE)
d.text((IX0 + 22, 48), '当前时间', font=font(13), fill=SUB, anchor='lm')
d.text((icx, 95), '19:43', font=font(44), fill=(232, 236, 241), anchor='mm')
d.text((icx, 135), '10月28日 周三', font=font(15), fill=SUB, anchor='mm')

# 室外天气卡
rrect(d, (IX0, 170, IX1, 300), 20, CARD, CARD_EDGE)
d.text((IX0 + 22, 186), '室外天气', font=font(13), fill=SUB, anchor='lm')
d.text((icx, 235), '☁  阴  22°C', font=font(24, True), fill=(203, 213, 225), anchor='mm')
d.text((icx, 270), '风速 2.5 m/s', font=font(14), fill=SUB, anchor='mm')

# 室内环境卡
rrect(d, (IX0, 320, IX1, 690), 20, CARD, CARD_EDGE)
d.text((IX0 + 22, 336), '室内环境', font=font(13), fill=SUB, anchor='lm')
env_items = [
    ('温度', '23°C', (56, 189, 248)),
    ('湿度', '45%', (52, 211, 153)),
    ('新风', '212', (245, 158, 11)),
    ('CO2', '620', (52, 211, 153)),
    ('PM2.5', '10', (56, 189, 248)),
    ('VOC', '116', (52, 211, 153)),
]
# 两列排布
col_x = [IX0 + 40, icx + 20]
col_w = 110
for idx, (label, val, color) in enumerate(env_items):
    col = idx // 3
    row = idx % 3
    x = col_x[col]
    y = 380 + row * 95
    d.text((x, y), label, font=font(15), fill=SUB, anchor='lm')
    d.text((x, y + 26), val, font=font(26, True), fill=color, anchor='lm')

img.save('sample_panel.png')
print('已生成 sample_panel.png, 尺寸', img.size)
