# Debian 12 发行镜像使用的第三方文件

从 `debian12-jsbsbxjxh66.7z`（SHA-256：`e03ef31e2f7e314ffc0a11da42b3068dbca6ac34102b123e807738283cf1f4ef`）中，实际选用了以下两个文件；路径均为归档内的相对路径：

1. `debian12-酷安-jsbsbxjxh66/jsbsbxjxh66/rootfs.img`（SHA-256：`9d8ba302f5a717b5e7423987930c984a0c776e9382b7a035c7526a8d35c2f505`）。作为 Debian 12 rootfs 的输入；补齐 MPSS、清理预生成身份并加入 USB/Wi‑Fi/SSH 配置后，形成发布的 `rootfs-debian12-usb-wifi-ssh-local-network.img`。发布文件与原始文件**不相同**。
2. `debian12-酷安-jsbsbxjxh66/jsbsbxjxh66-boot/msm8916-jsbsbxjxh66-ufix0x-1.0.dtb-boot.img`（SHA-256：`4d992bb0210a4cb7ce371a378e35580b7d21b5764a2573c73e56805a2ee32af5`）。发布包中的 `boot-debian12-6.4-ufix0x.img` 与它逐字节相同。

这份归档里的其他 boot 变体、刷机脚本和 Windows 工具未用于当前发行镜像；GPT、启动链及后补的 MPSS 不归为这份归档的实际选用文件。
