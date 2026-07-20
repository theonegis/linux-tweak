# Noctalia greeter 本地修正包

这个目录为 ArchLinuxCN 的同名 `noctalia-greeter-git` 包应用一份合并补丁
`0005-quiet-console-handoff.patch`：

1. shell、Noctalia logger 和 wlroots 默认只向 tty 输出 ERROR，INFO 与
   WARNING 不再产生文字闪屏；
2. 在 `wlr_backend_start()` 成功、VT 已处于隐藏图形模式之后清空画面与
   scrollback，清屏本身不会再提前触发 fbcon；
3. 显式文件日志仍保留全部级别，便于发生问题时排查。

上游从 `r161` 起已经合入了 display teardown 的键盘/seat 崩溃修复，因此
旧的 `0001`–`0004` 文件只作为历史记录保留，不再由 PKGBUILD 应用。
合并补丁保留真正的错误输出。显式文件日志仍记录全部 Noctalia 日志；
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
