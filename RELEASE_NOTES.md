# v1.0.0：UFI103S V03 Debian 实机验证版

这是私有备份 Release，仅适用于 PCB 丝印 `UFI103S_V03` 的 MSM8916 设备。

## 主要内容

- Debian 11 sparse rootfs
- UFI103S 对应 GPT、CDT 与 boot chain
- 修复 MPSS 内存节点的 1.2 GHz boot image
- Linux fastboot 一键刷写脚本
- 完整 SHA-256 校验文件

## 实机结果

- Debian 与 `4G-WIFI` 热点正常
- rootfs 自动扩展至约 3.3 GB
- Qualcomm MPSS、RMTFS、ModemManager 正常
- 中国电信 LTE 注册、IPv4/IPv6、DNS 与互联网访问正常

## 强制要求

刷机前必须备份目标设备自己的 `fsc/fsg/modemst1/modemst2`，并通过 `--calibration-dir` 传给刷写脚本。Release 不包含任何设备专属校准数据。

刷写完成后物理断电再上电。默认账号 `user`、密码 `1`，热点密码 `12345678`，首次登录后必须修改。

第三方二进制来源和许可限制见 `THIRD_PARTY.md`。

