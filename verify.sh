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

ok()   { printf '  \033[32m  OK  \033[0m %s\n' "$1"; }
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
head_ "3. Guncelleme mekanizmasi"
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

# ---------------------------------------------------------------
head_ "4. bootc gereksinimleri"
# ---------------------------------------------------------------
VAR_FILES="$(find /var -mindepth 1 \( -type f -o -type l \) 2>/dev/null | wc -l)"
if [[ "${VAR_FILES}" -eq 0 ]]; then
    ok "/var temiz (bos dizinler normal)"
else
    warn "/var icinde ${VAR_FILES} duz dosya var — kurulumda kaybolur:"
    find /var -mindepth 1 \( -type f -o -type l \) 2>/dev/null | head -10 | sed 's/^/           /'
fi

# --- Kimlik ---
if grep -q '^PRETTY_NAME=.*mfaOS' /usr/lib/os-release 2>/dev/null; then
    ok "sistem kimligi: $(. /usr/lib/os-release; echo "${PRETTY_NAME}")"
else
    warn "os-release hala Fedora olarak gorunuyor"
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
if [[ "${NVIDIA_ENABLED:-0}" == "1" ]]; then
head_ "5. NVIDIA"
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
printf '\n\033[1mSonuc:\033[0m %d hata, %d uyari\n' "${FAIL}" "${WARN}"
if [[ "${FAIL}" -gt 0 ]]; then
    printf '\033[31mImaj kullanilabilir durumda degil.\033[0m\n'
    exit 1
fi
printf '\033[32mImaj dogrulandi.\033[0m\n'
