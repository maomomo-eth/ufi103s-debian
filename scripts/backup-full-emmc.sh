#!/usr/bin/env bash
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8

usage() {
    cat <<'EOF'
用法：
  ./scripts/backup-full-emmc.sh [选项] /仓库外/板号/bak-15位IMEI

备份目录必须命名为 bak-<15位IMEI>；先从机身标签或原系统核对 IMEI。
9008 模式无法仅凭目录名核实正在连接的设备身份，请勿猜测 IMEI。

选项：
  --loader FILE       指定 Qualcomm Firehose loader
  --reset             备份成功后发送 EDL reset
  --skip-usb-check    跳过 05c6:9008 检查，仅用于特殊环境或测试
  -h, --help          显示帮助

环境变量：
  EDL=/绝对路径/edl
  LSUSB=/绝对路径/lsusb
EOF
}

loader=""
reset_after_backup=0
skip_usb_check=0
target_dir=""

while (($#)); do
    case "$1" in
        --loader)
            loader="${2:-}"
            shift 2
            ;;
        --reset)
            reset_after_backup=1
            shift
            ;;
        --skip-usb-check)
            skip_usb_check=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "未知参数：$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$target_dir" ]]; then
                echo "只能指定一个备份目录。" >&2
                exit 2
            fi
            target_dir="$1"
            shift
            ;;
    esac
done

if [[ -z "$target_dir" ]]; then
    usage >&2
    exit 2
fi

backup_name="$(basename -- "$target_dir")"
if [[ ! "$backup_name" =~ ^bak-([0-9]{15})$ ]]; then
    echo '备份目录必须命名为 bak- 后接 15 位 IMEI。' >&2
    exit 2
fi
imei="${BASH_REMATCH[1]}"
if [[ "$imei" == 000000000000000 ]]; then
    echo 'IMEI 不能全为 0；请核对设备标签。' >&2
    exit 2
fi
check_sum=0
for ((index=0; index<15; index++)); do
    digit=$((10#${imei:index:1}))
    if ((index % 2 == 1)); then
        digit=$((digit * 2))
        if ((digit > 9)); then digit=$((digit - 9)); fi
    fi
    check_sum=$((check_sum + digit))
done
if ((check_sum % 10 != 0)); then
    echo 'IMEI 校验位不正确，请重新核对设备标签。' >&2
    exit 2
fi

edl_bin="${EDL:-edl}"
lsusb_bin="${LSUSB:-lsusb}"

if ! command -v "$edl_bin" >/dev/null 2>&1 && [[ ! -x "$edl_bin" ]]; then
    echo "找不到 EDL 工具：$edl_bin" >&2
    exit 1
fi

if ((skip_usb_check == 0)); then
    if ! command -v "$lsusb_bin" >/dev/null 2>&1 && [[ ! -x "$lsusb_bin" ]]; then
        echo "找不到 lsusb：$lsusb_bin" >&2
        exit 1
    fi
    edl_count="$($lsusb_bin | awk 'tolower($0) ~ /05c6:9008/ {count++} END {print count+0}')"
    if [[ "$edl_count" != "1" ]]; then
        echo "必须且只能连接一个 05c6:9008 EDL 设备，当前数量：$edl_count" >&2
        exit 1
    fi
fi

if [[ -n "$loader" && ! -s "$loader" ]]; then
    echo "loader 不存在或为空：$loader" >&2
    exit 1
fi

if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    echo "目标已存在，为避免覆盖而退出：$target_dir" >&2
    exit 1
fi

target_parent="$(dirname -- "$target_dir")"
if [[ ! -d "$target_parent" || ! -w "$target_parent" ]]; then
    echo "目标父目录不存在或不可写：$target_parent" >&2
    exit 1
fi
target_parent="$(realpath -e -- "$target_parent")"
target_dir="$target_parent/$backup_name"
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$target_dir/" == "$repo_root/"* ]] \
    || [[ "$(git -C "$target_parent" rev-parse --is-inside-work-tree 2>/dev/null || true)" == true ]]; then
    echo '拒绝把含 IMEI 和校准数据的备份放入 Git 仓库。' >&2
    exit 1
fi

edl_options=(--memory=eMMC)
if [[ -n "$loader" ]]; then
    edl_options+=("--loader=$loader")
fi

mkdir -m 700 -- "$target_dir"
mkdir -m 700 -- "$target_dir/gpt" "$target_dir/partitions"

on_error() {
    status=$?
    echo "备份失败，已保留现场文件：$target_dir" >&2
    echo "请勿把不完整备份用于恢复。" >&2
    exit "$status"
}
trap on_error ERR

echo "读取设备信息与 GPT……"
"$edl_bin" printgpt "${edl_options[@]}" | tee "$target_dir/edl-printgpt.log"

disk_hex="$({ sed -n 's/^Total disk size:\(0x[0-9A-Fa-f]*\).*/\1/p' "$target_dir/edl-printgpt.log" || true; } | tail -n 1)"
if [[ -z "$disk_hex" ]]; then
    echo "无法从 EDL 输出解析 eMMC 容量。" >&2
    exit 1
fi
disk_bytes=$((disk_hex))
if ((disk_bytes < 512 * 1024 * 1024)); then
    echo "解析出的 eMMC 容量异常：$disk_bytes 字节" >&2
    exit 1
fi

available_bytes="$(df -PB1 "$target_parent" | awk 'NR == 2 {print $4}')"
required_bytes=$((disk_bytes + 512 * 1024 * 1024))
if ((available_bytes < required_bytes)); then
    echo "空间不足：至少需要 $required_bytes 字节，当前可用 $available_bytes 字节。" >&2
    exit 1
fi

cat >"$target_dir/BACKUP_INFO.txt" <<EOF
backup_format=ufi103s-edl-full-emmc
created_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
imei=$imei
disk_bytes=$disk_bytes
disk_hex=$disk_hex
usb_mode=05c6:9008
full_image=original-full-emmc.bin
EOF

echo "保存 GPT……"
"$edl_bin" gpt "$target_dir/gpt" "${edl_options[@]}"

echo "读取完整 eMMC，共 $disk_bytes 字节；此过程可能需要较长时间……"
"$edl_bin" rf "$target_dir/original-full-emmc.bin" "${edl_options[@]}"

actual_bytes="$(stat -c '%s' "$target_dir/original-full-emmc.bin")"
if [[ "$actual_bytes" != "$disk_bytes" ]]; then
    echo "全盘镜像大小错误：预期 $disk_bytes，实际 $actual_bytes" >&2
    exit 1
fi

critical_partitions=(
    DDR aboot abootbak boot cdt devinfo fsc fsg hyp hypbak modem
    modemst1 modemst2 persist rpm rpmbak sbl1 sbl1bak sec tz tzbak
)

echo "额外导出当前 GPT 中存在的关键分区……"
for partition in "${critical_partitions[@]}"; do
    if grep -Eq "^${partition}:" "$target_dir/edl-printgpt.log"; then
        "$edl_bin" r "$partition" "$target_dir/partitions/$partition.bin" "${edl_options[@]}"
    fi
done

echo "生成 SHA-256 清单……"
(
    cd -- "$target_dir"
    find . -type f ! -name SHA256SUMS -print0 \
        | sort -z \
        | xargs -0 sha256sum > SHA256SUMS
    sha256sum -c SHA256SUMS
)

chmod -R go-rwx -- "$target_dir"
trap - ERR

if ((reset_after_backup == 1)); then
    echo "发送 EDL reset……"
    if ! "$edl_bin" reset "${edl_options[@]}"; then
        echo "备份已完成，但 EDL reset 失败；请手动物理断电重启。" >&2
    fi
fi

cat <<EOF

完整备份成功：$target_dir
全盘镜像大小：$actual_bytes 字节
SHA-256 清单：$target_dir/SHA256SUMS

BACKUP_INFO.txt 和 EDL 日志可能包含硬件标识；整个目录必须私密保存。
建议再复制一份到另一块存储介质，并重新执行 sha256sum -c SHA256SUMS。
EOF
