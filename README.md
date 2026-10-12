# EyeBreak 护眼番茄钟

常驻 macOS 菜单栏的护眼计时器：每专注 20 分钟，弹出提醒让你眺望远处 20 秒，休息完撒花庆祝，再自动开始下一轮。

## 下载安装

1. 到 [Releases](../../releases/latest) 下载最新的 `EyeBreak-x.x.dmg`
2. 打开 DMG，把 EyeBreak 拖进「应用程序」
3. 第一次打开：本应用没有 Apple 开发者签名和公证，macOS 会提示「无法验证开发者」。这时打开 **系统设置 → 隐私与安全性**，在页面底部找到 EyeBreak，点「仍要打开」。之后再打开就不会提示了

也可以在终端里移除下载隔离标记，效果相同：

```bash
xattr -dr com.apple.quarantine /Applications/EyeBreak.app
```

支持 macOS 13 及以上，Apple 芯片和 Intel 芯片通用。

## 使用流程

1. 点菜单栏 👁 →「开始」，进入专注倒计时（默认 20 分钟）
2. 时间到：播放提示音，右上角弹出**常驻提醒面板**，同时发送系统通知；番茄计时暂停，**不会重复提醒**
3. 点面板或通知上的「开始休息」（点通知本身也可以），进入眺望休息倒计时（默认 20 秒）
4. 休息结束：撒花动画 + 提示音，自动开始下一轮专注
5. 不想休息可以点「跳过本次」，休息中也可以「提前结束」，两者都会直接开始下一轮

专注时长（1–180 分钟）和休息时长（5–600 秒）都能在菜单面板里调整，退出后会记住。

- Swift + SwiftUI + AppKit，原生 `MenuBarExtra`，不显示 Dock 图标
- 支持 macOS 13.0 及以上
- 无网络、无账户、无埋点；开启 App Sandbox，不申请任何与提醒无关的权限

## 一、用 Xcode 运行（推荐新手）

1. 双击打开 `EyeBreak.xcodeproj`
2. 顶部工具栏 Scheme 选 **EyeBreak**，目标选 **My Mac**
3. 按 `⌘R` 运行
4. 屏幕右上角菜单栏出现 👁 眼睛图标（Dock 里不会出现图标，这是正常的）
5. 首次运行会弹出「EyeBreak 想要发送通知」，点 **允许**
6. 点击眼睛图标 → 点「开始」

> 签名：工程使用「Sign to Run Locally」（本地临时签名），不需要 Apple 开发者账号。

### 快速测试提醒流程（10 秒间隔）

正式默认值是 20 分钟，测试时等 20 分钟太久：

1. Xcode 菜单 **Product → Scheme → Edit Scheme…**（`⌘<`）
2. 左侧选 **Run** → 顶部 **Arguments** 标签
3. 勾选已预置的 `-EyeBreakTestInterval 10`
4. `⌘R` 运行，面板里会出现橙色「测试模式：专注 10 秒」

另一个 Debug 参数 `-EyeBreakAutoStart YES` 会让 App 启动后自动开始计时，不用手动点「开始」。

该参数**只在 Debug 构建中生效**，Release 构建永远是 20 分钟。测完记得取消勾选。

## 二、用命令行构建

本机如果 `xcode-select -p` 显示的是 `/Library/Developer/CommandLineTools`，需要临时指定 Xcode（或执行一次 `sudo xcode-select -s /Applications/Xcode.app` 永久切换）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

构建 Release 版：

```bash
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -configuration Release -derivedDataPath build build
```

运行：

```bash
open build/Build/Products/Release/EyeBreak.app
```

运行单元测试：

```bash
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -derivedDataPath build test
```

以 10 秒测试间隔启动 Debug 版，并自动开始计时：

```bash
open build/Build/Products/Debug/EyeBreak.app --args -EyeBreakTestInterval 10 -EyeBreakAutoStart YES
```

想长期使用，可以把 `build/Build/Products/Release/EyeBreak.app` 拖进「应用程序」文件夹。

打包发布用的 DMG（产物在 `dist/`）：

```bash
./scripts/package.sh
```

## 三、通知权限

| 状态 | 面板显示 | 行为 |
|---|---|---|
| 已允许 | 🔔 系统通知已开启 | 到时：提示音 + 横幅 |
| 尚未决定 | 尚未授权 + 「允许通知」按钮 | 到时：仅提示音 |
| 已拒绝 | 系统通知已关闭 + 「打开系统设置」 | 到时：仅提示音，计时不受影响 |
| 允许但样式为「无」 | 提醒样式为「无」 | 到时：提示音，通知只进通知中心 |

手动路径：**系统设置 → 通知 → EyeBreak → 允许通知**，提醒样式建议选「横幅」。

## 四、项目结构

```
EyeBreak/
├── EyeBreakApp.swift          应用入口、MenuBarExtra、AppDelegate（生命周期）
├── EyeBreakModel.swift        状态机：专注 → 等待休息 → 休息 → 专注，含暂停、睡眠唤醒、防重复触发
├── NotificationService.swift  通知授权、带「开始休息」按钮的通知、提示音
├── BreakPanel.swift           常驻提醒悬浮面板：提醒 / 休息倒计时 / 庆祝
├── ConfettiView.swift         撒花动画（SwiftUI Canvas + TimelineView）
├── MenuContentView.swift      菜单栏弹出面板与时长设置
├── EyeBreakConfig.swift       时长设置的读写（含 Debug 测试参数）
└── Assets.xcassets/AppIcon    应用图标（A 番茄仔，16–1024px）
EyeBreakTests/
└── EyeBreakModelTests.swift   计时逻辑单元测试（注入假时钟，毫秒级跑完）
Design/
├── icons/                     初版 SVG 图标方案（6 套，备选）
└── icons-canvas/              Q 版 Canvas 图标方案（6 套）
    ├── icons.js               所有图标的 Canvas 绘制代码
    ├── index.html             对比预览页
    └── export.html            导出页：export.html?key=A-tomato&size=128
```

### 修改应用图标

图标由 [Design/icons-canvas/icons.js](Design/icons-canvas/icons.js) 绘制。改完后：

1. 启动本地预览服务器：

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory Design
```

2. 浏览器打开 `http://127.0.0.1:8765/icons-canvas/` 查看效果
3. 用无头 Chrome 打开 `export.html?key=A-tomato&size=N`（N 取 16、32、64、128、256、512、1024），截图后替换 `EyeBreak/Assets.xcassets/AppIcon.appiconset/icon_N.png`

每个尺寸都直接按目标像素绘制，不是从大图缩小，所以 16px 的小图也比较清晰。

### 关键设计

- **基于截止时间计时**：记录「本轮几点结束」，每秒用 `截止时间 - 当前时间` 计算剩余时间，而不是每秒减 1。Timer 回调被系统延迟也不会累计误差。
- **单一计时器**：每次创建 Timer 前先销毁旧的；「开始」在已运行时直接忽略，连点不会叠加。
- **状态机**：`idle → working ⇄ paused`，专注到点进入 `awaitingBreak`，点「开始休息」进入 `resting`，休息结束回到 `working`。
- **防重复提醒**：专注到点时先切到「等待休息」并停表，再投递提醒；用户不操作就一直停在这个状态，同一个提醒不会反复触发。
- **常驻提醒**：系统通知横幅会自动收起，App 无法强制它常驻，所以另做了一个不抢焦点的悬浮面板（`NSPanel`，在所有桌面和全屏应用上方都能看到），直到用户操作才会消失。
- **睡眠/唤醒**：监听 `NSWorkspace.willSleepNotification` / `didWakeNotification`。专注中睡眠 → 暂停，唤醒后从原处继续；已暂停 → 唤醒后仍暂停；等待休息或休息中睡眠 → 睡眠算作休息，唤醒后直接开始新一轮专注（不撒花）。
- **计时与界面解耦**：模型由 `AppDelegate` 持有，关闭面板不影响计时。

## 五、验收对照（PRD 第 8 节，TC-07 已按新流程调整）

| 编号 | 场景 | 验证方式 |
|---|---|---|
| TC-01 | 菜单栏出现入口 | 手动 |
| TC-02 ~ TC-06 | 开始/递减/暂停/继续/重置 | 单元测试 + 手动 |
| TC-07 | 到时一次声音、通知和常驻面板，不点开始休息不会重复提醒 | 单元测试 + 手动（10 秒测试间隔） |
| 新增 | 开始休息 → 倒计时 → 撒花 → 自动下一轮；跳过 / 提前结束；自定义时长 | 单元测试 + 手动 |
| TC-08 | 拒绝通知后计时、提示音正常 | 手动：系统设置里关闭通知后再测 |
| TC-09 | 关闭面板后继续计时 | 手动 |
| TC-10/11 | 睡眠暂停、唤醒恢复 | 单元测试 + 手动：苹果菜单 → 睡眠 |
| TC-12 | 重复点开始不叠加 | 单元测试 |
| TC-13 | 退出后不再提醒 | 单元测试 + 手动 |
| TC-14 | 通知发送失败不崩溃 | 代码保证：错误被捕获并显示在面板上 |

查看运行日志（睡眠、唤醒、提醒触发）：

```bash
log stream --predicate 'subsystem == "EyeBreak"' --level info
```

## 六、常见问题

- **菜单栏找不到图标**：菜单栏图标太多时会被刘海或其他图标挤掉，可以按住 `⌘` 拖动整理图标，或退出几个其他菜单栏应用。
- **没有横幅只有声音**：检查「系统设置 → 通知 → EyeBreak」；同时确认没有开启「专注模式 / 勿扰」。
- **想换 Bundle ID**：在 Xcode 的 Target → Signing & Capabilities 中修改（当前为 `com.yau.EyeBreak`）。修改后系统会视为新应用，需要重新授权通知。
