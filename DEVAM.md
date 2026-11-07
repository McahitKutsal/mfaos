# Devam notlari

Bu dosya, calismaya baska bir oturumda devam etmek icin yazildi.
Projenin ne oldugu `README.md`'de; burada **nerede kaldigimiz**,
**sirada ne var** ve **hangi tuzaklara bir daha dusmemek gerektigi**
var.

Son guncelleme: 7 Kasim 2026

---

## 1. Nerede kaldik

### Calisan ve dogrulanmis

| Katman | Durum |
|---|---|
| 0 — gelistirme ortami (WSL2 + podman) | Tamam |
| 1 — imaj derlemesi | Tamam |
| 2 — icerik dogrulama (`verify.sh`, 40 kontrol) | Tamam |
| 3 — QEMU'da boot | Tamam |
| CI: derle -> ghcr'ye gonder -> cosign imzala -> dogrula | Tamam, yesil |

Imaj GNOME masaustu olarak aciliyor, kendini `mfaOS 0.1` diye
tanitiyor, Turkce arayuz ve Turkce Q klavye ile geliyor, Fedora
logolari (143 gorsel) kendi armamizla degismis durumda. Giris
ekraninda yatay logo, geri kalan her yerde kare arma.

### HENUZ TEST EDILMEMIS — en onemli eksik

**Katman 4: guncelleme ve geri alma.** Mimarinin butun vaadi bu ve bir
kez bile denenmedi. Yani su an "dogru tasarlanmis" bir sistem var, ama
"robust" oldugunun kaniti yok.

**Katman 5: gercek donanim.** Hicbir fiziksel makineye kurulmadi.

**Imza zincirinin makine tarafi.** CI imzaliyor, ama hicbir makine
henuz bir imzayi dogrulamadi. `policy.json`'un gercekten ise yarayip
yaramadigini bilmiyoruz.

---

## 2. Sirada ne var (oncelik sirasiyla)

### Adim 1 — ghcr paketini herkese acik yap

Depo acik olsa bile ghcr paketleri varsayilan olarak ozel. Bu
yapilmadan hicbir makine imaji cekemez.

GitHub -> profil -> Packages -> `mfaos` -> Package settings ->
Change visibility -> Public.

Dogrulama (kimlik dogrulamasi olmadan calismali):

```bash
podman pull ghcr.io/mcahitkutsal/mfaos:44
```

### Adim 2 — Katman 4: guncelleme ve geri alma testi

Projenin en kritik eksik testi. VM'de:

```bash
# 1. VM'i ghcr'deki imzali imaja bagla.
#    Bu komut ayni zamanda imza zincirinin ILK gercek sinavi:
#    policy.json imzayi dogrulayamazsa burada durur.
sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44
sudo systemctl reboot

# 2. Gorunur bir degisiklik yap (ornek: OS_VERSION'i 0.2 yap),
#    push et, CI'in yesil olmasini bekle. Sonra VM'de:
sudo bootc upgrade
bootc status          # yeni surum "staged" gorunmeli
sudo systemctl reboot
# Ayarlar -> Hakkinda: 0.2 gorunmeli

# 3. Geri alma
sudo bootc rollback
sudo systemctl reboot
# 0.1'e donmus olmali
```

**Asil test bundan sonrasi:** bilerek bozuk bir imaj yayinla (ornegin
`20-hardening.sh`'e `exit 1` koyma degil — derleme gecmeli ama sistem
acilmamali; mesela gecersiz bir cekirdek argumani) ve otomatik geri
donusun devreye girdigini gor. O mekanizma calismiyorsa "robust"
iddiasi bos.

### Adim 3 — Katman 5: gercek makineye kurulum

**Once cevaplanmasi gereken soru:** feda edilebilir bir test makinesi
var mi, yoksa hedef laptop tek makine mi? Tek makineyse once harici
diske kurup oradan boot etmek gerekir; ana diske dokunmadan.

Windows'tan calisildigi icin en guvenilir yol kurulum ISO'su:
CI'da `anaconda-iso` uretip USB'ye yazmak. Boot zincirini gercek
firmware uzerinde test etmis olursun — QEMU'nun taklit edemedigi
seyler dahil.

### Adim 4 — Faz 3: guvenlik zincirini muhurle

Ilk konusmada istenen guvenlik seviyesi burada. Sirayla:

- LUKS2 + TPM2 muhurleme (`systemd-cryptenroll --tpm2-device=auto`),
  **yaninda mutlaka kurtarma parolasi** — burada acele edilmez
- Kendi Secure Boot anahtarlarini kaydet (`sbctl`)
- `lockdown=integrity` ve `module.sig_enforce=1`'i ac
  (`files/usr/lib/bootc/kargs.d/10-hardening.toml` icinde yorumda
  duruyorlar). NVIDIA'dan ONCE acilabilir; NVIDIA eklenince modul
  imzalama kurulmadan acilmaz.
- Sealed imaj: systemd-boot + imzali UKI + fs-verity'li composefs.
  Ekosistem henuz olgunlasmadi, beklemek makul.

### Adim 5 (en sona) — NVIDIA

Bilerek en sona birakildi. Teshis ve planlanan cozum `README.md`'nin
"Bilinen riskler" bolumunde. Kisaca: Fedora 44'te konteyner icinde
akmod derlenemiyor (`akmodsbuild` kontrolu `[[ -w / ]]`'ye bakiyor),
cozum ublue-os/akmods'un hazir RPM'lerini kopyalamak.

`build_files/40-nvidia.sh` duruyor, CI'da yorumda. Acmak icin
`.github/workflows/build.yml` icindeki matrix girdisini ac.

---

## 3. Gelistirme ortami (WSL2 ozellikleri)

Proje Windows makinede, WSL2/Ubuntu icinde gelistiriliyor.

```bash
cd ~/mfaos          # ASIL kopya burada, Windows tarafinda degil
./preflight.sh      # ortam kontrolu
./test.sh all       # derle + dogrula
./test.sh vm        # QEMU'da boot et
```

Tuzaklar:

- **Proje `~/mfaos`'ta durmali.** `/mnt/c` uzerinde derleme 10 kat
  yavas; WSL'in Windows diskine erisimi bir cevirme katmanindan
  geciyor.
- **`/mnt/c` uzerinde `find` kullanma.** Ozyinelemeli tarama
  dakikalarca kilitleniyor. Dosya aramak icin dogrudan `ls <yol>`.
- **`wsl --shutdown` WSL icinden calismaz.** PowerShell'den, ya da
  `/mnt/c/Windows/System32/wsl.exe --shutdown`.
- **Grup uyeligi** (`usermod -aG`) ancak `wsl --shutdown` sonrasi
  gecerli olur; oturum kapatip acmak yetmez.
- VM testi icin `/dev/kvm` gerekiyor ve calisiyor (ic ice
  sanallastirma acik).

Degisiklik akisi: yerelde `./test.sh all` -> gecerse `git push` ->
CI iki asamayi daha yapiyor (ghcr'ye gonderme + imzalama).

---

## 4. Tekrar dusulmemesi gereken tuzaklar

Hepsi bu projede yasandi ve duzeltildi. Yeni bir derleme adimi
yazarken bunlari hatirla.

**Onbellek hatalari gizliyor.** Yerelde gecen bir derleme CI'da
patlayabilir. `/var/lib/dnf/repos` sorunu tam boyle bulundu: yerelde
dnf onbellegi sicakti, o dizinler katmana hic girmedi. **Yerelde gecti
diye emin olma; CI'in yesil olmasini bekle.**

**`os-release`'e YORUM SATIRI KOYMA.** Kabuk dosyasina benziyor ama
kati ayristiricilar duz `ANAHTAR=DEGER` listesi olarak okuyor. Bir
yorum satiri `bootc-image-builder`'i `readOSRelease: invalid input`
ile dusuruyor. `50-branding.sh` artik uretilen dosyayi kendi kontrol
ediyor.

**`ID` ve `VERSION_ID` degistirilmez.** `fedora` ve `44` kalmali. RPM
Fusion depo yapilandirmalari, Flatpak runtime eslestirmesi ve ucuncu
parti kurulum scriptleri bu alanlara bakiyor; degistirilirse paket
yonetimi sessizce bozulur. Gorunen isim/surum icin `NAME`,
`PRETTY_NAME`, `VERSION`, `MFAOS_VERSION` kullaniliyor.

**`/var` ve `/run` imajda temiz olmali.** Lint iki sey istiyor: duz
dosya olmasin, **ve** systemd-tmpfiles kaydi olmayan dizin kalmasin.
Sadece dosyalari silmek yetmiyor. `/var/lib/rpm` sembolik bag oldugu
icin suzgeclere takilmiyor ve korunuyor — silinirse `rpm` sorgulari
bozulur.

**Zaten kurulu paket istemek dnf5'te TUM islemi dusuruyor.** Depoda
olmayan paket de ayni. Bu yuzden `install_if_missing` once `rpm -q`
ile eliyor. Yeni paket eklerken bu fonksiyonu kullan, dogrudan
`dnf install` yazma.

**`/var`'a yazan ayarlar imajda kalmaz.** `/var` makinenin durumu,
imajin degil. Flatpak uzak deposu bu yuzden derleme sirasinda degil,
ilk acilista calisan `mfaos-flatpak-setup.service` ile ekleniyor.

**`cosign` ve `podman` kimlik bilgilerini ayri yerde ariyor.** podman
`auth.json`, cosign `~/.docker/config.json`. CI'da cosign'in kendi
`cosign login` adimi var; kaldirilmamali.

**GHCR yollari kucuk harf.** Kullanici adi `McahitKutsal` ama yollar
`ghcr.io/mcahitkutsal/...`. CI `${GITHUB_REPOSITORY_OWNER,,}` ile
ceviriyor.

**`/var` ayri bolum olamaz.** bootc/ostree'de `/var` kokun parcasi.
`disk-config.toml`'da tek genis kok bolumu var.

**Kok dosya sistemi `ext4` olarak sabitlendi**
(`files/usr/lib/bootc/install/20-mfaos-rootfs.toml`). Bilincli tercih:
fs-verity ext4 ve btrfs'te var, XFS'te YOK — xfs secmek Faz 3'teki
sealed imaj hedefinin onunu kapatirdi.

**Otomatik yeniden baslatma kapali.** Guncelleme pasif slota yaziliyor
(`stage-only` override), kullanici bir sonraki reboot'ta geciyor.
Masaustunde otomatik reboot kabul edilemez.

---

## 5. Bakim — projeyi bitiren sey bu

Asil maliyet derleme degil, bakim.

**Gunluk yeniden derleme kozmetik degil.** CI her gece 04:17'de
Fedora'nin o anki tabanindan yeniden derliyor; guvenlik yamalarini
boyle devraliyorsun. O zamanlayici kapatilirsa imaj donar ve CVE bakim
yuku tamamen sana gecer. Bu dagitimi Fedora tabani uzerine kurmanin
butun sebebi buydu.

**GitHub Actions bildirimlerini ac.** Sessiz basarisizlik en
tehlikelisi: gece koşan derleme kirmiziya doner ve iki hafta fark
etmezsin. CI'in surekli kirmizi durmamasi da bu yuzden onemli —
NVIDIA varyanti tam bu nedenle kapatildi.

**Fedora 45 gecisi yakinda.** Fedora 45 3 Kasim 2026'da cikti; proje
bilerek 44'te. Gecis `FEDORA_VERSION` degerini degistirmek, ama taban
imaj degisince derleme scriptleri kirilacak — `power-profiles-daemon`
ve `/var/lib/dnf` ile yasananin aynisi. Birkac hafta bekleyip gecmek
makul.

---

## 6. Proje yapisi

```
Containerfile              imaj tanimi, build arg'lari (OS_VERSION, NVIDIA_ENABLED)
build_files/build.sh       adimlari sirayla calistirir
build_files/10-packages.sh paket katmanlama
build_files/20-hardening.sh SELinux, servisler, guvenlik duvari
build_files/30-desktop.sh  flatpak + guncelleme timer'i
build_files/40-nvidia.sh   NVIDIA (su an CI'da kapali)
build_files/50-branding.sh os-release / sistem kimligi
build_files/60-logos.sh    fedora-logos degisimi + GDM logosu
build_files/70-locale.sh   Turkce dil ve klavye
files/                     imajin kok dizinine oldugu gibi kopyalanir
logo/                      logo kaynaklari (imaja girmez)
add-logo.sh                logo boyutlarini uretir: ./add-logo.sh <kare> [yatay]
preflight.sh               gelistirme ortami kontrolu
test.sh                    build | verify | shell | vm | all
verify.sh                  imaj icinde calisir, 40 kontrol
disk-config.toml           bootc-image-builder disk duzeni
```

Yeni bir derleme adimi eklerken: `build_files/` icine `NN-ad.sh`
olarak koy (sira numarasina gore calisiyor), `verify.sh`'e de bir
kontrol ekle. **Dogrulama kontrolu olmayan degisiklik sessizce
bozulabilir** — bu projede bes kez oyle oldu.
