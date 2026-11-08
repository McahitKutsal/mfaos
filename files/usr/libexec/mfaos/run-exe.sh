#!/usr/bin/env bash
# Windows yurutulebilirlerini (.exe, .msi) acar.
#
# Neden boyle bir sarmalayici var: Wine motoru BILEREK imajda degil.
# 30-desktop.sh'in yazdigi ilke gecerli — "degismez bir sistemde
# uygulamalar imaja girmez". Wine bir uygulama calisma zamani, yani
# Flatpak'in isi. Olcum: imaja katmanlamak 112 paket / 2,0 GiB kurulu
# demek ve hic .exe calistirmayacak makinelere de gidiyor.
#
# Ama ".exe'nin yerli gibi davranmasi" isletim sistemi tesisati, yani
# imajin isi. Bu dosya o iki karari birlestiren ince katman: motoru
# calisma aninda buluyor, bulamazsa kullaniciya ne yapacagini soyluyor.
#
# Cagrilma yollari:
#   1. binfmt_misc  -> ./kurulum.exe  (10-mfaos-exe.conf, MZ imzasi)
#   2. MIME         -> Dosyalar'da cift tiklama (mfaos-exe.desktop)
#   3. elle         -> mfaos-exe kurulum.exe
set -euo pipefail

WINE_APP="org.winehq.Wine"
BOTTLES_APP="com.usebottles.bottles"

# Mesaji NEREYE yazacagimiz cagiranla degisiyor: terminalden gelince
# stderr dogru yer, Dosyalar'dan cift tiklamayla gelince kimse stderr'i
# gormuyor. zenity bu imajda YOK (olculdu), notify-send var — ama
# "var olmasi" mesajin ulastigi anlamina gelmiyor, asagiya bak.
tell() {
    local title="$1" body="$2"

    # stderr'e HER ZAMAN yaziyoruz: terminalden gelindiyse kullanici
    # mesaji burada okur, Dosyalar'dan gelindiyse /dev/null'a gider ve
    # zarari olmaz.
    printf '%s\n%s\n' "${title}" "${body}" >&2
    if [[ -t 2 ]]; then
        return 0
    fi

    # Bildirimi DENIYORUZ ama basarili SAYMIYORUZ: notify-send'in kurulu
    # olmasi mesajin ULASTIGI anlamina gelmiyor. Oturum veriyolu yokken
    # "name is not activatable" diye duser (VM'de olculdu) ve kullanici
    # hicbir sey gormez; yalnizca varligina bakan bir denetim gunluk
    # yedegine hic gecmez. Bu yuzden cikis kodu denetleniyor —
    # sessizce olen bir cift tiklama teshis edilemez bir sikayettir.
    if command -v notify-send >/dev/null 2>&1 &&
       notify-send -a "MFAOS" -i mfaos -- "${title}" "${body}" 2>/dev/null
    then
        return 0
    fi
    logger -t mfaos-exe -- "${title}: ${body}" 2>/dev/null || true
}

# Hem sistem hem kullanici kurulumuna bakar.
flatpak_has() {
    command -v flatpak >/dev/null 2>&1 || return 1
    flatpak info -- "$1" >/dev/null 2>&1
}

if [[ $# -lt 1 ]]; then
    tell "Kullanim: mfaos-exe <dosya.exe> [arguman...]" \
         "Windows uygulamasini Wine ile acar."
    exit 2
fi

exe="$1"; shift

if [[ ! -e "${exe}" ]]; then
    tell "Dosya bulunamadi" "${exe}"
    exit 2
fi

# MUTLAK yola cevirmek zorunlu. binfmt bize goreli yol verebiliyor ve
# flatpak'e goreli yol gecirmek kum havuzunun ICINDE bambaska bir yeri
# gosterir — dosya "yok" diye duser, sebebi de hic anlasilmaz.
exe="$(readlink -f -- "${exe}")"
dir="$(dirname -- "${exe}")"

# Windows kurulumcularinin cogu yanindaki dosyalari goreli okuyor
# (setup.exe + data1.cab gibi). Windows'ta calisma dizini .exe'nin
# dizini olur; Dosyalar'dan aciliste ise CWD ev dizini ya da / olurdu.
cd -- "${dir}" || exit 1

# 1) Birisi wine'i imaja katmanladiysa onu kullan: kum havuzu yok,
#    dosya erisimi sorunu yok, en hizli yol.
if command -v wine >/dev/null 2>&1; then
    exec wine "${exe}" "$@"
fi

# 2) Flatpak Wine. --filesystem calisma aninda SART: org.winehq.Wine
#    varsayilan olarak yalnizca xdg-documents/desktop/pictures/music/
#    videos/download goruyor (olculdu). Ev dizinindeki baska bir klasor
#    ya da /tmp kum havuzunda "yok" cikiyor.
#
#    Neden --filesystem=host degil: en az yetki. Yalnizca .exe'nin
#    bulundugu dizini aciyoruz, butun diski degil. Daha genis erisim
#    gerekiyorsa kullanici kalici olarak kendi verir:
#      flatpak override --user --filesystem=home org.winehq.Wine
if flatpak_has "${WINE_APP}"; then
    exec flatpak run --filesystem="${dir}" --command=wine -- "${WINE_APP}" "${exe}" "$@"
fi

# 3) Bottles. Tabani org.winehq.Wine oldugu icin (metadata'da
#    base=app/org.winehq.Wine) kum havuzunun icinde calisan bir wine
#    ikilisi var; ham .exe'yi onunla aciyoruz. Bottles'in kendi
#    arayuzunden gelen "sise" yonetimi bu yoldan gecmiyor — burasi
#    yalnizca cift tiklamayi calistirmak icin.
if flatpak_has "${BOTTLES_APP}"; then
    exec flatpak run --filesystem="${dir}" --command=wine -- "${BOTTLES_APP}" "${exe}" "$@"
fi

tell "Windows uygulamalari icin Wine kurulu degil" \
"$(printf '%s\n' \
    "Kolay yol (grafik arayuz, sise yonetimi):" \
    "  flatpak install flathub com.usebottles.bottles" \
    "" \
    "Yalin yol (yalnizca motor, ~395 MB):" \
    "  flatpak install flathub org.winehq.Wine" \
    "" \
    "Kurulumdan sonra bu dosyayi yeniden ac.")"
exit 127
