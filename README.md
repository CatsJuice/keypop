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

## 发布与自动更新

App 内置 [Sparkle](https://sparkle-project.org) 自动更新：每天在后台检查一次 `appcast.xml`（孩子在玩时不检查、不弹窗），设置页底部和 App 菜单里也能手动「检查更新」。

发布流程全部在 GitHub Actions 里完成（`.github/workflows/release.yml`）：构建（Hardened Runtime + Developer ID 签名）→ 公证并装订 App → 制作 DMG 并签名、公证 → Sparkle 签名 → 把新版本写进 `appcast.xml` → 打 tag → 创建 GitHub Release 并上传 DMG。另外每次推送都会跑一遍构建检查（`build.yml`）。

### 一次性配置仓库 Secrets

1. 在「钥匙串访问」里把 *Developer ID Application* 证书（连同私钥）导出成 `.p12`，设一个密码
2. 准备好 App Store Connect API 密钥的 Issuer ID（App Store Connect →「用户和访问」→「集成」页面顶部），`.p8` 文件默认从 `~/.appstoreconnect/private_keys/` 读取
3. 运行脚本，按提示操作，它会校验后用 `gh secret set` 写进仓库：

   ```bash
   ./scripts/setup-ci-secrets.sh
   ```

Sparkle 更新签名私钥存在本机登录钥匙串（账户 `keypop`），脚本会自动导出上传。**私钥务必另外备份**，丢了以后旧版本就再也收不到更新：

```bash
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account keypop -x keypop-sparkle-private.key
```

### 发布新版本

GitHub → Actions → Release → Run workflow，填版本号和更新说明（多条用分号分隔）。或者命令行：

```bash
gh workflow run release.yml -f version=1.1.0 -f notes="新增了 xxx；修复了 yyy"
```

本地也能用同一个脚本发布或试打包：`DRY_RUN=1 SKIP_NOTARIZE=1 ./scripts/release.sh 1.1.0`（只在 `build/release/` 里打包，不推送）。

## 素材

Emoji 来自 [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji)，MIT 协议。
