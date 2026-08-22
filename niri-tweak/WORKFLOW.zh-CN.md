# niri-tweak 更新、构建与安装流程

## 工程结构

- `apply-niri-tweak.py`：对干净 Niri 源码严格施加 Overlay、手势和既有 session 修正。
- `update-build-install.sh`：获取稳定标签、清理源码、执行变换、构建并按需安装。
- `PKGBUILD.local`：当前 Arch 本地包定义。
- `niri-src/`：脚本管理的可丢弃 Niri checkout。
- `build-local/`：makepkg 工作目录和生成的软件包。

变换脚本会先在内存中验证所有关键源码锚点，全部匹配后才写文件。上游代码结构发生变化时会直接停止，避免生成只改了一半的 Niri。

## 常用命令

只构建、不安装：

```sh
cd /home/tanzhenyu/Developer/linux-tweak/niri-tweak
./update-build-install.sh --build-only
```

构建并安装：

```sh
./update-build-install.sh
```

固定到已经验证的 v26.04：

```sh
NIRI_TAG=v26.04 ./update-build-install.sh --build-only
```

脚本默认行为是：

1. fetch 上游 tags；
2. 将 `niri-src` 强制恢复到目标稳定标签；
3. 执行 `apply-niri-tweak.py`；
4. 运行 `git diff --check`；
5. 用 `PKGBUILD.local` 构建同名 `niri` 包；
6. 未指定 `--build-only` 时调用 `sudo pacman -U`。

## 手势实现位置

脚本会修改：

- `Cargo.toml`：启用 `input` crate 的 `libinput_1_28` 功能。
- `src/input/mod.rs`：启用三指拖动，重映射四指 swipe，并消费四指 pinch。
- `src/niri.rs`：保存一次四指 pinch 是否已触发的状态。

四指捏合使用 libinput 提供的累计 `scale`：小于 1 表示向内，大于 1 表示向外。默认阈值为 0.8 和 1.2，达到阈值后直接调用 Niri 的 `open_overview()` 或 `close_overview()`。四指 swipe 与 pinch 按事件类型分别处理。

## Overlay 实现位置

脚本会修改：

- `src/ui/hotkey_overlay.rs`
- `src/ui/mru.rs`
- `src/ui/screenshot_ui.rs`

三个面板都在透明 ARGB surface 上绘制圆角路径，再填充原有深色背景并沿同一路径绘制 Border。因此四角保持透明，不会出现“圆角图形外仍有黑色方角”的问题。Border 宽度和颜色来自 `config.layout.border.width` 与 `active_color`；窗口 Border 即使配置为 `off`，Overlay Border 仍然显示。

## 更新到新的 Niri 版本

先运行普通的 `--build-only`。如果脚本报告源码锚点不匹配：

1. 不要直接在已经部分修改的 `niri-src` 上继续堆改动；
2. 对照新版本源码更新 `apply-niri-tweak.py` 中对应的精确片段；
3. 再次运行脚本两次，第二次应输出所有 tweak 已应用；
4. 运行 `cargo check --locked`、`git diff --check` 和 release 构建；
5. 实机确认三指拖动、四指上下/左右滑动、四指内外捏合和三个 Overlay。

## 回退

自定义包名仍为 `niri`。需要回到仓库版本时，直接使用系统包管理器重新安装仓库中的 Niri 即可。不要在正在运行的图形会话里替换并重启 compositor，建议切换到 TTY 或注销后操作。
