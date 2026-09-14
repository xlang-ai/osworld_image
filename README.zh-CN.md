# OSWorld Image Builder

[English](README.md) | 中文

这个仓库用于从现有 OSWorld 基础镜像出发，复现性地构建带确定性增量配置的评测镜像。它不会从通用 Ubuntu ISO 或 Canonical AMI 重新制作系统，而是把已验证的 OSWorld base image 当作事实源，只在其上应用可审计的 Packer + Ansible delta。

支持的目标产物：

- AWS AMI，基于 `ami-0d23263edb96951d8`
- QEMU qcow2，基于 Hugging Face 上的 OSWorld qcow2
- Windows QEMU qcow2，基于 Hugging Face 上的 Windows OSWorld qcow2
- VMware Workstation VM，基于 Hugging Face 上的 OSWorld VMX
- Docker XFCE 基础镜像，基于 OSWorld qcow2 rootfs
- Docker XFCE 更新镜像，基于 Docker 基础镜像并应用同一套 Ansible delta

更完整的操作说明见 [docs/usage.md](docs/usage.md)。

## 目录结构

```text
packer/      Packer builder 定义和变量
ansible/     共享 provisioner playbook 与 roles
docker/      Docker 基础镜像和更新镜像定义
scripts/     下载、准备、构建验证和 smoke test 脚本
tests/       镜像内 smoke check
docs/        详细使用文档
downloads/   本地下载缓存，git ignored
build/       构建输出，git ignored
```

## 前置条件

本机需要：

- `packer`
- `ansible-playbook`，Windows target 还需要 WinRM 支持
- `aws` CLI 和有效 AWS 凭证
- `qemu-system-x86_64`、`qemu-img`、KVM 权限
- `virt-customize`，用于给 qcow2 base 准备 SSH
- `docker`、`guestfish`、`qemu-img`，用于 Docker rootfs 迁移
- VMware Workstation 和 `vmrun`，仅在需要完整 VMware 本地测试时使用

敏感信息只通过环境变量或 ignored var 文件传入。不要把 AWS key、私有 SSH 密码、下载的镜像、构建产物或 `.pkrvars.hcl` 提交进仓库。OSWorld 的公开默认密码会直接写在配置里：AWS 使用 `osworld-public-evaluation`，本地 Linux VM base 使用 `password`，Linux QEMU/VMware 最终产物会把 `user` 重置为 `osworld-public-evaluation`，Windows 产物保留 `Administrator` 并把它重置为 `osworld-public-evaluation`。

## 快速开始

初始化 Packer 插件：

```bash
packer init packer
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

下载 Hugging Face base image，并生成 ignored Packer var 文件：

```bash
scripts/download-base-images.sh
```

如果希望提前缓存 Packer 或 Docker update 构建用到的固定安装包，可以手动执行：

```bash
scripts/download-provision-assets.sh
```

Playbook 会优先检查 `downloads/provision/` 和 `downloads/osworld_server/` 里的 deb、AppImage、tar 归档、snap 缓存以及 OSWorld server 源码归档；脚本也会刷新 WPS 字体和 QEMU SSH deb 缓存。带 checksum 的文件会先校验再复制到目标镜像。缓存缺失时才回退到固定的上游来源。这个脚本需要用户手动跑，Packer 不会默认执行。

Linux QEMU base 默认不暴露 SSH，需要先准备一个 ignored 的 SSH-enabled qcow2 副本：

```bash
scripts/prepare-qemu-source.sh
```

本地校验：

```bash
packer validate packer
ansible-playbook --syntax-check ansible/playbook.yml
ansible-playbook --syntax-check ansible/windows-playbook.yml
bash -n scripts/*.sh tests/smoke.sh
```

## AWS 构建和验证

AWS builder 固定使用 OSWorld base AMI：

```hcl
source_ami = "ami-0d23263edb96951d8"
```

构建 AMI：

```bash
export AWS_REGION=us-east-1
packer build -only=aws.amazon-ebs.osworld packer
```

只有源 AMI 密码不同于公开默认值时，才需要覆盖 `PKR_VAR_aws_ssh_password`。

Smoke test AMI。可以提供已有 security group：

```bash
AWS_SMOKE_SECURITY_GROUP_ID=sg-... \
scripts/smoke-aws.sh ami-...
```

也可以让脚本创建并清理临时 security group：

```bash
AWS_SMOKE_ALLOW_TEMP_NETWORK=true \
scripts/smoke-aws.sh ami-...
```

## QEMU 构建和验证

构建 qcow2：

```bash
packer build -only=qemu.qemu.osworld packer
```

本地 VM builder 默认使用公开 base image 密码 `password`。只有源 qcow2 密码不同才需要覆盖 `PKR_VAR_ssh_password`。

QEMU 产物会把 `user` 密码重置为公开 OSWorld 密码：`osworld-public-evaluation`。

验证产物：

```bash
scripts/smoke-qemu.sh build/qemu-osworld-<build-id>/osworld-v2-ubuntu-x86.qcow2 user
```

## Windows QEMU 构建

Windows builder 基于 `xlangai/windows_osworld` 里的 `Windows-10-x64.qcow2.zip`，通过 WinRM provision：

```bash
packer build -only=windows.qemu.windows_osworld packer
```

Windows playbook 只做 Windows 需要的增量：安装 WPS Office `12.2.0.23131`，替换同一个 pinned OSWorld server commit，把 `C:\OSWorld\desktop_env\server\main.exe` 重新构建成无可见控制台窗口，关闭 Windows 隐私/OOBE 首次登录提示并把隐私选项设为 off，并把 `Administrator` 密码和 AutoAdminLogon 更新为 `osworld-public-evaluation`。

## VMware 构建

VMware builder 从下载解压出的 `.vmx` 派生：

```bash
packer build -only=vmware.vmware-vmx.osworld packer
```

本地 VM builder 默认使用公开源 VM 密码 `password`。只有源 VM 密码不同才需要覆盖 `PKR_VAR_ssh_password`。

VMware 产物也会把 `user` 密码重置为 `osworld-public-evaluation`。

完整 VMware 本地 smoke test 需要 `vmrun`。如果当前机器没有 VMware Workstation 或 `vmrun`，只能验证 builder 配置，不能完成本地运行测试。

## Docker 构建和验证

Docker 流程分两层。基础层从 qcow2 导入 rootfs，移除 VM/GNOME/systemd 相关内容，安装 XFCE、supervisor 和 noVNC，并保留原 desktop user 与 server 布局。更新层基于该基础镜像，用 `target_platform=docker` 执行同一套 Ansible delta。

构建并运行 Docker 基础镜像：

```bash
scripts/build-docker-base.sh
scripts/run-docker-base.sh
scripts/smoke-docker-base.sh
```

构建并运行 Docker 更新镜像：

```bash
scripts/build-docker-update.sh
scripts/run-docker-update.sh
scripts/smoke-docker-update.sh
CONTAINER_NAME=osworld-xfce scripts/smoke-docker-base.sh
```

Docker 目标会刻意跳过 snapd/snap，因为镜像不运行 systemd。如果 Docker 中需要 Audacity，应新增 deb/AppImage 安装路径，而不是重新启用 snapd。

## 应用增量

Ansible playbook 会安装或验证以下版本：

- Obsidian `1.10.6`
- Audacity `3.7.5`
- Shotcut `26.2.26`
- XMind `26.01.03145`
- Zotero `8.0.2`
- VM 目标额外安装 Zotero snap `9.0.1`（revision `128`），与 8 月 25 日镜像修复一致
- LabPlot `2.12.1`
- Blender `5.0.0`
- WPS Office `11.1.0.11723`
- REAPER `7.64`
- MuseScore `4.6`

单独的 Windows playbook 只安装 WPS Office `12.2.0.23131`，更新同一份 OSWorld server，隐藏 server 进程窗口，关闭 Windows 隐私/OOBE 首次登录提示，并在改密码后刷新 `Administrator` 的 Windows AutoAdminLogon。

同时会配置：

- Chrome Safe Browsing 为 no protection managed policy
- Zotero 本机通信设置及任务使用的 snap 数据库初始化
- OSWorld server，缓存存在时来自 `downloads/osworld_server/`，否则回退到 `https://github.com/xlang-ai/osworld-server`
- `/etc/X11/xorg.conf` 的 `MaxClients 2048`
- 常见 office MIME 类型默认使用 LibreOffice
- WPS symbol fonts，并通过 checksum 和 `fc-list` 验证
- QEMU 和 VMware 的 `user` 密码设置为 `osworld-public-evaluation`
- Docker runtime 通过 supervisor 启动 DBus、Xvfb、XFCE、x11vnc/noVNC 和 OSWorld server

## Smoke Check

`tests/smoke.sh` 会在镜像内检查：

- 应用版本或 pinned artifact checksum
- Chrome policy
- Zotero preference、实际启动、本机 API 和数据库完整性（[8 月 25 日修复说明及测试入口](docs/zotero-image-parity.md)）
- Xorg `MaxClients`
- LibreOffice MIME defaults
- WPS fonts
- OSWorld server commit marker

`scripts/verify-artifact.sh` 是统一入口：

```bash
scripts/verify-artifact.sh aws ami-...
scripts/verify-artifact.sh qemu build/qemu-osworld-<build-id>/osworld-v2-ubuntu-x86.qcow2 user
```

## 本地生成文件

以下路径通常是构建副产物，已通过 `.gitignore` 排除：

- `downloads/`
- `build/`
- `packer/*.auto.pkrvars.hcl`
- `packer/*.pkrvars.hcl`
- `*.qcow2`
- `*.vmdk`
- `*.vmx`
- `*.deb`
- `*.AppImage`
- `*.tar.xz`
- `*.pem`
