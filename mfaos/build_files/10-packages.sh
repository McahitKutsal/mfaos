#!/usr/bin/env bash
# Paket katmanlama: sisteme ne eklenecek, ne cikarilacak.
set -euo pipefail

# Fedora Atomic Desktop imajlarinda paket yoneticisi surume gore
# degisebiliyor. Hangisi varsa onu kullan.
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

remove_pkgs() {
    if [[ "${PKG}" == "rpm-ostree" ]]; then
        rpm-ostree override remove "$@" || true
    else
        ${PKG} remove "$@" || true
    fi
}

# ---------------------------------------------------------------
# Ekstra depolar
# ---------------------------------------------------------------
# RPM Fusion: codec'ler, NVIDIA surucuSu, bazi firmware. Lisans
# acisindan Fedora disinda; istemiyorsan bu blogu sil.
install_pkgs \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

# ---------------------------------------------------------------
# Sistem araclari
# ---------------------------------------------------------------
install_pkgs \
    distrobox \
    podman-compose \
    tmux \
    htop \
    ripgrep \
    fd-find \
    jq \
    git \
    rsync \
    nmap-ncat \
    usbguard \
    tpm2-tools \
    sbsigntools \
    cryptsetup \
    fwupd \
    audit \
    setroubleshoot-server

# ---------------------------------------------------------------
# Donanim / laptop
# ---------------------------------------------------------------
# Laptop'ta fark yaratan sey: guc yonetimi ve firmware.
install_pkgs \
    power-profiles-daemon \
    thermald \
    intel-media-driver \
    libva-utils \
    linux-firmware

# ---------------------------------------------------------------
# Cikarilacaklar
# ---------------------------------------------------------------
# Masaustunde ihtiyacin olmayan dinleyen servisler saldiri
# yuzeyidir. Burayi kendine gore genislet.
remove_pkgs \
    avahi \
    sendmail

echo "Paketler tamam."
