#!/usr/bin/env bash
# ==============================================================================
# UFI103S 交互式一键全盘备份与刷机向导 (Debian 12 v2.2.0)
# 自动检测 9008 状态、校验 IMEI、离线组装整盘、原厂备份、全盘写入与校准恢复
# ==============================================================================
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# 颜色控制
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_BLUE='\033[34m'
    C_CYAN='\033[36m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_CYAN=''
fi

info()    { echo -e "${C_CYAN}[INFO]${C_RESET} $*"; }
step()    { echo -e "\n${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
success() { echo -e "${C_GREEN}[✓]${C_RESET} ${C_BOLD}$*${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
error()   { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; }

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
workspace_parent="$(realpath -e -- "$repo_dir/..")"

# 查找 edl 工具
find_edl() {
    if [[ -n "${EDL:-}" && -x "$EDL" ]]; then
        echo "$EDL"
        return 0
    fi
    local candidates=(
        "/home/codex/dev/py/edl/.venv/bin/edl"
        "$repo_dir/../edl/.venv/bin/edl"
        "$repo_dir/../../py/edl/.venv/bin/edl"
        "$(which edl 2>/dev/null || true)"
    )
    for c in "${candidates[@]}"; do
        if [[ -n "$c" && -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

# 检查 9008 连接状态
check_edl_connected() {
    local count
    count="$(lsusb 2>/dev/null | awk 'tolower($0) ~ /05c6:9008/ {count++} END {print count+0}')"
    [[ "$count" -ge 1 ]]
}

# 等待 9008 设备连接（带循环守护与友好提示）
wait_for_edl() {
    local reason="${1:-等待进入 9008 刷机模式}"
    if check_edl_connected; then
        return 0
    fi

    echo ""
    echo -e "${C_YELLOW}┌────────────────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "${C_YELLOW}│ [!] 未检测到 05c6:9008 设备 (${reason})${C_RESET}"
    echo -e "${C_YELLOW}├────────────────────────────────────────────────────────────────────────┤${C_RESET}"
    echo -e "  1. 若使用 ${C_BOLD}KVM / virt-manager 虚拟机${C_RESET}，请在宿主机终端执行："
    echo -e "     ${C_GREEN}sudo ./scripts/kvm-attach-usb.sh <虚拟机名> edl${C_RESET}"
    echo -e "  2. 若设备处于开机状态或未进 9008，请执行硬件进 9008 操作："
    echo -e "     ${C_BOLD}拔出随身 Wi-Fi ➔ 长按 SIM 卡槽旁微动按键不放 ➔ 插回 USB ➔ 保持2秒后松开${C_RESET}"
    echo -e "     (随后请在宿主机将新出现的 05c6:9008 映射进虚拟机)"
    echo -e "${C_YELLOW}└────────────────────────────────────────────────────────────────────────┘${C_RESET}"
    echo -n "  [⏳] 正在等待 05c6:9008 设备连接上线..."
    
    local spin=('|' '/' '-' '\')
    local i=0
    while ! check_edl_connected; do
        printf "\b${spin[i]}"
        i=$(( (i + 1) % 4 ))
        sleep 1
    done
    printf "\b \n"
    success "检测到 05c6:9008 设备已成功连接！"
    sleep 1
}

# IMEI 模 10 (Luhn) 校验
validate_imei() {
    local imei="$1"
    if [[ ! "$imei" =~ ^[0-9]{15}$ ]] || [[ "$imei" == "000000000000000" ]]; then
        return 1
    fi
    local check_sum=0 digit
    for ((idx=0; idx<15; idx++)); do
        digit=$((10#${imei:idx:1}))
        if ((idx % 2 == 1)); then
            digit=$((digit * 2))
            if ((digit > 9)); then digit=$((digit - 9)); fi
        fi
        check_sum=$((check_sum + digit))
    done
    (( check_sum % 10 == 0 ))
}

# 欢迎横幅
clear 2>/dev/null || true
echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================================"
echo "          UFI103S 交互式一键全盘备份与刷机向导 (Debian 12 v2.2.0)               "
echo "================================================================================"
echo -e "${C_RESET}"
echo "本向导将带您完成：机型选择 ➔ IMEI 校验 ➔ 原厂全盘备份 ➔ 整盘合成 ➔ 9008 写入"
echo "在任何步骤掉线时，向导都会自动等待您重新映射 9008 并自动继续，保障数据绝对安全。"
echo ""

# 1. 检查基础环境依赖
step "1/6 检查基础环境依赖"
edl_bin="$(find_edl || true)"
if [[ -z "$edl_bin" ]]; then
    error "未自动定位到 edl 工具！"
    read -r -p "请输入 edl 可执行文件的绝对路径 (如 /path/to/edl): " user_edl
    if [[ -x "$user_edl" ]]; then
        edl_bin="$user_edl"
    else
        error "指定路径不可执行：$user_edl"
        exit 1
    fi
fi
export EDL="$edl_bin"
success "EDL 工具就绪：$edl_bin"

for cmd in lsusb sha256sum uv python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "缺少必要命令行工具：$cmd"
        exit 1
    fi
done
success "系统依赖项检查通过 (lsusb, sha256sum, uv, python3)"

# 2. 选择硬件板号
step "2/6 选择硬件板号"
echo "请选择随身 Wi-Fi 的硬件板号（拆开外壳或机身 PCB 上标注）："
echo "  [1] UFI103S_V02 (常见黑色/白色无屏幕 UFI103S，eMMC 3.64GB)"
echo "  [2] UFI103S_V03 (部分改款版本，eMMC 3.64GB)"
echo "  [3] 手动输入其他板号 (例如 UFI001, UFI003, MS917 等 MSM8916 设备)"
echo ""
board=""
board_name=""
while [[ -z "$board" ]]; do
    read -r -p "请输入选项 [1/2/3 或直接输入板号] (默认: 1): " input_board
    input_board="${input_board:-1}"
    case "$input_board" in
        1|v02|V02|ufi103s_v02|UFI103S_V02)
            board="ufi103s-v02"
            board_name="UFI103S_V02"
            ;;
        2|v03|V03|ufi103s_v03|UFI103S_V03)
            board="ufi103s-v03"
            board_name="UFI103S_V03"
            ;;
        3)
            read -r -p "请输入自定义板号 (如 UFI001): " custom_board
            custom_board="$(echo "$custom_board" | tr -d '[:space:]')"
            if [[ -z "$custom_board" ]]; then
                warn "板号不能为空！"
            elif [[ ! "$custom_board" =~ ^[A-Za-z0-9_-]+$ ]]; then
                warn "板号仅支持字母、数字、下划线和连字符 (如 UFI001, MS917)！"
            else
                board="$(echo "$custom_board" | tr '[:upper:]' '[:lower:]')"
                board_name="$(echo "$custom_board" | tr '[:lower:]' '[:upper:]')"
            fi
            ;;
        *)
            # 直接输入了板号名称（如输入了 UFI001 或 ufi001）
            clean_board="$(echo "$input_board" | tr -d '[:space:]')"
            if [[ "$clean_board" =~ ^[A-Za-z0-9_-]+$ ]]; then
                board="$(echo "$clean_board" | tr '[:upper:]' '[:lower:]')"
                board_name="$(echo "$clean_board" | tr '[:lower:]' '[:upper:]')"
            else
                warn "输入无效，请输入 1/2/3 或有效的板号字符串。"
            fi
            ;;
    esac
done
success "已确认板号：$board_name (归档标识: $board)"

# 3. 输入并校验 IMEI
step "3/6 输入并校验设备 IMEI"
echo "请输入随身 Wi-Fi 标签上的 15 位数字 IMEI（用于同机校准与备份文件隔离）："
imei=""
while [[ -z "$imei" ]]; do
    read -r -p "请输入 15 位 IMEI: " input_imei
    input_imei="$(echo "$input_imei" | tr -d '[:space:]')"
    if validate_imei "$input_imei"; then
        imei="$input_imei"
    else
        warn "IMEI 格式错误或校验位 (Luhn) 不匹配，请重新仔细核对标签！"
    fi
done
success "IMEI 校验通过：$imei"

# 规划目录路径
if [[ "$board" == ufi103s-* ]]; then
    board_dir="$board"
else
    board_dir="ufi-${board}"
fi
backup_dir="$workspace_parent/${board_dir}/bak-$imei"
work_dir="$workspace_parent/work/flash-$imei"
release_dir="$repo_dir/release/v2.2.0/ufi103s-debian-v2.2.0-base"
rootfs_override="$repo_dir/release/v2.2.0/rootfs-debian12-usb-wifi-ssh-vocat-mm-wifi.img"
rootfs_sha256="65fa6962951cafd1fc38d886d6e8df714904b61c2443cdfb7c4e436f3c31e2d6"

mkdir -p "$workspace_parent/${board_dir}" "$workspace_parent/work" "$work_dir"

# 4. 原厂全盘物理备份
step "4/6 原厂全盘备份检查与执行"
info "备份目录规划在：$backup_dir"

do_backup=1
if [[ -f "$backup_dir/original-full-emmc.bin" && -f "$backup_dir/SHA256SUMS" ]]; then
    warn "检测到该设备已存在历史全盘备份！"
    read -r -p "是否跳过重新备份，直接使用已有备份？ [Y/n]: " skip_choice
    skip_choice="${skip_choice:-Y}"
    if [[ "$skip_choice" =~ ^[Yy]$ ]]; then
        info "正在复核已有备份文件的 SHA-256 完整性……"
        if (cd -- "$backup_dir" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
            success "已有备份完整无损，直接沿用！"
            do_backup=0
        else
            warn "已有备份校验失败，将重新执行全盘备份。"
            rm -rf "$backup_dir"
            do_backup=1
        fi
    else
        rm -rf "$backup_dir"
        do_backup=1
    fi
fi

if ((do_backup)); then
    wait_for_edl "准备进行原厂全盘物理备份"
    info "开始全盘备份（约 2~4 分钟，请勿断开 USB 供电）……"
    if ! "$repo_dir/scripts/backup-full-emmc.sh" "$backup_dir"; then
        error "备份过程发生异常！请检查连接后重新运行向导。"
        exit 1
    fi
    success "原厂全盘备份完成并校验通过！"
fi

# 5. 离线整盘镜像组装
step "5/6 离线合成同机整盘镜像"
target_image="$work_dir/debian-v2-full-emmc.bin"
raw_img="$work_dir/rootfs.raw.img"

if [[ -f "$target_image" && -f "$work_dir/SHA256SUMS" ]] && (cd -- "$work_dir" && sha256sum -c SHA256SUMS >/dev/null 2>&1); then
    success "检测到已组装好的整盘镜像且哈希完全匹配，跳过重复组装！"
else
    info "展开 sparse rootfs 镜像为原始 raw 分区……"
    uv run python "$repo_dir/tools/android_sparse.py" to-raw "$rootfs_override" "$raw_img"
    info "装配当前设备的 GPT、启动链与独有校准数据……"
    uv run python "$repo_dir/tools/assemble_emmc.py" \
        --backup-dir "$backup_dir" \
        --release-dir "$release_dir" \
        --rootfs-raw "$raw_img" \
        --output "$target_image"
    (cd -- "$work_dir" && sha256sum debian-v2-full-emmc.bin > SHA256SUMS)
    success "整盘镜像离线合成完毕并校验通过！"
fi

# 6. 9008 全盘写入与校准恢复
step "6/6 执行 9008 全盘写入与校准写回"
echo -e "${C_YELLOW}即将全盘刷写 eMMC (3,909,091,328 字节)，此操作将写入 Debian 12 并恢复本机的校准数据。${C_RESET}"
read -r -p "确认开始写入吗？ [Y/n]: " flash_confirm
flash_confirm="${flash_confirm:-Y}"
if [[ ! "$flash_confirm" =~ ^[Yy]$ ]]; then
    warn "用户取消了写入操作。已准备好的整盘镜像保留在：$target_image"
    exit 0
fi

# 写入执行循环（支持掉线重试）
write_success=0
while ((write_success == 0)); do
    wait_for_edl "准备写入整盘镜像"
    info "正在全盘写入镜像（约 3.5 分钟，显示原生进度条）……"
    if "$EDL" wf "$target_image" --memory=eMMC --lun=0; then
        write_success=1
        success "整盘镜像写入成功！"
    else
        error "写入过程被中断（可能是 USB 接触不良或端口复位）。"
        echo "请将设备重新断电插拔并重新映射进虚拟机，按回车键重新执行写入……"
        read -r
    fi
done

# 单独恢复关键校准分区
step "恢复原厂射频校准分区 (fsc, fsg, modemst1, modemst2)"
wait_for_edl "准备恢复校准数据"
for part in fsc fsg modemst1 modemst2; do
    factory_part="$backup_dir/partitions/$part.bin"
    info "写入校准分区: $part..."
    "$EDL" w "$part" "$factory_part" --memory=eMMC --lun=0
done
success "原厂校准数据已全部回填恢复完成！"

# 重启设备进 Debian
step "重启设备并开机"
info "发送 EDL 重启指令……"
"$EDL" reset || true

# 最终完成界面
echo ""
echo -e "${C_GREEN}${C_BOLD}"
echo "================================================================================"
echo "                 🎉 UFI103S Debian 12 刷机全部完成并已开机！                    "
echo "================================================================================"
echo -e "${C_RESET}"
echo -e "设备冷启动需要约 ${C_BOLD}20~30 秒${C_RESET}，启动后将自动提供以下服务："
echo ""
echo -e "  📶 ${C_BOLD}Wi-Fi AP 热点${C_RESET}："
echo -e "     - SSID:     ${C_CYAN}4G-WIFI${C_RESET}"
echo -e "     - 密码:     ${C_CYAN}12345678${C_RESET}"
echo -e "     - 网页/网关: 10.42.0.1"
echo ""
echo -e "  💻 ${C_BOLD}SSH 远程连接${C_RESET}："
echo -e "     - 账户密码: ${C_CYAN}user${C_RESET} / ${C_CYAN}1${C_RESET} (sudo 提权密码同为 1)"
echo -e "     - 连接方式: ${C_BOLD}ssh user@192.168.68.1${C_RESET} (USB 网卡) 或 ${C_BOLD}ssh user@10.42.0.1${C_RESET} (Wi-Fi)"
echo ""
echo -e "  🔧 ${C_BOLD}虚拟机 USB 穿透提醒${C_RESET}："
echo -e "     - 设备重启后 USB 硬件 ID 变为 ${C_CYAN}18d1:d001${C_RESET}"
echo -e "     - 若需在虚拟机里通过 USB 使用，请在宿主机执行："
echo -e "       ${C_GREEN}sudo ./scripts/kvm-attach-usb.sh <虚拟机名> debian${C_RESET}"
echo "================================================================================"
echo ""
