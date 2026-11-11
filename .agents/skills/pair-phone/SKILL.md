---
name: pair-phone
description: 帮用户把安卓手机和这台 Mac 配对，让 Mirrorbar / scrcpy 能镜像和操作手机：检查 adb 与 scrcpy、按品牌一步步指导打开开发者选项和 USB 调试、处理授权弹窗、检测并解决「只能看不能点」、开启 Wi-Fi 连接、最后验证镜像。Use when the user wants to pair / connect a new Android phone, says the phone is not detected, "unauthorized", "offline", mirroring shows but taps do nothing, or asks how to set up Mirrorbar. 触发：配对手机、连接手机、新手机、手机连不上、识别不到手机、只能看不能点、Mirrorbar 怎么用。
---

# 配对安卓手机

目标：手机出现在 `adb devices` 里且状态是 `device`，能收到点击，Mirrorbar 能开始镜像。

人只需要在手机上点几下。其余的检查、判断和排错都由你来做：每一步先跑体检脚本，按结果里的 `next` 决定下一步，一次只让用户做一件事，做完再体检。

## 体检脚本

```sh
bash .agents/skills/pair-phone/scripts/check.sh            # 自动选设备
bash .agents/skills/pair-phone/scripts/check.sh <serial>   # 指定设备
```

只读，约 1 秒。逐行输出 `key=value`，重点看这几项：

| 字段 | 含义 |
|---|---|
| `adb` / `adb_version` | 选中的 adb，与 Mirrorbar 设置里的一致 |
| `other_adbs` | 其他 adb 及版本。版本不同的两个 adb 会互相重启 adb 服务、打断镜像 |
| `devices` / `device_N` | 设备列表和状态（`device` / `unauthorized` / `offline`） |
| `usb_android_seen` | 没有设备时，USB 上有没有看到安卓手机：用来区分「线或 USB 模式有问题」和「没开 USB 调试」 |
| `manufacturer` / `android` | 品牌和系统版本，决定后面给哪套路径 |
| `control` | `ok` 能点击；`blocked` 只能看不能点 |
| `wifi_ip` / `tcp_port` | 手机 Wi-Fi 地址；`tcp_port=5555` 表示已开启 Wi-Fi 连接 |
| `next` | 下一步，见下表 |

## 按 `next` 走

| `next` | 做什么 |
|---|---|
| `install_adb` | 见「安装依赖」 |
| `enable_usb_debugging` | `usb_android_seen=none`：先换一根能传数据的线、换个 USB 口，手机通知栏里把 USB 用途改成「文件传输」。看到了手机但没有设备：按「打开 USB 调试」指导用户 |
| `authorize_on_phone` | 让用户解锁手机，在弹窗里勾「始终允许使用这台计算机进行调试」，再点「允许」。没弹窗见「排错」 |
| `reconnect` | 设备是 `offline`：执行 `$ADB reconnect`，不行就让用户拔插一次 |
| `enable_control_permission` | 按「只能看不能点」按品牌指导用户 |
| `ready` | 见「收尾」 |

`$ADB` 一律用体检结果里的 `adb=` 那个路径，不要换成 PATH 里的另一个。

## 打开 USB 调试

还不知道品牌时，先问用户是什么手机。路径是各家常见位置，系统版本不同会有差异；找不到时让用户在「设置」顶部搜索框里搜「版本号」「开发者」「USB 调试」。

**第一步，打开开发者选项**：在下面的位置连点 7 次，提示「您已处于开发者模式」即可。

| 品牌 | 连点哪里 | 开发者选项在哪 |
|---|---|---|
| 小米 / Redmi / POCO（HyperOS、MIUI） | 设置 → 我的设备 → 全部参数 → OS 版本（旧版叫 MIUI 版本） | 设置 → 更多设置 → 开发者选项 |
| 三星（One UI） | 设置 → 关于手机 → 软件信息 → 编译编号 | 设置最底部 |
| 华为 / 荣耀 | 设置 → 关于手机 → 版本号 | 设置 → 系统和更新 → 开发人员选项 |
| OPPO / 一加 / realme（ColorOS） | 设置 → 关于手机 → 版本信息 → 版本号 | 设置 → 系统设置（或其他设置）→ 开发者选项 |
| vivo / iQOO | 设置 → 系统管理 → 关于手机 → 版本信息 → 软件版本号 | 设置 → 系统管理 → 开发者选项 |
| Pixel 及原生安卓 | 设置 → 关于手机 → 版本号 | 设置 → 系统 → 开发者选项 |

华为的纯血鸿蒙（HarmonyOS NEXT）不是安卓，adb 和 scrcpy 都用不了，直接告诉用户。

**第二步**：在开发者选项里打开「USB 调试」，插上数据线，然后重新体检。

## 只能看不能点（`control=blocked`）

画面能出来，但点击、滑动、按键都发不过去。这是手机厂商额外加的开关：

| 品牌 | 开发者选项里要开的 |
|---|---|
| 小米 / Redmi / POCO | 「USB 调试（安全设置）」。要插 SIM 卡并登录小米账号；开的时候有倒计时确认 |
| OPPO / 一加 / realme | 关掉「禁止权限监控」（不同版本叫法略有差异） |
| 其他 | 让用户在开发者选项里找带「安全」「模拟点击」「权限监控」字样的开关 |

开完重新体检，看到 `control=ok` 才算好。

## 收尾（`next=ready`）

1. **Wi-Fi 连接**：Mirrorbar 在运行时，会在插着 USB 时自动执行 `adb tcpip 5555` 并记下手机 IP，等几秒后体检，看到 `tcp_port=5555` 即可。没装 Mirrorbar 时手动执行：
   ```sh
   $ADB -s <USB serial> tcpip 5555
   $ADB connect <wifi_ip>:5555
   ```
   手机重启后 5555 端口会关掉，插一次 USB 就会重新打开。
2. **试镜像**：`open "mirrorbar://start"`，等 6 秒后看 `~/Library/Logs/Mirrorbar/mirrorbar.log` 里有没有 `Texture`，有就说明画面通了。再请用户看一眼窗口，并在镜像窗口里点一下确认能操作。
3. 告诉用户：以后插线或在同一个 Wi-Fi 下打开 Mirrorbar 就能用；手机锁屏时只能看到锁屏界面，要在手机上解锁。

## 没有数据线时（安卓 11 以上）

手机和 Mac 要在同一个 Wi-Fi 下。让用户打开开发者选项 → 无线调试 → 使用配对码配对设备，报给你屏幕上的「IP 地址和端口」和 6 位配对码；无线调试主页面上方还有一个「IP 地址和端口」，那个是连接端口，和配对端口不是同一个。

```sh
$ADB pair <IP>:<配对端口> <配对码>
$ADB connect <IP>:<连接端口>
```

无线调试的端口每次重新开启都会变，Mirrorbar 不会自动跟进。之后有机会插一次线，按上面的流程开启 5555 端口，以后就不用再配对了。公司或公共网络常常屏蔽 mDNS，「二维码配对」在这种网络里用不了，只能用配对码。

## 排错

| 现象 | 处理 |
|---|---|
| 一直 `unauthorized`、手机不弹窗 | 拔插数据线；USB 用途改成「文件传输」；仍不行，征得用户同意后在开发者选项里点「撤销 USB 调试授权」再插（会让这台手机上所有电脑的授权都失效） |
| 设备时有时无、镜像突然断 | 看 `other_adbs`：有不同版本的 adb 在互相抢服务。让用户只保留一个，或把 Mirrorbar 设置里的 adb 路径和终端里用的统一 |
| `adb connect` 超时 | 手机和 Mac 不在同一网段，或 IP 变了。插 USB 重新体检拿新的 `wifi_ip` |
| 点击位置不准或没反应 | 先看 `control`；再确认没开「手势模拟」类第三方应用 |

## 规则

- 手机上的操作只能让用户做：授权弹窗、开关、解锁。不要猜锁屏密码，也不要试图绕过锁屏。
- 不删 `~/.android/adbkey*`，不撤销手机授权，除非用户明确同意：两者都会让已经配好的设备全部失效。
- 安装软件（Homebrew、adb、scrcpy）前先告诉用户要装什么，等用户同意。
- 一次只给一条指令，用用户手机上的叫法；用户做完后重新体检，不凭感觉判断。
- `adb tcpip` 模式下画面在局域网里是明文传输的。在公共或不信任的网络里，建议用户只用 USB。

## 安装依赖

```sh
brew install scrcpy                         # 镜像
brew install --cask android-platform-tools  # adb（已有 Android Studio 的话用它的 SDK 里的 adb 即可）
./scripts/build-app.sh --install            # 在仓库根目录构建并安装 Mirrorbar
```

装了 Homebrew 的 adb 又有 Android SDK 的 adb 时，在 Mirrorbar 设置里把 adb 路径指定成其中一个，终端里也只用这一个。
