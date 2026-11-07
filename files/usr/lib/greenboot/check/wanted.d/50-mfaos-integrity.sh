#!/usr/bin/env bash
# greenboot ISTENEN kontrol: basarisiz olursa SADECE gunluge yazilir,
# geri donus TETIKLEMEZ.
#
# Buraya "bilmek istiyorum ama ugruna makineyi geri dondurmem" turunden
# seyler giriyor. Geri donus bunlari zaten duzeltmez: imza anahtari
# eksikse eski deployment'ta da eksiktir.
#
# Gormek icin: journalctl -u greenboot-healthcheck.service
set -uo pipefail

problem=0

# Imza zinciri. Bunlar bozulursa makine imzasiz imaj kabul etmeye baslar
# ve bunu hicbir yerde fark etmezsin.
if ! grep -q sigstoreSigned /etc/containers/policy.json 2>/dev/null; then
    echo "UYARI: policy.json imza zorunlulugu icermiyor" >&2
    problem=1
fi
if [[ ! -s /etc/pki/containers/mfaos.pub ]]; then
    echo "UYARI: cosign ortak anahtari yok — bootc upgrade imaji reddeder" >&2
    problem=1
fi

# Guncelleme zamanlayicisi. Sessizce olurse makine imajda donar ve
# CVE yamalarini almayi birakir.
if ! systemctl is-enabled --quiet bootc-fetch-apply-updates.timer 2>/dev/null; then
    echo "UYARI: bootc guncelleme timer'i etkin degil" >&2
    problem=1
fi

[[ "${problem}" -eq 0 ]] && echo "Butunluk kontrolleri tamam"
exit "${problem}"
