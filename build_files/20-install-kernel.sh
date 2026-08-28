#!/bin/bash
set -euxo pipefail

# The TB321FU port intentionally uses the verified Lenovo Y700 kernel/device
# payload from ubuntu-y700-build-ci instead of Armada's generic kernel package.
if [ -f /ctx/tb321fu/port.env ]; then
    # shellcheck disable=SC1091
    source /ctx/tb321fu/port.env
    if [ "${TB321FU_PORT:-0}" = 1 ]; then
        bash /ctx/tb321fu/install-device-payload.sh
        exit 0
    fi
fi

shopt -s nullglob
tarballs=(/packages/kernel/armada-kernel-*.tar.zst)
if [ "${#tarballs[@]}" -ne 1 ]; then
    echo "ERROR: expected exactly one kernel tarball, found ${#tarballs[@]}" >&2
    printf '  %s\n' "${tarballs[@]}" >&2
    exit 1
fi

TARBALL="${tarballs[0]}"
KVER="${TARBALL##*/armada-kernel-}"
KVER="${KVER%.tar.zst}"
CHECKSUM="${TARBALL}.sha256"

dnf5 -y remove kernel kernel-core kernel-modules kernel-modules-core 2>/dev/null || true
rm -rf /usr/lib/modules/*

[ -f "${CHECKSUM}" ] || { echo "ERROR: kernel checksum missing at ${CHECKSUM}"; exit 1; }
( cd /packages/kernel && sha256sum -c "$(basename "${CHECKSUM}")" )

tar --extract --zstd -f "${TARBALL}" -C /usr/
depmod -a "${KVER}" -b /

mkdir -p /usr/lib/firmware
cp -a /ctx/system_files/usr/lib/firmware/. /usr/lib/firmware/

echo "armada kernel ${KVER} installed at /usr/lib/modules/${KVER}/"
ls -la "/usr/lib/modules/${KVER}/" | head -10
