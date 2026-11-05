#!/usr/bin/env bash
# Masaustu uygulama akisi ve guncelleme zamanlayicisi.
set -euo pipefail

# ---------------------------------------------------------------
# Flatpak: GUI uygulamalarinin yeri
# ---------------------------------------------------------------
# Degismez bir sistemde uygulamalar imaja girmez. GUI uygulamalari
# Flatpak'ten, CLI/gelistirme araclari distrobox'tan gelir.
#
# Uzak depoyu BURADA eklemiyoruz: flatpak yapilandirmayi /var altina
# yazar ve /var imajin parcasi degil — imaj derlenirken oraya yazilan
# her sey kaybolur. Is ilk acilista calisan servise devredildi.
systemctl enable mfaos-flatpak-setup.service 2>/dev/null || true

# ---------------------------------------------------------------
# Otomatik guncelleme
# ---------------------------------------------------------------
# Timer'i imajda etkinlestiriyoruz: yeni kurulan her makine ilk
# acilisindan itibaren guncellemeleri cekmeye baslar. Elle adim yok.
systemctl enable bootc-fetch-apply-updates.timer 2>/dev/null || true

echo "Masaustu akisi tamam."
