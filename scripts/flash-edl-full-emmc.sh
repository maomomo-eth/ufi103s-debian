#!/usr/bin/env bash
# 原厂完整备份 → 组装同机 Debian v2 整盘镜像 → 9008 写盘 → 恢复本机校准 → 整盘回读。
set -Eeuo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
umask 077

usage() {
    cat <<'EOF'
用法：
  ./scripts/flash-edl-full-emmc.sh \
    --backup-dir /绝对路径/本机原厂全盘备份 \
    --release-dir /绝对路径/ufi103s-debian-v2.2.0-base \
    --output-dir /仓库外的全新私有目录 [--yes] [--reset] \
    --rootfs-override /绝对路径/实测rootfs.img --rootfs-sha256 64位摘要

选项：
  --prepare-only    只组装并验证整盘镜像，不连接设备、不写入 eMMC
  --reflash-debian   仅用于已安装本仓库 Debian 的同机重刷；核对 Debian GPT、原机 EDL 串号和 fsc
  --force-no-serial  配合 --reflash-debian：原厂日志缺少串号时跳过串号核对；必须交互确认机身 IMEI
  --loader FILE     指定与目标设备匹配的 Firehose loader
  --yes             跳过普通模式的写盘确认；不能与 --force-no-serial 同用
  --reset           完成整盘回读后发送 EDL reset；默认停在 9008
  --rootfs-override 指定 Release 中单独下载的 rootfs；不修改基础包
  --rootfs-sha256   必须同时提供 rootfs 的 SHA-256

环境变量：EDL=/绝对路径/edl

只支持原厂 GPT 与本仓库 UFI103S V02/V03 实测布局一致、eMMC 容量为
3909091328 字节的设备。完整备份、校准文件、工作目录均不得放入 Git。
EOF
}

backup_dir=""
release_dir=""
output_dir=""
loader=""
rootfs_override=""
rootfs_sha256=""
prepare_only=0
assume_yes=0
reset_after=0
reflash_debian=0
force_no_serial=0
while (($#)); do
    case "$1" in
        --backup-dir|--release-dir|--output-dir|--loader|--rootfs-override|--rootfs-sha256)
            if (($# < 2)) || [[ -z "$2" ]]; then
                echo "参数缺少路径：$1" >&2
                exit 2
            fi
            case "$1" in
                --backup-dir) backup_dir="$2" ;;
                --release-dir) release_dir="$2" ;;
                --output-dir) output_dir="$2" ;;
                --loader) loader="$2" ;;
                --rootfs-override) rootfs_override="$2" ;;
                --rootfs-sha256) rootfs_sha256="$2" ;;
            esac
            shift 2
            ;;
        --prepare-only) prepare_only=1; shift ;;
        --reflash-debian) reflash_debian=1; shift ;;
        --force-no-serial) force_no_serial=1; shift ;;
        --yes) assume_yes=1; shift ;;
        --reset) reset_after=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$backup_dir" || -z "$release_dir" || -z "$output_dir" ]]; then
    usage >&2
    exit 2
fi
if ((prepare_only && reset_after)); then
    echo "--prepare-only 不能与 --reset 同时使用。" >&2
    exit 2
fi
if ((force_no_serial && !reflash_debian)); then
    echo '--force-no-serial 必须与 --reflash-debian 同用。' >&2
    exit 2
fi
if ((force_no_serial && (prepare_only || assume_yes))); then
    echo '--force-no-serial 不能与 --prepare-only 或 --yes 同用；离线组装无需强刷选项。' >&2
    exit 2
fi
if ((force_no_serial)) && [[ ! -t 0 ]]; then
    echo '--force-no-serial 必须从交互式终端执行，以便人工核对机身 IMEI。' >&2
    exit 2
fi
if [[ -z "$rootfs_override" || ! "$rootfs_sha256" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo '必须指定 rootfs 路径及有效的 64 位 SHA-256。' >&2
    exit 2
fi
for program in uv sha256sum cmp lsusb rg; do
    command -v "$program" >/dev/null 2>&1 || { echo "缺少工具：$program" >&2; exit 1; }
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
backup_dir="$(realpath -e -- "$backup_dir")"
release_dir="$(realpath -e -- "$release_dir")"
rootfs_override="$(realpath -e -- "$rootfs_override")"
if ((force_no_serial)); then
    backup_name="$(basename -- "$backup_dir")"
    if [[ ! "$backup_name" =~ ^bak-([0-9]{15})$ ]]; then
        echo '强刷要求原厂备份目录命名为 bak- 后接机身标签的 15 位 IMEI。' >&2
        exit 2
    fi
    backup_imei="${BASH_REMATCH[1]}"
fi
[[ -f "$rootfs_override" && -s "$rootfs_override" ]] || {
    echo "rootfs 文件无效：$rootfs_override" >&2; exit 1;
}
output_parent="$(realpath -e -- "$(dirname -- "$output_dir")")"
output_dir="$output_parent/$(basename -- "$output_dir")"
repo_root="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$repo_root" && "$output_dir/" == "$repo_root/"* ]]; then
    echo "拒绝把包含设备数据的输出写入 Git 仓库：$output_dir" >&2
    exit 1
fi
if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    echo "输出目录已经存在，拒绝覆盖：$output_dir" >&2
    exit 1
fi
if [[ ! -s "$backup_dir/SHA256SUMS" || ! -s "$release_dir/SHA256SUMS" ]]; then
    echo "原厂备份和 Release 必须各自具有 SHA256SUMS 清单。" >&2
    exit 1
fi
if [[ ! -w "$output_parent" ]]; then
    echo "输出目录的父目录不可写：$output_parent" >&2
    exit 1
fi
echo "校验原厂全盘备份及 Release SHA-256……"
(cd -- "$backup_dir" && sha256sum -c SHA256SUMS >/dev/null)
(cd -- "$release_dir" && sha256sum -c SHA256SUMS >/dev/null)
actual_rootfs_sha256="$(sha256sum -- "$rootfs_override")"
actual_rootfs_sha256="${actual_rootfs_sha256%% *}"
if [[ "${actual_rootfs_sha256,,}" != "${rootfs_sha256,,}" ]]; then
    echo 'rootfs SHA-256 不匹配，拒绝刷写。' >&2
    exit 1
fi
rootfs_image="$rootfs_override"
echo "已验证 rootfs：$rootfs_image"

edl_bin="${EDL:-edl}"
if ((prepare_only == 0)); then
    command -v "$edl_bin" >/dev/null 2>&1 || { echo "找不到 EDL 工具：$edl_bin" >&2; exit 1; }
    if [[ -n "$loader" && ! -s "$loader" ]]; then
        echo "Firehose loader 不存在或为空：$loader" >&2
        exit 1
    fi
    edl_count="$( { lsusb -d 05c6:9008 || true; } | awk 'END {print NR+0}')"
    if [[ "$edl_count" != 1 ]]; then
        echo "必须且只能映射一台 05c6:9008 设备，当前数量：$edl_count" >&2
        exit 1
    fi
fi

disk_bytes=3909091328
rootfs_raw_bytes=1048576000
required_bytes=$((disk_bytes * 2 + rootfs_raw_bytes + 512 * 1024 * 1024))
available_bytes="$(df -PB1 "$output_parent" | awk 'NR==2 {print $4}')"
if ((available_bytes < required_bytes)); then
    echo "空间不足：至少需要 $required_bytes 字节，当前仅 $available_bytes 字节。" >&2
    exit 1
fi

mkdir -m 700 -- "$output_dir"
on_error() {
    local status=$?
    echo "操作中断（退出码 $status）。私有现场保留在：$output_dir" >&2
    echo "如果已经开始写盘，请保持 9008，不要启动尚未通过回读校验的设备。" >&2
    exit "$status"
}
trap on_error ERR

image="$output_dir/debian-v2-full-emmc.bin"
readback="$output_dir/device-readback.bin"
raw="$output_dir/rootfs.raw.img"
echo "展开 sparse rootfs 并组装整盘镜像……"
uv run python "$repo_dir/tools/android_sparse.py" to-raw \
    "$rootfs_image" "$raw"
uv run python "$repo_dir/tools/assemble_emmc.py" \
    --backup-dir "$backup_dir" --release-dir "$release_dir" \
    --rootfs-raw "$raw" --output "$image"
(cd -- "$output_dir" && sha256sum debian-v2-full-emmc.bin > SHA256SUMS && sha256sum -c SHA256SUMS >/dev/null)

if ((prepare_only)); then
    echo "只完成了镜像准备和校验；没有连接或写入设备：$image"
    exit 0
fi

edl_options=(--memory=eMMC --lun=0)
reset_options=()
if [[ -n "$loader" ]]; then
    edl_options+=("--loader=$loader")
    reset_options+=("--loader=$loader")
fi
test "$( { lsusb -d 05c6:9008 || true; } | awk 'END {print NR+0}')" -eq 1
"$edl_bin" printgpt "${edl_options[@]}" > "$output_dir/preflight-printgpt.log" 2>&1
reported_hex="$(sed -n 's/^Total disk size:\(0x[0-9A-Fa-f]*\).*/\1/p' "$output_dir/preflight-printgpt.log" | tail -n 1)"
if [[ -z "$reported_hex" ]] || ((reported_hex != disk_bytes)); then
    echo "9008 设备容量不匹配，拒绝写盘。" >&2
    exit 1
fi
"$edl_bin" rs 0 34 "$output_dir/target-gpt-before.bin" "${edl_options[@]}" \
    > "$output_dir/preflight-gpt-readback.log" 2>&1
test "$(stat -c '%s' "$output_dir/target-gpt-before.bin")" -eq $((34 * 512))
if ((reflash_debian)); then
    expected_gpt="$image"
else
    expected_gpt="$backup_dir/original-full-emmc.bin"
fi
if ! cmp -n $((34 * 512)) "$expected_gpt" \
    "$output_dir/target-gpt-before.bin" >/dev/null; then
    echo '当前设备 GPT 与本次刷机模式期望的布局不一致，拒绝写盘；请核对设备及 --reflash-debian 参数。' >&2
    exit 1
fi
# GPT 在多台设备上可能一致；默认核对串号，显式强刷只能由人工核对机身身份。
# Debian GPT 没有 persist 分区；运行中的基带可能更新 fsg 和 modemst1/2，
# 因此已装 Debian 的设备不能用这些旧备份文件做逐字节身份判定。
if ((reflash_debian)); then
    if ((force_no_serial)); then
        echo '强刷：不核对原厂 EDL 串号；GPT、容量和 fsc 仍须通过检查。'
    else
        original_edl_log="$backup_dir/edl-printgpt.log"
        [[ -s "$original_edl_log" ]] || {
            echo '原厂备份没有 EDL 硬件串号日志；可了解 --force-no-serial 的风险后显式强刷。' >&2; exit 1;
        }
        original_serial="$(sed -n 's/^[[:space:]]*Serial:[[:space:]]*\(0x[[:xdigit:]]*\).*/\1/p' "$original_edl_log" | head -n 1)"
        current_serial="$(sed -n 's/^[[:space:]]*Serial:[[:space:]]*\(0x[[:xdigit:]]*\).*/\1/p' "$output_dir/preflight-printgpt.log" | head -n 1)"
        if [[ -z "$original_serial" || "$original_serial" == 0x0 || "$original_serial" != "$current_serial" ]]; then
            echo '当前设备 EDL 硬件串号与原厂备份不一致，拒绝写盘。' >&2; exit 1;
        fi
    fi
    identity_partitions=(fsc)
else
    # 首次刷机必须在备份后、原系统重新启动前执行，校验当时的 NV 状态。
    identity_partitions=(modemst1 modemst2 persist)
fi
for partition in "${identity_partitions[@]}"; do
    "$edl_bin" r "$partition" "$output_dir/target-$partition-before.bin" "${edl_options[@]}" \
        > "$output_dir/preflight-$partition.log" 2>&1
    if ! cmp -s "$backup_dir/partitions/$partition.bin" \
        "$output_dir/target-$partition-before.bin"; then
        echo "当前设备的 $partition 与这份原厂备份不同，拒绝写盘；请核对设备并重新备份。" >&2
        exit 1
    fi
done

if ((force_no_serial)); then
    cat <<EOF
警告：EDL 硬件串号未核对，GPT、容量和 fsc 均无法证明正在连接的设备就是这份备份所属设备。
本仓库的 V02/V03 原厂备份中 fsc 与 fsg 相同，绝不能把它们当作同机身份凭证。
错误地刷入其他设备的原厂 NV/校准数据，可能导致基带、IMEI 或射频异常。
请直接核对手中设备的机身标签；不要照抄备份目录名或本屏幕内容。
EOF
    read -r -p '输入机身标签上的 15 位 IMEI：' confirmed_imei
    if [[ "$confirmed_imei" != "$backup_imei" ]]; then
        echo '机身标签 IMEI 与原厂备份目录不一致，拒绝写盘。' >&2
        exit 1
    fi
fi

cat <<EOF
即将覆盖当前设备的全部 $disk_bytes 字节 eMMC（包括 GPT、系统和原有数据）。
原厂备份：$backup_dir
目标镜像：$image
此步骤不可撤销；请确认没有把其他设备的 9008 映射进来。
EOF
if ((assume_yes == 0)); then
    read -r -p '输入 UFI103S-EDL-ERASE 才开始写盘：' confirmation
    if [[ "$confirmation" != "UFI103S-EDL-ERASE" ]]; then
        echo "已取消写盘；准备好的镜像仍保留在：$image"
        exit 1
    fi
fi

echo "从 9008 写入整块 eMMC；请保持供电和 USB 连接……"
"$edl_bin" wf "$image" "${edl_options[@]}" > "$output_dir/full-write.log" 2>&1
rg -q 'Wrote .* to sector 0\.' "$output_dir/full-write.log"
rg -q '100\.0% Write' "$output_dir/full-write.log"
"$edl_bin" printgpt "${edl_options[@]}" > "$output_dir/after-write-printgpt.log" 2>&1
for partition in rootfs boot fsc fsg modemst1 modemst2; do
    rg -q "^$partition:" "$output_dir/after-write-printgpt.log"
done

echo "从同一台设备的原厂备份单独恢复校准数据……"
for partition in fsc fsg modemst1 modemst2; do
    factory="$backup_dir/partitions/$partition.bin"
    "$edl_bin" w "$partition" "$factory" "${edl_options[@]}" \
        > "$output_dir/restore-$partition.log" 2>&1
    rg -q 'Wrote .* to sector' "$output_dir/restore-$partition.log"
    "$edl_bin" r "$partition" "$output_dir/readback-$partition.bin" "${edl_options[@]}" \
        > "$output_dir/readback-$partition.log" 2>&1
    cmp -n "$(stat -c '%s' "$factory")" "$factory" \
        "$output_dir/readback-$partition.bin" >/dev/null
    echo "已回读确认：$partition"
done

echo "回读整块 eMMC，逐字节核对；这一步可能需要几分钟……"
"$edl_bin" rf "$readback" "${edl_options[@]}" > "$output_dir/full-readback.log" 2>&1
test "$(stat -c '%s' "$readback")" -eq "$disk_bytes"
cmp "$image" "$readback"
echo "整盘回读与目标镜像逐字节一致，刷写验证完成。"
if ((reset_after)); then
    "$edl_bin" reset "${reset_options[@]}" > "$output_dir/after-verify-reset.log" 2>&1
    echo "已发送 EDL reset；请确认 Debian USB 或热点真正启动。"
else
    echo "设备仍停留在 9008；可在确认后手动执行 edl reset 或物理断电再上电。"
fi
echo "保留原厂备份与本次私有回读：$backup_dir；$output_dir"
