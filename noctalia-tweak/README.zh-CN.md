# Noctalia V5 剪贴板修正包

此目录在 ArchLinuxCN 的同名 `noctalia-git` 包上应用
`0001-fix-deferred-clipboard-orphan-adoption.patch`。

## 修复的问题

Wayland 剪贴板的内容由当前 selection 的 data source 负责提供。这个 data
source 的生命周期与程序进程的生命周期并不相同：程序即使仍在运行，也可能
因为内部控件重建、页面切换或客户端自身的剪贴板实现而释放或替换 data
source。此时 compositor 可能向 Noctalia 报告一次 NULL selection。为避免在
正常的 selection 交接过程中因短暂 NULL 而恢复旧内容，Noctalia 会把接管动作
推迟到下一次 clipboard poll dispatch。

Noctalia 主循环只 dispatch 有 fd 就绪或 timeout 到期的 poll source；selection
变为 NULL 后，clipboard source 恰好可能没有任何 fd，也没有注册 timeout。
因此接管会一直处于 pending 状态：Noctalia 历史面板仍能看到文字，但系统的
实时剪贴板为空，`Ctrl+V` 和右键粘贴都会失败。后续新的剪贴板事件可能令其
再次工作，所以现象是偶发的；源程序不需要退出就可能触发。

补丁让 clipboard poll source 在有待处理的 orphan adoption 时请求一次 0 ms
timeout。主循环会在下一轮立即 dispatch，并由 Noctalia 接管实时 selection。
补丁同时扩展了上游 clipboard service 测试，验证 timeout 会被设置并在接管后
清除。

这项修改修复的是已经从代码和运行状态确认的“历史中有内容、实时 Wayland
selection 却为空”的路径。如果故障发生时 `wl-paste --list-types` 仍能列出 MIME
类型，则属于另一条路径（例如目标程序读取或 MIME 协商失败），需要另外抓取
故障现场，不能用本补丁解释。

## 构建并安装

```bash
cd /home/tanzhenyu/Developer/linux-tweak/noctalia-tweak
./update-build-install.sh
```

只构建和测试、不安装：

```bash
./update-build-install.sh --build-only
```

安装后注销并重新登录，确保正在运行的是新二进制。可用下列命令验证当前
Wayland selection 是否存在；命令只显示 MIME 类型，不打印剪贴板正文：

```bash
wl-paste --list-types
```

## 后续更新

本地包继续使用真实包名 `noctalia-git`。ArchLinuxCN 发布更高 VCS 版本时，
`paru -Syu` 仍会正常更新；更新后重新运行本目录的脚本即可对最新源码应用
补丁。本地版本带有 `.local1` 后缀，因此同一 Git revision 的本地包高于仓库
包，而仓库中 revision 数字更大的新版仍会正常覆盖。若上游已经合入完全相同
的补丁，构建脚本会跳过重复应用；若上游以
不同方式修改了相关代码，构建会安全停止，届时应先检查上游实现再更新补丁。

另外，当前 niri 配置和 XDG autostart 都会启动 Fcitx5，因而开机会产生一次
“another fcitx already running”日志。后启动的实例随即退出，这不是本次
剪贴板失效的根因，但可删除 niri 中重复的 `spawn-at-startup "fcitx5" ...`
以清理日志；系统的 XDG autostart 已会正常启动 Fcitx5。
