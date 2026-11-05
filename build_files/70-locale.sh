#!/usr/bin/env bash
# Turkce dil destegi ve klavye duzeni. Bunlar VARSAYILAN, kilit degil.
set -euo pipefail

PKG="dnf5 -y"; command -v dnf5 >/dev/null 2>&1 || PKG="dnf -y"

install_if_missing() {
    local pkg missing=()
    for pkg in "$@"; do rpm -q "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}"); done
    [[ ${#missing[@]} -eq 0 ]] && { echo "  (zaten kurulu)"; return 0; }
    echo "  kurulacak: ${missing[*]}"
    ${PKG} install "${missing[@]}"
}

# Fedora imajlari yer kazanmak icin tum yerel ayarlari atiyor,
# istedigimizi acikca eklemek zorundayiz.
echo "==> Turkce dil paketleri"
install_if_missing glibc-langpack-tr langpacks-tr

# Paket kurulu gorunup veri eksik olursa sistem sessizce C.UTF-8'e duser.
if ! locale -a 2>/dev/null | grep -qi '^tr_TR'; then
    echo "HATA: tr_TR yerel ayari uretilmemis." >&2
    exit 1
fi
echo "  tr_TR.UTF-8 dogrulandi"

# local.d ayarlarinin kullaniciya ulasmasi icin profilde system-db:local
# olmali. Uzerine yazmak yerine eksikse ekliyoruz.
PROFILE=/etc/dconf/profile/user
mkdir -p "$(dirname "${PROFILE}")"
if [[ ! -f "${PROFILE}" ]]; then
    printf 'user-db:user\nsystem-db:local\n' > "${PROFILE}"
elif ! grep -q '^system-db:local$' "${PROFILE}"; then
    echo 'system-db:local' >> "${PROFILE}"
fi

command -v dconf >/dev/null 2>&1 && { dconf update 2>/dev/null || true; }
echo "Dil ve klavye tamam: tr_TR.UTF-8 / Turkce Q"
