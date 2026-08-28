#!/usr/bin/env bash
set -euo pipefail

source /ctx/tb321fu/port.env

[ "${TB321FU_PORT:-0}" = 1 ] || exit 0

work=$(mktemp -d /tmp/tb321fu.XXXXXX)
trap 'rm -rf "$work"' EXIT

fetch_verified() {
    local url=$1 sha=$2 out=$3
    curl --connect-timeout 30 --max-time 600 --retry 4 -fL "$url" -o "$out"
    printf '%s  %s\n' "$sha" "$out" | sha256sum -c -
}

extract_deb_data() {
    local deb=$1 dest=$2 member
    member=$(ar t "$deb" | awk '/^data\.tar(\..+)?$/ {print; exit}')
    [ -n "$member" ] || { echo "No data archive in $deb" >&2; return 1; }
    ar p "$deb" "$member" | tar -x -C "$dest"
}

copy_tree_if_present() {
    local source=$1 dest=$2
    [ -e "$source" ] || return 0
    mkdir -p "$dest"
    rsync -aHAX "$source"/ "$dest"/
}

kernel_archive="$work/kernel.tar.gz"
device_archive="$work/device-debs.tar.gz"
kernel_extract="$work/kernel"
debs_extract="$work/debs"
payload="$work/payload"
mkdir -p "$kernel_extract" "$debs_extract" "$payload"

fetch_verified "$TB321FU_KERNEL_ARTIFACT_URL" "$TB321FU_KERNEL_ARTIFACT_SHA256" "$kernel_archive"
fetch_verified "$TB321FU_DEVICE_DEBS_URL" "$TB321FU_DEVICE_DEBS_SHA256" "$device_archive"

tar -xf "$kernel_archive" -C "$kernel_extract"
tar -xf "$device_archive" -C "$debs_extract"

image=$(find "$kernel_extract" -type f -name Image -print -quit)
dtb=$(find "$kernel_extract" -type f -name "$TB321FU_DTB_NAME" -print -quit)
[ -n "$image" ] || { echo "TB321FU kernel Image not found" >&2; exit 1; }
[ -n "$dtb" ] || { echo "TB321FU DTB $TB321FU_DTB_NAME not found" >&2; exit 1; }

while IFS= read -r -d '' deb; do
    extract_deb_data "$deb" "$payload"
done < <(find "$debs_extract" -type f -name '*.deb' -print0)

# Replace Armada's generic kernel with the verified TB321FU kernel/modules.
dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core 2>/dev/null || true
rm -rf /usr/lib/modules/*

module_src=""
for candidate in \
    "$payload/usr/lib/modules/$TB321FU_KERNEL_VERSION" \
    "$payload/lib/modules/$TB321FU_KERNEL_VERSION"; do
    if [ -d "$candidate" ]; then
        module_src=$candidate
        break
    fi
done
[ -n "$module_src" ] || { echo "TB321FU modules $TB321FU_KERNEL_VERSION not found in device payload" >&2; exit 1; }

mkdir -p "/usr/lib/modules/$TB321FU_KERNEL_VERSION/dtb"
rsync -aHAX "$module_src"/ "/usr/lib/modules/$TB321FU_KERNEL_VERSION"/
install -m 0644 "$image" "/usr/lib/modules/$TB321FU_KERNEL_VERSION/vmlinuz"
install -m 0644 "$dtb" "/usr/lib/modules/$TB321FU_KERNEL_VERSION/dtb/$TB321FU_DTB_NAME"
ln -sfn "dtb/$TB321FU_DTB_NAME" "/usr/lib/modules/$TB321FU_KERNEL_VERSION/dtb/platform.dtb"

# Import hardware payload only. Do not copy the whole Ubuntu rootfs into Fedora.
copy_tree_if_present "$payload/usr/lib/firmware" /usr/lib/firmware
copy_tree_if_present "$payload/lib/firmware" /usr/lib/firmware
copy_tree_if_present "$payload/usr/lib/udev/rules.d" /usr/lib/udev/rules.d
copy_tree_if_present "$payload/etc/udev/rules.d" /etc/udev/rules.d
copy_tree_if_present "$payload/usr/lib/systemd/system" /usr/lib/systemd/system
copy_tree_if_present "$payload/etc/systemd/system" /etc/systemd/system
copy_tree_if_present "$payload/usr/share/alsa" /usr/share/alsa
copy_tree_if_present "$payload/usr/share/alsa-card-profile" /usr/share/alsa-card-profile

# Canonical firmware aliases required by the TB321FU kernel.
mkdir -p /usr/lib/firmware/qcom/sm8650 /usr/lib/firmware/qcom/vpu
copy_first() {
    local dest=$1; shift
    [ -e "$dest" ] && return 0
    local src
    for src in "$@"; do
        if [ -f "$src" ]; then
            install -D -m 0644 "$src" "$dest"
            return 0
        fi
    done
    return 1
}
copy_first /usr/lib/firmware/qcom/gen70900_zap.mbn \
    /usr/lib/firmware/qcom/sm8650/lenovo/tb321fu/gen70900_zap.mbn || true
copy_first /usr/lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin \
    /usr/lib/firmware/qcom-tb321fu/Lenovo-Y700-TB321FU-tplg.bin || true

required=(
    /usr/lib/firmware/qcom/gen70900_aqe.fw
    /usr/lib/firmware/qcom/gen70900_sqe.fw
    /usr/lib/firmware/qcom/gen70900_zap.mbn
    /usr/lib/firmware/qcom/gmu_gen70900.bin
    /usr/lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin
    /usr/lib/firmware/qcom/vpu/vpu33_p4.mbn
)
for file in "${required[@]}"; do
    [ -e "$file" ] || { echo "Required TB321FU firmware missing: $file" >&2; exit 1; }
done

depmod -a "$TB321FU_KERNEL_VERSION" -b /
printf '%s\n' "$TB321FU_DTB_NAME" > /usr/lib/armada/tb321fu-dtb
printf '%s\n' "$TB321FU_KERNEL_VERSION" > /usr/lib/armada/tb321fu-kernel

echo "TB321FU device payload installed: kernel=$TB321FU_KERNEL_VERSION dtb=$TB321FU_DTB_NAME"
