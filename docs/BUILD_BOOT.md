# 重建修复版 boot

Release 已包含实机验证的 `boot-1.2-modem-fixed.img`。本页用于审计和复现该修复，不是普通刷机必需步骤。

依赖：

```bash
sudo apt install device-tree-compiler patch
```

假设原始第三方 1.2 GHz boot 名为 `1.2.img`：

```bash
python3 tools/extract_boot_dtb.py 1.2.img vendor-1.2.dtb
dtc -I dtb -O dts -o vendor-1.2.dts vendor-1.2.dtb
patch vendor-1.2.dts < tools/1.2-add-mpss.patch
dtc -I dts -O dtb -o vendor-1.2-modem-fixed.dtb vendor-1.2.dts
python3 tools/build_patched_boot.py \
  1.2.img \
  vendor-1.2-modem-fixed.dtb \
  boot-1.2-modem-fixed.img
```

预期输入 SHA-256：

```text
1.2.img  f6901678a1b7c060962955cf25c2c299801d8b8f5cc81658332a625a47970395
```

预期输出 SHA-256：

```text
boot-1.2-modem-fixed.img  720db87d583c19f4c9bb0744bf9f153acc97d08e707779226accf89f3da3af96
```

结构校验结果：

- Android boot image 总大小仍为 `16150528` 字节
- kernel 前缀逐字节不变
- ramdisk 起始偏移仍为 `9504768`
- ramdisk 及后续内容逐字节不变
- DTB 从 `49477` 字节变为 `49716` 字节
- kernel size 字段从 `9500833` 更新为 `9501072`
- DTB 中没有加入 1.3/1.4 GHz OPP

