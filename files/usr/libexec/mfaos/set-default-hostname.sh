#!/usr/bin/env bash
# Makine adini os-release'deki DEFAULT_HOSTNAME'e cekiyor.
#
# Neden gerekiyor: adi initramfs'in systemd'si koyuyor, KENDI
# os-release'ine gore, ve orada DEFAULT_HOSTNAME yok — initramfs temel
# imajdan geliyor, yani bizim markalama adimimizdan once uretilmis.
# Olculen satirlar (monotonic 2.23, initrd-*.target'lardan hemen once):
#   systemd[1]: No hostname configured, using default hostname.
#   systemd[1]: Hostname set to <fedora>.
# Gercek kokun systemd'si "ad zaten ayarli" diye uzerine YAZMIYOR, bu
# yuzden os-release'e DEFAULT_HOSTNAME yazmak tek basina yetmiyor.
# Cekirdek argumani da yok: `systemd.hostname` dizgisi systemd 259
# ikilisinde bulunmuyor, yani o yol hic mevcut degil.
#
# Statik ad varsa buraya hic gelinmiyor: unit'te
# ConditionPathExists=!/etc/hostname var. Kullanici Ayarlar'dan adi
# degistirdiyse /etc/hostname olusuyor ve onun secimi kaliyor.
set -euo pipefail

want="$(. /usr/lib/os-release 2>/dev/null; printf '%s' "${DEFAULT_HOSTNAME:-}")"
if [[ -z "${want}" ]]; then
    echo "os-release'de DEFAULT_HOSTNAME yok, ad oldugu gibi birakiliyor"
    exit 0
fi

# `hostname` ikilisi ayri bir pakette; /proc her zaman var.
cur="$(cat /proc/sys/kernel/hostname 2>/dev/null || true)"
if [[ "${cur}" == "${want}" ]]; then
    echo "ad zaten ${want}"
    exit 0
fi

echo "makine adi: ${cur:-?} -> ${want}"
exec hostnamectl --transient set-hostname "${want}"
