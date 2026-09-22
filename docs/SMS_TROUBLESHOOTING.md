# VoCat 短信转发与 modem 端口

使用者已在 `UFI103S_V02`、`UFI103S_V03` 上实测刷入 Debian、安装 VoCat 后正常转发短信。是否支持**某张卡/运营商**取决于驻网、短信中心和该卡的短信业务；LTE 有数据不等于短信一定可用。本仓库不捆绑 VoCat，也不修改它的配置。

## 先诊断，再移交端口

初次 SSH 登录先执行镜像自带的只读脚本：

```bash
sudo ufi103s-modem-test
```

预期 MPSS 为 `running`，`rmtfs`、ModemManager 为 `active`，有可见 modem。脚本不会向 modem 发 AT 指令，也不会写 NV/校准分区。切换 VoCat 前请停止使用 ModemManager 的其他程序，避免两个程序同时占用 AT/QMI。应停止 ModemManager 而不是 NetworkManager。

v2.2.0 镜像已内置 `ufi103s-modemmanager`，不需要另行下载或安装。准备让 VoCat 独占 modem 时执行：

```bash
sudo ufi103s-modemmanager disable
ufi103s-modemmanager status
```

`disable` 会 `mask` 并停止 ModemManager，防止 D-Bus 自动拉起；保留 NetworkManager 及其管理的热点和 USB DHCP，但现有蜂窝数据连接可能断开。恢复时**先停止 VoCat**，再执行 `sudo ufi103s-modemmanager enable`。直接执行 `systemctl stop ModemManager` 不够持久；重启后仍可能自动恢复。不要在公开日志或 Issue 中粘贴 IMEI、ICCID、IMSI、手机号或完整短信内容。

## Wi‑Fi 上网与热点的选择

- 默认 Wi‑Fi 是热点，USB 网关 `192.168.68.1` 可用于 SSH；保留 NetworkManager 管理热点和 USB DHCP。禁用 ModemManager 后不要假定原有蜂窝数据连接仍可上网。
- 如果自行把 `wlan0` 改成 Wi‑Fi **客户端**给 VoCat 联网，保留管理这条连接的 NetworkManager，只用 `ufi103s-modemmanager disable` 释放 modem。
- 改无线连接前保留 USB/ADB 登录路径；同一无线电是否支持热点+客户端并发不能假定。

## 已知的短信测试边界

| SIM/网络 | 本次结果 |
| --- | --- |
| 中国移动 | VoCat 普通 AT/PDU 路径，收发正常 |
| 中国电信 | LTE 数据正常，但本次短信测试未建立可用的 CS 短信路径；不能据数据连接判断短信可用 |
| Saily eSIM 小白卡（`+1` 号码） | 漫游中国移动，接收正常 |
| A1 eSIM 小白卡（`+385` 号码） | 漫游中国联通，接收正常 |
| HahaSim 实体 SIM（`+852` 号码） | 漫游中国联通，接收正常 |

以上只说明当时设备、卡与所在地区的结果；漫游卡仅核对接收，不推断发送一定成功。查询短信问题时可先确认 SIM ready、`AT+CREG?`/`AT+CEREG?`、`AT+CSCA?`、`AT+CPMS?` 和 `AT+CNMI?`，并查看 VoCat 的端口占用/发送结果。中国移动发送成功时有 modem 返回 `+CMGS`，只看前端提示不足以证明基带真正接受短信。

任何恢复 `modem`、`fsc/fsg/modemst1/modemst2` 的动作都必须使用**本机原厂备份**，先检查镜像、分区大小与对应关系；不要因为短信失败而盲目覆盖 NV，更不要复制别的设备的基带/校准数据。请优先回到 [9008 备份与刷机指南](FLASHING.md) 核对来源。
