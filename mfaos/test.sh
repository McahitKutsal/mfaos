#!/usr/bin/env bash
# Yerel derleme ve test.
#
#   ./test.sh build    -> imaji derle
#   ./test.sh verify   -> imajin icerigini dogrula (hizli)
#   ./test.sh shell    -> imaja konteyner olarak gir
#   ./test.sh vm       -> qcow2 uret ve QEMU'da gercekten boot et
#   ./test.sh all      -> build + verify
#
# NVIDIA varyanti icin basina VARIANT=nvidia koy:
#   VARIANT=nvidia ./test.sh all
set -euo pipefail

VARIANT="${VARIANT:-base}"
if [[ "${VARIANT}" == "nvidia" ]]; then
    IMAGE_NAME="${IMAGE_NAME:-mfaos-nvidia}"
    NVIDIA_ENABLED=1
else
    IMAGE_NAME="${IMAGE_NAME:-mfaos}"
    NVIDIA_ENABLED=0
fi

FEDORA_VERSION="${FEDORA_VERSION:-44}"
TAG="localhost/${IMAGE_NAME}:${FEDORA_VERSION}"
OUT_DIR="$(pwd)/output"

# ---------------------------------------------------------------
build() {
    echo "==> ${TAG} derleniyor (NVIDIA=${NVIDIA_ENABLED})"
    podman build \
        --build-arg="FEDORA_VERSION=${FEDORA_VERSION}" \
        --build-arg="NVIDIA_ENABLED=${NVIDIA_ENABLED}" \
        --build-arg="OS_NAME=${IMAGE_NAME}" \
        -t "${TAG}" \
        -f Containerfile \
        .
    echo "==> Tamam: ${TAG}"
}

# Derlemenin basarili bitmesi, istedigin seyin imaja girdigi anlamina
# gelmez: scriptlerdeki `|| true`'lar hatalari yutar. Bu adim onu yakalar.
verify() {
    echo "==> ${TAG} dogrulaniyor"
    podman run --rm \
        -v "$(pwd)/verify.sh:/verify.sh:ro" \
        --entrypoint /bin/bash \
        "${TAG}" /verify.sh
}

shell() {
    podman run --rm -it --entrypoint /bin/bash "${TAG}"
}

# ---------------------------------------------------------------
# UEFI firmware'i dagitima gore farkli yerde duruyor.
find_ovmf() {
    local code vars
    for code in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        /usr/share/qemu/ovmf-x86_64-code.bin
    do
        [[ -f "${code}" ]] || continue
        for vars in \
            "${code/CODE/VARS}" \
            "${code/code/vars}" \
            /usr/share/edk2/ovmf/OVMF_VARS.fd \
            /usr/share/OVMF/OVMF_VARS_4M.fd
        do
            if [[ -f "${vars}" ]]; then
                echo "${code}:${vars}"
                return 0
            fi
        done
    done
    return 1
}

vm() {
    mkdir -p "${OUT_DIR}"

    local ovmf
    if ! ovmf="$(find_ovmf)"; then
        echo "HATA: OVMF (UEFI firmware) bulunamadi." >&2
        echo "  Fedora:        sudo dnf install edk2-ovmf" >&2
        echo "  Debian/Ubuntu: sudo apt install ovmf" >&2
        echo "  Arch:          sudo pacman -S edk2-ovmf" >&2
        exit 1
    fi
    local ovmf_code="${ovmf%%:*}" ovmf_vars="${ovmf##*:}"

    # Imaji rootless podman ile derledik (~/.local/share/containers),
    # ama image-builder root olarak calisir ve root'un deposuna bakar
    # (/var/lib/containers). Aktarmazsan "image not found" alirsin.
    if ! sudo podman image exists "${TAG}" 2>/dev/null; then
        echo "==> Imaj root deposuna aktariliyor (birkac dakika surer)"
        podman save "${TAG}" | sudo podman load
    fi

    echo "==> Disk imaji uretiliyor (birkac dakika surer)"
    sudo podman run --rm -it --privileged \
        --security-opt label=type:unconfined_t \
        -v "${OUT_DIR}":/output \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v "$(pwd)/disk-config.toml":/config.toml:ro \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 --local --config /config.toml \
        "${TAG}"

    local qcow="${OUT_DIR}/qcow2/disk.qcow2"
    # NVRAM yazilabilir olmali: bootloader acilis kaydini oraya yazar.
    # Salt okunur birakirsan yeniden baslatma davranisini test edemezsin.
    local nvram="${OUT_DIR}/OVMF_VARS.local.fd"
    [[ -f "${nvram}" ]] || cp "${ovmf_vars}" "${nvram}"

    echo "==> Baslatiliyor: ${qcow}"
    qemu-system-x86_64 \
        -M q35 -cpu host -enable-kvm \
        -m 4096 -smp 4 \
        -drive if=pflash,format=raw,readonly=on,file="${ovmf_code}" \
        -drive if=pflash,format=raw,file="${nvram}" \
        -drive file="${qcow}",if=virtio,format=qcow2 \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
        -display gtk
}

case "${1:-build}" in
    build)  build ;;
    verify) verify ;;
    shell)  shell ;;
    vm)     vm ;;
    all)    build && verify ;;
    *)      echo "Kullanim: $0 {build|verify|shell|vm|all}"; exit 1 ;;
esac
