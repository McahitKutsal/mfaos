#!/usr/bin/env bash
# Katman 4: guncelleme ve OTOMATIK geri donus testi.
#
# VM'IN ICINDE calisir, imajin icinde degil. Ayrimi karistirmamak lazim:
#   verify.sh        -> zincir KURULU mu    (imaj icinde, podman run)
#   rollback-test.sh -> zincir CALISIYOR mu (acilmis sistemde)
#
#   sudo ./rollback-test.sh status   zincirin su anki durumu
#   sudo ./rollback-test.sh arm      kasitli basarisiz kontrol kur
#   sudo ./rollback-test.sh disarm   kontrolu ve sayaci kaldir
#
# Neden ikinci bir bozuk imaj yayinlamiyoruz: greenboot ozel kontrolleri
# /etc/greenboot/check/required.d'den de okuyor (/usr/lib ostree'de salt
# okunur). Oraya bilerek basarisiz bir kontrol koymak, bozuk bir imaj
# uretip imzalayip registry'e koymakla AYNI mekanizmayi test ediyor.
set -uo pipefail

PASS=0; FAIL=0; WARN=0
ok()    { printf '  \033[32m  OK  \033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  \033[31m HATA \033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn()  { printf '  \033[33mUYARI \033[0m %s\n' "$1"; WARN=$((WARN+1)); }
info()  { printf '         %s\n' "$1"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

CHECK=/etc/greenboot/check/required.d/99-mfaos-rollback-test.sh
COUNT=/var/lib/mfaos-rollback-test.count
BEFORE=/var/lib/mfaos-rollback-test.before
BEFORE_DEPLOY=/var/lib/mfaos-rollback-test.before-deploy

# ASIL olcut bu: deployment'in ostree checksum'i. Kimligi biz
# uretmiyoruz, ostree uretiyor, ve her deployment'in checksum'i yapisal
# olarak ayri.
#
# Neden gerekti: hukum once YALNIZCA MFAOS_BUILD_DATE'e bakiyordu, yani
# os-release'e KENDIMIZIN yazdigi bir alana. Iki deployment ayni
# derlemeden geliyorsa o alan AYNI olur ve hukum BOS cikar — geri donus
# olsa da olmasa da "ayni" yazar. Testin kendi sonucunu dogrulayamaz
# hale gelmesi demek bu.
#
# `*` isaretli satir acilmis deployment:
#   * default 8dc30ed5...0
#     default a89e1c3e...0 (rollback)
deploy_id() { ostree admin status 2>/dev/null | awk '/^\*/ {print $3; exit}'; }

# Acilmis OLMAYAN butun deployment'lar: stage edilen, ve/veya geri
# dusmus olan. Stage anindan sonra UC tane olabiliyor (staged + booted +
# rollback), o yuzden ilkini degil HEPSINI okuyoruz — ilkini almak
# raporda yanlis deployment'i isimlendiriyordu.
#
# Hukmun ONSARTI: bunlarin arasinda arm anindakinden FARKLI en az biri
# olmali. Yoksa karsilastirilacak iki sey yok, yani test hukumsuz.
others() { ostree admin status 2>/dev/null | awk '!/^\*/ && $1 == "default" {print $2}'; }

# Destekleyici olcut: 50-branding.sh'in yazdigi alan. Insan tarafindan
# okunabildigi icin raporda duruyor, ama hukmu tek basina VERMIYOR.
build_id() { grep -h "^MFAOS_BUILD_DATE=" /usr/lib/os-release 2>/dev/null | cut -d= -f2- | tr -d '"'; }

# Yanlis makinede calistirilmamali: `arm` bilerek basarisiz boot uretir.
# ostree ile acilmis bir sistem degilsek hemen duruyoruz.
require_ostree() {
    if [[ ! -f /run/ostree-booted ]]; then
        echo "HATA: burasi ostree/bootc ile acilmis bir sistem degil." >&2
        echo "      Bu betik VM'in ICINDE calisir, gelistirme makinesinde degil." >&2
        exit 1
    fi
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "HATA: root gerekiyor — sudo ile calistir." >&2
        exit 1
    fi
}

grubenv_path() {
    local p
    for p in /boot/grub2/grubenv /boot/efi/EFI/fedora/grubenv; do
        [[ -f "${p}" ]] && { echo "${p}"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------
cmd_status() {
    require_ostree

    head_ "1. Deployment'lar"
    if command -v bootc >/dev/null 2>&1; then
        bootc status 2>/dev/null | sed 's/^/         /' || true

        # Kayitli guncelleme kaynagi. Yerelde derlenmis bir imajdan
        # kurulduysa `localhost/...` olur ve VM icinden COZULEMEZ —
        # `bootc upgrade` tam burada patlar. Testin ilk adimi bunu
        # duzeltmek, ve o adim ayni zamanda imza zincirini sinar.
        local src
        src="$(bootc status --format json 2>/dev/null \
               | tr ',' '\n' | grep -oE '"image":"[^"]*"' | head -1 \
               | cut -d'"' -f4)"
        if [[ -z "${src}" ]]; then
            warn "guncelleme kaynagi okunamadi"
        elif [[ "${src}" == localhost/* ]]; then
            bad "guncelleme kaynagi '${src}' — VM icinden cozulemez"
            info "once: sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44"
        else
            ok "guncelleme kaynagi: ${src}"
        fi
    else
        bad "bootc ikilisi yok"
    fi

    head_ "2. greenboot zinciri"
    local u
    for u in greenboot-healthcheck.service greenboot-set-rollback-trigger.service; do
        if systemctl is-enabled --quiet "${u}" 2>/dev/null; then
            ok "${u} etkin"
        else
            bad "${u} ETKIN DEGIL — otomatik geri donus calismaz"
        fi
    done

    # Kurulu olmasi kostugu anlamina gelmiyor. Katman 4'un butun
    # meselesi bu ayrim, o yuzden bu acilista gercekten kosup kosmadigina
    # ve sonucuna ayri ayri bakiyoruz.
    if systemctl show -p ExecMainStartTimestamp --value \
       greenboot-healthcheck.service 2>/dev/null | grep -q '[0-9]'; then
        local res
        res="$(systemctl show -p Result --value greenboot-healthcheck.service 2>/dev/null)"
        case "${res}" in
            success) ok "saglik kontrolu bu acilista kostu ve GECTI" ;;
            "")      warn "saglik kontrolu kostu, sonuc okunamadi" ;;
            *)       bad "saglik kontrolu bu acilista BASARISIZ (${res})" ;;
        esac
    else
        bad "saglik kontrolu bu acilista HIC calismamis"
    fi

    head_ "3. GRUB sayaclari"
    # Otomatik geri donus, GRUB'un boot_counter'i KALICI yazabilmesine
    # bagli. Imajdan okunamayan, ancak acilmis sistemde gorulebilen sey.
    local ge
    if ge="$(grubenv_path)"; then
        ok "grubenv: ${ge}"
        local env_out bs bc
        env_out="$(grub2-editenv "${ge}" list 2>/dev/null)" || env_out=""
        bs="$(printf '%s\n' "${env_out}" | grep '^boot_success=' | cut -d= -f2)"
        bc="$(printf '%s\n' "${env_out}" | grep '^boot_counter=' | cut -d= -f2)"

        if [[ "${bs}" == "1" ]]; then
            ok "boot_success=1 (saglikli acilis isaretlenmis)"
        elif [[ -z "${bs}" ]]; then
            warn "boot_success yazilmamis"
        else
            bad "boot_success=${bs} — bu acilis saglikli sayilmadi"
        fi

        if [[ -z "${bc}" ]]; then
            ok "boot_counter yok (saglikli sistemde temizlenmis olmali)"
        else
            warn "boot_counter=${bc} — deneme suruyor, geri donus yaklasiyor"
        fi
    else
        bad "grubenv bulunamadi — boot_counter kalici yazilamaz"
        info "bu durumda otomatik geri donus HIC calismaz"
    fi

    head_ "4. Deneme sayisi"
    if [[ -s /etc/greenboot/greenboot.conf ]]; then
        local conf
        conf="$(grep -vE '^[[:space:]]*(#|$)' /etc/greenboot/greenboot.conf 2>/dev/null)"
        if [[ -n "${conf}" ]]; then
            ok "greenboot.conf ayarli:"
            printf '%s\n' "${conf}" | sed 's/^/           /'
        else
            ok "greenboot.conf bos — paket varsayilani gecerli"
        fi
    else
        ok "greenboot.conf yok — paket varsayilani gecerli"
    fi
    # Sayiyi tahmin etmiyoruz: kurulu greenboot'un kendi dosyalarindan
    # okuyoruz. Surum degisirse yanlis bir sayi yazmaktansa hic yazmayalim.
    local knob
    knob="$(grep -rhoE 'GREENBOOT_MAX_BOOT_ATTEMPTS:?-?[0-9]+' \
            /usr/libexec/greenboot /usr/lib/systemd/system 2>/dev/null \
            | grep -oE '[0-9]+$' | head -1)"
    if [[ -n "${knob}" ]]; then
        info "greenboot varsayilan deneme sayisi: ${knob}"
    fi

    head_ "5. Test kontrolu"
    # Asil hukum. "Sonunda acildi" HICBIR sey kanitlamiyor: kontrol
    # kendini kapattigi icin geri donus olsa da olmasa da aciliyor,
    # ustelik sayac /var'da oldugu ve /var paylasildigi icin o kapanma
    # durumu her iki deployment'ta gecerli. Ayirt eden tek sey HANGI
    # deployment'in acildigi.
    if [[ -f "${BEFORE_DEPLOY}" ]]; then
        local bd now_d oth bi o have_other
        bd="$(cat "${BEFORE_DEPLOY}" 2>/dev/null)"
        now_d="$(deploy_id)"
        oth="$(others)"
        bi="$(cat "${BEFORE}" 2>/dev/null || true)"
        info "arm aninda deployment: ${bd:-?}"
        info "su an deployment:      ${now_d:-?}"
        info "imaj (destekleyici):   ${bi:-?} -> $(build_id)"

        # ONSART: arm anindakinden FARKLI en az bir deployment olmali.
        # Stage edilen sey acilmis olanla ayni commit'e cozulduyse test
        # hicbir sey olcmemistir; orada "gecti" demek yanlis olur.
        have_other=0
        while read -r o; do
            [[ -z "${o}" ]] && continue
            info "diger deployment:      ${o}"
            if [[ "${o}" != "${bd}" ]]; then have_other=1; fi
        done <<<"${oth}"
        [[ -z "${oth}" ]] && info "diger deployment:      yok"

        if [[ -z "${bd}" || -z "${now_d}" ]]; then
            warn "deployment kimligi okunamadi, hukum verilemiyor"
        elif [[ "${have_other}" -eq 0 ]]; then
            bad "arm anindakinden farkli deployment yok — test HUKUMSUZ"
            info "stage islememis ya da ayni commit'e cozulmus;"
            info "ostree admin status'ta IKI ayri checksum gormelisin"
        elif [[ "${now_d}" == "${bd}" ]]; then
            ok "GERI DONUS GERCEKLESTI — arm oncesi deployment'tasin"
        else
            bad "geri donus OLMADI — yeni deployment'ta acilmissin"
            info "greenboot kontrolu basarisizdi ama geri donus yapilmadi"
        fi
    elif [[ -f "${BEFORE}" ]]; then
        # Eski bir arm'dan kalma kayit: deployment kimligi yok, yalnizca
        # imaj kimligi var. O tek basina hukum veremiyor.
        warn "yalnizca imaj kimligi kayitli (eski arm) — yeniden arm et"
    fi

    if [[ -f "${CHECK}" ]]; then
        local n
        n="$(cat "${COUNT}" 2>/dev/null || echo 0)"
        warn "KASITLI BASARISIZ kontrol kurulu (${n} kez basarisiz oldu)"
        info "kaldirmak icin: sudo $0 disarm"
    else
        ok "kasitli basarisiz kontrol kurulu degil (normal durum)"
    fi

    printf '\n\033[1mSonuc:\033[0m %d kontrol — %d gecti, %d hata, %d uyari\n' \
        "$((PASS + FAIL + WARN))" "${PASS}" "${FAIL}" "${WARN}"
    [[ "${FAIL}" -gt 0 ]] && return 1
    return 0
}

# ---------------------------------------------------------------
cmd_arm() {
    require_ostree
    require_root

    # Ustte bekleyen bir gecis varken arm etmek testi OKUNAMAZ hale
    # getiriyor: reboot'ta hangi deployment'in acilacagi artik bizim
    # kurdugumuz senaryoya degil, o eski duruma bagli oluyor. Bir
    # kosuda tam olarak bu oldu — `bootOrder: rollback` ustte kalmisti,
    # acilis bambaska bir deployment'ta takildi ve hukum cikmadi.
    local st
    st="$(bootc status --format=yaml 2>/dev/null || true)"
    if grep -qE '^[[:space:]]*bootOrder:[[:space:]]*rollback' <<<"${st}" \
       || grep -qE '^[[:space:]]*rollbackQueued:[[:space:]]*true' <<<"${st}"; then
        echo "HATA: bekleyen bir geri donus var (bootOrder/rollbackQueued)." >&2
        echo "      Once temiz bir zemine gec, yoksa test hukum vermez:" >&2
        echo "        sudo bootc rollback && sudo systemctl reboot" >&2
        echo "      Acildiktan sonra tekrar: sudo $0 arm" >&2
        exit 1
    fi
    if grep -qE '^  staged:' <<<"${st}" \
       && ! grep -qE '^  staged:[[:space:]]*null' <<<"${st}"; then
        echo "HATA: zaten stage edilmis bir deployment var." >&2
        echo "      arm, stage etmeden ONCE kosulmak zorunda: kasitli" >&2
        echo "      basarisiz kontrol /etc'de yasiyor ve yeni deployment'a" >&2
        echo "      ancak stage aninda yapilan 3'lu birlestirmeyle gecer." >&2
        echo "      Bekleyen stage'i at, sonra sirayi duzgun yap:" >&2
        echo "        sudo bootc rollback      # stage'i geri alir" >&2
        exit 1
    fi

    # Kontrol KENDINI SINIRLIYOR, ve bu sart. /etc bir sonraki
    # deployment'a merge ile tasiniyor, ama GERI DONUS HEDEFINDE de ayni
    # dosya var. Kendini kapatmasa makine saglikli bir acilisa hic
    # ulasmaz ve testi yapan kisi kendi VM'ini kilitler. Sayac /var'da:
    # /var deployment'lar arasinda PAYLASILDIGI icin geri donusten sonra
    # da ayni sayac okunuyor.
    install -d "$(dirname "${CHECK}")" /var/lib
    rm -f "${COUNT}"
    # Testin sonucu "acildi mi" ile OLCULEMEZ: kontrol kendini kapattigi
    # icin geri donus olsa da olmasa da sonunda aciliyor. Olculebilir tek
    # sey HANGI deployment'in acildigi. Hukmu deployment checksum'i
    # veriyor; imaj kimligi yalnizca rapora yaziliyor.
    deploy_id > "${BEFORE_DEPLOY}"
    build_id  > "${BEFORE}"

    cat > "${CHECK}" <<'CHK'
#!/usr/bin/env bash
# KASITLI BASARISIZ greenboot kontrolu — Katman 4 testi icin.
# rollback-test.sh arm kurdu; disarm kaldirir.
#
# Esik, GREENBOOT_MAX_BOOT_ATTEMPTS'ten BIR FAZLA olmak ZORUNDA. Ilk
# olcumde ikisi de 3'tu ve test hic geri donus uretmedi: greenboot sayaci
# 3 -> 2 -> 1 diye indirdi, dorduncu acilista bu kontrol kendini kapatti,
# greenboot sistemi "saglikli" gorup sayaci TEMIZLEDI ve bozuk
# deployment'i iyi olarak muhurledi. Sayacin 0'a inmesi icin dorduncu
# acilista da basarisiz olmak gerekiyor. Esigi gectikten sonra kapaniyor
# ki geri donus hedefinde de basarisiz olup makineyi kilitlemesin.
set -uo pipefail
# greenboot kontrolleri noclobber ACIK bir ortamda kosuyor: `>` var olan
# dosyayi REDDEDIYOR. Ilk denemede sayac bu yuzden 1'de kaldi ve
# kendini kapatma korumasi hic devreye girmedi. Acikca kapatiyoruz.
set +o noclobber
C=/var/lib/mfaos-rollback-test.count
MAX=3
for f in /etc/greenboot/greenboot.conf /usr/lib/greenboot/greenboot.conf; do
    [[ -r "${f}" ]] || continue
    v="$(grep -hm1 '^[[:space:]]*GREENBOOT_MAX_BOOT_ATTEMPTS=' "${f}" \
         | cut -d= -f2 | tr -dc '0-9')"
    if [[ -n "${v}" ]]; then MAX="${v}"; break; fi
done
LIMIT=$(( MAX + 1 ))
n="$(cat "${C}" 2>/dev/null || echo 0)"
if [[ "${n}" -ge "${LIMIT}" ]]; then
    echo "geri donus testi tamamlandi (${n} basarisizlik), kontrol kendini kapatti"
    exit 0
fi
echo "$((n + 1))" > "${C}"
echo "KASITLI BASARISIZLIK #$((n + 1))/${LIMIT} — Katman 4 geri donus testi" >&2
exit 1
CHK
    chmod 0755 "${CHECK}"

    echo "Kasitli basarisiz kontrol kuruldu:"
    echo "  ${CHECK}"
    echo
    echo "Sirada:"
    echo "  1. sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44"
    echo "     (upgrade DEGIL: kaynak localhost kaldiysa hicbir sey stage etmez)"
    echo "     Hedef GERCEKTEN farkli bir imaj olmali. Ayni commit'e"
    echo "     cozulurse karsilastirilacak iki deployment olmaz ve status"
    echo "     'test HUKUMSUZ' der — yanlislikla 'gecti' demez."
    echo "  2. ostree admin status       # IKI ayri checksum gorunmeli"
    echo "  3. bootc status              # 'staged' gorunmeli"
    echo "  4. sudo systemctl reboot"
    echo
    echo "Beklenen: kontrol DORT acilis boyunca basarisiz olur. greenboot"
    echo "ilk basarisizlikta boot_counter'i kurar, sonrakilerde indirir;"
    echo "sifira varinca ONCEKI deployment acilir. Dorduncu basarisizlik"
    echo "sart: ucte kesilirse sayac 1'de kalir, greenboot sistemi saglikli"
    echo "gorur ve bozuk deployment'i iyi olarak muhurler."
    echo
    echo "Donduktan sonra:  sudo $0 status   sonra   sudo $0 disarm"
}

cmd_disarm() {
    require_ostree
    require_root
    rm -f "${CHECK}" "${COUNT}" "${BEFORE}" "${BEFORE_DEPLOY}"
    echo "Test kontrolu ve sayac kaldirildi."
    echo "Bir sonraki acilista saglik kontrolu normale doner."
}

case "${1:-status}" in
    status) cmd_status ;;
    arm)    cmd_arm ;;
    disarm) cmd_disarm ;;
    *)      echo "Kullanim: $0 {status|arm|disarm}"; exit 1 ;;
esac
