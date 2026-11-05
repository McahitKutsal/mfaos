#!/usr/bin/env bash
# Sertlestirme: varsayilanlari guvenli tarafa cek.
set -euo pipefail

# ---------------------------------------------------------------
# SELinux
# ---------------------------------------------------------------
# Fedora'da zaten enforcing; yanlislikla permissive'e dusmesin diye
# konfigurasyonu imaja sabitliyoruz.
if [[ -f /etc/selinux/config ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

# ---------------------------------------------------------------
# Gereksiz servisleri kapat
# ---------------------------------------------------------------
# Masaustunde SSH dinlemesine gerek yok. Lazimsa makine bazinda
# `systemctl enable --now sshd` ile acarsin.
systemctl disable sshd.service 2>/dev/null || true

# Denetim gunlugu acik kalsin — olay sonrasi inceleme icin tek
# gercek kaynagin bu.
systemctl enable auditd.service 2>/dev/null || true

# Firmware guncellemeleri
systemctl enable fwupd-refresh.timer 2>/dev/null || true

# ---------------------------------------------------------------
# Guvenlik duvari: varsayilan olarak her seyi reddet
# ---------------------------------------------------------------
if command -v firewall-offline-cmd >/dev/null 2>&1; then
    firewall-offline-cmd --set-default-zone=block || true
fi

# ---------------------------------------------------------------
# Kok hesabi kilitle
# ---------------------------------------------------------------
# Yonetim sudo uzerinden. Kurtarma icin bootloader + kurtarma
# parolasi (Faz 3'te TPM yanina koydugumuz) var.
passwd -l root 2>/dev/null || true

echo "Sertlestirme tamam."
