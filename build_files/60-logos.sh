#!/usr/bin/env bash
# fedora-logos'un koydugu her gorseli kendi logomuzla degistirir.
#
# Fedora logosu onlarca yerden geliyor ve her biri farkli bir mekanizma
# kullaniyor: GDM gschema override'indan, Plymouth tema klasorundeki
# watermark.png'den, GNOME Hakkinda ikon temasindan. Ayar kovalamak
# yerine DOSYALARI degistiriyoruz; hangi ayarin kazandigi onemsizlesiyor.
set -euo pipefail

LOGO_DIR="/usr/share/mfaos-logo"
SIZES=(16 22 24 32 48 64 72 96 128 192 256 512)

[[ -d "${LOGO_DIR}" ]] || { echo "Logo yok, atlaniyor"; exit 0; }
rpm -q fedora-logos >/dev/null 2>&1 || { echo "fedora-logos yok, atlaniyor"; exit 0; }

nearest() {
    local want="$1" best=512 bestdiff=99999 s diff
    for s in "${SIZES[@]}"; do
        diff=$(( s > want ? s - want : want - s ))
        if (( diff < bestdiff )); then bestdiff=${diff}; best=${s}; fi
    done
    echo "${best}"
}

png_width() {
    python3 -c "
import struct, sys
try:
    d = open(sys.argv[1], 'rb').read(24)
    print(struct.unpack('>II', d[16:24])[0] if d[:8] == b'\x89PNG\r\n\x1a\n' else 0)
except Exception:
    print(0)
" "$1"
}

replaced=0
while IFS= read -r f; do
    [[ -f "${f}" ]] || continue
    case "${f,,}" in
        *.png)
            w="$(png_width "${f}")"
            [[ "${w}" -gt 0 ]] || continue
            cp -f "${LOGO_DIR}/$(nearest "${w}").png" "${f}"
            replaced=$((replaced+1)) ;;
        *.svg)
            cp -f "${LOGO_DIR}/logo.svg" "${f}"
            replaced=$((replaced+1)) ;;
    esac
done < <(rpm -ql fedora-logos 2>/dev/null)
echo "fedora-logos: ${replaced} gorsel degistirildi"

# Bazi temalar logoyu fedora-logos disinda tutuyor.
for wm in /usr/share/plymouth/themes/*/watermark.png; do
    [[ -f "${wm}" ]] || continue
    w="$(png_width "${wm}")"
    [[ "${w}" -gt 0 ]] || continue
    cp -f "${LOGO_DIR}/$(nearest "${w}").png" "${wm}"
    echo "  acilis amblemi: ${wm}"
done

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
