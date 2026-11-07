#!/usr/bin/env bash
# Yerel derleme ve test.
#
#   ./test.sh build    -> imaji derle
#   ./test.sh verify   -> imajin icerigini dogrula (hizli)
#   ./test.sh shell    -> imaja konteyner olarak gir
#   ./test.sh vm       -> qcow2 uret ve QEMU'da gercekten boot et
#   ./test.sh all      -> build + verify
#   ./test.sh boot     -> build + verify + vm (bastan sona tek komut)
#
# Ortam degiskenleri:
#   VARIANT=nvidia    NVIDIA varyantini derle
#   SECURE_BOOT=1     VM'i Secure Boot acik firmware ile baslat (Faz 3)
#   DISK_CONFIG=...   baska bir bootc-image-builder yapilandirmasi
#                     (varsayilan: disk-config.test.toml — test hesapli)
#   REBUILD_DISK=1    qcow2'yi onbellekten degil yeniden uret
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

# CI bu degeri build-arg olarak geciyor; yerelde de gecmezsek nvidia
# varyantinin imaji icinde MFAOS_IMAGE_REF yanlis depoyu gosterir.
IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io/mcahitkutsal}"

# VM testi, sudo yetkili `test` hesabini iceren AYRI yapilandirmayi
# kullanir. disk-config.toml (gercek kurulum) o hesabi icermiyor.
DISK_CONFIG="${DISK_CONFIG:-disk-config.test.toml}"

# SECURE_BOOT=1 ./test.sh vm  -> Secure Boot acik firmware ile baslat.
# Faz 3 (MOK, sbctl, module.sig_enforce) ancak boyle test edilebilir.
SECURE_BOOT="${SECURE_BOOT:-0}"

# ---------------------------------------------------------------
build() {
    echo "==> ${TAG} derleniyor (NVIDIA=${NVIDIA_ENABLED})"
    podman build \
        --build-arg="FEDORA_VERSION=${FEDORA_VERSION}" \
        --build-arg="NVIDIA_ENABLED=${NVIDIA_ENABLED}" \
        --build-arg="OS_NAME=${IMAGE_NAME}" \
        --build-arg="IMAGE_REF=${IMAGE_REGISTRY}/${IMAGE_NAME}" \
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
#
# SECURE_BOOT=1 ise imzali firmware varyantini ariyoruz. Faz 3'un
# tamami — MOK ile nvidia modulu imzalama, sbctl, module.sig_enforce —
# ancak Secure Boot acik bir makinede dogrulanabilir.
find_ovmf() {
    local code vars
    local -a codes vars_extra
    if [[ "${SECURE_BOOT}" == "1" ]]; then
        codes=(
            /usr/share/edk2/ovmf/OVMF_CODE.secboot.fd
            /usr/share/OVMF/OVMF_CODE_4M.secboot.fd
            /usr/share/OVMF/OVMF_CODE.secboot.fd
            /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
            /usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd
        )
        # Anahtarlari kayitli NVRAM sablonu. Bos bir VARS ile firmware
        # setup moduna duser ve Secure Boot kapali gibi davranir.
        vars_extra=(
            /usr/share/edk2/ovmf/OVMF_VARS.secboot.fd
            /usr/share/OVMF/OVMF_VARS_4M.ms.fd
            /usr/share/OVMF/OVMF_VARS.ms.fd
            /usr/share/edk2/x64/OVMF_VARS.4m.fd
        )
    else
        codes=(
            /usr/share/edk2/ovmf/OVMF_CODE.fd
            /usr/share/OVMF/OVMF_CODE_4M.fd
            /usr/share/OVMF/OVMF_CODE.fd
            /usr/share/edk2/x64/OVMF_CODE.4m.fd
            /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
            /usr/share/qemu/ovmf-x86_64-code.bin
        )
        vars_extra=(
            /usr/share/edk2/ovmf/OVMF_VARS.fd
            /usr/share/OVMF/OVMF_VARS_4M.fd
        )
    fi

    for code in "${codes[@]}"; do
        [[ -f "${code}" ]] || continue
        for vars in "${code/CODE/VARS}" "${code/code/vars}" "${vars_extra[@]}"; do
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
    local local_id rootful_id
    local_id="$(podman image inspect --format '{{.Id}}' "${TAG}" 2>/dev/null || true)"
    rootful_id="$(sudo podman image inspect --format '{{.Id}}' "${TAG}" 2>/dev/null || true)"

    if [[ -z "${local_id}" ]]; then
        echo "HATA: ${TAG} yok. Once: ./test.sh build" >&2
        return 1
    fi

    if [[ "${local_id}" != "${rootful_id}" ]]; then
        echo "==> Imaj root deposuna aktariliyor (birkac dakika surer)"
        podman save "${TAG}" | sudo podman load
    else
        echo "==> Root deposundaki imaj guncel"
    fi

    local qcow="${OUT_DIR}/qcow2/disk.qcow2"
    local marker="${OUT_DIR}/.built-from"

    if [[ -f "${qcow}" && -f "${marker}" \
          && "$(cat "${marker}")" == "${local_id}" \
          && "${REBUILD_DISK:-0}" != "1" ]]; then
        echo "==> Disk imaji guncel (REBUILD_DISK=1 ile yeniden uret)"
    else
        echo "==> Disk imaji uretiliyor (birkac dakika surer)"
        sudo podman run --rm -it --privileged \
            --security-opt label=type:unconfined_t \
            -v "${OUT_DIR}":/output \
            -v /var/lib/containers/storage:/var/lib/containers/storage \
            -v "$(pwd)/${DISK_CONFIG}":/config.toml:ro \
            quay.io/centos-bootc/bootc-image-builder:latest \
            --type qcow2 --config /config.toml \
            "${TAG}"

        sudo chown -R "$(id -u):$(id -g)" "${OUT_DIR}"
        echo "${local_id}" > "${marker}"
    fi
    # NVRAM yazilabilir olmali: bootloader acilis kaydini oraya yazar.
    # Salt okunur birakirsan yeniden baslatma davranisini test edemezsin.
    #
    # Dosya adi moda gore ayri: Secure Boot'lu ve Secure Boot'suz NVRAM
    # birbirinin yerine kullanilamaz. Ayni dosyayi paylasirlarsa mod
    # degistirdiginde firmware hic acilmaz.
    local nvram="${OUT_DIR}/OVMF_VARS.local.fd"
    [[ "${SECURE_BOOT}" == "1" ]] && nvram="${OUT_DIR}/OVMF_VARS.secboot.local.fd"
    [[ -f "${nvram}" ]] || cp "${ovmf_vars}" "${nvram}"

    # Secure Boot, SMM ve "secure" pflash olmadan UYGULANMAZ. Bu iki
    # ayar yoksa imzali firmware acilir ama imza kontrolu yapmaz — yani
    # testin gecmesi hicbir sey kanitlamaz, en kotu test turu.
    local machine="q35"
    local -a sb_args=()
    if [[ "${SECURE_BOOT}" == "1" ]]; then
        machine="q35,smm=on"
        # Surucu adi (cfi.pflash01) nokta iceriyor, bu yuzden kisa
        # `-global surucu.ozellik=deger` bicimi KULLANILAMAZ: QEMU ilk
        # noktadan boluyor ve suruculeri "cfi" sanip hata veriyor. Uzun
        # bicim zorunlu; buradaki virguller QEMU'nun -global sozdizimi,
        # dizi ayraci degil.
        # shellcheck disable=SC2054
        sb_args=(
            -global driver=cfi.pflash01,property=secure,value=on
            -global ICH9-LPC.disable_s3=1
        )
        echo "==> Secure Boot ACIK (${ovmf_code##*/})"
    fi

    echo "==> Baslatiliyor: ${qcow}"
    # QEMU penceresinde calismak eziyet: kaydirma yok, kopyala-yapistir
    # yok. 2222 yonlendirmesi, VM icinde bir kez sshd acildiktan sonra
    # WSL terminalinden calismayi mumkun kiliyor. sshd imajda bilerek
    # kapali (20-hardening.sh); feda edilebilir test VM'inde acmak
    # sorun degil, gercek makinede acma.
    echo "    VM icinde bir kez: sudo systemctl enable --now sshd"
    echo "    sonra WSL'den:     ssh -p 2222 test@localhost  (parola: test)"
    qemu-system-x86_64 \
        -M "${machine}" -cpu host -enable-kvm \
        -m 4096 -smp 4 \
        "${sb_args[@]}" \
        -drive if=pflash,format=raw,readonly=on,file="${ovmf_code}" \
        -drive if=pflash,format=raw,file="${nvram}" \
        -drive file="${qcow}",if=virtio,format=qcow2 \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -display gtk
}

case "${1:-build}" in
    build)  build ;;
    verify) verify ;;
    shell)  shell ;;
    vm)     vm ;;
    all)    build; verify ;;
    boot)   build; verify; vm ;;
    *)      echo "Kullanim: $0 {build|verify|shell|vm|boot|all}"; exit 1 ;;
esac
