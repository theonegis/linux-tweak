# Noctalia greeter 本地修正包

这个目录为 ArchLinuxCN 的同名 `noctalia-greeter-git` 包增加四个补丁：

1. 在销毁 wlroots display 之前解除所有键盘 listener，避免登录成功时
   `wlr_keyboard_finish()` 进入已经失效的回调链并触发 SIGSEGV；
2. 原始清屏补丁，用于清除控制 VT 的画面和 scrollback；
3. 原始 DRM 交接补丁，用于 greeter 退出时再次处理 VT；
4. 根据实际启动时间线修正前两个补丁的时机：移除 DRM 接管前会触发
   fbcon 的清屏，把清屏移动到 `wlr_backend_start()` 成功、VT 已处于隐藏
   图形模式之后；同时让 shell、Noctalia logger 和 wlroots 默认只向 tty
   输出 ERROR，INFO 与 WARNING 不再产生文字闪屏。

第四个补丁保留真正的错误输出。显式文件日志仍记录全部 Noctalia 日志；
需要临时恢复控制台诊断时，可以设置
`NOCTALIA_GREETER_LOG_LEVEL=info` 和 `WLR_LOG=info`。两个 compositor 之间
仍会有不可避免的 DRM 交接，但在没有错误时底层 VT 应保持空白。

## 构建并安装

```bash
cd /home/tanzhenyu/Developer/linux-tweak/noctalia-greeter-tweak
./update-build-install.sh
```

只构建、不安装：

```bash
./update-build-install.sh --build-only
```

本地包继续使用 `noctalia-greeter-git` 这个真实包名。ArchLinuxCN 出现更高
VCS 版本时，`paru -Syu` 仍可正常覆盖它；之后重新运行本脚本即可在最新
源码上再次应用补丁。如果上游源码改变导致补丁无法应用，构建会在编译和
安装之前停止。

## 验证

重启并完成一次登录后检查：

```bash
coredumpctl list /usr/bin/noctalia-greeter-compositor
journalctl -b -u greetd --no-pager
```

新的登录时间点不应再出现 `noctalia-greeter-compositor` 的 SIGSEGV。
正常启动时，Noctalia 出现之前以及进入 niri 之前不应再显示 INFO/WARNING
文字；如果 greeter 或 compositor 发生 ERROR，错误仍可写入 tty。
