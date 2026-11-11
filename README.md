# Mirrorbar

A macOS menu bar app that keeps [scrcpy](https://github.com/Genymobile/scrcpy) mirroring of an Android phone running smoothly: USB or Wi-Fi, auto reconnect, refresh-rate lock, and a window placed on a high-refresh display.

在 Mac 菜单栏里一键镜像、操作安卓手机：看视频、回消息、刷应用。画面和控制由 scrcpy 完成，Mirrorbar 负责连接、参数和各种琐事。

## 功能

| 功能 | 说明 |
|---|---|
| 一键开始 / 停止 | 菜单栏图标，或 ⌘M |
| USB 和 Wi-Fi 自动切换 | 插 USB 时自动开启无线 adb（`adb tcpip 5555`），并经 USB 记下手机的 Wi-Fi 地址；拔线后自动连 Wi-Fi，不依赖 mDNS |
| 断线自动重连 | scrcpy 异常退出后 3 秒重连，最多 8 次 |
| 锁定手机刷新率 | 镜像期间把小米 / HyperOS 手机锁到 60/90/120Hz，结束后恢复原值；App 崩溃后下次连上手机也会恢复 |
| 选显示器 | 自动把窗口放到刷新率够高的屏幕上（60Hz 屏只能显示 60fps）；手机横屏时窗口横向居中 |
| 画质 | 默认 H.265；码率上限按连接分开：USB 24M，Wi-Fi 12M，切换连接时自动换 |
| 声音 | 只在 Mac 播放 / Mac 和手机都响 / 关闭 |
| 操作栏 | 贴在镜像窗口旁边，跟着窗口走：返回、主页、后台、横竖屏切换、下拉通知栏、截图、音量加减、息屏、锁屏、上滑、下滑 |
| 手机息屏 | 默认开启：镜像时手机屏幕黑着、画面和操作照常，省电；操作栏的月亮 / 太阳按钮随时切换，窗口位置不变 |
| 截图 | 存到桌面，同时复制到剪贴板 |
| 菜单快捷开关 | 操作栏、窗口置顶、手机息屏、声音，改了立即生效 |
| 帧率显示 | 菜单里显示实时 fps |
| 链接控制 | 见下方「链接」，可接快捷指令或 Raycast 绑热键 |

## 依赖

- macOS 14 及以上，Apple 芯片
- scrcpy：`brew install scrcpy`
- adb：建议用 Android SDK 的 platform-tools。如果同时装了 Homebrew 的 adb，两个版本不一致时会互相重启 adb server、打断镜像，所以 Mirrorbar 会把 scrcpy 固定到设置里指定的那一个 adb
- 手机打开 USB 调试，并在第一次插线时授权这台 Mac

## 构建

```sh
./scripts/build-app.sh            # 生成 build/Mirrorbar.app
./scripts/build-app.sh --install  # 安装到 ~/Applications 并启动
```

用本机临时签名（ad-hoc），没有公证。只在自己的 Mac 上构建、使用。

## 使用

1. 插上 USB，菜单栏图标从 `iphone.slash` 变成手机图标
2. 点「开始镜像」。之后拔线，Mirrorbar 会自动切到 Wi-Fi 重新连上
3. 帧率、编码、码率、分辨率、显示器、键盘模式在「设置…」里改

操作栏只在镜像窗口在最前面时出现，鼠标移开 3 秒后变半透明；不想要可以在菜单里关掉「显示操作栏」。按钮直接发给手机，不用先点镜像窗口。

输中文：在 Mac 上复制，到镜像窗口按 ⌘V，scrcpy 会把 Mac 剪贴板同步到手机再粘贴。

scrcpy 自带的快捷键都能用（默认修饰键是左 ⌥ 或左 ⌘），见 [scrcpy 快捷键文档](https://github.com/Genymobile/scrcpy/blob/master/doc/shortcuts.md)。

## 链接

| 链接 | 作用 |
|---|---|
| `mirrorbar://start` / `stop` / `toggle` | 开始、停止、切换镜像 |
| `mirrorbar://back` / `home` / `recents` | 返回、主页、后台 |
| `mirrorbar://rotate` | 横竖屏切换 |
| `mirrorbar://notifications` | 下拉通知栏 |
| `mirrorbar://screenshot` | 截图 |
| `mirrorbar://volume-up` / `volume-down` | 音量加减 |
| `mirrorbar://screen` | 手机息屏 / 亮屏（镜像照常） |
| `mirrorbar://power` | 锁屏 / 亮屏（电源键） |
| `mirrorbar://swipe-up` / `swipe-down` | 上滑、下滑 |

终端里可以直接 `open mirrorbar://back`。

## 已知限制

- 手机锁屏时只能看到锁屏界面，要在手机上解锁
- 息屏和窗口置顶要重启 scrcpy 才能切换，画面会断 1 秒左右
- 横竖屏切换改的是系统旋转（会关掉自动旋转，停止镜像后恢复）；自己锁定方向的 App（很多视频播放页、小米「设置」）不受影响
- 刷新率锁定只适配了小米 / HyperOS（`is_smart_fps`、`user_refresh_rate`），其他手机会跳过这一步
- 帧率上限取决于手机屏幕当前刷新率和 Mac 显示器刷新率中较低的那个
- 菜单里的帧率是 Mac 端实际画出来的帧数；镜像窗口被别的窗口完全挡住时 macOS 会暂停渲染，这时显示的帧率会很低，不代表手机掉帧
- 日志在 `~/Library/Logs/Mirrorbar/mirrorbar.log`；`defaults write io.github.liangjh0712.mirrorbar fpsLogInterval 1` 可以让日志每秒记一次帧率

## License

MIT。scrcpy 使用 Apache-2.0 许可，本项目不包含 scrcpy 代码，只调用本机安装的 scrcpy。
