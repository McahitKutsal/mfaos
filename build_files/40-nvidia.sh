#!/usr/bin/env bash
# NVIDIA surucusu — SADECE nvidia varyantinda calisir.
#
# Buradaki kritik fikir: cekirdek modulu IMAJ DERLENIRKEN derlenir.
# Degismez bir sistemde calisma zamaninda DKMS derlemesi yapamazsin;
# /usr salt okunur. Modul imaja girmezse makine siyah ekranla acilir.
set -euo pipefail

PKG="dnf5"
command -v dnf5 >/dev/null 2>&1 || PKG="dnf"

# Zaten kurulu paketleri istemek dnf5'te tum islemi dusuruyor. Depoda
# olmayan bir paket de ayni sekilde dusuruyor. Ikisini de onceden eliyoruz.
pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
pkg_available() { ${PKG} repoquery --quiet "$1" 2>/dev/null | grep -q .; }

# Olmazsa derlemeyi durdururuz: bunlar olmadan GPU hic calismaz.
install_required() {
    local pkg missing=()
    for pkg in "$@"; do
        pkg_installed "${pkg}" && continue
        if ! pkg_available "${pkg}"; then
            echo "HATA: zorunlu paket depoda yok: ${pkg}" >&2
            echo "      RPM Fusion paketi yeniden adlandirmis olabilir." >&2
            exit 1
        fi
        missing+=("${pkg}")
    done
    [[ ${#missing[@]} -eq 0 ]] && { echo "  (zorunlular zaten kurulu)"; return 0; }
    echo "  kurulacak: ${missing[*]}"
    ${PKG} -y install "${missing[@]}"
}

# Olmazsa uyarip devam ederiz. RPM Fusion paket adlarini ara sira
# degistiriyor (nvidia-vaapi-driver -> libva-nvidia-driver gibi); ikincil
# paketler yuzunden tum derlemeyi kaybetmiyoruz.
install_optional() {
    local pkg missing=() skipped=()
    for pkg in "$@"; do
        pkg_installed "${pkg}" && continue
        if pkg_available "${pkg}"; then missing+=("${pkg}"); else skipped+=("${pkg}"); fi
    done
    [[ ${#skipped[@]} -gt 0 ]] && echo "  UYARI: depoda yok, atlandi: ${skipped[*]}"
    [[ ${#missing[@]} -eq 0 ]] && return 0
    echo "  kurulacak: ${missing[*]}"
    ${PKG} -y install "${missing[@]}"
}

echo "==> NVIDIA surucusu (zorunlu)"
install_required akmod-nvidia xorg-x11-drv-nvidia-cuda

echo "==> Ek bilesenler (opsiyonel)"
# xorg-x11-drv-nvidia-power: laptop suspend/resume icin onemli
# libva-nvidia-driver: VA-API donanim kod cozme (eski adi nvidia-vaapi-driver)
install_optional \
    xorg-x11-drv-nvidia-power \
    libva-nvidia-driver \
    libva-utils \
    vulkan-loader

# Imajdaki cekirdegin tam surumu. akmod bunun karsisinda derlenmeli;
# surum kaymasi olursa modul yuklenmez.
KERNEL="$(rpm -q kernel-core --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | tail -1)"
echo "Hedef cekirdek: ${KERNEL}"

akmods --force --kernels "${KERNEL}"

# Dogrulama. Bu kontrol olmazsa acilmayan bir imaji farkinda olmadan
# yayinlarsin — ve filodaki NVIDIA makineleri sabaha siyah ekranda bulursun.
if ! modinfo -k "${KERNEL}" nvidia >/dev/null 2>&1; then
    echo "HATA: nvidia cekirdek modulu derlenmedi." >&2
    echo "      akmods ciktisina bak: /var/cache/akmods/" >&2
    exit 1
fi
echo "nvidia.ko dogrulandi."

# ---------------------------------------------------------------
# Secure Boot modul imzalama
# ---------------------------------------------------------------
# NVIDIA modulu imzasiz gelir. Secure Boot acik bir makinede Fedora
# cekirdegi otomatik olarak lockdown=integrity'ye girer ve imzasiz
# modulu REDDEDER. Yani NVIDIA + Secure Boot = kendi MOK anahtarinla
# imzalamak zorundasin.
if [[ -f /run/secrets/mok.key && -f /run/secrets/mok.der ]]; then
    echo "MOK anahtari bulundu, modul imzalaniyor."
    find "/usr/lib/modules/${KERNEL}" -name 'nvidia*.ko*' -print0 |
    while IFS= read -r -d '' mod; do
        /usr/src/kernels/"${KERNEL}"/scripts/sign-file \
            sha256 /run/secrets/mok.key /run/secrets/mok.der "${mod}"
    done
else
    echo "UYARI: MOK anahtari yok — nvidia modulu IMZASIZ."
    echo "       Bu imaj Secure Boot acik makinelerde GPU'yu kullanamaz."
fi

# ---------------------------------------------------------------
# initramfs: erken KMS
# ---------------------------------------------------------------
# nvidia-drm.modeset=1'in ise yaramasi icin modul initramfs'te olmali.
# Olmazsa acilista nouveau->nvidia gecisinde ekran titremesi/siyahlik olur.
dracut --force --no-hostonly --kver "${KERNEL}" \
    --add-drivers " nvidia nvidia_modeset nvidia_uvm nvidia_drm " \
    "/usr/lib/modules/${KERNEL}/initramfs.img"

# ---------------------------------------------------------------
# Cekirdek argumanlari
# ---------------------------------------------------------------
mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/20-nvidia.toml <<'KARGS_EOF'
kargs = [
  # nouveau'yu tamamen devre disi birak — iki surucu ayni GPU'yu
  # tutmaya calisirsa acilis bozulur.
  "rd.driver.blacklist=nouveau",
  "modprobe.blacklist=nouveau",

  # Wayland icin zorunlu.
  "nvidia-drm.modeset=1",

  # Laptop'ta kritik: suspend sirasinda VRAM icerigini koru.
  # Bu olmadan uyku sonrasi pencereler bozuk geri geliyor.
  "nvidia.NVreg_PreserveVideoMemoryAllocations=1",
]
KARGS_EOF

# Suspend/resume servisleri — laptop icin sart.
systemctl enable nvidia-suspend.service nvidia-resume.service 2>/dev/null || true
systemctl enable nvidia-hibernate.service 2>/dev/null || true

echo "NVIDIA tamam (cekirdek ${KERNEL})."
