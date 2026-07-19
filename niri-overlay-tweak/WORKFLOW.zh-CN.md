# niri 源码更新、修改和打包流程

这个目录提供三个长期维护文件：

- `apply-niri-acrylic.py`：修改 niri 源码；
- `PKGBUILD.local`：从修改后的本地源码生成 Arch 包；
- `update-build-install.sh`：自动完成拉取、修改、构建和安装。

`niri-src` 仅作为可丢弃的上游源码副本。不要在里面保存自己的修改，
因为更新脚本会使用 `git switch --force` 和 `git reset --hard` 清除其中的
tracked changes。永久修改应写入 `apply-niri-acrylic.py`。

## 第一次使用

安装构建依赖：

```bash
sudo pacman -S --needed base-devel git rust clang inter-font
```

然后执行：

```bash
cd /home/tanzhenyu/Developer/linux-tweak/niri-overlay-tweak
./update-build-install.sh
```

脚本会：

1. 将上游仓库克隆到 `niri-src`；
2. 找到版本号最高的稳定 release tag；
3. 将源码重置到该 tag；
4. 修改三个 overlay UI 源文件，并在上游仍保留相应原始命令时，修正
   `resources/niri-session` 的环境导入并在启动 niri 前清空 Linux VT；
5. 构建 `niri-版本-1.3-x86_64.pkg.tar.zst`；
6. 使用 `sudo pacman -U` 安装。

新的自定义包使用仓库包同名的 `niri`。从旧的 `niri-acrylic`
第一次迁移时，pacman 会提示替换冲突包，确认即可。安装完成后注销
并重新登录。

因为已安装包的真实名称是 `niri`，仓库之后出现更高版本时，
`paru -Syu`/`pacman -Syu` 会正常用官方包覆盖它。官方更新后如果要
恢复自定义 overlay，再运行本脚本；脚本会在最新稳定 tag 上重新
应用修改并安装同名的 `niri` 包。

本地 `pkgrel` 使用 `1.3`，以避免被 CachyOS 当前同源码版本的
`1.1` 优化包立即覆盖。这不会阻止更高 `pkgver` 的新 niri 版本，
也不会阻止更高的仓库 `pkgrel`。

如果只想编译包而暂时不安装：

```bash
./update-build-install.sh --build-only
```

生成的包位于 `build-local/`。

如需暂时固定到某个稳定版本，可以指定 tag：

```bash
NIRI_TAG=v26.04 ./update-build-install.sh
```

## 以后每次 niri 发布新版本

仍然只需运行：

```bash
cd /home/tanzhenyu/Developer/linux-tweak/niri-overlay-tweak
./update-build-install.sh
```

脚本每次都会重新检查最新稳定 tag。Cargo 的依赖缓存和 `niri-src/target`
会被保留，所以后续构建通常比第一次快。

如果上游改变了 overlay 的实现，修改脚本会报出具体是哪个锚点没有匹配，
并且不会写入半成品。这时需要根据新版的 `mru.rs` 或
`hotkey_overlay.rs` 或 `screenshot_ui.rs` 更新修改脚本。

`niri-session` 修正是可选的精确匹配：如果检测到上游旧的环境导入
命令，就显式传入当前环境里的所有变量名，以保留 niri 原有行为并
避免 systemd 的弃用警告。如果仍检测到上游原始的
`systemctl --user --wait start niri.service`，脚本还会在它之前清空
编号 Linux VT 的当前画面和 scrollback；伪终端与嵌套会话不受影响。
如果上游以后移除或改写相应命令，脚本会保留上游内容，不会猜测式
替换。

## 分步手动执行

下面是自动脚本所做工作的等价命令，便于排查：

```bash
cd /home/tanzhenyu/Developer/linux-tweak/niri-overlay-tweak

git clone https://github.com/niri-wm/niri.git niri-src
git -C niri-src fetch --tags --prune origin

tag=$(git -C niri-src for-each-ref --count=1 --sort=-version:refname \
  --format='%(refname:short)' 'refs/tags/v[0-9]*')
git -C niri-src switch --detach --force "$tag"
git -C niri-src reset --hard "$tag"

./apply-niri-acrylic.py niri-src
git -C niri-src diff --check

export NIRI_SRC="$PWD/niri-src"
export NIRI_PKGVER="${tag#v}"
export NIRI_COMMIT=$(git -C niri-src rev-parse --short=7 HEAD)

makepkg --syncdeps --force -p PKGBUILD.local
package_file=$(makepkg --packagelist -p PKGBUILD.local | head -n 1)
sudo pacman -U "$package_file"
```

仓库已经存在时不要再次 `git clone`，从 `git fetch` 那一行继续即可。

## 检查与恢复

确认安装的版本：

```bash
niri --version
pacman -Q niri
```

回到官方仓库版本：

```bash
sudo pacman -S niri
```
