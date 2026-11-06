#!/usr/bin/env bash
# Sistem kimligi: makine kendini "Fedora Linux" degil "mfaOS" olarak tanitsin.
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

EXCLUDE='^(NAME|VERSION|PRETTY_NAME|VARIANT|VARIANT_ID|HOME_URL|BUG_REPORT_URL|SUPPORT_URL|DOCUMENTATION_URL|REDHAT_BUGZILLA_PRODUCT|REDHAT_BUGZILLA_PRODUCT_VERSION|REDHAT_SUPPORT_PRODUCT|REDHAT_SUPPORT_PRODUCT_VERSION'
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
echo "Kimlik: $(grep '^PRETTY_NAME=' /usr/lib/os-release)"
exit 0
