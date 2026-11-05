#!/usr/bin/env bash
# Katman 0: ortam kontrolu.
#
# Derlemeye baslamadan once neyin eksik oldugunu soyler ve kendi
# dagitimin icin kurulum komutunu yazar.
#
#   ./preflight.sh

FAIL=0
WARN=0

ok()   { printf '  \033[32m  OK  \033[0m %s\n' "$1"; }
bad()  { printf '  \033[31mEKSIK \033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33mUYARI \033[0m %s\n' "$1"; WARN=$((WARN+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

MISSING=()

# ---------------------------------------------------------------
# Dagitimi tespit et
# ---------------------------------------------------------------
DISTRO="bilinmiyor"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID}:${ID_LIKE:-}" in
        fedora:*|*:*fedora*|rhel:*|centos:*)  DISTRO="fedora" ;;
        debian:*|ubuntu:*|*:*debian*)         DISTRO="debian" ;;
        arch:*|*:*arch*)                      DISTRO="arch"   ;;
        opensuse*:*|*:*suse*)                 DISTRO="suse"   ;;
    esac
fi

# Paket adlari dagitimdan dagitima degisiyor.
pkg_for() {
    local tool="$1"
    case "${DISTRO}:${tool}" in
        fedora:podman) echo podman ;;
        fedora:qemu)   echo qemu-system-x86 ;;
        fedora:ovmf)   echo edk2-ovmf ;;
        fedora:cosign) echo cosign ;;
        fedora:git)    echo git ;;

        debian:podman) echo podman ;;
        debian:qemu)   echo qemu-system-x86 ;;
        debian:ovmf)   echo ovmf ;;
        debian:git)    echo git ;;

        arch:podman)   echo podman ;;
        arch:qemu)     echo qemu-system-x86_64 ;;
        arch:ovmf)     echo edk2-ovmf ;;
        arch:cosign)   echo cosign ;;
        arch:git)      echo git ;;

        suse:podman)   echo podman ;;
        suse:qemu)     echo qemu-x86 ;;
        suse:ovmf)     echo qemu-ovmf-x86_64 ;;
        suse:cosign)   echo cosign ;;
        suse:git)      echo git ;;

        *) echo "" ;;
    esac
}

install_cmd() {
    case "${DISTRO}" in
        fedora) echo "sudo dnf install -y" ;;
        debian) echo "sudo apt install -y" ;;
        arch)   echo "sudo pacman -S --needed" ;;
        suse)   echo "sudo zypper install -y" ;;
        *)      echo "" ;;
    esac
}

printf '\033[1mmfaos ortam kontrolu\033[0m\n'
printf 'Dagitim: %s (%s)\n' "${PRETTY_NAME:-bilinmiyor}" "${DISTRO}"

# ---------------------------------------------------------------
head_ "1. Zorunlu araclar"
# ---------------------------------------------------------------
need() {
    local cmd="$1" tool="$2" label="$3"
    if command -v "${cmd}" >/dev/null 2>&1; then
        ok "${label} — $(command -v "${cmd}")"
    else
        bad "${label}"
        local p; p="$(pkg_for "${tool}")"
        [[ -n "${p}" ]] && MISSING+=("${p}")
    fi
}

need podman            podman "podman (imaji derlemek icin)"
need git               git    "git"
need qemu-system-x86_64 qemu  "qemu (VM testi icin)"

# cosign cogu dagitimda paketli degil; ozel ele aliyoruz.
if command -v cosign >/dev/null 2>&1; then
    ok "cosign — $(command -v cosign)"
else
    bad "cosign (imza anahtarini uretmek icin)"
    COSIGN_MISSING=1
fi

# ---------------------------------------------------------------
head_ "2. UEFI firmware (QEMU icin)"
# ---------------------------------------------------------------
OVMF_FOUND=""
for f in \
    /usr/share/edk2/ovmf/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/qemu/ovmf-x86_64-code.bin
do
    [[ -f "${f}" ]] && { OVMF_FOUND="${f}"; break; }
done

if [[ -n "${OVMF_FOUND}" ]]; then
    ok "OVMF — ${OVMF_FOUND}"
else
    bad "OVMF (UEFI firmware)"
    p="$(pkg_for ovmf)"; [[ -n "${p}" ]] && MISSING+=("${p}")
fi

# ---------------------------------------------------------------
head_ "3. KVM erisimi"
# ---------------------------------------------------------------
# KVM olmadan VM calisir ama 10-20 kat yavas olur.
if [[ ! -e /dev/kvm ]]; then
    warn "/dev/kvm yok — sanallastirma BIOS'ta kapali olabilir (VT-x/AMD-V)"
elif [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ok "/dev/kvm erisilebilir"
else
    bad "/dev/kvm var ama erisemiyorsun"
    printf '         Duzeltmek icin: sudo usermod -aG kvm %s\n' "${USER}"
    printf '         Sonra oturumu kapatip acman gerekiyor.\n'
fi

# ---------------------------------------------------------------
head_ "4. Disk alani"
# ---------------------------------------------------------------
# Kabaca: taban imaj ~8GB, katmanlarimiz ~2GB, NVIDIA varyanti +2GB,
# image-builder ~1GB, qcow2 ciktisi ~15GB. Iki varyant derlersen daha fazla.
free_gb() { df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc '0-9'; }

HOME_FREE="$(free_gb "${HOME}")"
if [[ -n "${HOME_FREE}" ]]; then
    if   [[ "${HOME_FREE}" -ge 80 ]]; then ok "ev dizini: ${HOME_FREE}GB bos"
    elif [[ "${HOME_FREE}" -ge 50 ]]; then warn "ev dizini: ${HOME_FREE}GB bos — yeterli ama rahat degil"
    else bad "ev dizini: sadece ${HOME_FREE}GB bos — en az 50GB gerekiyor"
    fi
fi

# VM adimi `sudo podman` kullanir; o ayri bir depoya yazar.
VAR_FREE="$(free_gb /var)"
if [[ -n "${VAR_FREE}" && "${VAR_FREE}" -lt 40 ]]; then
    warn "/var: ${VAR_FREE}GB bos — VM adimi root podman deposunu kullanir, dolabilir"
elif [[ -n "${VAR_FREE}" ]]; then
    ok "/var: ${VAR_FREE}GB bos"
fi

# ---------------------------------------------------------------
head_ "5. podman calisiyor mu"
# ---------------------------------------------------------------
if command -v podman >/dev/null 2>&1; then
    if podman info >/dev/null 2>&1; then
        ok "podman calisiyor ($(podman --version | awk '{print $3}'))"
    else
        bad "podman kurulu ama calismiyor — 'podman info' ciktisina bak"
    fi
fi

# ---------------------------------------------------------------
# Ozet
# ---------------------------------------------------------------
printf '\n\033[1mSonuc:\033[0m %d eksik, %d uyari\n' "${FAIL}" "${WARN}"

if [[ ${#MISSING[@]} -gt 0 ]]; then
    IC="$(install_cmd)"
    printf '\nKurulum komutu:\n'
    if [[ -n "${IC}" ]]; then
        printf '  \033[1m%s %s\033[0m\n' "${IC}" "${MISSING[*]}"
    else
        printf '  Dagitim taninmadi. Su paketleri kur: %s\n' "${MISSING[*]}"
    fi
fi

if [[ -n "${COSIGN_MISSING:-}" ]]; then
    printf '\ncosign cogu dagitimda paketli degil. Dogrudan indir:\n'
    printf '  \033[1mcurl -sSfLo /tmp/cosign \\\n'
    printf '    https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64\n'
    printf '  sudo install -m 755 /tmp/cosign /usr/local/bin/cosign\033[0m\n'
fi

[[ "${FAIL}" -gt 0 ]] && exit 1
printf '\n\033[32mOrtam hazir. Sirada: ./test.sh all\033[0m\n'
