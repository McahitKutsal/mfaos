#!/usr/bin/env bash
# greenboot ZORUNLU kontrolu: burasi basarisiz olursa makine birkac
# denemeden sonra onceki deployment'a GERI DONER.
#
# Bu yuzden buraya kolay kolay kontrol eklenmez. Her yanlis "basarisiz",
# calisan bir makineyi geri dondurur — yani kontrolun kendisi kesinti
# sebebi olur. Kesin olmayan her sey wanted.d'ye gider (orada sadece
# gunluge yazilir).
#
# Masaustunde "bozuk guncelleme"nin asil belirtisi grafik oturumun hic
# acilmamasi: cekirdek modulu ile cekirdek surumunun kaymasi (NVIDIA),
# bozuk bir cekirdek argumani, kirik bir mesa guncellemesi. Siyah ekran
# tam olarak bu kontrolun yakalamasi gereken sey.
set -uo pipefail

DM=display-manager.service
systemctl cat "${DM}" >/dev/null 2>&1 || DM=gdm.service

# Grafik oturum bilincli olarak kapatilmissa (konsoldan hata ayiklama)
# dogrulanacak bir sey yok. Basarili say — yoksa hata ayiklamak icin
# gdm'i kapatan kullanici kendini geri donus dongusunde bulur.
if ! systemctl is-enabled --quiet "${DM}" 2>/dev/null; then
    echo "${DM} etkin degil, kontrol atlandi"
    exit 0
fi

# greenboot-healthcheck.service `WantedBy=multi-user.target` — yani gdm'den
# ONCE calisabiliyor. Beklemeden "aktif degil" demek saglikli bir makineyi
# geri dondurur. 45s, unit'in 90s varsayilan TimeoutStartSec'ine sigar.
for _ in $(seq 1 22); do
    if systemctl is-active --quiet "${DM}"; then
        echo "${DM} aktif"
        exit 0
    fi
    sleep 2
done

echo "HATA: ${DM} 45 saniyede aktif olmadi — grafik oturum acilmiyor." >&2
systemctl status "${DM}" --no-pager --lines=20 >&2 2>&1 || true
exit 1
