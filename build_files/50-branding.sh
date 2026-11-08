#!/usr/bin/env bash
# Sistem kimligi: makine kendini "Fedora Linux" degil "MFAOS" olarak tanitsin.
#
# ONEMLI: ID=fedora oldugu gibi kaliyor. RPM Fusion depo yapilandirmalari,
# Flatpak runtime eslestirmesi ve ucuncu parti kurulum scriptleri bu alana
# bakiyor; degistirirsen paket yonetimi sessizce bozulur.
set -euo pipefail

REPO_URL="https://github.com/McahitKutsal/mfaos"

LOGO_KEY=""
if [[ -f "/usr/share/pixmaps/${OS_NAME}.png" ]] \
   || compgen -G "/usr/share/icons/hicolor/*/apps/${OS_NAME}.png" >/dev/null; then
    LOGO_KEY="${OS_NAME}"
    echo "Logo bulundu: ${OS_NAME}"
else
    echo "Logo yok, Fedora logosu korunuyor"
fi

EXCLUDE='^(DEFAULT_HOSTNAME|NAME|VERSION|PRETTY_NAME|VARIANT|VARIANT_ID|HOME_URL|BUG_REPORT_URL|SUPPORT_URL|DOCUMENTATION_URL|REDHAT_BUGZILLA_PRODUCT|REDHAT_BUGZILLA_PRODUCT_VERSION|REDHAT_SUPPORT_PRODUCT|REDHAT_SUPPORT_PRODUCT_VERSION'
[[ -n "${LOGO_KEY}" ]] && EXCLUDE="${EXCLUDE}|LOGO"
EXCLUDE="${EXCLUDE})="

NEW=/tmp/os-release.new
grep -v -E "${EXCLUDE}" /usr/lib/os-release \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' > "${NEW}"

{
    echo "NAME=\"${OS_PRETTY_NAME}\""
    echo "PRETTY_NAME=\"${OS_PRETTY_NAME} ${OS_VERSION}\""
    echo "VERSION=\"${OS_VERSION}\""
    echo "VARIANT=\"${OS_PRETTY_NAME} ${OS_VERSION}\""
    echo "MFAOS_VERSION=\"${OS_VERSION}\""
    echo "VARIANT_ID=${OS_NAME}"
    echo "DEFAULT_HOSTNAME=${OS_NAME}"
    echo "HOME_URL=\"${REPO_URL}\""
    echo "DOCUMENTATION_URL=\"${REPO_URL}\""
    echo "BUG_REPORT_URL=\"${REPO_URL}/issues\""
    echo "SUPPORT_URL=\"${REPO_URL}/issues\""
    echo "MFAOS_IMAGE_REF=\"${IMAGE_REF}\""
    echo "MFAOS_BUILD_DATE=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    [[ -n "${LOGO_KEY}" ]] && echo "LOGO=${LOGO_KEY}"
} >> "${NEW}"

if grep -vqE '^[A-Za-z_][A-Za-z0-9_]*=' "${NEW}"; then
    echo "HATA: os-release icinde gecersiz satir var:" >&2
    grep -vnE '^[A-Za-z_][A-Za-z0-9_]*=' "${NEW}" >&2
    exit 1
fi

cat "${NEW}" > /usr/lib/os-release
rm -f "${NEW}"

if [[ -n "${LOGO_KEY}" ]] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -qf /usr/share/icons/hicolor 2>/dev/null || true
fi

# Aygit adi. GNOME'un "Sistem Hakkinda > Aygit Adi" satirini
# cc_hostname_get_display_hostname() belirliyor: once PRETTY_HOSTNAME'e
# bakiyor, yoksa hostname'e dusuyor.
#
# PRETTY_HOSTNAME -> /etc/machine-info (gosterilen ad: MFAOS)
# hostname        -> os-release'deki DEFAULT_HOSTNAME (agdaki ad: mfaos)
#
# /etc/hostname'e YAZMIYORUZ ve yazamayiz: buildah da podman gibi
# /etc/hostname, /etc/hosts ve /etc/resolv.conf dosyalarini bind-mount
# ediyor, yani konteyner derlemesinde oraya yazilan sey KATMANA HIC
# GIRMIYOR. Ilk denemede tam bu oldu: machine-info imaja girdi,
# hostname girmedi ve makine kendini "fedora" diye tanitti.
#
# Dogru mekanizma os-release'in DEFAULT_HOSTNAME alani (systemd 248+):
# "/etc/hostname yoksa ve baska bir kaynak belirtmiyorsa" kullanilan
# deger. Image tabanli sistemler icin zaten bunun icin var.
#
# Ikisi de VARSAYILAN, kilit degil: kullanici Ayarlar'dan degistirince
# /etc/hostname olusuyor ve o kazaniyor — istedigimiz de bu.
printf 'PRETTY_HOSTNAME="%s"\n' "${OS_PRETTY_NAME}" > /etc/machine-info

# Dogrulama burada, cunku verify.sh konteyner icinde calisiyor.
grep -q "^PRETTY_HOSTNAME=\"${OS_PRETTY_NAME}\"\$" /etc/machine-info || {
    echo "HATA: /etc/machine-info PRETTY_HOSTNAME yazilamadi." >&2
    exit 1
}
grep -q "^DEFAULT_HOSTNAME=${OS_NAME}\$" /usr/lib/os-release || {
    echo "HATA: os-release'e DEFAULT_HOSTNAME yazilamadi." >&2
    exit 1
}

# DEFAULT_HOSTNAME tek basina YETMIYOR. Adi initramfs'in systemd'si
# koyuyor, kendi os-release'ine gore, ve orada bu alan yok: initramfs
# temel imajdan geliyor, bu adimdan once uretilmis. Olculen sonuc —
# Ayarlar'daki aygit adi dogru (PRETTY_HOSTNAME oradan okunuyor), ama
# kabukta ve agda ad `fedora` kaliyor. Asagidaki birim adi acilista bir
# kez duzeltiyor; statik ad varsa hic kosmuyor.
systemctl enable mfaos-hostname.service 2>/dev/null || true

# `systemctl enable`in cikis kodu konteynerde guvenilir degil; gercek
# kosulu — sembolik bagin olusup olusmadigini — kendimiz kontrol ediyoruz.
if find /etc/systemd/system /usr/lib/systemd/system \
     -name mfaos-hostname.service -type l 2>/dev/null | grep -q .; then
    echo "  mfaos-hostname.service etkin"
else
    echo "HATA: mfaos-hostname.service etkinlestirilemedi — ad 'fedora' kalir." >&2
    exit 1
fi

# Calistirma biti olmayan ExecStart birimi 203/EXEC ile duser.
[[ -x /usr/libexec/mfaos/set-default-hostname.sh ]] || {
    echo "HATA: set-default-hostname.sh calistirilabilir degil." >&2
    exit 1
}
echo "Kimlik: $(grep '^PRETTY_NAME=' /usr/lib/os-release)"
echo "Aygit adi: ${OS_PRETTY_NAME} (hostname: ${OS_NAME})"
exit 0
