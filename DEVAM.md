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
| 2 — icerik dogrulama (`verify.sh`) | Tamam |
| 3 — QEMU'da boot | Tamam |
| CI: derle -> dogrula -> ghcr'ye gonder -> cosign imzala | Dogrulama adimi yeni, CI'da denenmedi |

Imaj GNOME masaustu olarak aciliyor, kendini `MFAOS 0.1` diye
tanitiyor, aygit adi `MFAOS` (hostname `mfaos`), Turkce arayuz ve
Turkce Q klavye ile geliyor, Fedora logolari kendi armamizla degismis
durumda. Giris ekraninda yatay logo, geri kalan her yerde kare arma.
GNOME'un bagis bildirimi ve Sistem Hakkinda'daki bagis kutucugu
kaldirilmis; kutucugun gittigi ve logonun bizim oldugu QEMU'da
gozle dogrulandi.

fedora-logos'un 143 PNG/SVG'sinden 81'i degisiyor, 62'si kasitli olarak
korunuyor — plymouth animasyonu, anaconda arka planlari ve kurulum
slayt cizimleri logo degil (bak: 4. bolumdeki tuzaklar). Sayilar
Fedora 44'teki `fedora-logos-42.0.1-3` icin; paket surumu degisirse
`verify.sh` "sadece N logo degismis" diye uyarir.

### HENUZ TEST EDILMEMIS — en onemli eksik

**Katman 4: guncelleme ve geri alma.** Mimarinin butun vaadi bu ve bir
kez bile denenmedi. Otomatik geri donus artik *kurulu* (greenboot,
`build_files/25-rollback.sh`) — ama kurulu olmasi calistigi anlamina
gelmiyor. Su an "dogru tasarlanmis" bir sistem var, "robust"
oldugunun kaniti yok.

**Katman 5: gercek donanim.** Hicbir fiziksel makineye kurulmadi.

**Imza zincirinin makine tarafi.** CI imzaliyor, ama hicbir makine
henuz bir imzayi dogrulamadi. `policy.json`'un gercekten ise yarayip
yaramadigini bilmiyoruz.

**Bu oturumda eklenenlerin hicbiri derlenmedi.** greenboot adimi,
`verify.sh`'in yeni kontrolleri, CI'in dogrulama adimi, lint isi ve
yeniden yazilan `60-logos.sh` yerelde bir kez bile calismadi. Sirada
ilk is: `./test.sh all`. Kirilabilecek yerler:

- `greenboot` paket adi Fedora 44 deposunda bulunmayabilir; o zaman
  `25-rollback.sh` kasitli olarak patlar.
- Lint isi mevcut scriptlerde birikmis shellcheck uyarilarini bulabilir.
  Imaji etkilemez, sadece CI'i kirmizi yapar.
- `60-logos.sh` artik PNG basligini `od` ile kendisi okuyor; python3
  bagimliligi kalkti. Filtre ve geometri mantigi gercek fedora-logos
  dosya listesine karsi yerelde test edildi (81 degisti / 62 korundu),
  ama imajin icinde bir kez bile kosmadi.

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
**Asil test bundan sonrasi.** Otomatik geri donus artik kurulu
(`greenboot` — bkz. `build_files/25-rollback.sh`) ama bir kez bile
calistigi gorulmedi. Sirayla:

```bash
# a. Zincir ayakta mi?
systemctl is-enabled greenboot-healthcheck.service \
                     greenboot-set-rollback-trigger.service
journalctl -u greenboot-healthcheck.service -b

# b. Saglikli acilistan sonra sayac temizlenmis mi?
sudo grub2-editenv - list | grep boot_   # boot_success=1, boot_counter YOK

# c. Simdi bilerek bozuk bir imaj yayinla.
#    Derleme GECMELI ama sistem acilmamali — `exit 1` koymak ise
#    yaramaz, derlemeyi kirar. Dogru kirma yollari: gecersiz bir
#    cekirdek argumani, ya da gdm'i acilmaz hale getirmek.
#    Guncelle, reboot et, izle: makine 3 denemeden sonra 0.1'e donmeli.
```

Burada iki ayri sey test ediliyor, ikisini karistirmamak lazim:
`bootc rollback` **elle** geri donus (yukaridaki 3. adim), greenboot
ise **otomatik** geri donus. Ilki calisiyor diye ikincisi calisiyor
sanma — ikincisi GRUB'un `boot_counter` degiskenini kalici
yazabilmesine bagli ve bu henuz dogrulanmadi.
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
./test.sh boot      # hepsi bir arada
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

**CRLF satir sonu her seyi sessizce bozar.** Proje Windows'ta, git
`core.autocrlf=true` ile duruyor. Commit'ler LF kalir ama Windows
calisma kopyasi CRLF olur. O kopyadan (ya da `/mnt/c` uzerinden)
derlersen `COPY files/ /` imaja `#!/usr/bin/env bash\r` tasir:
"bad interpreter". En kotu hali greenboot zorunlu kontrolu —
calismayan kontrol "basarisiz" sayilir ve makine her acilista geri
doner. `.gitattributes` artik satir sonunu depo genelinde LF'e
sabitliyor; silme.

**greenboot'un varsayilan kontrolleri masaustunu geri dondurur.**
`greenboot-default-health-checks` BILEREK kurulmuyor. Icindeki
`required.d/01_repository_dns_check.sh` iki sekilde yanlis karar
veriyor: `/etc/ostree/remotes.d` yoksa dogrudan `exit 1` (bootc
kurulumunda kaynak konteyner registry'si, ostree remote degil), ve
depo alan adlarinin DNS cozumlemesini sart kosuyor (laptop agsiz
acilir). Kurmak zorunda kalirsan `/etc/greenboot/greenboot.conf`
icinde `DISABLED_HEALTHCHECKS=("01_repository_dns_check.sh")`.

**`required.d`'ye kontrol eklemek kesinti uretir.** Oradaki her yanlis
"basarisiz" calisan bir makineyi geri dondurur. `greenboot-healthcheck`
`WantedBy=multi-user.target` — yani gdm'den ONCE calisabiliyor; bu
yuzden masaustu kontrolu beklemeli, hemen karar vermemeli. Emin
olmadigin her sey `wanted.d`'ye (sadece gunluge yazar).

**CI artik push'tan once `verify.sh` calistiriyor.** O adimi silme ya
da push'un arkasina alma. Dogrulanmamis bir imaj registry'ye ciktigi an
imzalanir ve makineler onu mesru guncelleme olarak ceker — yerelde
uygulanan disiplinin CI'da da bulunmasi gerekiyor.

**fedora-logos sadece logo tasimiyor — ve filtre ALLOWLIST olmak
zorunda.** Fedora 44'teki paket 143 PNG/SVG iceriyor ve bunlarin 62'si
logo DEGIL: plymouth acilis animasyonu (35 kare), anaconda
`sidebar-bg.png` / `topbar-bg.png` (12), kurulum slayt cizimleri
(`rnotes/en/*.svg`, 5), genis acilis gorselleri, bir `-symbolic` ikon
ve `fedora-logo-sprite.*`. `60-logos.sh` 81'ini degistirip 62'sini
koruyor; korudugu adlari derleme ciktisina yaziyor.

Filtrenin YONU onemli. "Chrome diye bildiklerim haric her seyi
degistir" (denylist) Fedora pakete yeni bir dosya ekledigi an ACIK
duser: bilinmeyen arayuz parcasi logoyla ezilir. "Tanidigim logo
adlarini degistir" (allowlist) KAPALI duser: bilinmeyen bir logo
Fedora'nin kalir — gorunur ve zararsiz. En kotu senaryo denylist'te:
Faz 3'te LUKS parola isteminde parola kutusunun yerinde logo bulmak.

**Kare armayi genis slota koymak goruntuyu bozar.** `60-logos.sh` artik
PNG basligini kendisi okuyup en/boy oranina bakiyor; 1.5:1'den genis
slotlara `wide-*.png` gidiyor. En gorunur ornegi `system-logo-white.png`
ve GDM logosu. `verify.sh` giris ekrani logosunun orani kareye dustuyse
HATA veriyor.

**Koyu zemin slotlari beyaz varyant istiyor — HENUZ URETILMEDI.** Dokuz
dosya (`*whitelogo*`, `*darkbackground*`, `system-logo-white.png`,
plymouth `watermark.png`, GDM logosu) siyah/koyu zemine ciziliyor.
Oraya lacivert-mercan armayi koyunca logo GORUNMEZ olabilir — ve bu,
ekrana bakmadan anlasilmayan tek hata sinifi. Mekanizma hazir,
kaynaklar depoda; eksik olan sadece uretim adimi:

```bash
WHITE=logo/simge/simge-beyaz-1024.png \
  ./add-logo.sh logo.png logo/kilit/yatay-kilit-mercan-2048.png
```

Uretmezsen derleme `UYARI: 9 koyu zemin slotuna renkli arma kondu`
yaziyor, `verify.sh` de ayni seyi uyari olarak tekrarliyor. Yatay beyaz
kaynak yok; o yuzden genis koyu slotlar renkli yatayi aliyor (kare
beyaza DUSMUYOR — genis slota kare koymak daha kotu).

**GNOME'un bagis kutucugu `.ui`'ye SABIT gomulu — overlay surume
bagli.** Ayarlar > Sistem Hakkinda'daki "Support GNOME" satirinin
id'si yok, `visible` ozelligi hicbir seye bagli degil, GSettings
anahtari yok, meson secenegi de yok. Bildirimi kapatmak kolay
(`donation-reminder-enabled=false`, gnome-settings-daemon anahtari
okuyup hemen cikiyor) ama kutucuk ayri bir is: `80-gnome.sh` derlenmis
`.ui`'yi `gresource extract` ile cikarip `visible=0` ekliyor ve
`G_RESOURCE_OVERLAYS` ile devreye aliyor.

Iki kurali bozma: (1) **`.ui`'yi depoya koyma**, kurulu binary'den
derleme aninda uret — depoda duran eski bir kopya C kodu ile
uyusmazsa Ayarlar penceresi HIC acilmaz. (2) **Yama tutmazsa
derlemeyi patlatma**, uyarip gec; kotu senaryo kutucugun kalmasi,
bozuk bir Ayarlar degil. GNOME o satira bir gun `id` verirse desen
tutmaz, `verify.sh` "kutucuk duruyor" diye uyarir ve orada yeniden
bakmak gerekir. Yama sadece ekleme yapiyor: cikti boyutu girdiden
tam olarak eklenen ozellik kadar buyuk olmali, degilse atlaniyor.

`gresource` taban imajda **yok**, `glib2-devel`'den geliyor — ilk
denemede derleme tam burada atladi. Adim paketi gecici kuruyor ve ayni
betikte kaldiriyor; derlemenin tamami tek `RUN` katmani oldugu icin
imajda iz kalmiyor. Kaldirma `|| true` ile cagrildigi icin `verify.sh`
paketin gercekten gittigini ayrica kontrol ediyor.


**Buyuk/kucuk harf ayrimi kasitli: `MFAOS` gorunen ad, `mfaos`
tanimlayici.** `OS_PRETTY_NAME=MFAOS` os-release'in
NAME/PRETTY_NAME/VARIANT alanlarina ve `PRETTY_HOSTNAME`'e gidiyor —
kullanicinin gordugu her yer. `OS_NAME=mfaos` ise GHCR yollarina,
dosya adlarina (`mfaos.pub`, `50-mfaos-desktop.sh`),
`/usr/share/mfaos-logo`'ya, `LOGO=` ikon anahtarina ve hostname'e
gidiyor. **Toptan arama-degistirme yapma:** GHCR yollari kucuk harf
olmak ZORUNDA, ve `LOGO=` degeri kurulu ikon dosyasinin adiyla birebir
eslesmek zorunda. `verify.sh`'in kimlik kontrolleri bu yuzden harf
duyarsiz (`grep -qi`) — bir sonraki yeniden adlandirmada sessizce
bozulmasinlar.

**`verify.sh` konteyner icinden `/etc/hostname`'i GOREMEZ.** podman
`/etc/hostname`, `/etc/hosts` ve `/etc/resolv.conf`'u kendi
urettikleriyle bind-mount ederek eziyor; konteyner icinden okunan
deger konteyner kimligi oluyor. Ilk denemede kontrol
`OK hostname: 9df541b629d4` diye **gecti** — imajda `fedora` yazsa da
aynen gecerdi, yani yanlis gecis. Yanlis bir OK, hic kontrol olmamasindan
kotudur: kontrol var saniyorsun. Bu yuzden hostname dogrulamasi
`50-branding.sh` icinde, dosyanin yazildigi yerde duruyor.
`/etc/machine-info` ezilmiyor, `PRETTY_HOSTNAME` kontrolu bu yuzden
`verify.sh`'te kalabildi. Yeni bir kontrol yazarken sor: bu dosyayi
podman eziyor mu?

**Ucuncu parti GitHub action'lari SHA'ya pinli olmali.** Derleme isi
`COSIGN_PRIVATE_KEY` ve `packages: write` tasiyor. `@main` ile duran
bir action, o branch'i kontrol eden herkese imzalama anahtarini
okuma imkani verir — zincirin en zayif halkasi imzalama adimi degil,
ayni iste calisan ucuncu parti kod.

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
Containerfile               imaj tanimi, build arg'lari (OS_VERSION, NVIDIA_ENABLED)
build_files/build.sh        adimlari sirayla calistirir
build_files/10-packages.sh  paket katmanlama
build_files/20-hardening.sh SELinux, servisler, guvenlik duvari
build_files/25-rollback.sh  greenboot — basarisiz boot sonrasi geri donus
build_files/30-desktop.sh   flatpak + guncelleme timer'i
build_files/40-nvidia.sh    NVIDIA (su an CI'da kapali)
build_files/50-branding.sh  os-release / sistem kimligi
build_files/60-logos.sh     fedora-logos logolari (allowlist) + GDM logosu
build_files/70-locale.sh     Turkce dil ve klavye
build_files/80-gnome.sh      GNOME bagis istekleri (bildirim + About kutucugu)
files/                      imajin kok dizinine oldugu gibi kopyalanir
files/usr/lib/greenboot/    saglik kontrolleri (required.d = geri donus tetikler)
logo/                       logo kaynaklari (imaja girmez)
add-logo.sh                 logo boyutlarini uretir (WHITE= ile beyaz varyant)
preflight.sh                gelistirme ortami kontrolu
test.sh                     build | verify | shell | vm | boot | all
verify.sh                   imaj icinde calisir; kontrol sayisini kendi yazar
disk-config.toml            gercek kurulum disk duzeni (kullanici tanimi YOK)
disk-config.test.toml       QEMU testi — sudo yetkili test/test hesabi burada
KOMUTLAR.md                 komut basvuru kagidi (derle + QEMU)
.gitattributes              satir sonlarini LF'e sabitler (Windows tuzagi)
```

Yeni bir derleme adimi eklerken: `build_files/` icine `NN-ad.sh`
olarak koy (sira numarasina gore calisiyor), `verify.sh`'e de bir
kontrol ekle. **Dogrulama kontrolu olmayan degisiklik sessizce
bozulabilir** — bu projede bes kez oyle oldu.
