# EyeBreak

[中文](README.md) | English

A cute tomato that reminds you to rest your eyes. EyeBreak lives in the macOS menu bar and, by default, reminds you to take a 20-second break every 20 minutes. Follow the tomato through rotating break activities: look far away, blink, close your eyes to relax, roll your eyes, sip some water, and take a walk. It then celebrates and starts the next round.

## Download

1. Download the latest `EyeBreak-x.x.dmg` from [Releases](../../releases/latest)
2. Open the DMG and drag EyeBreak into Applications
3. The app isn't signed with an Apple Developer ID, so macOS will say it can't verify the developer the first time. Open **System Settings → Privacy & Security** and click **Open Anyway** at the bottom. You only need to do this once.

You can also remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/EyeBreak.app
```

Requires macOS 13 or later. Universal app for Apple silicon and Intel.

If the GitHub Release download path returns HTTP 504, the [same signed 1.7 DMG is available from this repository's Raw channel](https://raw.githubusercontent.com/yauyy/EyeBreak/refs/heads/feature/ymy/update-channel/updates/EyeBreak-1.7.dmg). An original 1.6 installation was verified to download, validate, install and relaunch as 1.7 after an explicitly approved feed preference migration. The original Release URL has not been confirmed restored, and other existing clients are not automatically migrated. See the [verification record](docs/verification/20261108-应用内升级验收.md) and [channel instructions](README.md#发布新版本).

## How it works

1. Click the tomato in the menu bar and press **Start**. A focus round begins (20 minutes by default)
2. When time is up, a reminder panel appears on the screen you're looking at and stays until you respond. The timer pauses and you won't be nagged again
3. Press **Start break** and follow the tomato for a short break activity (20 seconds by default): look far away, blink, close your eyes, roll your eyes, sip some water, or take a walk
4. When the break ends you collect a tomato, there's a little confetti, and the next round starts
5. Not a good moment? Choose **In 5 min** or **Skip**

**It takes care of the details**
- **Away from the Mac**: after 5 minutes without keyboard or mouse input the timer pauses; a fresh round starts when you're back
- **Meetings and full screen**: while the microphone is in use or another app is full screen, the reminder waits until you're done
- **Work hours**: optionally remind only during set hours and on weekdays
- **Focus modes**: add an EyeBreak Focus filter to hold reminders during a Focus
- **Restarts**: the timer state is restored after quitting or rebooting

**Long breaks**: by default every 4th break is a 3-minute long break where the tomato asks you to get up for water or a walk; the short breaks stay eye exercises. Adjust or turn it off under Settings > Break.

**Pause for a while**: after pausing, pick "in 1 h", "in 2 h" or "tomorrow" in the menu and the timer resumes on its own.

**Routines**: open **Settings → Routines** to set a daily first reminder and add follow-up reminders at intervals. For example, 08:00, then 5 minutes later, then another 10 minutes later gives 08:00, 08:05 and 08:15. Each interval is relative to the preceding step, with every reminder anchored to the first scheduled time. Acknowledging a reminder does not delay the next one. Reminders may cross midnight but must stay strictly before the next daily first reminder; saving and scheduling both enforce this, including daylight saving changes. After adding, editing or re-enabling a routine, past times are skipped and the rest of today's reminders still fire.

Routines run independently of the eye-break timer and appear in a persistent panel at the top left, using your chosen reminder sound. Keep EyeBreak running: it cannot alert while the app is closed or your Mac is asleep. On return, it shows only the latest due reminder in the current cycle with its original scheduled time, without replaying past cycles.

**Also included**: today's tomatoes, a seven-day chart, achievements, Shortcuts actions, and in-app updates. Focus and rest lengths are right in the menu; **Settings…** (⌘,) holds appearance (System / Light / Dark), language (System / 简体中文 / English), sounds, the menu bar countdown, open at login, which eye exercises to use, and work hours. Appearance changes immediately; use **Reopen now** to apply a language change. The **Achievements** page in Settings shows all eight badges, their requirements, and your progress.

## Privacy

- No accounts, no analytics, App Sandbox enabled
- Meeting and full screen detection only read whether the microphone is in use and where windows are; EyeBreak never records audio, captures the screen, or reads window titles
- The only network access is checking for updates: once a day it reads `appcast.xml` from GitHub, and downloads an update only if you accept it. Turn off **Auto-check for updates** to stop it

## Build from source

Requires Xcode 16 or later.

```bash
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -configuration Release -derivedDataPath ~/Library/Developer/Xcode/DerivedData/EyeBreak-build build
```

Run the tests:

```bash
xcodebuild -project EyeBreak.xcodeproj -scheme EyeBreak -derivedDataPath ~/Library/Developer/Xcode/DerivedData/EyeBreak-build test
```

Keep the build folder outside protected folders such as Documents; otherwise every new build asks for permission to access that folder.

## Feedback

Use **Feedback** at the bottom of the menu, or open an issue on [GitHub](https://github.com/yauyy/EyeBreak/issues).

## License

EyeBreak is released under the [MIT License](LICENSE). Third-party notices (currently [Sparkle](https://sparkle-project.org)) are in [EyeBreak/ThirdPartyNotices.txt](EyeBreak/ThirdPartyNotices.txt).
