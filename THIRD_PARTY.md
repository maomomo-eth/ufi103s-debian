# 第三方组件说明

私有 Release 包含来自本地第三方文件。仓库中的文档和原创脚本不改变这些第三方二进制的归属。

# Debian 12 发行镜像使用的文件

使用酷安@jsbsbxjxh66 发布的镜像包`debian12-酷安-jsbsbxjxh66` 选用了以下两个文件：

- `jsbsbxjxh66/rootfs.img`：作为最终 rootfs 的基础，修正后发布，并非原样使用。
- `jsbsbxjxh66-boot/msm8916-jsbsbxjxh66-ufix0x-1.0.dtb-boot.img`：作为发行版的 boot，文件内容未修改。
- 这份镜像包里的其他 boot 变体、刷机脚本和 Windows 工具未用于当前发行镜像；GPT、启动链及后补的 MPSS 不归为这份归档的实际选用文件。