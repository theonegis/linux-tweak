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
cd /home/tanzhenyu/Developer/niri-overlay-acrylic
./update-build-install.sh
```

脚本会：

1. 将上游仓库克隆到 `niri-src`；
2. 找到版本号最高的稳定 release tag；
3. 将源码重置到该 tag；
4. 修改 `src/ui/mru.rs`、`src/ui/screenshot_ui.rs` 和 `src/ui/hotkey_overlay.rs`；
5. 构建 `niri-acrylic-版本-1-x86_64.pkg.tar.zst`；
6. 使用 `sudo pacman -U` 安装。

第一次安装时，pacman 会提示 `niri` 与 `niri-acrylic` 冲突。确认移除仓库
中的 `niri` 即可；`niri-acrylic` 已提供 `niri` 和 `wayland-compositor`。
安装完成后注销并重新登录。

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
cd /home/tanzhenyu/Developer/niri-overlay-acrylic
./update-build-install.sh
```

脚本每次都会重新检查最新稳定 tag。Cargo 的依赖缓存和 `niri-src/target`
会被保留，所以后续构建通常比第一次快。

如果上游改变了 overlay 的实现，修改脚本会报出具体是哪个锚点没有匹配，
并且不会写入半成品。这时需要根据新版的 `mru.rs` 或
`hotkey_overlay.rs` 或 `screenshot_ui.rs` 更新修改脚本。

## 分步手动执行

下面是自动脚本所做工作的等价命令，便于排查：

```bash
cd /home/tanzhenyu/Developer/niri-overlay-acrylic

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
pacman -Q niri-acrylic
```

回到官方仓库版本：

```bash
sudo pacman -S niri
```

pacman 会提示移除冲突的 `niri-acrylic`。
