# mfaos

Degismez (immutable), imzali, atomik guncellenen bir GNOME masaustu
isletim sistemi. Fedora Silverblue tabani uzerine kurulu, `bootc` ile
dagitilir.

Isletim sistemi bir **konteyner imaji**. Onu bu depoda tanimliyorsun,
CI derleyip imzaliyor, makineler cekip boot ediyor. Kurulumdan sonra
hicbir makineye elle dokunmuyorsun: degisiklik imaja girer, makineler
onu alir.

---

> **Calismaya devam etmek icin:** `DEVAM.md` — nerede kaldigimiz,
> sirada ne var, hangi tuzaklara bir daha dusmemek gerektigi.

## Iki varyant

Filo karisik oldugu icin tek imaj dogru cozum degil:

| Imaj | Kime |
|---|---|
| `mfaos` | Intel / AMD grafikli makineler |
| `mfaos-nvidia` | NVIDIA GPU'lu makineler |

Ikisi de ayni Containerfile'dan derlenir, farki `NVIDIA_ENABLED` build
argumani. NVIDIA olmayan makinelere ~1.5GB surucu ve nouveau blacklist'i
tasimanin anlami yok — ayri tutmak hem imaji kucuk hem de davranisi
ongorulebilir yapiyor.

Bir makineyi varyantlar arasinda tasimak:

```bash
sudo bootc switch ghcr.io/mcahitkutsal/mfaos-nvidia:44
```

---

## Mimari

```
  git repo (bu depo)
       │  push / gunluk zamanlayici
       ▼
  GitHub Actions ── matrix: base + nvidia
       │
       ├── push    ──> ghcr.io/mcahitkutsal/mfaos:44
       │              ghcr.io/mcahitkutsal/mfaos-nvidia:44
       └── cosign sign (ozel anahtar, repo secret'i)
                        │
                        ▼
  ┌──────────────── makineler ─────────────────────────────────────┐
  │  bootc-fetch-apply-updates.timer  (gunluk, 4s rastgele gecikme) │
  │       │                                                         │
  │       ▼                                                         │
  │  policy.json ── imza dogrulanmazsa DUR ◄── mfaos.pub            │
  │       │ gecerli                                                 │
  │       ▼                                                         │
  │  pasif slota yaz (stage) ── kullanici reboot edince aktif olur  │
  │       │                                                         │
  │       ▼  boot basarisiz?                                        │
  │  onceki deployment'a otomatik geri don                          │
  └─────────────────────────────────────────────────────────────────┘
```

Zincirdeki kritik halka `policy.json`. Imzasiz imaj makineye hic inmez.

---

## Kurulum

### 0. Ortami kontrol et

```bash
./preflight.sh
```

Dagitimini tanir, eksik araclari listeler ve kurulum komutunu yazar.
Gerekenler: podman, git, qemu, OVMF (UEFI firmware), cosign. Ayrica
`/dev/kvm` erisimi ve **en az 50GB bos disk** — taban imaj ~8GB,
katmanlarimiz ~2GB, NVIDIA varyanti +2GB, qcow2 ciktisi ~15GB.

### 1. Imzalama anahtari uret

Bu ilk adim, cunku onsuz hicbir sey calismaz.

```bash
cosign generate-key-pair
mkdir -p files/etc/pki/containers
cp cosign.pub files/etc/pki/containers/mfaos.pub
```

- `cosign.pub` → depoya commit et (hem kokte hem imajda lazim)
- `cosign.key` → GitHub'da `COSIGN_PRIVATE_KEY` secret'i
- parola → `COSIGN_PASSWORD` secret'i

`cosign.key`'i **asla** commit etme. `.gitignore` seni korur ama yine de
dikkat et: o anahtar, makinelerinin kabul edecegi her seyi uretebilir.

> **GHCR notu:** GitHub kullanici adin `McahitKutsal` ama konteyner
> registry yollari kucuk harf olmak zorunda. Depodaki tum referanslar
> `ghcr.io/mcahitkutsal/...` seklinde; CI de `repository_owner`'i kucuk
> harfe ceviriyor. Buyuk harfli bir yol yazarsan push sessizce baska bir
> namespace'e gider ya da reddedilir.

### 2. Yerelde derle ve test et

```bash
./test.sh build     # imaji derle
./test.sh verify    # icerigi dogrula — derleme basarili olsa bile calistir
./test.sh all       # build + verify
./test.sh shell     # imajin icine bak
./test.sh vm        # QEMU'da gercekten boot et

VARIANT=nvidia ./test.sh all   # NVIDIA varyanti
```

`verify` adimini atlama: derlemenin basarili bitmesi, istedigin seyin
imaja girdigi anlamina gelmiyor. Scriptlerdeki `|| true`'lar hatalari
yutar ve sessizce eksik bir imaj uretirsin. `verify.sh` sertlestirme
dosyalarini, imza zincirini, timer'lari ve NVIDIA modulunu tek tek
kontrol eder.

`./test.sh vm` atlanacak bir adim degil: `podman run` sana cekirdek,
bootloader veya boot zinciri hakkinda hicbir sey soylemez.

### 3. Makineye kur

Fedora live USB'den boot et, diski hazirla, sonra:

```bash
sudo podman run --rm --privileged --pid=host \
  --security-opt label=type:unconfined_t \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev -v /:/run/host \
  ghcr.io/mcahitkutsal/mfaos:44 \
  bootc install to-filesystem --replace=alongside /run/host/mnt
```

NVIDIA'li makinede imaj adini `mfaos-nvidia` yap. Baska fark yok.

---

## NVIDIA hakkinda bilmen gerekenler

**Modul imaj derlenirken derleniyor.** Degismez bir sistemde calisma
zamaninda DKMS derlemesi yapamazsin — `/usr` salt okunur. `40-nvidia.sh`
akmod'u imajdaki cekirdegin tam surumune karsi derliyor ve `modinfo` ile
dogruluyor. Dogrulama basarisizsa derleme duruyor; bu kontrol olmasa
siyah ekranla acilan bir imaji farkinda olmadan filoya yayarsin.

**Secure Boot ile catisma var ve bu cozulmesi gereken bir sey.** NVIDIA
modulu imzasiz gelir. Secure Boot acik bir makinede Fedora cekirdegi
otomatik olarak `lockdown=integrity`'ye girer ve imzasiz modulu reddeder.
Yani su an uc secenekten birini secmek zorundasin:

1. NVIDIA makinelerinde Secure Boot kapali — en kolay, en zayif
2. Kendi MOK anahtarinla modulu imzala — dogru cozum, Faz 3
3. NVIDIA makinelerinde surucuyu kullanma — pratik degil

`40-nvidia.sh` ikinci secenege hazir: derleme sirasinda
`/run/secrets/mok.key` ve `/run/secrets/mok.der` varsa modulu imzaliyor,
yoksa uyari basip devam ediyor. Anahtari uretip CI'a baglamak ve her
NVIDIA makinesinde `mokutil --import` ile kaydetmek kaldi.

Bu yuzden `10-hardening.toml` icindeki `module.sig_enforce=1` ve
`lockdown=integrity` hala kapali. Once MOK zincirini kur, sonra ac.

---

## Gunluk kullanim

```bash
bootc status              # hangi imajdasin, bekleyen guncelleme var mi
bootc upgrade             # simdi cek, bir sonraki reboot'ta aktif
bootc upgrade --apply     # cek ve hemen yeniden baslat
bootc rollback            # onceki deployment'a don
bootc switch <imaj>       # baska varyanta gec
```

**Uygulama kurmak:** imaja degil.

| Ne | Nereye |
|---|---|
| GUI uygulamalari | `flatpak install <app>` |
| CLI / gelistirme | `distrobox create` icinde |
| Sistem servisi, surucu | Containerfile'a ekle, imaji yeniden yayinla |

Bu ayrim projenin kalbi. Imaja her ekledigin sey her makineye ve her
guncellemeye tasinir — ve senin bakim yukun olur.

---

## Yol haritasi

**Faz 1 — calisir hale getir** *(simdi buradasin)*
- [x] Containerfile + derleme scriptleri
- [x] sysctl / kernel arg sertlestirmesi
- [x] CI + cosign imzalama, iki varyant
- [x] NVIDIA varyanti (imaj derleme zamaninda akmod)
- [x] Registry yollari dolduruldu (`ghcr.io/mcahitkutsal`)
- [ ] cosign anahtari uret
- [ ] **Ilk derleme — henuz hic calismadi**
- [ ] QEMU'da boot testi (her iki varyant)
- [ ] Laptop'a ilk kurulum

**Faz 2 — gunluk surucu yap**
- [ ] Flatpak/distrobox akisini oturt
- [ ] Ikinci makineye kur, guncellemenin filoya yayildigini dogrula
- [ ] Rollback'i gercekten test et (bilerek bozuk imaj yayinla)
- [ ] `/etc` kisminda ne degistigini izle (`ostree admin config-diff`)
- [ ] Yedekleme: `/var/home` disinda hicbir sey kalici degil

**Faz 3 — zinciri muhurle**
- [ ] MOK anahtari + NVIDIA modul imzalama (NVIDIA makineleri icin zorunlu)
- [ ] LUKS2 + TPM2 muhurleme, yaninda kurtarma parolasi
- [ ] Kendi Secure Boot anahtarlarini kaydet (`sbctl`)
- [ ] `lockdown=integrity` ve `module.sig_enforce=1`'i ac
- [ ] Sealed imaja gec: systemd-boot + imzali UKI + fs-verity'li composefs

---

## Bilinen riskler

Hicbiri henuz test edilmedi; ilk derlemede bunlardan biriyle
karsilasman muhtemel:

- Taban imajda `bootc` ikilisi olmayabilir (lint adimi artik atlaniyor, derlemeyi kirmaz)
- `avahi` kaldirma bagimlilik zincirini sürükleyebilir
- `flatpak-system-update.timer` bu isimde olmayabilir
- `firewall-offline-cmd --set-default-zone=block` mDNS ve yazici kesfini kirar
- RPM Fusion surumu taban imaj surumuyle eslesmezse paket kurulumu duser
- NVIDIA: `akmods` cekirdek surumu kaymasi — en kirilgan nokta burasi

---

## Sürüm notu

Proje Fedora 44'e sabitli. Fedora 45 3 Kasim 2026'da cikti. Birkac hafta
44'te kalmak mantikli: iki gunluk bir surumle yeni projeye baslamak,
kendi hatalarinla Fedora'nin cikis hatalarini ayni anda ayiklamak demek.
Gecis tek satir (`FEDORA_VERSION`).

---

## Kaynaklar

- [Fedora bootc dokumantasyonu](https://docs.fedoraproject.org/en-US/bootc/)
- [Sealed Fedora Atomic Desktop imajlari](https://github.com/travier/fedora-atomic-desktops-sealed)
- [Universal Blue image-template](https://github.com/ublue-os/image-template)
- [KSPP cekirdek sertlestirme onerileri](https://kspp.github.io/Recommended_Settings)
