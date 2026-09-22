# VoCat 短信转发与基带故障排查

本项目固件在 `UFI103S_V02` 和 `UFI103S_V03` 硬件上均已实测支持通过 [VoCat](https://github.com/0x7b1/vocat) 进行短信接收与转发。

> [!NOTE]
> - 本固件**不捆绑** VoCat，仅提供纯净可靠的基带驱动与端口解耦管理工具。
> - 4G 数据连接正常并不代表短信功能可用（二者在基带层分别走 PS 域与 CS/NAS 域）。

---

## 1. 端口独占机制与管理工具

Linux 下的 Qualcomm 基带通常暴露 AT 与 QMI 虚拟串口。若 ModemManager 正在运行，VoCat 启动时会因串口被占用而报错。

固件内已预装专用管理命令 `ufi103s-modemmanager`：

### 1.1 切换为 VoCat 独占模式
```bash
# 停止并屏蔽 (mask) ModemManager 服务（重启仍保持禁用）
sudo ufi103s-modemmanager disable

# 查看状态（确认 ModemManager 为 masked/inactive）
ufi103s-modemmanager status
```
> [!IMPORTANT]
> `ufi103s-modemmanager` 仅管理 ModemManager，**绝对不会停止 NetworkManager**，因此 Wi-Fi 热点/客户端和 USB RNDIS DHCP 均保持正常连接。

### 1.2 恢复系统蜂窝网络管理
若需恢复 Linux 系统的蜂窝上网能力：
```bash
# 1. 必须先停止 VoCat 释放串口
sudo systemctl stop vocat   # 或停止对应后台进程

# 2. 重新启用 ModemManager
sudo ufi103s-modemmanager enable
```

---

## 2. 常用 AT 诊断与基带自检

首次登录或遇到短信异常时，建议按顺序排查：

### 2.1 基础驱动与服务状态检查
```bash
sudo ufi103s-modem-test
```
预期关键输出：
- `MPSS` 远程处理器状态：`running`
- `rmtfs` 射频共享内存服务：`active (running)`
- Modem 设备节点存在且无 I/O 错误

### 2.2 核心 AT 检查指令 (VoCat 模式下)
若使用串口工具或 VoCat 自检，重点关注：

| AT 命令 | 用途 | 正常预期返回值 |
| :--- | :--- | :--- |
| `AT+CPIN?` | 检查 SIM 卡就绪状态 | `+CPIN: READY` |
| `AT+CSQ` | 检查信号质量 | `+CSQ: <rssi>,<ber>`（rssi > 10 为佳） |
| `AT+CREG?` / `AT+CEREG?` | 检查网络注册状态 | `+CREG: 0,1` (本地) 或 `0,5` (漫游) |
| `AT+CSCA?` | 查询短信服务中心 (SMSC) 号码 | `+CSCA: "+861380xxxx500",145` |
| `AT+CPMS?` | 查询短信存储介质首选项 | `+CPMS: "SM","SM","SM"...` |
| `AT+CMGS=...` | 发送短信确认 | 真正成功基带应返回 `+CMGS: <mr>` |

---

## 3. SIM 卡与运营商实测兼容性

以下为使用者在实际环境中的实测记录（持续更新）：

| SIM 卡类型 / 归属 | 漫游/驻留网络 | 短信接收 | 短信发送 | 备注 |
| :--- | :--- | :---: | :---: | :--- |
| **中国移动** (实体卡) | 中国移动 (原网) | ✅ 正常 | ✅ 正常 | VoCat 标准 AT/PDU 路径 |
| **中国电信** (实体卡) | 中国电信 (原网) | ❌ 无法收发 | ❌ 无法收发 | LTE 数据上网正常；但因基带版本过老不支持 VoLTE，而电信已全面普及 VoLTE，故无法收发短信 |
| **HahaSim** (香港实体卡 `+852`) | 漫游中国联通 | ✅ 正常 | - | 境外卡漫游接收验证码稳定 |
| **Saily eSIM** 小白卡 (`+1`) | 漫游中国移动 | ✅ 正常 | - | 接收验证码正常 |
| **A1 eSIM** 小白卡 (`+385`) | 漫游中国联通 | ✅ 正常 | - | 接收验证码正常 |

> [!IMPORTANT]
> **关于中国电信收不到短信的原因说明**：
> 实测中国电信卡可以建立正常的 4G LTE 数据网络（PS 域上网），但**无法收发短信**。
> 其根本原因在于：**随身 Wi-Fi 硬件搭载的基带版本过老，不支持 VoLTE（SMS over IMS）**；而中国电信目前已基本全面下线 CDMA 1X (2G/3G) 网络，短信业务全面依赖 VoLTE 承载。因此在当前基带版本下，**中国电信卡仅可作为 4G 数据上网卡，无法用于短信收发或 VoCat 转发**。若有短信转发需求，请优先使用中国移动或支持联通漫游的 SIM/eSIM 卡。

> [!WARNING]
> 遇到短信收发异常时，请先排查是否为运营商网络与 VoLTE 依赖原因。**切勿因为单张卡短信问题而盲目刷入网传的其他型号基带或校准文件**！
