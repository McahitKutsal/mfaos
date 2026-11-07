#!/usr/bin/env bash
# fedora-logos'un koydugu LOGO gorsellerini kendi armamizla degistirir.
#
# Fedora logosu onlarca yerden geliyor ve her biri farkli bir mekanizma
# kullaniyor: GDM gschema override'indan, Plymouth tema klasorundeki
# watermark.png'den, GNOME Hakkinda ikon temasindan. Ayar kovalamak
# yerine DOSYALARI degistiriyoruz; hangi ayarin kazandigi onemsizlesiyor.
#
# AMA: fedora-logos sadece logo tasimiyor. Fedora 44'te paket 143
# PNG/SVG iceriyor ve bunlarin 62'si logo DEGIL:
#
#   plymouth/themes/charge/progress-*.png   acilis animasyonu (19 kare)
#   plymouth/themes/charge/throbber-*.png   acilis animasyonu (16 kare)
#   anaconda/pixmaps/*/sidebar-bg.png       arka plan (6)
#   anaconda/pixmaps/*/topbar-bg.png        ust serit (6)
#   anaconda/pixmaps/rnotes/en/*.svg        kurulum slayt cizimleri (5)
#   anaconda/boot/*splash*.png              genis acilis gorseli (2)
#   anaconda/pixmaps/anaconda_header.png    genis baslik
#   icons/*/apps/anaconda.png               kurulum UYGULAMA ikonu
#   .../AnacondaInstaller-symbolic.svg      tek renk ikon
#   pixmaps/fedora-logo-sprite.{png,svg}    sprite sayfasi, tek kare degil
#
# Bu yuzden filtre ALLOWLIST: "tanidigim logo adlarini degistir",
# "chrome diye bildiklerim haric her seyi degistir" DEGIL. Fark onemli:
# denylist yeni bir dosya geldiginde ACIK duser (bilinmeyen arayuz
# parcasi logoyla ezilir), allowlist KAPALI duser (bilinmeyen logo
# Fedora'nin kalir — gorunur, zararsiz ve verify.sh'te raporlanir).
#
# En kotu senaryo denylist'te: Faz 3'te LUKS parola isteminde parola
# kutusunun yerinde logo bulmak.
set -euo pipefail

LOGO_DIR="/usr/share/mfaos-logo"
SIZES=(16 22 24 32 48 64 72 96 128 192 256 512)
WIDE_SIZES=(64 128 192)

# Hedef slot 1.5:1'den genisse kare arma yerine yatay logo. Kare armayi
# genis bir slota kopyalamak goruntuyu bozuyor: en belirgin ornegi
# /usr/share/pixmaps/system-logo-white.png.
WIDE_RATIO_MIN=150

# LOGO_DIR bizim dosyamiz, `COPY files/ /` ile her zaman geliyor.
# Yoksa paketleme hatasi var. Burada `exit 0` demek, markasiz bir imaji
# "derleme basarili" diye yayinlamak olurdu — projenin kacindigi tam o.
if [[ ! -f "${LOGO_DIR}/512.png" ]]; then
    echo "HATA: ${LOGO_DIR}/512.png yok. files/usr/share/mfaos-logo/" >&2
    echo "      imaja kopyalanmamis; ./add-logo.sh ile uretilmis mi?" >&2
    exit 1
fi

nearest() {
    local want="$1" best=512 bestdiff=99999 s diff
    for s in "${SIZES[@]}"; do
        diff=$(( s > want ? s - want : want - s ))
        if (( diff < bestdiff )); then bestdiff=${diff}; best=${s}; fi
    done
    echo "${best}"
}

nearest_wide() {
    local want="$1" best=128 bestdiff=99999 s diff
    for s in "${WIDE_SIZES[@]}"; do
        diff=$(( s > want ? s - want : want - s ))
        if (( diff < bestdiff )); then bestdiff=${diff}; best=${s}; fi
    done
    echo "${best}"
}

# PNG basligini dogrudan okuyoruz. Eskiden python3'e shell out ediyordu;
# taban imajda python3 bulunmasi garanti degil ve derleme zamani
# bagimliligi olmasinin bir sebebi yok. IHDR sabit: 8 bayt imza,
# 4 uzunluk, 4 "IHDR", sonra 4 bayt genislik + 4 bayt yukseklik.
png_size() {
    local sig out
    local -a b=()
    sig="$(od -An -tx1 -N8 -- "$1" 2>/dev/null | tr -d ' \n')" || sig=""
    [[ "${sig}" == "89504e470d0a1a0a" ]] || { echo "0 0"; return 0; }
    out="$(od -An -tu1 -j16 -N8 -- "$1" 2>/dev/null)" || out=""
    read -r -a b <<<"${out}" || true
    (( ${#b[@]} == 8 )) || { echo "0 0"; return 0; }
    echo "$(( (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3] )) $(( (b[4]<<24)|(b[5]<<16)|(b[6]<<8)|b[7] ))"
}

# Slot olculerine gore kaynak sec: genis slota yatay, kareye kare.
# $3 = varyant oneki ("" veya "white-")
pick_src() {
    local w="$1" h="$2" prefix="${3:-}" ratio side cand n
    (( h > 0 && w > 0 )) || return 1
    ratio=$(( w * 100 / h ))

    # Genis slot. Onekli varyant yoksa RENKLI yatayi kullaniyoruz, kare
    # beyaza DUSMUYORUZ: kare bir gorseli genis slota koymak goruntuyu
    # bozar, renk uyusmazligi ise sadece daha az guzel.
    if (( ratio >= WIDE_RATIO_MIN )); then
        n="$(nearest_wide "${h}")"
        for cand in "${LOGO_DIR}/${prefix}wide-${n}.png" \
                    "${LOGO_DIR}/wide-${n}.png"; do
            [[ -f "${cand}" ]] && { echo "${cand}"; return 0; }
        done
    fi

    side=$(( w > h ? w : h ))
    n="$(nearest "${side}")"
    for cand in "${LOGO_DIR}/${prefix}${n}.png" "${LOGO_DIR}/${n}.png"; do
        [[ -f "${cand}" ]] && { echo "${cand}"; return 0; }
    done
    return 1
}

# ALLOWLIST. Yapisal dayanak: fedora-logos icinde marka dosyalari
# markanin adini tasiyor (fedora-logo-icon.png, sidebar-logo.png,
# start-here.png, kmenu.png), arayuz parcalari ise genel adli
# (progress-07.png, sidebar-bg.png, topbar-bg.png, throbber-03.png).
is_logo_asset() {
    local path="$1" base="${1##*/}" low
    low="${base,,}"

    # Paketin kendi logo dizini: tanim geregi logo.
    case "${path}" in
        /usr/share/fedora-logos/*) return 0 ;;
    esac

    # Sprite sayfasi birden fazla kareyi yan yana tasiyor; tek goruntuyle
    # degistirmek onu kullanan animasyonu bozar. Adinda "logo" gecse de
    # degistirilemez. Symbolic ikonlar tek renk cizilmek uzere
    # tasarlanmis; renkli bir arma GNOME'un symbolic islemesini bozar.
    case "${low}" in
        *sprite*|*-symbolic.*) return 1 ;;
    esac

    case "${low}" in
        *logo*)                                     return 0 ;;
        start-here*)                                return 0 ;;
        gnome-main-menu.png|icon-panel-menu.png)    return 0 ;;
        kmenu.png|xfce4_xicon1.svg)                 return 0 ;;
        favicon.png|watermark.png|header-image.png) return 0 ;;
    esac
    return 1
}

# Koyu zemin slotlari. fedora-logos'ta bazi dosyalar siyah/koyu zemin
# uzerine ciziliyor: GDM giris ekrani, plymouth acilis ekrani ve adinda
# "whitelogo" / "darkbackground" / "-white" gecen varyantlar. Oraya
# lacivert-mercan armayi koymak logoyu GORUNMEZ yapar — "degistirdim"
# der, ekranda hicbir sey olmaz.
#
# Beyaz varyant (white-*.png / white-logo.svg) varsa onu kullaniyoruz;
# yoksa renkli armayi koyup sayiyoruz ve derleme sonunda raporluyoruz.
# Uretmek icin: WHITE=logo/simge/simge-beyaz-1024.png ./add-logo.sh ...
dark_slots_unfilled=0

is_dark_slot() {
    local b="${1##*/}"
    b="${b,,}"
    case "${b}" in
        *whitelogo*|*darkbackground*|*-white.*) return 0 ;;
        watermark.png|*gdm*logo*)               return 0 ;;
    esac
    return 1
}

replace_asset() {
    local f="$1" w h src prefix=""
    if is_dark_slot "${f}"; then
        if [[ -f "${LOGO_DIR}/white-512.png" ]]; then
            prefix="white-"
        else
            dark_slots_unfilled=$((dark_slots_unfilled+1))
        fi
    fi

    case "${f,,}" in
        *.svg)
            src="${LOGO_DIR}/${prefix}logo.svg"
            [[ -f "${src}" ]] || src="${LOGO_DIR}/logo.svg"
            cp -f "${src}" "${f}"
            return 0 ;;
    esac

    read -r w h <<<"$(png_size "${f}")" || true
    [[ "${w:-0}" -gt 0 ]] || return 1
    src="$(pick_src "${w}" "${h}" "${prefix}")" || return 1
    [[ -f "${src}" ]] || return 1
    cp -f "${src}" "${f}"
    return 0
}

replaced=0
kept=0
kept_anim=0
KEPT_NAMES=()
if rpm -q fedora-logos >/dev/null 2>&1; then
    while IFS= read -r f; do
        [[ -f "${f}" ]] || continue
        case "${f,,}" in
            *.png|*.svg) ;;
            *) continue ;;
        esac
        if ! is_logo_asset "${f}"; then
            kept=$((kept+1))
            # Animasyon kareleri duzine duzine; raporu bogmasinlar.
            case "${f}" in
                */plymouth/*) kept_anim=$((kept_anim+1)) ;;
                *) KEPT_NAMES+=("${f##*/}") ;;
            esac
            continue
        fi
        if replace_asset "${f}"; then
            replaced=$((replaced+1))
        fi
    done < <(rpm -ql fedora-logos 2>/dev/null)

    echo "fedora-logos: ${replaced} logo degistirildi, ${kept} dosya korundu" \
         "(${kept_anim} acilis animasyon karesi)"
    if (( ${#KEPT_NAMES[@]} > 0 )); then
        echo "  korunan arayuz/icerik gorselleri:"
        printf '%s\n' "${KEPT_NAMES[@]}" | sort -u | sed 's/^/    /'
    fi
    # Hicbir sey degismediyse logo katmani calismamis demektir.
    if (( replaced == 0 )); then
        echo "HATA: fedora-logos kurulu ama hicbir logo degistirilemedi." >&2
        exit 1
    fi
else
    echo "fedora-logos kurulu degil, paket icerigi atlandi"
fi

# Bazi plymouth temalari (bgrt gibi) watermark'i fedora-logos disinda
# tutuyor; rpm listesi onlari gostermiyor.
shopt -s nullglob
for wm in /usr/share/plymouth/themes/*/watermark.png; do
    if replace_asset "${wm}"; then
        echo "  acilis amblemi: ${wm}"
    fi
done
shopt -u nullglob

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    for theme in hicolor Bluecurve oxygen; do
        [[ -d "/usr/share/icons/${theme}" ]] || continue
        gtk-update-icon-cache -qf "/usr/share/icons/${theme}" 2>/dev/null || true
    done
fi

# GDM logoyu genis bir seride yerlestiriyor; kare amblem orada kucuk
# kalir. Iki mekanizma var: gdm paketinin gschema override'i dogrudan
# /usr/share/pixmaps/fedora-gdm-logo.png dosyasini gosteriyor, ayrica
# dconf'ta org.gnome.login-screen logo anahtari var. Dosyayi degistirip
# ayari da yazinca hangisinin kazandigi onemsizlesiyor.
#
# Dosyanin kendisi yukaridaki donguden gecti (adinda "logo" var ve
# genis oldugu icin yatay varyanti aldi); burada kalan is dconf ayari.
GDM_LOGO="/usr/share/pixmaps/mfaos.png"
if [[ -f "${LOGO_DIR}/wide-128.png" ]]; then
    GDM_LOGO="/usr/share/pixmaps/mfaos-wide.png"
    shopt -s nullglob
    for g in /usr/share/pixmaps/*gdm*logo*.png; do
        replace_asset "${g}" && echo "  giris ekrani logosu: ${g}"
    done
    shopt -u nullglob
else
    echo "  yatay logo yok, giris ekrani kare logoyu kullanacak"
fi

install -d /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/95-mfaos-logo <<EOF
[org/gnome/login-screen]
logo='${GDM_LOGO}'
EOF

command -v dconf >/dev/null 2>&1 && { dconf update 2>/dev/null || true; }


# Beyaz varyant eksikse sessiz kalmiyoruz: logo "degistirildi" ama koyu
# zeminde gorunmuyor olabilir — ekrana bakmadan anlasilmayan tek hata
# sinifi bu, o yuzden derleme ciktisinda duruyor.
if (( dark_slots_unfilled > 0 )); then
    echo "UYARI: ${dark_slots_unfilled} koyu zemin slotuna renkli arma kondu."
    echo "       GDM / plymouth zemini koyu; arma gorunmeyebilir."
    echo "       Duzeltmek icin beyaz varyanti uret:"
    echo "         WHITE=logo/simge/simge-beyaz-1024.png \\"
    echo "           ./add-logo.sh logo.png logo/kilit/yatay-kilit-mercan-2048.png"
fi
exit 0
