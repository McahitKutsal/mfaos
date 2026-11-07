#!/usr/bin/env bash
# Imajin ihtiyac duydugu tum logo boyutlarini uretir.
#
#   ./add-logo.sh [kare] [yatay]
#
# Koyu zemin (GDM, plymouth) icin beyaz varyant ortam degiskeniyle.
# Bu depodaki kaynaklarla tam komut:
#
#   WHITE=logo/simge/simge-beyaz-1024.png \
#     ./add-logo.sh logo.png logo/kilit/yatay-kilit-mercan-2048.png
#
# Imajda ImageMagick yok; boyutlari burada uretip hazir koyuyoruz.
set -euo pipefail

SRC="${1:-logo.png}"
WIDE="${2:-}"
# Koyu zemin icin beyaz varyant (istege bagli, ortam degiskeniyle):
#   WHITE=logo/simge/simge-beyaz-1024.png  ./add-logo.sh ...
WHITE="${WHITE:-}"
WHITE_WIDE="${WHITE_WIDE:-}"
NAME="mfaos"
SIZES=(16 22 24 32 48 64 72 96 128 192 256 512)
WIDE_HEIGHTS=(64 128 192)

[[ -f "${SRC}" ]] || { echo "HATA: ${SRC} bulunamadi." >&2; exit 1; }
if [[ -n "${WIDE}" && ! -f "${WIDE}" ]]; then
    echo "HATA: yatay logo ${WIDE} bulunamadi." >&2
    exit 1
fi
for f in "${WHITE}" "${WHITE_WIDE}"; do
    if [[ -n "${f}" && ! -f "${f}" ]]; then
        echo "HATA: beyaz varyant kaynagi ${f} bulunamadi." >&2
        exit 1
    fi
done

MAGICK="$(command -v magick || command -v convert || true)"
[[ -n "${MAGICK}" ]] || { echo "HATA: sudo apt install -y imagemagick" >&2; exit 1; }

# Harici dosyaya referans veren SVG'ler cogu yerde engelleniyor,
# bu yuzden PNG'yi base64 olarak gomuyoruz.
make_svg() {
    python3 - "$1" "$2" <<'PY'
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
}

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

make_svg "${OUT}/512.png" "${OUT}/logo.svg"
echo "  logo.svg uretildi"

install -Dm644 "${OUT}/256.png" "files/usr/share/pixmaps/${NAME}.png"
for s in 16 22 24 32 48 64 128 256 512; do
    install -Dm644 "${OUT}/${s}.png" \
        "files/usr/share/icons/hicolor/${s}x${s}/apps/${NAME}.png"
done
install -Dm644 "${OUT}/logo.svg" \
    "files/usr/share/icons/hicolor/scalable/apps/${NAME}.svg"
echo "Tamam."

if [[ -n "${WIDE}" ]]; then
    for h in "${WIDE_HEIGHTS[@]}"; do
        "${MAGICK}" "${WIDE}" -resize "x${h}" "${OUT}/wide-${h}.png"
    done
    install -Dm644 "${OUT}/wide-128.png" "files/usr/share/pixmaps/${NAME}-wide.png"
    echo "Yatay logo: ${WIDE} -> ${#WIDE_HEIGHTS[@]} boyut uretildi"
else
    echo "Yatay logo verilmedi — giris ekrani kare logoyu kullanacak."
fi

# Koyu zemin varyanti. GDM giris ekrani, plymouth acilis ekrani ve
# fedora-logos'un *whitelogo* / *darkbackground* / *-white slotlari
# koyu zemin uzerine ciziliyor (Fedora 44'te 7 dosya). Oraya renkli
# armayi koyarsan logo GORUNMEZ olur. 60-logos.sh asagidaki dosyalar
# varsa onlari otomatik kullanir, yoksa renkliyi koyup uyarir.
if [[ -n "${WHITE}" ]]; then
    for s in "${SIZES[@]}"; do
        "${MAGICK}" "${WHITE}" -resize "${s}x${s}" \
            -background none -gravity center -extent "${s}x${s}" \
            "${OUT}/white-${s}.png"
    done
    make_svg "${OUT}/white-512.png" "${OUT}/white-logo.svg"
    echo "Beyaz varyant: ${#SIZES[@]} boyut + white-logo.svg"

    if [[ -n "${WHITE_WIDE}" ]]; then
        for h in "${WIDE_HEIGHTS[@]}"; do
            "${MAGICK}" "${WHITE_WIDE}" -resize "x${h}" "${OUT}/white-wide-${h}.png"
        done
        echo "Beyaz yatay: ${#WIDE_HEIGHTS[@]} boyut uretildi"
    else
        echo "WHITE_WIDE verilmedi — genis koyu zemin slotlari renkli yatayi alacak."
    fi
else
    echo "WHITE verilmedi — koyu zemin slotlarina renkli arma gidecek."
    echo "  WHITE=logo/simge/simge-beyaz-1024.png $0 ${SRC} ${WIDE}"
fi
