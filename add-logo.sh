#!/usr/bin/env bash
# logo.png'den imajin ihtiyac duydugu tum boyutlari uretir.
#   ./add-logo.sh [dosya]
# Imajda ImageMagick yok; boyutlari burada uretip hazir koyuyoruz.
set -euo pipefail

SRC="${1:-logo.png}"
NAME="mfaos"
SIZES=(16 22 24 32 48 64 72 96 128 192 256 512)

[[ -f "${SRC}" ]] || { echo "HATA: ${SRC} bulunamadi." >&2; exit 1; }

MAGICK="$(command -v magick || command -v convert || true)"
[[ -n "${MAGICK}" ]] || { echo "HATA: sudo apt install -y imagemagick" >&2; exit 1; }

read -r W H < <(python3 -c "
import struct, sys
d = open('${SRC}', 'rb').read(24)
if d[:8] != b'\x89PNG\r\n\x1a\n':
    sys.exit('HATA: PNG degil')
w, h = struct.unpack('>II', d[16:24])
print(w, h)
")
echo "Kaynak: ${SRC} — ${W}x${H}"
[[ "${W}" == "${H}" ]] || echo "UYARI: kare degil, saydam bosluk eklenecek."

OUT="files/usr/share/${NAME}-logo"
rm -rf "${OUT}" files/usr/share/icons/hicolor
mkdir -p "${OUT}"

# Kare tuvale ortala: kaynak kare degilse bile ikonlar bozulmaz.
for s in "${SIZES[@]}"; do
    "${MAGICK}" "${SRC}" -resize "${s}x${s}" \
        -background none -gravity center -extent "${s}x${s}" "${OUT}/${s}.png"
done
echo "  ${#SIZES[@]} boyut uretildi"

# Harici dosyaya referans veren SVG'ler cogu yerde engelleniyor,
# bu yuzden PNG'yi base64 olarak gomuyoruz.
python3 - "${OUT}/512.png" "${OUT}/logo.svg" <<'PY'
import base64, sys
b64 = base64.b64encode(open(sys.argv[1], 'rb').read()).decode()
open(sys.argv[2], 'w').write(
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" '
    'width="512" height="512" viewBox="0 0 512 512">'
    f'<image width="512" height="512" xlink:href="data:image/png;base64,{b64}"/>'
    '</svg>'
)
PY
echo "  logo.svg uretildi"

install -Dm644 "${OUT}/256.png" "files/usr/share/pixmaps/${NAME}.png"
for s in 16 22 24 32 48 64 128 256 512; do
    install -Dm644 "${OUT}/${s}.png" \
        "files/usr/share/icons/hicolor/${s}x${s}/apps/${NAME}.png"
done
install -Dm644 "${OUT}/logo.svg" \
    "files/usr/share/icons/hicolor/scalable/apps/${NAME}.svg"
echo "Tamam."
