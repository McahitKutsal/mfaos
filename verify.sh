#!/usr/bin/env bash
# Imajin ICINDE calisir: yapilandirdigimiz her seyin gercekten imaja
# girdigini dogrular.
#
# `podman build` basarili bitmesi, istedigin seyin imaja girdigi
# anlamina gelmez — scriptlerdeki `|| true`'lar hatalari yutar ve
# sessizce eksik bir imaj uretirsin. Bu script o bosluklari yakalar.
#
# Kullanim (test.sh verify bunu zaten yapar):
#   podman run --rm -v "$PWD/verify.sh:/verify.sh:ro" \
#     --entrypoint /bin/bash localhost/mfaos:44 /verify.sh

FAIL=0
WARN=0
PASS=0

ok()   { printf '  \033[32m  OK  \033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m HATA \033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33mUYARI \033[0m %s\n' "$1"; WARN=$((WARN+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

have_file() {
    if [[ -f "$1" ]]; then ok "$2"; else bad "$2 — $1 yok"; fi
}

# Konteynerde systemd calismadigi icin `systemctl is-enabled` guvenilir
# degil; etkinlestirme sembolik baglarina dogrudan bakiyoruz.
unit_enabled() {
    local unit="$1" label="$2"
    if find /etc/systemd/system /usr/lib/systemd/system \
         -name "${unit}" -type l 2>/dev/null | grep -q .; then
        ok "${label}"
    else
        bad "${label} — etkinlestirilmemis"
    fi
}

printf '\033[1mmfaos imaj dogrulamasi\033[0m\n'
printf 'NVIDIA varyanti: %s\n' "${NVIDIA_ENABLED:-bilinmiyor}"

# ---------------------------------------------------------------
head_ "1. Sertlestirme"
# ---------------------------------------------------------------
have_file /usr/lib/sysctl.d/99-mfaos-hardening.conf "sysctl sertlestirme dosyasi"
have_file /usr/lib/bootc/kargs.d/10-hardening.toml  "cekirdek argumanlari"

if grep -q '^SELINUX=enforcing' /etc/selinux/config 2>/dev/null; then
    ok "SELinux enforcing"
else
    bad "SELinux enforcing degil"
fi

if passwd -S root 2>/dev/null | awk '{print $2}' | grep -q '^L'; then
    ok "root hesabi kilitli"
else
    warn "root hesabi kilitli degil"
fi

if find /etc/systemd/system /usr/lib/systemd/system \
     -name 'sshd.service' -type l 2>/dev/null | grep -q .; then
    warn "sshd etkin — masaustunde beklenmiyor"
else
    ok "sshd etkin degil"
fi

# 20-hardening.sh'teki `|| true`'larin arkasi. Ucu de sessizce
# dusebilir ve imaj yine "basarili" derlenir.
if grep -q '^DefaultZone=block' /etc/firewalld/firewalld.conf 2>/dev/null; then
    ok "guvenlik duvari varsayilan bolgesi: block"
else
    bad "guvenlik duvari varsayilan bolgesi ayarlanmamis"
fi

# Denetim gunlugu: olay sonrasi incelemede tek gercek kaynak.
unit_enabled 'auditd.service'      "denetim gunlugu (auditd) etkin"
unit_enabled 'fwupd-refresh.timer' "firmware guncelleme timer'i etkin"

# ---------------------------------------------------------------
head_ "2. Imza zinciri"
# ---------------------------------------------------------------
have_file /etc/containers/policy.json "imza politikasi"
have_file /etc/containers/registries.d/mfaos.yaml "sigstore eki yapilandirmasi"

if grep -q 'sigstoreSigned' /etc/containers/policy.json 2>/dev/null; then
    ok "policy.json imza zorunlulugu iceriyor"
else
    bad "policy.json imza zorunlulugu ICERMIYOR — imzasiz imaj kabul edilir"
fi

KEY=/etc/pki/containers/mfaos.pub
if [[ -f "${KEY}" ]] && grep -q 'BEGIN PUBLIC KEY' "${KEY}"; then
    ok "cosign ortak anahtari yerinde"
else
    bad "cosign ortak anahtari yok/gecersiz — bootc upgrade imaji REDDEDER"
fi

# ---------------------------------------------------------------
head_ "3. Guncelleme ve geri donus"
# ---------------------------------------------------------------
unit_enabled 'bootc-fetch-apply-updates.timer' "guncelleme timer'i etkin"
have_file /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/10-mfaos-stage-only.conf \
    "stage-only override (otomatik reboot kapali)"
have_file /usr/lib/systemd/system/bootc-fetch-apply-updates.timer.d/10-mfaos-schedule.conf \
    "zamanlama override"
unit_enabled 'mfaos-flatpak-setup.service' "flatpak kurulum servisi etkin"

if command -v bootc >/dev/null 2>&1; then
    ok "bootc ikilisi mevcut"
else
    bad "bootc ikilisi YOK — makine kendini guncelleyemez"
fi

# Otomatik geri donus bootc'den degil greenboot'tan geliyor. Bu
# kontrollerden biri duserse "bozuk guncelleme kendini geri alir"
# iddiasi gecersiz — ve bunu ancak gercekten bozuk bir guncellemede,
# en kotu anda ogrenirsin.
unit_enabled 'greenboot-healthcheck.service' "greenboot saglik kontrolu etkin"
unit_enabled 'greenboot-set-rollback-trigger.service' \
    "greenboot geri donus tetikleyicisi etkin (boot_counter'i kuran parca)"

# Calistirma biti olmayan bir kontrol "basarisiz" sayilir ve makine
# her acilista geri doner. CRLF satir sonu da ayni sonucu verir.
for chk in /usr/lib/greenboot/check/required.d/50-mfaos-desktop.sh \
           /usr/lib/greenboot/check/wanted.d/50-mfaos-integrity.sh; do
    if [[ -x "${chk}" ]]; then
        ok "saglik kontrolu calistirilabilir: ${chk##*/}"
    else
        bad "saglik kontrolu calistirilamaz: ${chk}"
    fi
done

# Tersi de bozuyor: systemd bir yapilandirma dosyasinda calistirma biti
# bulursa her acilista "Configuration file ... is marked executable.
# Please remove executable permission bits. Proceeding anyway." diye
# uyariyor. Simdilik devam ediyor, ama uyari bosa dusmuyor ve bir gun
# hata olacak. Bu bit fark edilmeden commit'lenebiliyor: Windows'ta
# core.filemode=false, yani calisma agacindaki kip izlenmiyor. Duzeltmesi
# calisma agacinda chmod degil, dogrudan indeks: git update-index
# --chmod=-x <dosya>. Yalnizca bizim sahibi oldugumuz yollara bakiyoruz;
# temel imajin dosyalarini denetlemek bize dusmez.
x_conf="$(find /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d \
               /usr/lib/systemd/system/bootc-fetch-apply-updates.timer.d \
               /usr/lib/systemd/system/mfaos-flatpak-setup.service \
               /usr/lib/sysctl.d/99-mfaos-hardening.conf \
               /usr/lib/bootc/kargs.d \
               /etc/containers/policy.json \
               /etc/containers/registries.d \
               /etc/pki/containers \
               -type f -perm -u+x 2>/dev/null)"
if [[ -z "${x_conf}" ]]; then
    ok "yapilandirma dosyalarinda calistirma biti yok"
else
    bad "yapilandirma dosyasinda calistirma biti var: $(echo "${x_conf}" | tr '\n' ' ')"
fi

# Bu paket kurulursa required.d/01_repository_dns_check.sh devreye girer
# ve agsiz acilan laptop'i geri dondurur. Bilerek kurmuyoruz.
if rpm -q greenboot-default-health-checks >/dev/null 2>&1; then
    warn "greenboot-default-health-checks kurulu — agsiz acilista geri donus tetikler"
else
    ok "greenboot varsayilan kontrolleri kurulu degil (bilincli)"
fi

# rollback-test.sh'in kasitli basarisiz kontrolu IMAJA SIZMAMALI. Onu
# calisma aninda /etc'ye koyuyor, ama biri files/ altina commit ederse
# her makine her acilista geri doner — tam olarak kacinmak istedigimiz
# kesinti, hem de kendi elimizle. Yapisal olarak engelleyemiyoruz
# (files/ serbest), o yuzden burada duruyor.
if compgen -G "/etc/greenboot/check/required.d/*rollback-test*" >/dev/null 2>&1 \
   || compgen -G "/usr/lib/greenboot/check/required.d/*rollback-test*" >/dev/null 2>&1; then
    bad "imajda kasitli basarisiz test kontrolu var — her makine geri doner"
else
    ok "imajda kasitli basarisiz test kontrolu yok"
fi

# ---------------------------------------------------------------
head_ "4. Paketler"
# ---------------------------------------------------------------
# Bir paket adi degisir ya da depodan duserse, kurulum adimlarindaki
# `|| true` sayesinde derleme devam eder. Vaat ettigimiz akislarin
# dayandigi paketleri tek tek soruyoruz.
for pkg in flatpak distrobox greenboot audit cryptsetup tpm2-tools \
           sbsigntools fwupd glibc-langpack-tr; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        ok "${pkg}"
    else
        bad "${pkg} kurulu degil"
    fi
done

# ---------------------------------------------------------------
head_ "5. bootc gereksinimleri"
# ---------------------------------------------------------------
# /var'da pakete ait girdiler normaldir: /var/lib/rpm, /var/run ve
# /var/mail taban imajin tasarimi geregi sembolik bag. Sorun olan,
# BIZIM ardimizda biraktigimiz dosyalar — onlar kurulumda sessizce
# kaybolur. Sabit bir dislama listesi yerine sahibini soruyoruz.
VAR_STRAY=()
while IFS= read -r p; do
    rpm -qf "${p}" >/dev/null 2>&1 && continue
    VAR_STRAY+=("${p}")
done < <(find /var -mindepth 1 \( -type f -o -type l \) 2>/dev/null)

if [[ ${#VAR_STRAY[@]} -eq 0 ]]; then
    ok "/var temiz (pakete ait girdiler ve bos dizinler normal)"
else
    warn "/var icinde pakete ait olmayan ${#VAR_STRAY[@]} girdi var — kurulumda kaybolur:"
    printf '           %s\n' "${VAR_STRAY[@]:0:10}"
fi

# --- Dil ve klavye ---
if locale -a 2>/dev/null | grep -qi '^tr_TR'; then
    ok "tr_TR yerel ayari mevcut"
else
    bad "tr_TR yerel ayari YOK — sistem C.UTF-8'e duser"
fi

if grep -q '^LANG=tr_TR' /etc/locale.conf 2>/dev/null; then
    ok "varsayilan dil Turkce"
else
    bad "varsayilan dil ayarlanmamis"
fi

if grep -q '^KEYMAP=trq' /etc/vconsole.conf 2>/dev/null; then
    ok "konsol klavyesi Turkce Q"
else
    warn "konsol klavyesi ayarlanmamis"
fi

if grep -q 'XkbLayout.*"tr' /etc/X11/xorg.conf.d/00-keyboard.conf 2>/dev/null; then
    ok "oturum klavyesi Turkce Q"
else
    warn "oturum klavyesi ayarlanmamis"
fi

# dconf anahtar dosyasi yazmak yetmiyor: `dconf update` derlenmis ikili
# db'yi uretmezse ayar kullaniciya HIC ulasmaz. O komut iki scriptte de
# `|| true` ile cagriliyor — yani tam sessizce dusebilecegi yer burasi.
have_file /etc/dconf/db/local "dconf local db derlenmis (klavye duzeni)"
have_file /etc/dconf/db/gdm   "dconf gdm db derlenmis (giris ekrani logosu)"

if grep -q '^system-db:local$' /etc/dconf/profile/user 2>/dev/null; then
    ok "dconf profilinde system-db:local var"
else
    bad "dconf profili eksik — local.d ayarlari kullaniciya ulasmaz"
fi

# --- Kimlik ---
if grep -qi '^PRETTY_NAME=.*mfaos' /usr/lib/os-release 2>/dev/null; then
    ok "sistem kimligi: $(. /usr/lib/os-release; echo "${PRETTY_NAME}")"
else
    warn "os-release hala Fedora olarak gorunuyor"
fi

# Aygit adi. Ayarlar > Sistem Hakkinda'daki "Aygit Adi" satiri once
# PRETTY_HOSTNAME'e bakiyor, yoksa hostname'e dusuyor; ikisi de yoksa
# makine kendini "fedora" diye tanitiyor. Kimlik bolumunun geri kalani
# gibi bunlar da uyari seviyesinde: yanlis ad imaji kullanilamaz
# yapmiyor, ama sessizce gecmesini de istemiyoruz.
if grep -qi '^PRETTY_HOSTNAME=.*mfaos' /etc/machine-info 2>/dev/null; then
    ok "aygit adi: $(. /etc/machine-info; echo "${PRETTY_HOSTNAME}")"
else
    warn "PRETTY_HOSTNAME yok — Ayarlar'da aygit adi 'fedora' gorunur"
fi

# Agdaki/kabuktaki ad. /etc/hostname'e BAKMIYORUZ ve bakamayiz: podman
# o dosyayi bind-mount ile eziyor (okunan deger konteyner kimligi olur),
# ustelik buildah ayni seyi derleme zamaninda yaptigi icin dosya imaja
# hic girmiyor. Dogru kaynak os-release'in DEFAULT_HOSTNAME alani —
# ve o maskelenmiyor, yani buradan gercekten dogrulanabiliyor.
if grep -q '^DEFAULT_HOSTNAME=' /usr/lib/os-release 2>/dev/null; then
    ok "varsayilan hostname: $(. /usr/lib/os-release; echo "${DEFAULT_HOSTNAME}")"
else
    warn "DEFAULT_HOSTNAME yok — makine kendini 'fedora' diye tanitir"
fi

# Ama DEFAULT_HOSTNAME TEK BASINA YETMIYOR, bu VM'de olculdu: adi
# initramfs'in systemd'si kendi os-release'ine gore koyuyor ve orada bu
# alan yok, gercek kokun systemd'si de "ad zaten ayarli" diye uzerine
# yazmiyor. Kabukta `fedora` kaliyor. Bu ikiliyi duzelten parca
# mfaos-hostname.service; ikisi birlikte olmali, yoksa alan imajda
# durur ama hicbir ise yaramaz.
if find /etc/systemd/system /usr/lib/systemd/system \
     -name mfaos-hostname.service -type l 2>/dev/null | grep -q .; then
    ok "mfaos-hostname.service etkin (adi acilista DEFAULT_HOSTNAME'e ceker)"
else
    bad "mfaos-hostname.service etkin degil — kabukta ad 'fedora' kalir"
fi
if [[ -x /usr/libexec/mfaos/set-default-hostname.sh ]]; then
    ok "set-default-hostname.sh calistirilabilir"
else
    bad "set-default-hostname.sh yok/calistirilamaz — birim 203/EXEC ile duser"
fi

# ID=fedora kalmali: RPM Fusion, Flatpak ve ucuncu parti scriptler bu
# alana bakiyor. Degismisse paket yonetimi sessizce bozulur.
if grep -q '^ID=fedora$' /usr/lib/os-release 2>/dev/null; then
    ok "ID=fedora korunmus"
else
    bad "ID degistirilmis — paket yonetimi bozulabilir"
fi

if grep -q '^LOGO=mfaos$' /usr/lib/os-release 2>/dev/null; then
    ok "logo ayarlanmis"
else
    warn "logo ayarlanmamis (Fedora logosu kullaniliyor)"
fi

KERNEL="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | tail -1)"
if [[ -n "${KERNEL}" && -d "/usr/lib/modules/${KERNEL}" ]]; then
    ok "cekirdek: ${KERNEL}"
else
    bad "cekirdek modul dizini bulunamadi"
fi


# ---------------------------------------------------------------
head_ "6. Logo katmani"
# ---------------------------------------------------------------
# 60-logos.sh iki yonde de yanlis gidebilir ve ikisi de ancak ekrana
# bakilinca anlasilir — tam o yuzden burada olculuyor:
#   logo degismemis -> imaj Fedora markasiyla yayinlanir
#   arayuz degismis -> acilis animasyonu / LUKS parola kutusu bozulur
have_file /usr/share/mfaos-logo/512.png "logo kaynaklari imajda"

if [[ -f /usr/share/mfaos-logo/white-512.png ]]; then
    ok "koyu zemin (beyaz) varyanti var"
else
    warn "beyaz varyant yok — GDM/plymouth koyu zemininde arma gorunmeyebilir"
fi

# PNG basligini dogrudan okuyoruz: IHDR'de 16. bayttan itibaren
# 4 bayt genislik + 4 bayt yukseklik.
png_ratio() {
    local sig out w h
    local -a b=()
    sig="$(od -An -tx1 -N8 -- "$1" 2>/dev/null | tr -d ' \n')" || sig=""
    [[ "${sig}" == "89504e470d0a1a0a" ]] || { echo 0; return 0; }
    out="$(od -An -tu1 -j16 -N8 -- "$1" 2>/dev/null)" || out=""
    read -r -a b <<<"${out}" || true
    (( ${#b[@]} == 8 )) || { echo 0; return 0; }
    w=$(( (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3] ))
    h=$(( (b[4]<<24)|(b[5]<<16)|(b[6]<<8)|b[7] ))
    (( h > 0 )) || { echo 0; return 0; }
    echo $(( w * 100 / h ))
}

if rpm -q fedora-logos >/dev/null 2>&1; then
    # Allowlist'i burada TEKRARLAMIYORUZ: iki kopya zamanla birbirinden
    # ayrilir. Onun yerine degismezleri olcuyoruz — logo degisti mi,
    # arayuz korundu mu. Karsilastirma dosya ozetiyle.
    OURS=" $(sha256sum /usr/share/mfaos-logo/* 2>/dev/null \
             | awk '{print $1}' | sort -u | tr '\n' ' ')"
    is_ours() {
        local h
        h="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')"
        [[ -n "${h}" && "${OURS}" == *" ${h} "* ]]
    }

    LOGO_N=0
    while IFS= read -r f; do
        [[ -f "${f}" ]] || continue
        if is_ours "${f}"; then LOGO_N=$((LOGO_N+1)); fi
    done < <(rpm -ql fedora-logos 2>/dev/null)

    if (( LOGO_N == 0 )); then
        bad "fedora-logos'ta hicbir dosya degismemis — imaj Fedora markali"
    elif (( LOGO_N < 60 )); then
        warn "sadece ${LOGO_N} logo degismis (Fedora 44'te 81 bekleniyor)"
    else
        ok "${LOGO_N} logo kendi armamizla degismis"
    fi

    # Arayuz parcalari KORUNMUS olmali. Logoyla ezilirlerse acilis
    # ekrani bozulur; Faz 3'te parola kutusunun yerinde logo bulursun.
    CHROME_HIT=()
    for c in /usr/share/plymouth/themes/charge/progress-00.png \
             /usr/share/plymouth/themes/charge/throbber-00.png \
             /usr/share/anaconda/pixmaps/sidebar-bg.png \
             /usr/share/anaconda/pixmaps/topbar-bg.png \
             /usr/share/pixmaps/fedora-logo-sprite.png; do
        [[ -f "${c}" ]] || continue
        if is_ours "${c}"; then CHROME_HIT+=("${c##*/}"); fi
    done
    if (( ${#CHROME_HIT[@]} > 0 )); then
        bad "arayuz parcalari logoyla ezilmis: ${CHROME_HIT[*]}"
    else
        ok "acilis animasyonu ve arka planlar korunmus"
    fi
fi

# Genis slota kare arma konmus mu? En gorunur ornegi giris ekrani:
# GDM logoyu genis bir seride cizer, kare amblem orada ezilir.
GDM_PNG="/usr/share/pixmaps/fedora-gdm-logo.png"
if [[ -f "${GDM_PNG}" ]]; then
    GDM_R="$(png_ratio "${GDM_PNG}")"
    if (( GDM_R >= 150 )); then
        ok "giris ekrani logosu yatay (en/boy ${GDM_R}%)"
    else
        bad "giris ekrani logosu kare (en/boy ${GDM_R}%) — GDM onu ezer"
    fi
fi

# ---------------------------------------------------------------
head_ "7. GNOME arayuzu"
# ---------------------------------------------------------------
# Bagis bildirimi. Derlenmis local db yukarida kontrol ediliyor;
# burada anahtarin gercekten yazildigina bakiyoruz.
DON=/etc/dconf/db/local.d/50-mfaos-donation
if grep -q '^donation-reminder-enabled=false$' "${DON}" 2>/dev/null; then
    ok "bagis bildirimi kapatilmis"
else
    bad "bagis bildirimi kapatilmamis (${DON})"
fi

# "Support GNOME" kutucugu. Overlay ve onu devreye alan env dosyasi
# BIRLIKTE var olmak zorunda: biri varken digeri yoksa 80-gnome.sh
# yarim kalmis demektir ve bu sessizce gecer.
OVL=/usr/share/mfaos/cc-about-page.ui
ENVF=/etc/environment.d/90-mfaos-gnome.conf
if [[ -f "${OVL}" && -f "${ENVF}" ]]; then
    if grep -q "G_RESOURCE_OVERLAYS=.*=${OVL}\$" "${ENVF}" 2>/dev/null; then
        ok "About sayfasi overlay'i devrede"
    else
        bad "overlay var ama env dosyasi onu gostermiyor"
    fi

    if grep -q '<property name="visible">0</property>' "${OVL}" 2>/dev/null; then
        ok "bagis kutucugu gizlenmis"
    else
        bad "overlay'de visible=0 yok — kutucuk gorunur kalir"
    fi

    # Bozuk bir .ui Ayarlar penceresini HIC actirmaz, o yuzden
    # dosyanin gercekten XML oldugunu da goruyoruz.
    if head -c 64 "${OVL}" 2>/dev/null | grep -q '<?xml\|<interface'; then
        ok "overlay XML olarak basliyor"
    else
        bad "overlay XML gibi gorunmuyor — Ayarlar acilmayabilir"
    fi
elif [[ -f "${OVL}" || -f "${ENVF}" ]]; then
    bad "overlay/env ikilisinden sadece biri var — 80-gnome.sh yarim kalmis"
else
    warn "About sayfasindaki bagis kutucugu duruyor (overlay uretilemedi)"
fi

# 80-gnome.sh gresource icin glib2-devel'i GECICI kuruyor ve ayni
# betikte kaldiriyor. Kaldirma `|| true` ile cagriliyor — yani sessizce
# dusebilir ve imajda bir -devel paketi, onunla birlikte gereksiz CVE
# yuzeyi kalir. Bu projede `|| true` olan her yerin bir kontrolu var.
if rpm -q glib2-devel >/dev/null 2>&1; then
    bad "glib2-devel imajda kalmis — gecici kurulum kaldirilamamis"
else
    ok "gecici derleme paketi imajda yok (glib2-devel)"
fi

# ---------------------------------------------------------------
if [[ "${NVIDIA_ENABLED:-0}" == "1" ]]; then
head_ "8. NVIDIA"
# ---------------------------------------------------------------
    have_file /usr/lib/bootc/kargs.d/20-nvidia.toml "nvidia cekirdek argumanlari"

    if modinfo -k "${KERNEL}" nvidia >/dev/null 2>&1; then
        NV_VER="$(modinfo -k "${KERNEL}" nvidia -F version 2>/dev/null)"
        ok "nvidia.ko yuklenebilir (surucu ${NV_VER:-?})"
    else
        bad "nvidia.ko YOK veya cekirdekle uyumsuz — makine siyah ekran acar"
    fi

    if modinfo -k "${KERNEL}" nvidia 2>/dev/null | grep -qi '^sig_id\|^signature'; then
        ok "nvidia.ko imzali (Secure Boot calisir)"
    else
        warn "nvidia.ko IMZASIZ — Secure Boot acik makinelerde yuklenmez"
    fi

    if [[ -f "/usr/lib/modules/${KERNEL}/initramfs.img" ]]; then
        ok "initramfs yeniden uretilmis"
    else
        warn "initramfs bulunamadi — erken KMS calismayabilir"
    fi
fi

# ---------------------------------------------------------------
head_ "9. Windows uygulamalari (.exe)"
# ---------------------------------------------------------------
# Wine'in KENDISI burada aranmiyor — bilerek imajda degil. Aranan sey
# tesisatin eksiksiz olmasi. Zincir uc halkadan olusuyor (binfmt kaydi,
# sarmalayici, MIME isleyicisi) ve biri kopuksa .exe SESSIZCE acilmiyor:
# ne hata mesaji ne gunluk kaydi. O yuzden her halka tek tek olculuyor.
have_file /usr/libexec/mfaos/run-exe.sh                "sarmalayici betik"
have_file /usr/lib/binfmt.d/10-mfaos-exe.conf          "binfmt kaydi"
have_file /usr/share/applications/mfaos-exe.desktop    ".desktop isleyicisi"
have_file /etc/xdg/mimeapps.list                       "MIME varsayilanlari"

WRAP=/usr/libexec/mfaos/run-exe.sh
BFCONF=/usr/lib/binfmt.d/10-mfaos-exe.conf

# Calistirma biti: depo Windows'ta core.filemode=false ile tutuluyor,
# yani kip yalnizca git indeksinde yasiyor. Indekse 644 girerse binfmt
# yorumlayiciyi kosturamaz ve kusur ancak gercek makinede gorunur.
if [[ -x "${WRAP}" ]]; then
    ok "sarmalayici calistirilabilir (0755)"
else
    bad "sarmalayici calistirilabilir DEGIL — binfmt onu kosturamaz"
fi

if [[ -L /usr/bin/mfaos-exe ]]; then
    ok "mfaos-exe komutu var"
else
    bad "mfaos-exe komutu yok"
fi

# Yorumlayici yolu IKI ayri dosyada elle yaziyor. Biri degisip oteki
# kalirsa kullanici "Exec format error" goruyor; burada yakaliyoruz.
BF_INT="$(awk -F: '/^:mfaos-exe:/ {print $7}' "${BFCONF}" 2>/dev/null)"
if [[ "${BF_INT}" == "${WRAP}" ]]; then
    ok "binfmt yorumlayicisi sarmalayiciyla ayni"
else
    bad "binfmt yorumlayicisi uyusmuyor: '${BF_INT:-bos}' != '${WRAP}'"
fi

# .desktop'taki Exec yolu da sarmalayiciyi gostermeli. GLib, Exec'teki
# program YOKSA girdiyi SESSIZCE atliyor — VM'de olculdu: yol yanlisken
# `gio mime` isleyiciyi hic listelemiyor ve hicbir hata vermiyor. Yani
# tek harflik bir yazim hatasi cift tiklamayi oldururken iz birakmaz.
DT_EXEC="$(awk -F= '/^Exec=/ {print $2; exit}' \
           /usr/share/applications/mfaos-exe.desktop 2>/dev/null \
           | awk '{print $1}')"
if [[ "${DT_EXEC}" == "${WRAP}" ]]; then
    ok ".desktop Exec yolu sarmalayiciyla ayni"
else
    bad ".desktop Exec yolu uyusmuyor: '${DT_EXEC:-bos}' != '${WRAP}'"
fi

# Imza MZ olmali: PE basliginin ilk iki bayti. Yanlis imza ya hicbir
# seyi yakalar ya da her seyi wine'a yonlendirir.
if grep -q '^:mfaos-exe:M::MZ::' "${BFCONF}" 2>/dev/null; then
    ok "binfmt imzasi MZ"
else
    bad "binfmt imzasi MZ degil"
fi

# F bayragi OLMAMALI. F yorumlayiciyi kayit aninda acip tutuyor ve
# gercek bir ikili olmasini sart kosuyor; bizimki kabuk betigi.
# Imajdaki qemu-aarch64-static.conf F kullaniyor (o bir ikili) — ona
# bakip buraya F eklemek kaydi sessizce bozar.
if awk -F: '/^:mfaos-exe:/ {print $8}' "${BFCONF}" 2>/dev/null | grep -q 'F'; then
    bad "binfmt'te F bayragi var — betik yorumlayiciyla kayit tutmaz"
else
    ok "binfmt'te F bayragi yok (betik yorumlayici icin dogru)"
fi

# mimeapps.list'te varsayilan yaptigimiz her tip .desktop'ta da
# bildirilmis olmali. Yalniz birinde olan bir tip icin cift tiklama
# calismiyor.
while IFS='=' read -r mt handler; do
    case "${mt}" in application/*) ;; *) continue ;; esac
    [[ "${handler}" == "mfaos-exe.desktop" ]] || continue
    if grep -q "${mt}" /usr/share/applications/mfaos-exe.desktop 2>/dev/null; then
        ok "MIME eslesmesi: ${mt}"
    else
        bad "MIME eslesmesi eksik: ${mt} .desktop'ta bildirilmemis"
    fi
done < /etc/xdg/mimeapps.list

# Dosyalar isleyiciyi bu onbellekten okuyor. Girdi yoksa .desktop
# dosyasi dogru olsa bile cift tiklama bir sey yapmiyor.
if grep -q 'mfaos-exe.desktop' /usr/share/applications/mimeinfo.cache 2>/dev/null; then
    ok "mimeinfo.cache'te kayitli"
else
    bad "mimeinfo.cache'te yok — Dosyalar isleyiciyi gormez"
fi

# Wine imajda OLMAMALI. Bu bir hata degil, dogrulanmasi gereken bir
# KARAR: kazara katmanlanirsa (bir bagimlilik onu cekebilir) imaj
# 2 GiB sisiyor ve kimse farketmiyor.
if command -v wine >/dev/null 2>&1; then
    warn "imajda wine var (~2 GiB) — motorun Flatpak'ten gelmesi bekleniyor"
else
    ok "wine imajda degil (motor Flatpak'ten gelecek)"
fi

# ---------------------------------------------------------------
# Kontrol sayisini betik kendisi bildiriyor: dokumandaki sabit bir sayi
# bayatlar, ciktidaki sayi bayatlamaz.
printf '\n\033[1mSonuc:\033[0m %d kontrol — %d gecti, %d hata, %d uyari\n' \
    "$((PASS+FAIL+WARN))" "${PASS}" "${FAIL}" "${WARN}"
if [[ "${FAIL}" -gt 0 ]]; then
    printf '\033[31mImaj kullanilabilir durumda degil.\033[0m\n'
    exit 1
fi
printf '\033[32mImaj dogrulandi.\033[0m\n'
