# Fcitx5 英文托盘标签补丁

Noctalia 托盘显示的是 Fcitx5 通过 StatusNotifierItem 提供的预渲染图标。
英文输入法 `keyboard-us` 的图标文字由 Fcitx5 内部标签 `en` 生成，因此不能用
Noctalia 的键盘布局标签配置修改。

`0001-label-keyboard-us-as-ying.patch` 只把 `keyboard-us` 的显示标签改为“英”，
不修改键盘布局、Rime、快捷键或输入行为。包名仍是 `fcitx5`，本地包版本为
`5.1.21-1.2`，高于当前 CachyOS 包的 `5.1.21-1.1`；后续 5.1.22 等新版仍可
正常覆盖。

构建并安装：

```bash
cd /home/tanzhenyu/Developer/linux-tweak/fcitx5-tweak
./update-build-install.sh
```

只构建和测试：

```bash
./update-build-install.sh --build-only
```
