# KeyPop 按键泡泡

给幼儿拍键盘玩的 macOS 原生 App：每个按键都会在屏幕上触发特效，并发出不同的声音。

## 构建运行

依赖 Xcode 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
./scripts/build.sh --open
```

产物在 `build/KeyPop.app`，可以拖进「应用程序」文件夹。工程文件由 `project.yml` 生成，不入库。

## 玩法

| 按键 | 画面 | 声音 |
| --- | --- | --- |
| 字母 | 立体大字母 + 对应的小动物/物品（A 苹果、B 小熊…） | 按键位从左到右、从下到上逐渐升高的五声音阶 |
| 数字 | 大数字 + 对应数量的小东西，可以数数 | 一个一个冒出来，每个一个音 |
| 空格 | 全屏大秀（烟花齐放 / 泡泡潮 / 彩纸炮 / 流星雨） | 和弦 + 低音 |
| 回车 | emoji 雨 | 上行琶音 |
| 方向键 | 火箭 / 降落伞 / 小鱼 / 小鸟带着拖尾飞过 | 上下行音阶 |
| 退格 | 旋涡把光点吸走 | 下行三音 |
| 其它键（含修饰键、F 键、媒体键） | 每个键固定的 emoji | 每个键固定的音 |
| 鼠标 | 星光拖尾、点击爆炸 | 啵 |

## 设置

- **特效主题**：烟花、泡泡、彩纸、星光
- **音效包**：木琴、八音盒、竖琴、游戏机、卡通（全部实时合成，没有音频素材）
- **朗读**：按字母读出“A，苹果”或“A. Apple”，数字读出数字
- 音量、显示大字母、背景星光、鼠标特效

## 锁定键盘

开启「锁定键盘」并在 **系统设置 → 隐私与安全性 → 辅助功能** 里允许 KeyPop 后，App 会在系统层面接管所有按键：Raycast / Spotlight 等全局快捷键、⌘Tab、⌘Q、⌘,、亮度音量等媒体键都不会再把孩子带出去。同时隐藏 Dock 和菜单栏、禁用强制退出。

没有授权时只能拦住 App 内的快捷键（⌘Q、⌘, 等）和 ⌘Tab。

**家长退出**（两种都要按住约 1.5 秒，防止孩子误触）：

- 动一下鼠标，左上角会出现「按住退出」按钮，按住它；鼠标静止 2 秒后按钮自动隐藏
- 或按住 ⌃ Control + ⌥ Option + ⌘ Command，再按住 E

## 开发

- `./scripts/fetch-emoji.sh`：按 `scripts/emoji.txt` 下载 Fluent Emoji 的矢量 SVG 并渲染成 640px PNG
- `./scripts/make-icon.sh`：重新生成 App 图标
- `KeyPop --demo [fireworks|bubbles|confetti|starlight] [键码...]`：在普通窗口里自动按键，方便截图调画面
- `KeyPop --play`：启动后直接进入游戏

`web/` 是最早的网页版，已不再维护。

## 素材

Emoji 来自 [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)，MIT 协议。
