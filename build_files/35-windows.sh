#!/usr/bin/env bash
# Windows uygulamalari (.exe) icin butunlesme katmani.
#
# BURADA WINE KURULMUYOR — bilincli karar. Olcum: `dnf install wine`
# Fedora 44'te 112 paket, 610 MiB indirme, 2,0 GiB kurulu boyut demek
# ve .exe calistirmayacak makinelere de giderdi. Motor Flatpak'ten
# geliyor (org.winehq.Wine ~395 MB ya da Bottles), yalnizca isteyen
# makinede, /var'da.
#
# Imaja giren sey yalnizca TESISAT, birkac KB:
#   - binfmt kaydi      -> ./kurulum.exe dogrudan kosar
#   - MIME varsayilani  -> Dosyalar'da cift tiklama acar
#   - mfaos-exe komutu  -> elle cagirmak icin
set -euo pipefail

WRAPPER="/usr/libexec/mfaos/run-exe.sh"
LINK="/usr/bin/mfaos-exe"
BINFMT="/usr/lib/binfmt.d/10-mfaos-exe.conf"
DESKTOP="/usr/share/applications/mfaos-exe.desktop"
MIMELIST="/etc/xdg/mimeapps.list"

# ---------------------------------------------------------------
# 1. Sarmalayici
# ---------------------------------------------------------------
# Yarim is birakmiyoruz: sarmalayici yoksa binfmt kaydi her .exe'yi
# olmayan bir yorumlayiciya yonlendirir ve kullanici "Exec format
# error" gorur. Bu durumda derlemeyi DURDURMAK dogru.
[[ -f "${WRAPPER}" ]] || { echo "HATA: ${WRAPPER} imajda yok"; exit 1; }

# Calistirma biti savunma amacli yeniden kuruluyor. Sebebi: depo
# Windows'ta core.filemode=false ile tutuluyor, yani kip bilgisi
# yalnizca git INDEKSINDE yasiyor. Indekse yanlis girilirse dosya
# 644 olarak imaja girer, binfmt onu calistiramaz ve kusur ancak
# gercek makinede gorunur.
chmod 0755 "${WRAPPER}"
echo "  sarmalayici: ${WRAPPER} (0755)"

# ---------------------------------------------------------------
# 2. Insan tarafindan cagrilabilir ad
# ---------------------------------------------------------------
# Gercek betik /usr/libexec altinda duruyor (ev usulu, bkz.
# set-default-hostname.sh) ve adi .sh ile bitiyor — CI'daki lint
# kapsami `git ls-files '*.sh'` oldugu icin uzantiyi korumak sart,
# yoksa betik hic denetlenmez. /usr/bin'deki ad sembolik bag.
ln -sf "${WRAPPER}" "${LINK}"
echo "  komut: ${LINK} -> ${WRAPPER}"

# ---------------------------------------------------------------
# 3. binfmt kaydi
# ---------------------------------------------------------------
[[ -f "${BINFMT}" ]] || { echo "HATA: ${BINFMT} imajda yok"; exit 1; }

# Kaydin yorumlayici alani gercekten var olan dosyayi gostermeli.
# Yolu elle iki yere yazdigimiz icin birinin degisip otekinin
# kalmasi gercek bir risk; burada yakalaniyor.
want="$(awk -F: '/^:mfaos-exe:/ {print $7}' "${BINFMT}")"
if [[ "${want}" != "${WRAPPER}" ]]; then
    echo "HATA: binfmt yorumlayicisi (${want}) sarmalayiciyla (${WRAPPER}) uyusmuyor"
    exit 1
fi
echo "  binfmt: MZ -> ${want}"

# .desktop Exec yolu da ayni sarmalayiciyi gostermeli. GLib,
# Exec'teki program yoksa girdiyi SESSIZCE atliyor (olculdu:
# `gio mime` isleyiciyi hic listelemiyor, hata da vermiyor).
# Yani buradaki bir yazim hatasi ancak gercek makinede, cift
# tiklamanin hicbir sey yapmamasi olarak gorunurdu.
dt_exec="$(awk -F= '/^Exec=/ {print $2; exit}' "${DESKTOP}" | awk '{print $1}')"
if [[ "${dt_exec}" != "${WRAPPER}" ]]; then
    echo "HATA: .desktop Exec yolu (${dt_exec}) sarmalayiciyla (${WRAPPER}) uyusmuyor"
    exit 1
fi
echo "  .desktop Exec: ${dt_exec}"

# systemd-binfmt.service'i ETKINLESTIRMIYORUZ: statik bir birim ve
# /usr/lib/binfmt.d bos olmadiginda sysinit.target ile kendiliginden
# kosuyor. Taban imajda qemu-aarch64 kaydi oldugu icin zaten etkin —
# VM'de `systemctl is-active systemd-binfmt` -> active olarak olculdu.

# ---------------------------------------------------------------
# 4. MIME eslesmesi
# ---------------------------------------------------------------
[[ -f "${DESKTOP}" ]] || { echo "HATA: ${DESKTOP} imajda yok"; exit 1; }
[[ -f "${MIMELIST}" ]] || { echo "HATA: ${MIMELIST} imajda yok"; exit 1; }

# Varsayilan olarak yazdigimiz tipler paylasilan MIME veritabaninda
# GERCEKTEN tanimli mi? Taban imaj bir tipi yeniden adlandirirsa
# mimeapps.list satirimiz sessizce hicbir ise yaramaz; cift tiklama
# yine calismaz ve sebebi hicbir yerde yazmaz.
#
# Ucuncu kaynak olarak aliases'a bakmak ZORUNLU: olculdu ki
# application/x-ms-dos-executable kendi basina bir tip DEGIL,
# application/x-msdownload'in takma adi — ne .xml dosyasi var ne
# types'ta duruyor. Yalnizca ilk iki kaynaga bakan bir denetim onu
# "yok" sanip her derlemede yanlis alarm uretir.
mime_known() {
    local t="$1"
    [[ -f "/usr/share/mime/${t}.xml" ]] && return 0
    grep -qx "${t}" /usr/share/mime/types 2>/dev/null && return 0
    awk -v t="${t}" '$1 == t { found = 1 } END { exit !found }' \
        /usr/share/mime/aliases 2>/dev/null && return 0
    return 1
}

missing=0
while IFS='=' read -r mimetype _; do
    case "${mimetype}" in ''|'#'*|'['*) continue ;; esac
    if ! mime_known "${mimetype}"; then
        echo "  UYARI: ${mimetype} paylasilan MIME veritabaninda yok"
        missing=$((missing + 1))
    fi
done < "${MIMELIST}"
[[ "${missing}" -eq 0 ]] && echo "  MIME tipleri dogrulandi (takma adlar dahil)"

# mimeinfo.cache'i tazeliyoruz: .desktop dosyasindaki MimeType=
# satirinin masaustune ulasmasi buna bagli. Taban imajda onbellek
# zaten var, bizim girdimiz onun icine girmeli.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications
    if grep -q 'mfaos-exe.desktop' /usr/share/applications/mimeinfo.cache 2>/dev/null; then
        echo "  mimeinfo.cache guncellendi"
    else
        echo "  UYARI: mimeinfo.cache'e girilmedi — cift tiklama calismayabilir"
    fi
else
    echo "  UYARI: update-desktop-database yok, mimeinfo.cache tazelenmedi"
fi

echo "Windows uygulama destegi tamam (motor Flatpak'ten gelecek)."
