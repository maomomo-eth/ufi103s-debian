# 第三方组件说明

私有 Release 包含来自本地第三方归档的 Debian rootfs、Qualcomm firmware、bootloader 和 kernel。原始批处理文件标注作者为 `jsbsbxjxh66`。

仓库中的文档和原创脚本不改变这些第三方二进制的归属。

Debian 11 第三方归档 SHA-256：

```text
1ec268a72c679d0126d4b94f93141efa6d0220eebfcfa8ec8324e83a340e2593
```

Debian 12 第三方归档：

```text
文件：debian12-jsbsbxjxh66.7z
SHA-256：e03ef31e2f7e314ffc0a11da42b3068dbca6ac34102b123e807738283cf1f4ef
```

`v2.0.0` 的 boot 和 rootfs 以 Debian 12 归档为基础。Debian 12 原始 rootfs 缺少完整 MPSS 文件，因此从已验证的 Debian 11 rootfs 复用了 `mba.mbn`、`modem.mdt` 和 `modem.b*` 文件集。GPT 与启动链文件经逐文件比较，与实机验证通过的 Debian 11 基线一致。

发布构建没有使用设备分区回读或设备运行中的 rootfs；目标设备自己的校准数据和网络配置未进入发布包。
