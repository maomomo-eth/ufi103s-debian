#!/usr/bin/env bash
set -Eeuo pipefail

if (($# != 2)); then
    echo "用法：sudo $0 <虚拟机名> <android|edl|fastboot|debian>" >&2
    exit 2
fi

vm_name="$1"
mode="$2"
virsh_bin="${VIRSH:-virsh}"

case "$mode" in
    android)  vendor="05c6"; product="90b4" ;;
    edl)      vendor="05c6"; product="9008" ;;
    fastboot) vendor="18d1"; product="d00d" ;;
    debian)   vendor="18d1"; product="d001" ;;
    *)
        echo "未知模式：$mode" >&2
        exit 2
        ;;
esac

xml_file="$(mktemp --tmpdir ufi103s-usb.XXXXXX.xml)"
cleanup() {
    rm -f -- "$xml_file"
}
trap cleanup EXIT

cat >"$xml_file" <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source startupPolicy='optional'>
    <vendor id='0x$vendor'/>
    <product id='0x$product'/>
  </source>
</hostdev>
EOF

"$virsh_bin" attach-device "$vm_name" "$xml_file" --live
echo "已把 $vendor:$product（$mode）映射到 $vm_name。"

