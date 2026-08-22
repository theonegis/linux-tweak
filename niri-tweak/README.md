# niri-tweak

这是一个自用的 Niri 源码修改与 Arch 打包工程，当前同时包含 Overlay 美化和触控板手势重映射。

## 已实现功能

### Overlay

- `Important Hotkeys`、截图帮助面板和 MRU `Scope` 面板改为圆角矩形。
- 保留 Niri 原有深色背景、间距和文字颜色；圆角 Border 的宽度和颜色读取 `layout.border` 的 `width` 与 `active-color`。
- `layout.border.off` 只控制窗口 Border，不会隐藏 Overlay Border。
- 正文与按键标签均使用 Pango 的通用 `sans` 字体族，由系统字体配置决定实际字体，不再依赖 Inter。

### 手势

- 三指移动：启用 libinput 原生三指左键拖动，可用于拖动窗口、选择文字和拖动应用内对象。
- 四指滑动：接管 Niri 原来的三指手势；上下切换工作区，左右移动当前工作区的视图。
- 四指向内捏合：累计缩放比例达到 `0.8` 时打开 Overview。
- 四指向外捏合：累计缩放比例达到 `1.2` 时关闭 Overview。
- swipe 与 pinch 是不同的 libinput 事件，因此四指滑动和四指捏合可以并存；每次捏合只触发一次。

三指拖动 API 需要 libinput 1.28 或更新版本。本机的 libinput 1.31.3 满足要求，工程同时将 Rust `input` crate 的功能级别提高到 `libinput_1_28`。

## 构建

```sh
cd /home/tanzhenyu/Developer/linux-tweak/niri-tweak
./update-build-install.sh --build-only
```

确认生成的软件包后再安装：

```sh
sudo pacman -U ./build-local/niri-*.pkg.tar.zst
```

也可以直接运行 `./update-build-install.sh`，让脚本构建后调用 `sudo pacman -U`。安装完成后请注销并重新登录 Niri 会话。

脚本默认选取最新稳定标签，也可固定版本：

```sh
NIRI_TAG=v26.04 ./update-build-install.sh --build-only
```

`niri-src` 是脚本管理的可丢弃源码目录，每次构建都会恢复到所选标签。所有长期修改都应放在 `apply-niri-tweak.py` 中，不要直接维护 `niri-src` 内的改动。

## 调整

- 修改 `FOUR_FINGER_PINCH_IN_THRESHOLD` / `FOUR_FINGER_PINCH_OUT_THRESHOLD` 的生成值可调整四指触发距离。
- 修改 Niri 配置中的 `layout { border { width ...; active-color ...; } }` 可调整 Overlay Border；无需启用窗口 Border。
- 修改 `paint_rounded_panel()` 中的 `radius` 可调整圆角大小。
- `PKGBUILD.local` 是当前构建入口；根目录的旧 `PKGBUILD`、`.SRCINFO` 和 Acrylic patch 仅作为历史快照保留，不参与当前构建。

详细的更新流程见 [WORKFLOW.zh-CN.md](WORKFLOW.zh-CN.md)。
