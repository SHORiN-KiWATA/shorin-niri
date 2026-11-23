---
name: niri-agent
description: "Operate GUI apps on the user's niri desktop (SHORiN-KiWATA's niri fork with the agent seat) in the background through `niri msg agent`: capture a window, click, type, press keys, launch apps, without moving the user's cursor or focus; prefers CLI and D-Bus routes when they can do the job. Use when asked to operate, click, fill in, read or check something in a desktop app, browser or other GUI window on this machine. 操作桌面应用、点按钮、填表、在浏览器里打开网页、看某个窗口的画面时使用。"
metadata:
  display_name: Operate the niri desktop
  summary: Click, type and read GUI apps on shorin-niri in the background
  display_name_zh: 操作 niri 桌面
  summary_zh: 在后台点、输入、读 shorin-niri 桌面上的图形界面应用
---

# 在 niri 桌面上操作图形界面应用

你有自己的一套指针和键盘（agent seat），输入只进你指定 id 的窗口，不影响用户的光标、焦点和剪贴板。窗口在不在屏幕上都能操作。命令都用 `shell` 工具跑。下文的 `agent-ui`、`agent-firefox` 和本文件（`SKILL.md`）在同一个文件夹里：照本文件的路径拼出来，用 `python3 <那个文件夹>/agent-ui …` 跑，下文简写成 `agent-ui`。

只在 SHORiN-KiWATA 的 niri 分支上能用（`niri msg agent` 是它加的；`niri msg agent --help` 报不认识的就是别的 niri，告诉用户，不要硬试）。`agent-ui` 要 PyGObject 和 AT-SPI。

## 先找接口，图形界面是最后手段

点界面慢、容易点错。动手前先看任务能不能直接办：

| 要做的事 | 先试 |
|---|---|
| 音量、麦克风 | `wpctl`（`wpctl set-volume @DEFAULT_AUDIO_SINK@ 40%`） |
| 网络、Wi-Fi | `nmcli` |
| 蓝牙 | `bluetoothctl` |
| 播放、暂停、当前曲目 | `playerctl` |
| 亮度 | `brightnessctl` |
| 窗口、工作区、显示器 | `niri msg`（`niri msg action --help`） |
| 通知 | 发：`notify-send`；看、关：`makoctl` |
| GNOME/GTK 应用设置 | `gsettings list-recursively 应用 id` |
| 读网页内容 | 不需要登录就直接用 curl，不开浏览器 |
| 其他应用 | `应用 --help` 有没有对应命令；D-Bus：`busctl --user list` 找服务，`busctl --user introspect 服务 路径` 看方法 |

找不到可用的接口，或者任务本身就要看界面（检查显示效果、用户点名要在某个窗口里做），再用下面的图形界面操作。接口改的是用户的真实状态，跟点界面一样遵守最后「注意」里的规则；不要改用户的配置文件。

## 选窗口

`niri msg -j windows`：`is_focused: true` 是用户正在用的，除非用户要求，不要碰；`is_agent: true` 是你自己开的。

**共享模式**：直接操作用户开着的窗口。GTK、Qt、Firefox、Alacritty 可以；Chromium、Electron（VS Code、QQ）、kitty、Zed 只认一个 seat，会报 `only handles one seat`，改用独立模式。

**独立模式**：`niri msg agent launch -- 命令`，等到第一个窗口出现，打印含 `id` 的 JSON。任何应用都能操作，开在 agent 工作区，不抢焦点。环境变量继承自 niri，不是你的 shell；要设就写 `launch -- env FOO=bar 命令`。

单实例应用必须用独立 profile，否则请求交给用户的进程，30 秒后报错：

| 应用 | 启动方式 |
|---|---|
| Firefox（上网首选） | `agent-firefox URL`：先复制用户当前的登录状态，再启动；已开着就开新窗口 |
| Chromium | `launch -- env ACCESSIBILITY_ENABLED=1 chromium --user-data-dir="$HOME/.local/share/niri-agent/chromium" --force-renderer-accessibility --no-first-run URL` |
| VS Code | `launch -- code --user-data-dir="$HOME/.local/share/niri-agent/vscode"` |
| Mousepad | `launch -- mousepad --disable-server` |

agent-firefox 里是用户的真实账号：不要向用户要密码，也不要替用户发帖、发消息、下单、改设置。

## 循环：定位 → 动作 → 看回执

**定位，优先用 `agent-ui`**：读应用的无障碍树，几百 token，名字是原文。

```sh
agent-ui --id 7                 # 全部可见控件
agent-ui --id 7 --find 首选项   # 名字、文字里含"首选项"的
```
```
menu item '首选项...' @ 227,521.5 (324x31)
check box '使用系统等宽字体' @ 119.5,368.5 (197x27) [checked]
spin button @ 299,216 (128x34) [disabled; text='80'; value=80]
```

`@ X,Y` 是窗口坐标，直接 `click --id 7 X Y`，不加 `--image`。网页里滚动到视野外的控件默认只计数，`--find` 会搜到并标 `offscreen below/above`：先 scroll 再重新 `agent-ui` 取坐标。数标题、找链接不用滚屏截图，直接 `--find "heading 2"`。kitty、Alacritty、游戏没有无障碍树，会报错；要看颜色、布局、图片内容时也要截图。

**截图**，再用 `read` 工具看：

```sh
niri msg agent capture --id 7 --path /tmp/niri-agent/7.png --max-size 1280
```

token 只取决于像素尺寸，1280 一般够用。截图包含阴影和展开的菜单。之后按图片像素坐标操作时加 `--image 那张图`，换了窗口就重截。

**动作**：

```sh
niri msg agent click  --id 7 --image /tmp/niri-agent/7.png 288 29   # --button right / --count 2
niri msg agent move   --id 7 --image /tmp/niri-agent/7.png 288 29   # 悬停
niri msg agent scroll --id 7 --image /tmp/niri-agent/7.png 300 500 --dy 400   # 正数向下，逻辑像素
niri msg agent key    --id 7 ctrl+shift+t                           # xkb 键名：Return Escape Tab BackSpace Page_Down F5…
printf '%s' '任意 Unicode 文字' | niri msg agent type --id 7 -      # 一律从标准输入传，不经过输入法
```

拖动：`button --pressed true`，`move`，`button --pressed false`。

多步用 `--require-change` 加 `&&` 串成一条命令。某步没有引起任何变化时，以退出码 3 停下，后面的不执行。悬停这类不一定有变化的步骤不要加：

```sh
niri msg agent --require-change click --id 7 304 120 &&
printf '%s' '张三' | niri msg agent type --id 7 - &&
niri msg agent --require-change key --id 7 ctrl+s
```

**回执**：每个动作等画面稳定（最多 2 秒）后打印 JSON，坐标是窗口坐标。

| 回执 | 含义 → 做法 |
|---|---|
| `changed`、`popups_opened`、`windows_opened` 全空 | 没点中 → 重新定位，不要原地再点 |
| `popups_opened` 非空，`focus: "popup"` | 菜单打开了 → `agent-ui --find` 找菜单项；按键会进菜单 |
| `windows_opened` | 新窗口或对话框，`parent_id` 是父窗口 → 改用新 `id` |
| `title` | 标题变了：页面加载完成，或文件未保存 |
| `settled: false` | 还在变（加载、动画、视频）→ 稍等再看 |
| 文本框里约 8 像素宽的 `changed` | 光标闪烁 → 忽略 |

回执能说明结果，就不要截图；需要知道变成什么样时，先 `agent-ui`，不够再截图。

## 注意

- 不关用户的窗口；不可撤销的操作（发送、付款、删除）要用户明确要求才做。
- 你的剪贴板是独立的，`ctrl+c` 的内容谁都读不到。要拿内容，就截图，或让应用存成文件。
- 锁屏期间照常工作，不要碰锁屏界面。
- 用户可以直接点你开的窗口来接管它（键盘焦点离开就交还）。接管期间你的所有输入动作都会被拒绝，截图和 `agent-ui` 照常。遇到登录、验证码、付款确认这类该由用户做的步骤，就告诉用户窗口 id 请他接管，做完后切走并告诉你，你再继续。

| 报错 | 处理 |
|---|---|
| `only handles one seat` | 改用独立模式 |
| `window N was not found` | 重新 `niri msg -j windows` |
| `no window appeared within 30 s` | 按上表加 profile 参数 |
| `is a capture of window A, not window B` | 给目标窗口重新截图 |
| `the agent seat is off` | 告诉用户，不要改配置 |
| `the user took over window N` | 用户正在用这个窗口：停下，不要重试，等用户说好了再继续 |
