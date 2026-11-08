# MFAOS

Degismez (immutable), imzali, atomik guncellenen bir GNOME masaustu
isletim sistemi. Fedora Silverblue tabani uzerine kurulu, `bootc` ile
dagitilir.

Isletim sistemi bir **konteyner imaji**. Onu bu depoda tanimliyorsun,
CI derleyip imzaliyor, makineler cekip boot ediyor. Kurulumdan sonra
hicbir makineye elle dokunmuyorsun: degisiklik imaja girer, makineler
onu alir.

---

> **Komutlar:** `KOMUTLAR.md` — derleyip QEMU'da gormek icin tek
> satirlik basvuru kagidi.
>
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
  │       ▼  boot basarisiz? (greenboot saglik kontrolu)            │
  │  boot_counter sifira iner ── onceki deployment acilir           │
  └─────────────────────────────────────────────────────────────────┘
```

Zincirdeki kritik halka `policy.json`: mfaos depolarindan gelen imzasiz
bir imaj makineye hic inmez. Dikkat — politikanin varsayilani
`insecureAcceptAnything`, yani garanti "mfaos deposu dogrulanir",
"hicbir imzasiz imaj kabul edilmez" degil. Podman ve Flatpak'in baska
registry'lerden cekebilmesi icin bilincli bir taviz.

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
./test.sh boot      # build + verify + vm — bastan sona tek komut

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

## Otomatik geri donus

"Bozuk guncelleme kendini geri alir" bootc'nin kendi davranisi degil.
bootc deployment'i stage eder; acilmazsa elinde bootloader menusu
kalir, o kadar. Otomatik geri donus `greenboot`'tan geliyor:

1. Yeni deployment stage edilirken `greenboot-set-rollback-trigger`
   GRUB'un `boot_counter` sayacini kuruyor.
2. Acilista `greenboot-healthcheck` zorunlu kontrolleri calistiriyor.
3. Gecerse sayac siliniyor, `boot_success=1` yaziliyor.
4. Gecmezse makine yeniden basliyor. Sayac sifira varinca (varsayilan
   3 deneme) onceki deployment aciliyor.

Zorunlu kontrol tek sey soruyor: **grafik oturum acildi mi?**
Masaustunde bozuk guncellemenin asil belirtisi bu — cekirdek modulu
surum kaymasi, bozuk bir cekirdek argumani, kirik bir mesa guncellemesi;
hepsi ayni yerde, siyah ekranda birlesiyor.

| Kontrol | Basarisiz olursa |
|---|---|
| `required.d/50-mfaos-desktop.sh` | geri donusu TETIKLER |
| `wanted.d/50-mfaos-integrity.sh` | sadece gunluge yazar |

`required.d`'ye kontrol eklemek kolay ama tehlikeli: her yanlis
"basarisiz", calisan bir makineyi geri dondurur — yani kontrolun
kendisi kesinti sebebi olur. Emin olmadigin her sey `wanted.d`'ye.

**`greenboot-default-health-checks` bilerek kurulmuyor.** Icindeki
`01_repository_dns_check.sh` *zorunlu* bir kontrol ve iki sebeple
masaustune uymuyor: `/etc/ostree/remotes.d` yoksa dogrudan basarisiz
oluyor (bootc ile kurulan makinede kaynak bir konteyner registry'si,
ostree remote degil), ve depo alan adlarinin DNS cozumlemesini sart
kosuyor — laptop ucakta ya da captive portal arkasinda agsiz acilir.
Ikisi de saglikli bir makineyi geri dondurur.

Durumu gormek:

```bash
journalctl -u greenboot-healthcheck.service -b
sudo grub2-editenv - list | grep boot_      # boot_counter / boot_success
```

> Bu zincir **henuz gercek bir bozuk guncellemeyle test edilmedi.**
> `DEVAM.md` Adim 2 tam olarak bunu yapiyor.

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
| Windows (.exe) | Wine Flatpak'ten; `./app.exe` kutudan calisir |
| CLI / gelistirme | `distrobox create` icinde |
| Sistem servisi, surucu | Containerfile'a ekle, imaji yeniden yayinla |

Bu ayrim projenin kalbi. Imaja her ekledigin sey her makineye ve her
guncellemeye tasinir — ve senin bakim yukun olur.

### Windows uygulamalari (.exe)

Calisiyor — motor imajda olmadan. Imajda yalnizca tesisat var: `MZ`
imzasini yakalayan bir `binfmt` kaydi, bir MIME isleyicisi ve
`mfaos-exe` komutu, toplam birkac KB. Motoru bir kez kuruyorsun:

```bash
flatpak install flathub com.usebottles.bottles   # grafik arayuz, sise yonetimi
flatpak install flathub org.winehq.Wine          # ya da yalin motor
```

Sonrasi yerli gibi:

```bash
chmod +x kurulum.exe && ./kurulum.exe    # Dosyalar'da cift tiklamak da calisir
```

Neden imaja katmanlanmadi: olculdu — `dnf install wine` Fedora 44'te
112 paket ve 2,0 GiB kurulu boyut demek, ve `.exe` calistirmayacak
makinelere de giderdi. Flatpak yolu imajda 0 bayt tutuyor ve maliyeti
yalnizca isteyen makineye yikliyor. Kullanim, kum havuzu izinleri ve
sinirlar: [KOMUTLAR.md](KOMUTLAR.md).

---

## Yol haritasi

**Faz 1 — calisir hale getir** *(tamam)*
- [x] Containerfile + derleme scriptleri
- [x] sysctl / kernel arg sertlestirmesi
- [x] CI + cosign imzalama
- [x] Registry yollari dolduruldu (`ghcr.io/mcahitkutsal`)
- [x] cosign anahtari uretildi, ortak anahtar imaja girdi
- [x] Imaj derlendi, `verify.sh` gecti, QEMU'da boot etti
- [x] CI imaj icerigini **push'tan once** dogruluyor
- [x] greenboot: basarisiz boot sonrasi geri donus zinciri kuruldu
- [ ] NVIDIA varyanti — script hazir, CI'da kapali (Fedora 44 engeli)

**Faz 2 — gunluk surucu yap** *(simdi buradasin)*
- [ ] ghcr paketini herkese acik yap
- [ ] **Geri donusu gercekten test et:** bilerek bozuk bir imaj yayinla,
      greenboot'un devreye girdigini gor
- [ ] Gercek makineye kurulum (`anaconda-iso`)
- [ ] Flatpak/distrobox akisini oturt
- [ ] Ikinci makineye kur, guncellemenin filoya yayildigini dogrula
- [ ] `/etc` kisminda ne degistigini izle (`ostree admin config-diff`)
- [ ] Yedekleme: `/var/home` disinda hicbir sey kalici degil

**Faz 3 — zinciri muhurle**
- [ ] MOK anahtari + NVIDIA modul imzalama (NVIDIA makineleri icin zorunlu)
- [ ] LUKS2 + TPM2 muhurleme, yaninda kurtarma parolasi
- [ ] Kendi Secure Boot anahtarlarini kaydet (`sbctl`) —
      `SECURE_BOOT=1 ./test.sh vm` ile test edilir
- [ ] `lockdown=integrity` ve `module.sig_enforce=1`'i ac
- [ ] Sealed imaja gec: systemd-boot + imzali UKI + fs-verity'li composefs

## Bilinen riskler

Asagidakiler ya yasandi ya da hala acik. Derlemenin gecmesi imajin
dogru oldugu anlamina gelmedigi icin `verify.sh` bunlarin cogunu artik
tek tek kontrol ediyor; kontrol sayisini betik kendisi bildiriyor.

- NVIDIA: Fedora 44'te konteyner icinde akmod derlenemiyor
  (`akmodsbuild` kontrolu `[[ -w / ]]`'ye bakiyor). Varyant CI'da
  kapali; cozum ublue-os/akmods'un hazir RPM'lerini kopyalamak.
- `firewall-offline-cmd --set-default-zone=block` mDNS ve yazici
  kesfini kirar. Bilincli taviz — `verify.sh` artik en azindan
  uygulanip uygulanmadigini dogruluyor.
- RPM Fusion surumu taban imaj surumuyle eslesmezse paket kurulumu duser.
- Fedora 45 gecisinde derleme scriptleri kirilacak: taban imaj degisince
  paket adlari ve dizin yapilari kayiyor.
- greenboot geri donusu **GRUB'a bagli degil**: sayaci GRUB tutuyor
  ama geri donusu greenboot kullanici alaninda yapiyor ("Boot counter
  exhausted and next-deployment-id is set - initiating rollback").
  Sonuc: hic acilmayan, greenboot'a kadar gelmeyen bir deployment bu
  zincirle kurtarilamaz. Gercek bir bozuk guncellemeyle VM'de olculdu.
  Ayrica `/boot` md RAID1 uzerindeyse `boot_counter` kalici olmuyor
  (greenboot-rs #220) — tek diskli kurulumda sorun degil.
- Bellek okuyan Windows uygulamalari (anti-cheat, overlay araclari)
  `kernel.yama.ptrace_scope = 1` yuzunden duser. Fedora varsayilani 0;
  bu bizim sertlestirme kararimiz. Dar kapsamli duzeltme
  (`setcap cap_sys_ptrace` wineserver'a) Flatpak icinde yapilamiyor.

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
