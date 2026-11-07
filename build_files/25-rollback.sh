#!/usr/bin/env bash
# Katman 4'un eksik parcasi: basarisiz boot sonrasi otomatik geri donus.
#
# bootc bunu KENDI BASINA YAPMIYOR. "Yeni deployment acilmazsa eskisine
# don" davranisi greenboot'tan geliyor: zorunlu saglik kontrolleri
# gecmezse GRUB'un boot_counter sayaci her denemede iner, sifira
# varinca onceki deployment acilir.
set -euo pipefail

PKG="dnf5 -y"; command -v dnf5 >/dev/null 2>&1 || PKG="dnf -y"

install_if_missing() {
    local pkg missing=()
    for pkg in "$@"; do rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}"); done
    [[ ${#missing[@]} -eq 0 ]] && { echo "  (zaten kurulu)"; return 0; }
    echo "  kurulacak: ${missing[*]}"
    ${PKG} install "${missing[@]}"
}

echo "==> greenboot"
# greenboot-default-health-checks BILEREK kurulmuyor. Icindeki
# required.d/01_repository_dns_check.sh masaustune uygun degil:
#
#   1. /etc/ostree/remotes.d yoksa dogrudan `exit 1` veriyor. bootc ile
#      kurulan makinede kaynak bir konteyner registry'si, ostree remote
#      degil — o dizin bos olabilir ya da hic olmayabilir. O durumda
#      SAGLIKLI her acilis "kirmizi" sayilir ve makine surekli geri doner.
#   2. Depo alan adlarinin DNS cozumlemesini zorunlu kiliyor. Laptop agsiz
#      acilir (ucak, captive portal, wifi henuz tanimsiz); bunu boot
#      basarisizligi saymak kendi eliyle kesinti uretmektir.
#
# Yerine masaustune uygun kendi kontrollerimiz var:
#   files/usr/lib/greenboot/check/{required,wanted}.d/50-mfaos-*.sh
#
# O paketi yine de istersen /etc/greenboot/greenboot.conf icinde
# DISABLED_HEALTHCHECKS=("01_repository_dns_check.sh") ile eleyebilirsin.
install_if_missing greenboot

# Kontrol scriptleri files/ ile geliyor. Calistirma biti git uzerinden
# (ozellikle Windows'tan) garanti degil; burada sabitliyoruz.
chmod 0755 /usr/lib/greenboot/check/required.d/*.sh \
           /usr/lib/greenboot/check/wanted.d/*.sh

# greenboot-set-rollback-trigger.service OLMADAN saglik kontrolu calisir
# ama GERI DONUS OLMAZ: boot_counter'i deployment stage edilirken kuran
# parca o (unit'te RequiredBy=ostree-finalize-staged.service).
# healthcheck unit'indeki `Also=` zaten onu da etkinlestiriyor; iki
# servisi acikca yazmak niyeti belgeliyor.
systemctl enable greenboot-healthcheck.service \
                 greenboot-set-rollback-trigger.service 2>/dev/null || true

# `systemctl enable`in cikis kodu konteynerde guvenilir degil; gercek
# kosulu — sembolik baglarin olusup olusmadigini — kendimiz kontrol
# ediyoruz. Bu adim sessizce basarisiz olursa geri donus hic calismaz
# ve bunu ancak bozuk bir guncellemede, en kotu anda ogrenirsin.
for unit in greenboot-healthcheck.service greenboot-set-rollback-trigger.service; do
    if find /etc/systemd/system /usr/lib/systemd/system \
         -name "${unit}" -type l 2>/dev/null | grep -q .; then
        echo "  ${unit} etkin"
    else
        echo "HATA: ${unit} etkinlestirilemedi — geri donus calismaz." >&2
        exit 1
    fi
done

echo "Geri donus zinciri tamam (deneme sayisi: /etc/greenboot/greenboot.conf)."
