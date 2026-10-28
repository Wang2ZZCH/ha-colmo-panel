# 进阶调优：弹窗放大、默认面板、主题

这部分是让 COLMO 条屏（1920×720）上的 HA 面板「好用」的关键细节，都是作者实测踩过的坑。

## 1. 弹窗（more-info）放大

条屏分辨率高但物理尺寸小，HA 默认的 `more-info` 弹窗会显得偏小、按钮难按。需要通过自定义 CSS 资源放大。

### 关键 CSS 变量

| 变量 | 作用 | 建议值 |
|------|------|--------|
| `--ha-dialog-width-md` | 弹窗宽度（**注意没有 `--ha-dialog-width`，别写错**） | 760px |
| `--ha-icon-button-size` | 图标按钮尺寸 | 88px |
| `--control-slider-thickness` | 滑杆粗细 | 72px |
| `--ha-favorite-color-button-size` | 收藏颜色按钮 | 72px |
| `--ha-animation-duration-*` | 动画时长 | 1ms（禁动画） |

### 坑：ha-control-button 的 CSS 变量无效

`ha-control-button` 的 `:host` 里把按钮尺寸**硬编码成 40px**，你写任何 CSS 变量都不生效。必须用 JS 遍历 shadow root 写 inline style：

```js
// 放在自定义资源里，遍历所有 ha-control-button 改大小
const btn = el.shadowRoot.querySelector('mwc-icon-button');
if (btn) btn.style.width = '88px';
```

### 禁动画

条屏上弹窗动画会显得拖沓，建议全关：

```css
ha-dialog { animation: none; }
:root {
  --ha-animation-duration-short: 1ms;
  --ha-animation-duration-medium: 1ms;
  --ha-animation-duration-long: 1ms;
}
```

再配合系统侧三个动画缩放归零（见 `start_agents.sh`）。

## 2. 默认面板（冷启动直达中控）

HA 2026.2 起默认面板是内置的 `home`（概览），不设的话屏冷启动会掉到首页，而不是你的中控面板。

要让屏开机直接进中控，需要把「默认面板」设成你的面板的 **url_path**（不是 `lovelace-xxx`）：

- 先确认面板的 `url_path`：在「配置 > Lovelace 面板」里看你的面板，或用 `get_panels` 查。
- 服务端持久化写两层：`frontend/set_system_data` + `frontend/set_user_data`，**key 都是 `core`**，字段 `default_panel`。
- 写 system 数据时，value 是**整体覆盖**，必须带上原本的 `onboarded_version` / `date` 等字段。

> 保存后屏上要 force-stop 重开 HA Companion 验证（App 前端有配置缓存）。

## 3. 主题

- 主题改动**必须重启 HA**（`reload_core_config` 不重载 themes）。
- 面板建议用暗色主题，贴合中控屏的「黑底」视觉，也配合纯黑息屏策略。

## 4. 面板部署流程（重要顺序）

每次改底图/布局，正确顺序是：

1. `python build_panel.py` → 生成新底图 + 上传，拿到新 image id
2. 把 picture-elements 的 `image` 换成新 id
3. **同步热区坐标**（如果增删了按钮）

> ⚠️ 删/加一个按钮，同行右侧所有按钮会左/右移一个 chip 宽度。只换新底图不同步坐标，就会出现「显示」和「控制」错位——看起来按钮在，点却不对位置。

同步坐标的思路：按「去掉 left/top 和 conditions 后的 JSON 签名」把新旧 elements 配对，**只改 style.left/top**，其余一律保留。

## 5. 户型图

- 户型图直接用酷家乐等工具导出的**原图**，**别做 inpaint 擦字**（容易破坏标注、且没必要）。
- 把户型图「蓝图化」（灰度反相 + 上色）能做出好看的科技感底图，示例见 `build_panel.py` 里的 `ImageOps` 处理。
