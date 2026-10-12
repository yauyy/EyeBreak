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

1. 点菜单栏的番茄仔 →「开始」，进入专注倒计时（默认 20 分钟）
2. 时间到：播放提示音，鼠标所在屏幕的右上角弹出**常驻提醒面板**；番茄计时暂停，**不会重复提醒**
3. 点「开始休息」，跟着番茄仔做护眼小动作（默认 20 秒）：看看远处、眨眨眼、闭眼放松、转转眼球，每次轮换
4. 休息结束：撒花庆祝，收集一个番茄 🍅，自动开始下一轮专注
5. 不方便马上休息可以点「5 分钟后」；也可以「跳过这次」，休息中可以「提前结束」

菜单栏的番茄仔会跟着状态换表情。菜单里能看到今天收集的番茄和连续天数。

**省心的自动处理**
- **离开电脑**：超过 5 分钟没有键鼠操作就暂停，回来后开始新一轮（离开期间眼睛已经休息过了）
- **开会时**：麦克风被会议软件占用时，到点先不提醒，会议结束再提醒
- **退出或重启**：会记住计时状态，重新打开后接着来
- **合盖睡眠**：短暂睡眠后接着计时，睡了很久则开始新一轮

**可调整的设置**：专注时长（5–180 分钟）、眺望时长（5–600 秒）、提示音（可关闭）、开机自启、自动检查更新。

**更新**：基于 [Sparkle](https://sparkle-project.org)。有新版本时，菜单顶部会出现提示，点「更新」自动下载、校验签名、安装并重启；菜单底部也可以手动「检查更新」。从 1.2 开始支持，1.1 及更早版本需要手动安装一次 1.2。

系统开了「减少动态效果」时，撒花和番茄仔的动作会自动关闭。

- Swift + SwiftUI + AppKit，原生 `MenuBarExtra`，不显示 Dock 图标
- 支持 macOS 13.0 及以上
- 无账户、无埋点；开启 App Sandbox，不申请任何与提醒无关的权限
- 唯一的联网行为是更新：每天最多一次读取 GitHub 上的更新源 `appcast.xml`，有新版本且你同意时下载安装包，不上传任何数据；在设置里关闭「自动检查更新」后不会主动联网

## 一、用 Xcode 运行（推荐新手）

1. 双击打开 `EyeBreak.xcodeproj`
2. 顶部工具栏 Scheme 选 **EyeBreak**，目标选 **My Mac**
3. 按 `⌘R` 运行
4. 屏幕右上角菜单栏出现番茄仔图标（Dock 里不会出现图标，这是正常的）
5. 点击菜单栏的番茄仔 → 点「开始」

> 签名：工程使用「Sign to Run Locally」（本地临时签名），不需要 Apple 开发者账号。

### 快速测试提醒流程（10 秒间隔）

正式默认值是 20 分钟，测试时等 20 分钟太久：

1. Xcode 菜单 **Product → Scheme → Edit Scheme…**（`⌘<`）
2. 左侧选 **Run** → 顶部 **Arguments** 标签
3. 勾选已预置的 `-EyeBreakTestInterval 10`
4. `⌘R` 运行，面板里会出现橙色「测试模式：专注 10 秒」

其他 Debug 参数（只在 Debug 构建中生效）：

| 参数 | 作用 |
|---|---|
| `-EyeBreakAutoStart YES` | 启动后自动开始计时，不用手动点「开始」 |
| `-EyeBreakTestAway 10` | 把「离开电脑」的判定时间从 5 分钟缩短为 10 秒 |
| `-EyeBreakTestFeedURL http://127.0.0.1:8766/appcast.xml` | 改用本地更新源，用来测试自动更新 |

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

### 发布新版本

发布用的签名私钥由 Sparkle 的 `generate_keys` 生成，保存在发布者 Mac 的钥匙串里（请另外备份），对应的公钥写在构建设置 `SPARKLE_PUBLIC_KEY` 里。

1. 在 Xcode 里修改 `MARKETING_VERSION`（Target → General → Version）；构建号由打包脚本按 git 提交数自动生成
2. 把更新说明写进 `docs/release-notes/<版本号>.md`，它会显示在 App 内的更新窗口里
3. 打包，生成 DMG 和签好名的更新源 `dist/appcast.xml`（会从钥匙串读取私钥，可能弹出授权）：

```bash
./scripts/package.sh
```

4. 创建 Release，**同时上传 DMG 和 appcast.xml**。App 读取的更新源地址是 `releases/latest/download/appcast.xml`，永远指向最新一个 Release 里的这个文件：

```bash
gh release create v1.3 dist/EyeBreak-1.3.dmg dist/appcast.xml --title "EyeBreak 1.3" --notes-file docs/release-notes/1.3.md
```

## 三、项目结构

```
EyeBreak/
├── EyeBreakApp.swift          应用入口、MenuBarExtra、AppDelegate（生命周期）
├── EyeBreakModel.swift        状态机：专注 → 等待休息 → 休息 → 专注，含暂停、离开、会议推迟、
│                              稍后提醒、睡眠唤醒、状态保存与恢复、防重复触发
├── EyeBreakConfig.swift       设置与状态的读写（含 Debug 测试参数）
├── BreakPanel.swift           常驻提醒悬浮面板：提醒 / 休息倒计时 / 庆祝
├── MenuContentView.swift      菜单栏弹出面板与设置
├── Theme.swift                Q 版配色、圆体字、圆角规范、胶囊按钮、圆环、开关等界面组件
├── TomatoCharacter.swift      SwiftUI 绘制的会动的番茄仔
├── RestExercise.swift         轮换的护眼小动作
├── TomatoStats.swift          番茄收集：每日数量与连续天数
├── ReminderSounds.swift       提示音与可选音效
├── SystemIdle.swift           读取键鼠空闲时间（判断是否离开）
├── MeetingDetector.swift      读取麦克风是否被占用（判断是否开会）
├── LaunchAtLogin.swift        开机自启（SMAppService）
├── AppUpdater.swift           自动更新（Sparkle）：后台检查、菜单提示、下载安装
├── ConfettiView.swift         撒花动画（SwiftUI Canvas + TimelineView）
└── Assets.xcassets            应用图标、番茄仔角色图、菜单栏表情图标
EyeBreakTests/
├── EyeBreakModelTests.swift   计时状态机单元测试（注入假时钟、空闲时间、会议状态，毫秒级跑完）
├── TomatoStatsTests.swift     番茄收集统计
└── ReminderSoundsTests.swift  提示音设置
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
- **防重复提醒**：专注到点时先切到「等待休息」并清掉截止时间，再投递提醒；用户不操作就一直停在这个状态，同一个提醒不会反复触发。
- **离开与会议**：空闲时间用 `CGEventSource` 读取，会议用 CoreAudio 的「设备是否在别处运行」判断，都只读系统状态，不需要辅助功能、麦克风等权限。摄像头不检测，因为沙盒里读取摄像头状态需要声明摄像头权限。
- **圆角规范**：数值对齐 macOS 原生界面（按钮 8、小控件 6、设置卡片 12、提醒面板 20），统一使用 continuous 超椭圆曲线；控件贴着容器边角时保持同心（面板 20 = 按钮 8 + 边距 12），见 `Theme.Radius`。
- **常驻提醒**：系统通知横幅会自动收起，App 无法强制它常驻，所以用一个不抢焦点的悬浮面板（`NSPanel`，在所有桌面和全屏应用上方都能看到）代替系统通知，直到用户操作才会消失。也因此 App 不需要申请通知权限。
- **睡眠/唤醒**：监听 `NSWorkspace.willSleepNotification` / `didWakeNotification`。专注中短暂睡眠 → 唤醒后从原处继续；睡眠超过 5 分钟 → 算作休息，开始新一轮；已暂停 → 唤醒后仍暂停。
- **计时与界面解耦**：模型由 `AppDelegate` 持有，关闭面板不影响计时。

## 四、验收对照（PRD 第 8 节，TC-07 已按新流程调整）

| 编号 | 场景 | 验证方式 |
|---|---|---|
| TC-01 | 菜单栏出现入口 | 手动 |
| TC-02 ~ TC-06 | 开始/递减/暂停/继续/重置 | 单元测试 + 手动 |
| TC-07 | 到时一次提示音和常驻面板，不点开始休息不会重复提醒 | 单元测试 + 手动（10 秒测试间隔） |
| 新增 | 开始休息 → 倒计时 → 撒花 → 自动下一轮；跳过 / 提前结束；自定义时长 | 单元测试 + 手动 |
| TC-08 | 不依赖通知权限 | 已改为悬浮面板提醒，无需授权 |
| TC-09 | 关闭面板后继续计时 | 手动 |
| TC-10/11 | 睡眠暂停、唤醒恢复 | 单元测试 + 手动：苹果菜单 → 睡眠 |
| TC-12 | 重复点开始不叠加 | 单元测试 |
| TC-13 | 退出后不再提醒 | 单元测试 + 手动 |
| TC-14 | 提醒失败不影响计时 | 提示音播放失败时退回系统提示音，不阻断流程 |

查看运行日志（睡眠、唤醒、提醒触发）：

```bash
log stream --predicate 'subsystem == "EyeBreak"' --level info
```

## 五、常见问题

- **菜单栏找不到图标**：菜单栏图标太多时会被刘海或其他图标挤掉，可以按住 `⌘` 拖动整理图标，或退出几个其他菜单栏应用。
- **到点没看到提醒面板**：面板出现在鼠标所在屏幕的右上角。如果正在开会（麦克风被占用），提醒会等会议结束再出现。
- **开机自启没生效**：如果菜单里提示「需要在系统设置里允许」，点「去设置」，在「通用 → 登录项」里打开 EyeBreak。建议先把 App 放进「应用程序」文件夹再开启。
- **想换 Bundle ID**：在 Xcode 的 Target → Signing & Capabilities 中修改（当前为 `com.yau.EyeBreak`）。修改后系统会视为新应用，之前保存的时长设置不会带过去。
