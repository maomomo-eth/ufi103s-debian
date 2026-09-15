# UFI103S V03 短信、基带与 ModemManager 排障记录

本文记录一台 `UFI103S_V03` 在 Debian 12 下排查驻网不稳定、短信收发失败和 MPSS/NV 恢复的实机结论。文中不包含手机号、ICCID、IMSI、IMEI、设备地址、私人网络配置或设备回读文件。

## 先看结论

- 同一台设备、同一套 Debian/MPSS 和同一条 VoCat AT 短信链路，使用中国移动 SIM 时，短信接收和发送均实测正常。
- 中国电信在本机上可以注册 LTE、建立数据连接，但短信测试中 CS 注册不可用，不能因为“流量能用”就判断短信也受支持。该结果与 OpenStick 410 对电信短信兼容性有限的社区经验一致。
- 中国移动的短信经普通 `cellular_at` 路径完成，不需要为了短信强开 VoLTE/IMS。本机 MPSS 未暴露可用的 IMS/IMSA QMI 服务，强制 `SMS on IMS=true` 返回不支持。
- VoCat 与 ModemManager 不应同时接管同一组 AT/QMI 端口。让其中一个独占 modem，可消除端口竞争这一干扰变量。
- 原机 `modem.bin`、`fsc`、`fsg`、`modemst1`、`modemst2` 可以作为恢复材料，但必须来自当前这台设备。不能把别的设备的 NV/校准分区混刷进来。

## 本次运营商对照

| SIM/网络 | 驻网表现 | 短信结果 | 判断 |
| --- | --- | --- | --- |
| 中国移动本地卡 | LTE 注册，CS/PS 可用 | 接收、发送均正常 | 硬件、卡槽、VoCat AT 收发链路正常 |
| 中国电信 | LTE/EPS 和数据连接可用，短信测试时 CS 不可用 | AT/QMI 发送失败，未收到短信 | 当前 OpenStick 410/MPSS 组合不应视为支持电信短信 |
| Saily eSIM 小白卡（`+1` 美国号码） | 漫游接入中国移动 | 接收正常；本次仅确认接收 | 中国移动漫游下行短信正常 |
| A1 eSIM 小白卡（`+385` 克罗地亚号码） | 漫游接入中国联通 | 接收正常；本次仅确认接收 | 中国联通漫游下行短信正常 |

这组对照只能说明上述 SIM 在本次环境中的结果，不代表所有地区、套餐和漫游合作网络都会相同。

表中的 `+1` 和 `+385` 仅表示号码国家码，未记录或提交完整手机号、ICCID、IMSI 等 SIM 标识。

## 短信状态的最小检查集

先停止可能占用 AT 端口的另一个管理程序，再通过正确的 AT 端口查询：

```text
AT
AT+CPIN?
AT+CREG?
AT+CEREG?
AT+CSMS?
AT+CSCA?
AT+CPMS?
AT+CNMI?
AT+CGSMS?
```

重点解释：

- `CPIN: READY` 只说明 SIM 应用可用，不代表已经具备短信业务。
- `CREG` 反映 CS 域状态，`CEREG` 反映 EPS/LTE 状态。只有 LTE 数据注册不能证明传统短信路径可用。
- `CSCA` 应返回运营商下发的短信中心地址；公开日志时应避免附带其他卡或用户信息。
- `CPMS` 和 `CMGL` 可判断短信是否真的进入 `SM`/`ME` 存储。如果两处都是零且 QMI 的 UIM/NV 列表也为空，VoCat 没有可读取的短信。
- `CNMI: 2,1,0,0,0` 表示新短信存储后用 `+CMTI` 通知，是本次成功接收时使用的配置。
- `CGSMS` 选择移动发起短信的首选域。本机把 `AT+CGSMS=1` 改为 `AT+CGSMS=0` 后继续测试；该设置主要影响发送，不能解释一条入站短信为什么没有到达存储，而且冷启动后可能恢复默认值。

发送成功不能只看前端气泡。至少应看到 modem 返回 `+CMGS`，或应用日志明确记录 submission accepted。本次中国移动发送测试同时得到 modem 接受证据和成功的 API 状态。

## VoCat 与 ModemManager 的所有权

本仓库默认镜像使用 ModemManager/NetworkManager 管理蜂窝网络。如果改由 VoCat 直接操作 AT 和 QMI，应让 ModemManager 忽略该设备，并关闭 NetworkManager 中旧 `modem` 连接的自动连接：

```bash
sudo nmcli connection modify modem connection.autoconnect no
```

udev 规则应使用设备路径、驱动或可靠的父设备属性精确匹配，并设置：

```text
ENV{ID_MM_DEVICE_IGNORE}="1"
```

不要写成忽略系统中所有 `wwan`、`rpmsg` 或 USB modem 的全局规则。应用规则后可保持 ModemManager 服务运行，但 `mmcli -L` 不应再列出由 VoCat 独占的设备。

要恢复 ModemManager 测试，应停止 VoCat、撤销针对该设备的 ignore 规则、重新加载 udev，再让 ModemManager 重新探测。测试结束后恢复原来的单一所有者，避免两个进程同时读写 AT/QMI。

## 驻网不稳定时不要连续强制注册

这代 MPSS 从 DMS `online` 返回后通常需要几十秒完成被动注册。连续执行以下操作容易把问题放大：

- 反复切换飞行模式；
- 立即发起多次 NAS 搜网或重新注册；
- 在 NetworkManager 自动连接期间重复运行 `nmcli connection up modem`；
- 在一次 `AT+CMGS` 尚未完成时再次发送。

实测中，停止在 DMS online 后立即追加注册操作，让 modem 自行完成驻网，注册状态更稳定。换入新 SIM 后还应确认管理程序没有因为“新卡保护策略”把 radio 留在飞行模式。

## `modem.bin` 在 Debian 中如何使用

原 Android 备份中的 `modem.bin` 是 FAT16 文件系统镜像，固件位于其中的 `image/` 目录。可以先在电脑上只读提取并检查：

```bash
7z l modem.bin
mkdir -p modem-extracted
7z x modem.bin -omodem-extracted
sha256sum modem-extracted/image/mba.mbn
sha256sum modem-extracted/image/modem.mdt
```

本仓库的 Debian GPT 没有独立 `modem` 分区，Linux remoteproc 从 `/lib/firmware` 加载 `mba.mbn`、`modem.mdt` 和 `modem.b*`。因此不要把 Android 的 64 MiB `modem.bin` 写到一个大小相近但用途不同的分区。

覆盖前必须备份当前目录：

```bash
sudo tar -C /lib/firmware -cpf /安全位置/lib-firmware-before.tar .
```

如果决定恢复原机 `modem.bin` 中的完整 `image/`，需要注意其中还可能包含 `wcnss.*`、`cmnlib.*`、`keymaste.*`、`playread.*`、`widevine.*`。覆盖 `wcnss.*` 会影响 Wi-Fi/蓝牙固件，必须准备 USB/串口等失联后的恢复手段，并在写入后完整断电重启。

## 恢复 `fsc/fsg/modemst1/modemst2`

这些分区可能包含设备身份、射频校准和运行时 NV，只能恢复当前设备自己的备份。刷写前至少完成以下检查：

```bash
sha256sum -c SHA256SUMS
readlink -f /dev/disk/by-partlabel/fsc
readlink -f /dev/disk/by-partlabel/fsg
readlink -f /dev/disk/by-partlabel/modemst1
readlink -f /dev/disk/by-partlabel/modemst2
sudo blockdev --getsize64 /dev/disk/by-partlabel/fsc
sudo blockdev --getsize64 /dev/disk/by-partlabel/fsg
sudo blockdev --getsize64 /dev/disk/by-partlabel/modemst1
sudo blockdev --getsize64 /dev/disk/by-partlabel/modemst2
```

不要在脚本中固定使用 `mmcblk0p7` 之类的编号，应优先使用 `by-partlabel`，并在写入前比较镜像和目标分区大小。如果二者不同，应停止并调查，不能默认补零、截断或扩展。

写入 NV 前应停止 VoCat、ModemManager 和 MPSS。remoteproc 编号可能在不同启动之间变化，必须通过 `name` 找到 MPSS，不能假定它永远是 `remoteproc0`：

```bash
for rp in /sys/class/remoteproc/remoteproc*; do
    printf '%s: ' "$rp"
    cat "$rp/name"
done
```

UFI103S V03 的 MPSS 名称为 `4080000.remoteproc`。确认设备、备份和尺寸后，才可以使用 `dd ... conv=fsync,notrunc` 写入对应的 `by-partlabel` 设备。写完必须 `sync`、按镜像长度回读计算 SHA-256，并完整断电重启。

本次备份里的 `fsg/modemst1/modemst2` 镜像为 1.5 MiB，而 Debian GPT 中目标分区为 2 MiB；只有在事先确认剩余 512 KiB 本来全零后才按原布局恢复。这个例外不能复制到其他设备或其他备份。

## 为什么本次不能证明“重刷 NV 修好了短信”

写入前的逐字节比较已经确认：

- 当前 `mba.mbn + modem.*` 与原机 `modem.bin` 中的蜂窝 MPSS 文件一致；
- `fsc` 完全一致；
- `fsg/modemst1/modemst2` 的前 1.5 MiB 与原机备份一致，剩余区域全零。

也就是说，重新写入并没有改变蜂窝 MPSS 或有效 NV 内容。完整复制 `modem.bin/image` 时，变化主要是补入当前 `/lib/firmware` 缺少的其他固件文件，并替换了不同的 `wcnss.*`。

重刷后又把测试卡从中国电信换成了中国移动，因此“恢复备份”和“更换运营商”是两个同时变化的变量。中国移动短信成功证明设备链路可用，但不能证明重复写入相同 NV 是修复原因。

## WMS 卡死与恢复

故障期间观察到过以下 MPSS fatal：

```text
smd_dsm_memcpy.c:297
coex_interface.c:530
```

也出现过 AT `CMGS/CMGF` 超时，以及原生 QMI WMS 请求长时间不返回。遇到这种情况：

1. 停止所有自动重试和另一个 modem 管理程序；
2. 保存 VoCat/ModemManager 日志和 `journalctl -k`；
3. 确认发送结果没有 modem acceptance，不能把超时记为发送成功；
4. 优先重启 MPSS 或整机恢复状态，不要连续写 NV；
5. 恢复后先验证 SIM、DMS online、CS/EPS 注册，再只发送一条测试短信。

## 推荐的对照顺序

1. 先把 SIM 放进手机，确认该卡本身能在当前位置接收短信。
2. 在 UFI103S 上检查 SIM ready、CS/EPS 注册和 SMSC。
3. 保证 VoCat 与 ModemManager 只有一个拥有 modem。
4. 向设备发送一条短信，同时检查 `+CMTI`、`SM/ME` 和 QMI UIM/NV。
5. 从设备发送一条短信，确认 `+CMGS` 或等价的 modem 接受证据。
6. 更换已知可用的运营商 SIM 做同机对照。
7. 只有 firmware 哈希不匹配、NV 明确损坏或已排除运营商因素时，才考虑恢复原机备份。

## 隐私边界

公开 Issue、日志和截图前必须删除或遮盖：

- 手机号及联系人；
- ICCID、IMSI、IMEI、序列号；
- 设备 IP、SSH 信息、Wi-Fi 凭据；
- APN 用户名和密码；
- Bot Token、API Key、Cookie 和认证头；
- `fsc/fsg/modemst1/modemst2`、完整 eMMC、设备回读 rootfs。

即使日志工具已经部分打码，也要在发布前再次人工检查。
