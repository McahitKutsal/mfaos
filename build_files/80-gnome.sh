#!/usr/bin/env bash
# GNOME'un bagis isteklerini kaldirir. Iki ayri yerde duruyorlar.
#
# 1. BILDIRIM — yilda iki kez cikan masaustu bildirimi.
#    gnome-settings-daemon'da ve temiz bir GSettings anahtari var:
#
#      settings = g_settings_new ("org.gnome.settings-daemon.plugins.housekeeping");
#      if (!g_settings_get_boolean (settings, "donation-reminder-enabled"))
#              return;
#
#    false yazmak eklentinin zamanlayicisini hic kurdurmuyor.
#
# 2. "Support GNOME" KUTUCUGU — Ayarlar > Sistem Hakkinda.
#    gnome-control-center'in Blueprint sablonuna SABIT gomulu: grubun
#    id'si yok, visible ozelligi hicbir seye bagli degil, GSettings
#    anahtari yok, meson secenegi de yok. Kalan tek yol derlenmis
#    .ui'yi calisma aninda degistirmek: G_RESOURCE_OVERLAYS.
#
# .ui'yi depoya STATIK KOYMUYORUZ: kurulu binary'den derleme aninda
# cikariyoruz. Boylece dosya her zaman kurulu gnome-control-center
# surumuyle uyumlu kaliyor. Depoya konmus eski bir kopya .ui ile C
# kodunu uyusmaz hale getirir ve Ayarlar penceresi HIC acilmaz.
#
# Grubu silmiyoruz, visible=0 yapiyoruz: XML yapisini bozmayan en
# kucuk mudahale. Herhangi bir adim tutmazsa UYARI verip geciyoruz;
# en kotu senaryo kutucugun kalmasi, bozuk bir Ayarlar degil.
set -euo pipefail

# ---------------------------------------------------------------
# 1. Bagis bildirimi
# ---------------------------------------------------------------
# local.d'nin kullaniciya ulasmasi icin profilde system-db:local
# olmasi gerekiyor; onu 70-locale.sh zaten yaziyor.
install -d /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/50-mfaos-donation <<'EOF'
# Yilda iki kez cikan bagis bildirimi kapali. KILIT DEGIL, varsayilan:
# isteyen kullanici geri acabilir.
[org/gnome/settings-daemon/plugins/housekeeping]
donation-reminder-enabled=false
EOF
echo "  bildirim kapatildi (donation-reminder-enabled=false)"

command -v dconf >/dev/null 2>&1 && { dconf update 2>/dev/null || true; }

# ---------------------------------------------------------------
# 2. Sistem Hakkinda'daki "Support GNOME" kutucugu
# ---------------------------------------------------------------
MARK='Support GNOME'
TAG='<object class="AdwPreferencesGroup"'
PROP='<property name="visible">0</property>'
OVERLAY="/usr/share/mfaos/cc-about-page.ui"
ENV_FILE="/etc/environment.d/90-mfaos-gnome.conf"

# Yarim is birakmiyoruz: overlay kurulamadiysa env degiskenini de
# yazmiyoruz, yoksa olmayan bir dosyayi gosterir.
skip() {
    rm -f "${OVERLAY}" "${ENV_FILE}"
    echo "UYARI: About sayfasindaki bagis kutucugu kaldirilamadi."
    echo "       Sebep: $1"
    echo "       Kutucuk duruyor; Ayarlar penceresi saglam."
    exit 0
}

command -v gresource >/dev/null 2>&1 || skip "gresource araci yok (glib2)"

# Kaynak hangi dosyaya gomulu? Su an ana binary'de ama yer
# degistirebilir diye sabitlemek yerine ariyoruz. Kaynak yolu da
# (surumle birlikte degisti, degisebilir) burada kesfediliyor.
RES_FILE=""
RES_PATH=""
for cand in /usr/bin/gnome-control-center \
            /usr/lib64/gnome-control-center/*.so \
            /usr/lib/gnome-control-center/*.so; do
    [[ -f "${cand}" ]] || continue
    found="$(gresource list "${cand}" 2>/dev/null \
             | grep -E '/cc-about-page\.ui$' | head -1)" || true
    if [[ -n "${found}" ]]; then
        RES_FILE="${cand}"
        RES_PATH="${found}"
        break
    fi
done
[[ -n "${RES_PATH}" ]] || skip "cc-about-page.ui hicbir gresource'ta bulunamadi"

TMP_IN="$(mktemp)"
TMP_OUT="$(mktemp)"
trap 'rm -f "${TMP_IN}" "${TMP_OUT}"' EXIT

gresource extract "${RES_FILE}" "${RES_PATH}" > "${TMP_IN}" 2>/dev/null \
    || skip "gresource extract basarisiz (${RES_PATH})"
[[ -s "${TMP_IN}" ]] || skip "cikarilan .ui bos"

# gresource icindeki .ui xml-stripblanks'ten gectigi icin tek satir
# olabilir; o yuzden satir degil, tum dosya tek dize olarak isleniyor.
set +e
awk -v MARK="${MARK}" -v TAG="${TAG}" -v PROP="${PROP}" '
BEGIN { RS = "\x01"; got = 0 }
{
    got = 1
    s = $0
    p = index(s, MARK);                      if (p == 0) exit 3
    head = substr(s, 1, p - 1)
    last = 0; start = 1
    while (1) {
        q = index(substr(head, start), TAG);  if (q == 0) break
        last = start + q - 1; start = last + 1
    }
    if (last == 0) exit 4
    gt = index(substr(s, last), ">");        if (gt == 0) exit 5
    if (substr(s, last + gt - 2, 1) == "/")  exit 6
    printf "%s%s%s", substr(s, 1, last + gt - 1), PROP, substr(s, last + gt)
}
END { if (!got) exit 7 }
' "${TMP_IN}" > "${TMP_OUT}"
rc=$?
set -e

case "${rc}" in
    0) ;;
    3) skip "\"${MARK}\" artik .ui icinde yok — GNOME kaldirmis olabilir" ;;
    4) skip "kutucugu saran AdwPreferencesGroup bulunamadi" ;;
    7) skip "awk girdiyi hic okuyamadi" ;;
    *) skip "yama basarisiz (awk ${rc})" ;;
esac

# Yamanin SADECE ekleme yaptigini dogruluyoruz: boyut tam olarak
# eklenen ozellik kadar buyumeli. Baska bir sey bozulduysa burada
# yakalanir ve kutucugu birakmak bozuk .ui'den iyidir.
IN_SZ="$(wc -c < "${TMP_IN}")"
OUT_SZ="$(wc -c < "${TMP_OUT}")"
[[ -s "${TMP_OUT}" ]]                      || skip "yamali .ui bos"
[[ $(( OUT_SZ - IN_SZ )) -eq ${#PROP} ]]   || skip "beklenmeyen boyut degisimi"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "${TMP_OUT}" 2>/dev/null || skip "yamali .ui gecerli XML degil"
fi

install -Dm644 "${TMP_OUT}" "${OVERLAY}"
install -d "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<EOF
# gnome-control-center'in About sayfasindaki bagis kutucugunu gizler.
# Kaynak yolu derleme aninda kurulu binary'den kesfedildi, sabit degil.
# Overlay yalniz bu tek kaynak yoluna bakiyor; diger GTK uygulamalari
# etkilenmiyor.
G_RESOURCE_OVERLAYS=${RES_PATH}=${OVERLAY}
EOF
chmod 644 "${ENV_FILE}"

echo "  kutucuk gizlendi: ${RES_PATH}"
echo "    kaynak: ${RES_FILE}"
echo "    overlay: ${OVERLAY} (${OUT_SZ} bayt)"
