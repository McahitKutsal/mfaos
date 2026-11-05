#!/usr/bin/env bash
# Paket katmanlama: sisteme ne eklenecek, ne cikarilacak.
set -euo pipefail

if command -v dnf5 >/dev/null 2>&1; then
    PKG="dnf5 -y"
elif command -v dnf >/dev/null 2>&1; then
    PKG="dnf -y"
else
    PKG="rpm-ostree"
fi

install_pkgs() {
    if [[ "${PKG}" == "rpm-ostree" ]]; then
        rpm-ostree install --idempotent "$@"
    else
        ${PKG} install "$@"
    fi
}

# Taban imajda zaten kurulu olan paketleri istemek dnf5'te islemi
# komple dusuruyor. Once eleyip oyle kuruyoruz.
install_if_missing() {
    local pkg missing=()
    for pkg in "$@"; do
        rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "  (hepsi zaten kurulu: $*)"
        return 0
    fi
    echo "  kurulacak: ${missing[*]}"
    install_pkgs "${missing[@]}"
}

remove_pkgs() {
    if [[ "${PKG}" == "rpm-ostree" ]]; then
        rpm-ostree override remove "$@" || true
    else
        ${PKG} remove "$@" || true
    fi
}

echo "==> RPM Fusion depolari"
for repo in free nonfree; do
    if rpm -q "rpmfusion-${repo}-release" >/dev/null 2>&1; then
        echo "  rpmfusion-${repo}-release zaten kurulu"
    else
        install_pkgs \
            "https://mirrors.rpmfusion.org/${repo}/fedora/rpmfusion-${repo}-release-${FEDORA_VERSION}.noarch.rpm"
    fi
done

echo "==> Sistem araclari"
install_if_missing \
    distrobox podman-compose tmux htop ripgrep fd-find jq git rsync \
    nmap-ncat usbguard tpm2-tools sbsigntools cryptsetup fwupd audit \
    setroubleshoot-server

# NOT: power-profiles-daemon BILEREK yok. Fedora 41'den beri varsayilan
# guc yonetimi TuneD; taban imajdaki tuned-ppd ayni D-Bus arayuzunu
# sagliyor ve ikisi catisiyor.
echo "==> Donanim destegi"
install_if_missing \
    thermald intel-media-driver libva-utils linux-firmware

echo "==> Gereksiz paketleri kaldir"
remove_pkgs sendmail

echo "Paketler tamam."
