# Devam notlari

Bu dosya, calismaya baska bir oturumda devam etmek icin yazildi.
Projenin ne oldugu `README.md`'de; burada **nerede kaldigimiz**,
**sirada ne var** ve **hangi tuzaklara bir daha dusmemek gerektigi**
var.

Son guncelleme: 8 Kasim 2026

---

## 1. Nerede kaldik

### Calisan ve dogrulanmis

| Katman | Durum |
|---|---|
| 0 — gelistirme ortami (WSL2 + podman) | Tamam |
| 1 — imaj derlemesi | Tamam |
| 2 — icerik dogrulama (`verify.sh`) | Tamam |
| 3 — QEMU'da boot | Tamam |
| 4 — guncelleme ve OTOMATIK geri donus | **Tamam — VM'de olculdu** |
| CI: derle -> dogrula -> ghcr'ye gonder -> cosign imzala | Tamam |
| Imza zincirinin makine tarafi | Tamam — VM ghcr imajini `policy.json` altinda dogruladi |
| Windows uygulamalari (.exe) | Tamam — VM'de 32/64 bit, konsol ve GUI olculdu |

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

### Katman 4 nasil olculdu

Zincirin tamami VM'de, mudahalesiz kosturuldu. Kanit satirlari:

- Stage aninda tetikleyici kuruluyor: `Setting rollback trigger for
  deployment: sha256:...` -> `Set grubenv:
  greenboot_next_deployment_id=sha256:...` -> `Set grubenv: fallback=1`
- Ilk basarisizlikta sayac kuruluyor: `boot_counter does not exists` ->
  `Set grubenv: boot_counter=3`
- Her denemede iniyor: `Boot counter is 2, rebooting to try again`,
  sonra `Boot counter is 1, ...`
- Tukenince geri donuyor: `Boot counter exhausted and
  next-deployment-id is set - initiating rollback`
- Besinci acilis yesil; acilan deployment `arm` oncesindeki, bozuk
  deployment `(rollback)` yuvasinda.

Test **iki kez** kosturuldu. Ikincisi daha gercekci ve hukmu daha
saglam: eski bir digest'e gecmek yerine gercek `bootc upgrade` ile en
yeni CI imajina yukseltildi, yani "bozuk guncelleme geldi" senaryosunun
kendisi kosuldu.

En guclu kanit, bizim hicbir kaydimiza dayanmayan sey: host'tan deployment
checksum'i izlenirken degisimin GORULMESI.

```
[11:51:19] deployment=35d8b55b8a26  boot_success=0  boot_counter=0
[11:52:08] deployment=8dc30ed54430  boot_success=1  boot_counter=yok
```

Ilk satirda bozuk (yeni) deployment'tayiz ve sayac tukenmis; ikincisinde
makine kendi basina arm oncesi deployment'a gecmis. Arada hicbir
mudahale yok.

**Zincirin sinirini bilmek lazim:** geri donusu GRUB degil greenboot
yapiyor, yani kullanici alaninda. Bozuk deployment'in greenboot'u
kosturacak kadar acilmasi gerekiyor. Hic acilmayan bir deployment
(bozuk cekirdek, kirik initramfs) bu zincirle KURTARILMIYOR; o durumda
GRUB menusunden elle onceki girdiyi secmek gerekiyor. "Bozuk guncelleme
kendini geri alir" vaadi bu kadariyla dogru.

**Testin kendi tuzagi:** kasitli basarisiz kontrolun kendini kapatma
esigi `GREENBOOT_MAX_BOOT_ATTEMPTS`'ten BIR FAZLA olmak zorunda. Ikisi
de 3 oldugunda test hic geri donus uretmiyor: sayac 3 -> 2 -> 1 diye
iniyor, dorduncu acilista kontrol kendini kapatiyor, greenboot sistemi
saglikli goruyor, sayaci temizliyor ve bozuk deployment'i iyi olarak
muhurluyor. Ilk olcumde tam bu oldu ve sonuc "geri donus yok" cikti —
isletim sisteminde degil, testte hata vardi. `rollback-test.sh` esigi
artik greenboot'un kendi ayarindan turetiyor.

**Hukmun kendisi de BOS cikabilir — asil tuzak bu.** Hukum bir sure
yalnizca `MFAOS_BUILD_DATE`'e bakiyordu, yani os-release'e KENDIMIZIN
yazdigi bir alana. Iki deployment ayni derlemeden geliyorsa o alan AYNI
olur ve karsilastirma "geri donus gerceklesti" der — geri donus olsa da
olmasa da. Yani test kendi sonucunu dogrulayamaz hale geliyor, ustelik
sessizce.

Uc sey birlikte gerekiyor:

1. **Yapisal olcut.** Hukum artik deployment'in ostree checksum'ina
   bakiyor (`ostree admin status`'ta `*` isaretli satir). Kimligi biz
   uretmiyoruz, ostree uretiyor, ve her deployment'in checksum'i ayri.
   `MFAOS_BUILD_DATE` raporda destekleyici olarak duruyor, hukmu
   vermiyor.
2. **Onsart denetimi.** `arm` anindakinden FARKLI en az bir deployment
   bulunmali. Yoksa sonuc "gecti" degil, **"test HUKUMSUZ"**. Stage
   adimi islememis ya da ayni commit'e cozulmusse bunu soyleyen tek sey
   bu.
3. **Stage sonrasi UC deployment olabiliyor** (staged + booted +
   rollback), o yuzden acilmis olmayanlarin ILKI degil hepsi okunuyor;
   ilkini almak raporda yanlis deployment'i isimlendiriyordu.

Ayrica "sonunda acildi" hicbir sey kanitlamiyor, ve sebebi sanilandan
guclu: sayac `/var/lib`'de, `/var` ise deployment'lar arasinda
PAYLASILIYOR. Yani kontrolun kendini kapatmis olmasi her iki
deployment'ta gecerli; son acilisin yesil olmasi hangi deployment'ta
oldugumuz hakkinda hicbir sey soylemiyor.

### Makine adi nasil duzeltildi

os-release'e `DEFAULT_HOSTNAME` yazmak TEK BASINA yetmiyordu. Adi
initramfs'in systemd'si koyuyor, KENDI os-release'ine gore, ve orada o
alan yok: initramfs temel imajdan geliyor, yani markalama adimindan
once uretilmis. Gercek kokun systemd'si de "ad zaten ayarli" diye
uzerine yazmiyor. Cekirdek argumani yolu hic mevcut degil —
`systemd.hostname` dizgisi systemd 259 ikilisinde bulunmuyor.

Cozum `mfaos-hostname.service`: acilista bir kez adi
`DEFAULT_HOSTNAME`'e cekiyor. VM'de olculen sira (monotonic):

```
[ 2.484] fedora  systemd[1]: Hostname set to <fedora>.      <- initramfs
[ 8.041] fedora  systemd[1]: Starting mfaos-hostname.service...
[ 8.106] mfaos   systemd-hostnamed: Hostname set to <mfaos> (transient)
[ 8.110] mfaos   systemd[1]: Finished mfaos-hostname.service.
[ 8.404] mfaos   systemd[1]: Starting gdm.service - GNOME Display Manager...
```

Gunlugun kendi makine adi alani iki satir arasinda `fedora`'dan
`mfaos`'a geciyor; baska kanita gerek yok. `gdm` 294 ms SONRA
basliyor, yani `Before=display-manager.service` isini yapiyor ve giris
ekrani adi dogru goruyor.

Kullanicinin secimi kazaniyor: birimde
`ConditionPathExists=!/etc/hostname` var, ve `hostnamectl` `Static
hostname: (unset)` / `Transient hostname: mfaos` gosteriyor.
Ayarlar'dan ad degistirilince `/etc/hostname` olusuyor ve birim bir
daha hic kosmuyor.

### Windows uygulamalari (.exe) nasil eklendi

Soru "mumkun mu" diye geldi; cevap tahminle degil olcumle verildi. Uc
yol vardi ve aralarindaki tek ciddi fark imaj agirligi:

| Yol | Imajda | /var'da |
|---|---|---|
| Flatpak motor | **0 bayt** | 848 MB Wine + paylasilan calisma zamani (toplam 2,2 GB) |
| Imaja katmanlamak | 112 paket / 610 MiB indirme / **2,0 GiB kurulu** | 0 |
| distrobox | 0 bayt | konteyner boyutu |

Secilen: **karma**. Motor Flatpak'ten geliyor — projenin kendi ilkesi
bu (30-desktop.sh: "degismez bir sistemde uygulamalar imaja girmez").
Ama `.exe`'nin yerli gibi davranmasi isletim sistemi tesisati, o
yuzden imaja giren sey (birkac KB):

- `files/usr/lib/binfmt.d/10-mfaos-exe.conf` — `MZ` imzasi -> sarmalayici
- `files/usr/libexec/mfaos/run-exe.sh` — motoru bulur, dosya iznini verir
- `files/usr/share/applications/mfaos-exe.desktop` — MIME isleyicisi
- `files/etc/xdg/mimeapps.list` — varsayilan isleyici
- `build_files/35-windows.sh` — `mfaos-exe` bagi + derleme denetimleri

binfmt yolunun imajda zaten kanitli altyapisi vardi: `systemd-binfmt`
`active` ve taban imajda calisan bir `qemu-aarch64` kaydi duruyor.

**VM'de olculen** (sertlestirme acik: SELinux `Enforcing`,
`ptrace_scope=1`):

| Test | Sonuc |
|---|---|
| 64-bit konsol PE (`cmd.exe /c ver`) | `Microsoft Windows 10.0.19045` |
| 32-bit konsol PE (syswow64 cmd.exe) | ayni cikti — WoW64 calisiyor |
| 64-bit GUI PE (`notepad.exe`) | Windows surec listesinde, explorer.exe yaninda |
| 32-bit GUI PE | `notepad.exe PID 216` |
| `./test.exe` (binfmt, XDG disi klasor) | `Microsoft Windows 10.0.19045`, cikis 0 |
| goreli yol + bosluklu dizin adi | gecti |
| ptrace reddi | 0 |

Sonra tesisatin **kendisi** imaj yollarina kurulup butun zincir tek
parca olarak olculdu (`/usr` gecici overlay, dosyalar gercek
yerlerinde, SELinux baglamlari `restorecon` ile):

| Test | Sonuc |
|---|---|
| `systemd-binfmt` yeniden kosturuldu (onyuklemedeki yolun ayni kodu) | birim `success`, cikis 0 |
| `mfaos-exe` kaydi | `enabled`, `magic 4d5a`, `flags:` bos, yorumlayici dogru |
| taban imajin `qemu-aarch64` kaydi | bozulmadi — iki bicim bir arada |
| MIME varsayilani (kullanici yapilandirmasi YOK) | dort tipin dordunde de `mfaos-exe.desktop`; tek "onerilen" uygulama o |
| `./surum.exe /c ver` (binfmt, bosluklu dizin) | `Microsoft Windows 10.0.19045`, cikis 0, **3 saniye** |
| `mfaos-exe <yol> /c echo ...` | cikti dondu, cikis 0 |
| **`gio open dosya.exe`** — Dosyalar'da cift tiklamanin ayni cagrisi | `not.exe` Windows surec tablosunda (PID 212/220) |
| calistirma biti olmayan `.exe` | cikis 126, "Erisim engellendi" — binfmt devreye girmiyor |
| motor kurulu degilken mesaj | tam kurulum metni + cikis 127 |
| SELinux AVC reddi | 0 |

`gio open` sonucu neden kesin: `org.winehq.Wine` izinleri yalnizca
`xdg-documents;xdg-desktop;xdg-pictures;xdg-music;xdg-videos;xdg-download`
(olculdu, kullanici gecersiz kilmasi da yok) ve sinama dosyasi bu
dizinlerin **hicbirinde degil**. `--filesystem` verilmeden ayni dosya
kum havuzunun icinden okunamiyor — ayrica olculdu. Dosya yine de
yuklendigine gore izni veren sarmalayici; yani zincir bastan sona
yurudu: cift tiklama -> `mfaos-exe.desktop` -> `run-exe.sh` ->
`flatpak run --filesystem=<dizin>` -> PE calisti.

AVC sayisi once **aracin kendisi dogrulanarak** alindi: ayni sorgu
gunlukteki 324 eski reddiyi buluyor, damgadan sonrasinda 0 buluyor.
Bu onlem bosuna degil — nedeni asagidaki tuzak bolumunde.

GUI testinde bir yanlis olumsuz yasandi: `pgrep -f notepad.exe`
host'tan BOS donuyor, cunku flatpak PID ad alani kullaniyor. "Calismadi"
sanildi; Wine'in kendi `tasklist`'iyle sorulunca surec orada cikti.
Flatpak icindeki bir seyi host araclariyla saymak yaniltir.

Olcum sirasinda cikan diger sayilar:

- Fedora 44'te wine **11.20**, Flathub'da **11.0**
- `wine-core.i686` F44'te **hala var** (11.0 ve 11.20), yani i686'yi
  dusurme plani F44'te tam uygulanmamis
- `wine-gecko` Fedora depolarinda **yok** (yalnizca `wine-mono` var);
  flatpak ikisini de getiriyor (gecko 217 MB + mono 236 MB). Yani .NET
  ve gomulu web icerigi icin Flatpak yolu RPM yolundan daha eksiksiz.
- `.exe` MIME tipinin taban imajdaki sahibi **File Roller**'di, yani
  cift tiklamak onu arsiv olarak acmayi deniyordu.
  `application/vnd.microsoft.portable-executable` ise tamamen sahipsizdi.

**Bilinen sinir:** bellek okuyan uygulamalar (anti-cheat, overlay
araclari) `kernel.yama.ptrace_scope = 1` yuzunden duser. Fedora
varsayilani 0 — bu bizim sertlestirme kararimiz, Wine'in kusuru degil.
Dar kapsamli duzeltme (`setcap cap_sys_ptrace` wineserver'a) Flatpak
icinde **yapilamiyor**; ya o makinede global ayari gevsetirsin ya da
wine'i imaja katmanlarsin. Yapilan testlerde (konsol + GUI, 32 + 64
bit) bu sinir hic devreye girmedi.

### HENUZ TEST EDILMEMIS

**Katman 5: gercek donanim.** Hicbir fiziksel makineye kurulmadi.
Listede kalan tek eksik bu, ve en buyugu: USB'den kurulum, gercek
disk ve UEFI, gercek ag donanimi, NVIDIA varyanti. QEMU'da olculen
hicbir sey bunlarin yerine gecmiyor.

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

### Adim 2 (TAMAMLANDI) — Katman 4: guncelleme ve geri alma testi

Olculdu ve gecti; kanit satirlari icin bkz. "Katman 4 nasil olculdu".
Komut dizisi `KOMUTLAR.md`'de. Burada kalan sey **neden** oyle
kurguladigimiz — testi tekrar kosturacak kisi icin.

**Sifir numarali adim atlanamaz.** VM yerelde derlenmis imajdan
kuruldugu icin bootc'nin kayitli guncelleme kaynagi `localhost/mfaos:44`
ve bu VM icinden cozulemez — `bootc upgrade` daha ilk adimda patlar.
`sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44` ile bir kez duzeltmek
gerekiyor, ve o komut ayni zamanda imza zincirinin ilk gercek sinavi:
`policy.json` imzayi dogrulayamazsa orada durur.

**Iki ayri sey test ediliyor, karistirmamak lazim.** `bootc rollback`
**elle** geri donus; greenboot ise **otomatik** geri donus. Ilki
calisiyor diye ikincisi calisiyor sanma.

Otomatiginin nasil isledigi olculdu: sayaci grubenv'e yazan ve tukenince
geri donusu BASLATAN taraf greenboot, GRUB degil. Yani geri donus
kullanici alaninda oluyor ve bozuk deployment'in greenboot'u
kosturacak kadar acilmasi gerekiyor (bkz. "Katman 4 nasil olculdu",
zincirin siniri).

**Bozuk imaj YAYINLAMIYORUZ.** Ilk plan bilerek bozuk bir imaj uretip
push etmekti; gerekmiyor. greenboot ozel kontrolleri
`/etc/greenboot/check/required.d`'den de okuyor (`/usr/lib` ostree'de
salt okunur), yani oraya bilerek basarisiz bir kontrol koymak AYNI
mekanizmayi sinar. Kazanci:

- bozuk imaj registry'e hic cikmiyor — gunluk timer onu makinelere
  dagitabilirdi,
- manuel imzalama derdi yok (imzasiz imaji policy.json reddederdi),
- test tek komutla kurulup kaldiriliyor.

**Test kontrolu kendini sinirliyor, ve bu sart.** `/etc` bir sonraki
deployment'a merge ile tasiniyor — ama GERI DONUS HEDEFINDE de ayni
dosya var. Kendini kapatmasa makine saglikli bir acilisa hic ulasmaz ve
kendi VM'ini kilitlersin. Sayac `/var`'da duruyor cunku `/var`
deployment'lar arasinda PAYLASILIYOR: geri donusten sonra da ayni sayac
okunuyor ve kontrol kendini kapatabiliyor.

Ama esik `GREENBOOT_MAX_BOOT_ATTEMPTS`'ten BIR FAZLA olmak zorunda,
yoksa test hicbir sey olcmez. Ayrintisi "Katman 4 nasil olculdu"
bolumunde; ilk olcumde tam bu yuzden yanlis sonuc aldik.

`verify.sh` o kontrolun imaja sizmadigini ayrica dogruluyor — `files/`
altina commit edilirse her makine her acilista geri donerdi.

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
- **Varsayilan WSL distrosu Ubuntu olmayabilir.** Docker Desktop
  kuruluysa `wsl -l -v` ciktisindaki yildiz `docker-desktop`'ta
  olabiliyor; duz `wsl` seni BusyBox kabuguna atiyor (prompt `MSI:~#`,
  `-ash: ssh: not found`). Her zaman `wsl -d Ubuntu`, ya da bir kez
  `wsl --set-default Ubuntu`.

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

**`/etc/hostname`'e konteyner derlemesinde YAZILAMAZ.** buildah de
podman gibi `/etc/hostname`, `/etc/hosts` ve `/etc/resolv.conf`
dosyalarini bind-mount ediyor; derleme adiminda oraya yazdigin sey
katmana **hic girmiyor**, sessizce kayboluyor. Ilk denemede
`50-branding.sh` iki satiri yan yana yaziyordu: `/etc/machine-info`
imaja girdi, `/etc/hostname` girmedi, ve makine kendini `fedora` diye
tanitmaya devam etti. Derleme basarili, kontrol yesil, sonuc yanlis.

Dogru mekanizma os-release'in **`DEFAULT_HOSTNAME`** alani (systemd
248+): "`/etc/hostname` yoksa ve baska bir kaynak belirtmiyorsa"
kullanilan deger — image tabanli sistemler icin zaten bunun icin var.
Kullanici Ayarlar'dan adi degistirirse `/etc/hostname` olusuyor ve o
kazaniyor; istedigimiz de bu.

Ayni maskeleme `verify.sh`'i de vurdu (bkz. ustteki podman tuzagi), ve
imaji `podman run ... cat /etc/hostname` ile denetlemeye calismak da
ayni sebepten konteyner kimligini veriyor. Katmani gercekten gormek
icin `podman cp` gerekiyor — konteyneri calistirmadan kopyaliyor.

**Ucuncu parti GitHub action'lari SHA'ya pinli olmali.** Derleme isi
`COSIGN_PRIVATE_KEY` ve `packages: write` tasiyor. `@main` ile duran
bir action, o branch'i kontrol eden herkese imzalama anahtarini
okuma imkani verir — zincirin en zayif halkasi imzalama adimi degil,
ayni iste calisan ucuncu parti kod.

**`/etc` deployment basina ayri; `sshd` ve guvenlik duvari kurali geri
donusle birlikte GELMIYOR.** Katman 4 testinde iki kez buna takildik.
Test VM'inde `sudo systemctl enable --now sshd` ve
`firewall-cmd --add-service=ssh` yapiyorsun, sonra sistem baska bir
deployment'a geciyor ve ssh olmuyor — cunku o deployment'in `/etc`'si sen bu degisikligi
yapmadan once olusmus. `/var` ve `/home` paylasiliyor, `/etc`
paylasilmiyor. Pratik sonucu: betikleri `/home/test`'e koy (her
deployment'ta elinin altinda olur), ama ssh erisimini her yeni
deployment'ta yeniden acmayi bekle.

**ostree yalnizca IKI deployment tutuyor.** `bootc switch` yeni birini
eklerken en eskiyi buduyor. "Bir sey ters giderse ucuncu bir yedegim
var" diye dusunmek yanlis: GRUB menusunde iki satir goruyorsun, hepsi
o. Test ederken bunu hesaba kat.

**`/boot` salt okunur bagli.** `grub2-editenv ... set` sessizce
basarisiz oluyor (cikis 1, hata mesaji yok denecek kadar sessiz).
greenboot bunu kendisi hallediyor — gunlugunde `Initial /boot mount
state: ro` → `Remounting /boot as rw for operation` → `Restoring /boot
mount to ro` satirlari var. Elle mudahale ederken ayni sirayi izle:
`sudo mount -o remount,rw /boot`, degistir, `sudo mount -o remount,ro
/boot`.

**Yapilandirma dosyasina calistirma biti kacarsa systemd her acilista
uyariyor.** `Configuration file ... is marked executable. Please remove
executable permission bits. Proceeding anyway.` Simdilik devam ediyor,
ama uyari bosa dusmuyor. Windows'ta `core.filemode=false` oldugu icin
calisma agacindaki kip izlenmiyor ve bit fark edilmeden
commit'lenebiliyor — bizde sekiz dosyada oyle olmus. Duzeltmesi calisma agacinda
`chmod` degil, dogrudan indeks: `git update-index --chmod=-x <dosya>`.
`verify.sh` artik bunu kontrol ediyor, ama yalnizca bizim sahibi
oldugumuz yollarda.

**Cekirdek komut satirinda `console=ttyS0` zaten var; bunu kullan.**
QEMU'yu `-serial file:output/serial.log` ile baslatinca butun acilis
gunlugu host'ta dosya olarak birikiyor. Bu, acilis **gunluk diske hic
yazilmadan** takildiginda tek okunabilir kaynak: bir kosuda iki acilis
erkenden takildi, `journalctl -b -1` o acilislar icin bos dondu ve
QEMU penceresine bakmaktan baska yol kalmadi. `MFAOS_HEADLESS=1
./test.sh vm` penceresiz baslatir, test tamamen mudahalesiz koser.

**`ostree=` yolundaki ozet deployment'i DEGIL, cekirdek+initramfs'i
tekilestiriyor.** `journalctl -b -2 -k -o cat | grep -o 'ostree=[^ ]*'`
gecmis bir acilisi anlamak icin ise yariyor, ama yalnizca iki
deployment'in cekirdegi farkliysa. Ayni cekirdekten uretilmis iki
deployment ayni ozeti tasiyor: olculdu — basarili bir geri donus
turunda bes acilis da ayni degeri gosterdi, sanki hicbir sey
degismemis gibi. Ilk okumada bunu deployment kimligi sanip "GRUB
yedege gecmiyor" diye yanlis bir sonuca varmistim.

"Geri donus oldu mu" sorusunu kesin yanitlayan uc kaynak var:

1. **Deployment'in ostree checksum'i** — `ostree admin status`'ta `*`
   isaretli satir. `rollback-test.sh` bunu `arm` aninda kaydediyor ve
   sonra karsilastiriyor. Yapisal kimlik: ostree uretiyor, biz degil.
2. **Host'tan izleyip degisimi gormek** — ssh ile checksum'i ornekleyip
   bozuk deployment'tan iyisine gecisi dogrudan yakalamak. Hicbir
   kaydimiza dayanmadigi icin en guclu kanit bu.
3. **greenboot'un kendi satiri** — `Boot counter exhausted and
   next-deployment-id is set - initiating rollback`.

`MFAOS_BUILD_DATE` karsilastirmasi bu listede DEGIL, cunku iki
deployment ayni derlemeden geliyorsa bos hukum veriyor (bak: 1. bolum,
"Hukmun kendisi de BOS cikabilir").

**Makine adini initramfs'in systemd'si koyuyor; os-release'deki
`DEFAULT_HOSTNAME` tek basina yetmiyor.** Olculen satirlar, monotonic
2.23'te, `initrd-*.target`'lardan hemen once:

    systemd[1]: No hostname configured, using default hostname.
    systemd[1]: Hostname set to <fedora>.

initramfs temel imajdan geliyor, yani markalama adimindan once
uretilmis ve icindeki os-release'de bu alan yok. Gercek kokun systemd'si
"ad zaten ayarli" diye uzerine yazmiyor, sonuc: Ayarlar'da aygit adi
dogru (`PRETTY_HOSTNAME`), kabukta ve agda ad `fedora` kaliyor.
Cekirdek argumani yolu da kapali — `systemd.hostname` dizgisi systemd
259 ikilisinde hic bulunmuyor. Cozum `mfaos-hostname.service`: statik
ad yoksa acilista bir kez adi `DEFAULT_HOSTNAME`'e cekiyor. Statik ad
varsa (`/etc/hostname`, kullanici Ayarlar'dan degistirdiyse olusuyor)
unit `ConditionPathExists=!` ile hic kosmuyor.

**Host askiya alinirsa misafirin saati bozuluyor ve acilis takiliyor.**
Takilan acilislarin son kernel satiri `clocksource: Watchdog remote CPU
N read timed out`. Katman 4 testi uc-dort yeniden baslatma demek;
laptop arada uyursa test yarida kaliyor ve sonuc okunamiyor — bizde tam
olarak bu oldu, 21:08'de takildi 05:47'ye kadar oyle kaldi. Testi
baslatmadan once makinenin uyumayacagindan emin ol.

### Ham olmayan bir Python dizgisinde ters bolu + yeni satir = satir birlestirme

Dosyalari Python ile duzenlerken bu iki kusur sessizce uretiliyor ve
ikisi de `bash -n`'den GECIYOR:

- `"...\` + yeni satir: Python bunu satir birlestirme sayiyor, kabugun
  devam satirlari tek satira cokuyor.
- `"\n"`: dosyaya yeni satir degil, iki karakter — ters bolu ve `n` —
  yaziliyor.

Uc kez isirdi. Ucuncusu `test.sh`'te uretim kusuruna dondu:

    -serial "file:${serial}" \n        -display gtk

`-display gtk` hic degismedi, yani `MFAOS_HEADLESS=1` test.sh
uzerinden hicbir ise yaramiyordu, ve qemu'ya `n` diye bir arguman
gidiyordu. Fark edilmemesinin sebebi: penceresiz kosumu test.sh'tan
degil elle kurulmus bir qemu komutundan baslatmistim, yani o kod yolu
hic kosmadi.

Kural: kabuk devam satiri iceren metni Python'dan yazarken HAM dizgi
kullan (`r"""..."""`), ve duzenledigin bolgeyi sonradan `cat -A` ya da
`grep -nP '\n'` ile gozle dogrula. Bu kusuru yakalayan sey `bash -n`
degil, shellcheck (SC1012) oldu.

### Lint kapsamini elle saymak — denetlenmeyen dosya

`.github/workflows/build.yml` hem sozdizimi hem shellcheck adiminda uc
globu ELLE sayiyordu. Bu oturumda `files/usr/libexec/mfaos/` dizini
eklendi, liste guncellenmedi, ve yeni betik `set-default-hostname.sh`
HIC denetlenmedi — iceride bir kusur olsa ancak VM'de gorunurdu.
Kapsam artik `git ls-files -z '*.sh'` ile geliyor, yani yeni bir dizin
acilsa bile kendiliginden genisliyor.

Ama kapsami git'e sormak TEK BASINA yetmiyor. Bos bir listede
`xargs -0 -n1 bash -n` argumansiz bash kosuyor, bos stdin'i okuyor ve
SESSIZCE 0 donuyor — yani glob kazara hicbir seyle eslesmezse lint
yesil kaliyor ve hicbir seyin denetlenmedigi anlasilmiyor. (shellcheck
bu durumda patlardi, cunku dosyasiz cagrilinca hata veriyor; iki adim
ayni girdide farkli davraniyor.) O yuzden adim artik listeyi basiyor
ve bos olmadigini dogruluyor.

Ayni mantik `verify.sh` icin de gecerli ve bu projede bes kez isiradi:
yeni bir dosya ekledigin anda onun kontrolunu de yaz.

### Yerelde shellcheck yok — ve CI kirmizi iken imaj yine push'laniyor

Bu makinede shellcheck kurulu degil: WSL'de `sudo` parola istiyor,
indirilen ikili de kum havuzunda kosmuyor. Yani betik degisiklikleri
yerelde yalnizca `bash -n` ile sinaniyor ve shellcheck uyarilari ilk
kez CI'da goruluyor.

Daha onemlisi: `lint` isi `build` isinden BAGIMSIZ kosuyor. Lint
duserken imaj yine derleniyor, imzalaniyor ve ghcr'ye push'laniyor —
yani "CI kirmizi" otomatik olarak "yeni imaj yok" demiyor. Iki ise
ayri ayri bakmak gerekiyor:

```bash
gh run view <id> --json conclusion
gh run view <id> --log | grep 'Successfully pushed'
```

Push etmeden once en azindan CI'in sozdizimi taramasini yerelde
kosturabilirsin:

```bash
git ls-files -z '*.sh' | xargs -0 -n1 bash -n
```

---

### Calisma agacinda CRLF — git gizliyor, yerel derleme oluyor

`./test.sh build` su hatayla duser:

```
/tmp/build_files/10-packages.sh: line 3: set: pipefail: invalid option name
```

Sebep: dosya calisma agacinda CRLF. `set -euo pipefail\r` satirinda
bash `pipefail\r`'i gecersiz secenek adi sayiyor.

Asil tuzak **git'in bunu gostermemesi**. `.gitattributes`'taki
`* text=auto eol=lf` yuzunden git karsilastirirken CRLF'i LF'e
normalize ediyor, yani `git status` TEMIZ diyor. Ama `COPY files/ /`
ham baytlari kopyaliyor — imaja CRLF giriyor.

Ve CI bunu hic gormuyor, cunku Linux checkout'u LF. Yani **CI yesil,
yerel derleme olu**: en yaniltici kombinasyon.

22 dosya bu durumdaydi ve aralarinda imaja DOGRUDAN kopyalananlar da
vardi: `99-mfaos-hardening.conf` (sysctl satiri `\r` ile biterse
uygulanmaz), `locale.conf`, `vconsole.conf`, `10-hardening.toml`,
systemd drop-in'leri, hatta `cosign.pub`.

Kaynagi muhtemelen PowerShell: Windows PowerShell 5.1'de
`Set-Content` ve `Out-File` varsayilan olarak CRLF yaziyor.

Bulmak ve duzeltmek:

```bash
# Hangi dosyalar? git'in raporuna degil GERCEK baytlara bak.
git ls-files -z | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$f" in *.png) continue ;; esac
  grep -qU $'\r' "$f" && echo "$f"
done

# Duzelt. Icerik DEGISMIYOR: git zaten LF sakliyor, yalnizca
# calisma agaci git'in sakladigi hale donuyor.
sed -i 's/\r$//' <dosya>
```

`git ls-files --eol` de gosteriyor (`i/lf w/crlf`) ama ciktisini
ayristirmak baska bir tuzak: `attr/` alani BOSLUK iceriyor
("attr/text=auto eol=lf"), o yuzden `read -r i w attr path` yoldan
cikiyor ve dosya adi `path`'e girmiyor.

Duzeltmeden sonra `git status` o dosyalari bir sure ` M` gosterebilir;
bu bayatlamis stat bilgisi, icerik farki degil. `git diff --numstat`
bos donuyorsa gercekten fark yok.

### binfmt.d satirinda awk alan numaralari bir kayiyor

`:ad:tip:ofset:imza:maske:yorumlayici:bayraklar` satiri iki nokta ile
**basliyor**, yani `awk -F:` icin `$1` BOS kaliyor ve her sey bir
kayiyor:

```
$2=ad  $3=tip  $4=ofset  $5=imza  $6=maske  $7=yorumlayici  $8=bayraklar
```

Yorumlayiciyi `$6` sanmak bos deger okutuyor. 35-windows.sh'in kendi
denetimi bunu derleme sirasinda yakaladi ve derlemeyi durdurdu —
dogrulama kontrolu koymanin karsiligi tam olarak bu.

### Flatpak kum havuzu ev dizinini gormuyor

`org.winehq.Wine` varsayilan olarak yalnizca `xdg-documents`,
`xdg-desktop`, `xdg-download`, `xdg-pictures`, `xdg-music` ve
`xdg-videos` goruyor. Olculdu: `~/baskaklasor/app.exe` ve
`/tmp/app.exe` kum havuzunun icinde "dosya yok".

Bu yuzden bir `.exe`'yi flatpak'e **goreli** yolla vermek de olumcul:
goreli yol kum havuzunun icinde bambaska bir yeri gosterir ve hata
mesaji "dosya yok" olur, sebebini soylemez. `run-exe.sh` once
`readlink -f` ile mutlaklastiriyor, sonra `--filesystem=<dizin>`
veriyor — butun diski degil, yalnizca `.exe`'nin dizinini.

### zenity yok — ve "program kurulu" mesajin ulastigi anlamina gelmiyor

Masaustu mesaji icin reflex olarak `zenity` yazilir ama Silverblue 44
tabaninda **yok**. Olculdu — var olanlar: `notify-send` ve `gdbus`.

`run-exe.sh`'in ilk yazimi su zinciri kurdu: tty varsa stderr, yoksa
`notify-send`, o da yoksa `logger`. VM'de kosturulunca motor-yok
mesaji **hic gorunmedi**:

```
Failed to show notification: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name is not activatable
```

Kusur zincirin kendisindeydi. Ortadaki adim `command -v notify-send`
ile programin VAR OLUP OLMADIGINA bakiyordu; ama program var olup
calisma aninda **dusebiliyor** — oturum veriyolu ya da bildirim
servisi yoksa tam olarak bu oluyor. `|| true` hatayi yutuyor,
`logger` yedegine ise hic gecilmiyor, cunku `notify-send` "var".
Yedegi olan bir zincir yedegine ulasamiyordu.

Duzeltme: bildirimin **cikis kodu** denetleniyor, ayrica stderr'e her
durumda yaziliyor (Dosyalar'dan gelindiginde /dev/null'a gider,
zarari yok). Duzeltmeden sonraki olcum: terminalde tam metin
goruldu, tty'siz cagrida ayni metin `journalctl -t mfaos-exe`
altinda cikti.

Genel ders: bir yedek zinciri "arac kurulu mu" ile degil "is oldu
mu" ile ilerlemeli. Birincisi yedegi yalnizca kagit uzerinde
birakiyor — ve sessizce olen bir cift tiklama teshis edilemez bir
sikayet.

### Olcum araci sessizce yalan soyleyebilir — once araci sina

.exe isinin sonunda uc olcum araci birbiri ardina yanlis "temiz"
raporu verdi. Ucu de ayni sinifta: **hata veriyor ama sonuc sifir
gibi gorunuyor.**

**1. `ausearch -ts` tarih bicimini reddetti.** Soyle sayiyordum:

```bash
ausearch -m AVC -ts "11/08/2026 14:48:44" | grep -c 'type=AVC'   # -> 0
```

Sifir "reddi yok" demek sanildi. Gercekte ausearch hic aramadi:

```
Invalid start time (11/08/2026 14:48:44). Hour, Minute, and Second are ...
```

Hata `grep -c`'nin icine aktigi ve cikis kodu boru yuzunden kayboldugu
icin gorunmedi. Dogru olcum: logu dogrudan okuyup zaman damgasini
kendin suzmek —

```bash
MARK=$(date +%s)
sudo awk -v m="$MARK" '/avc:  denied/ { if (match($0,/audit\(([0-9]+)\./,a) && a[1]>=m) n++ } END{print n+0}' \
     /var/log/audit/audit.log
```

ve **once aracin bir sey bulabildigini kanitlamak**: ayni sorgu
gunlukteki 324 eski reddiyi buluyor. Hicbir seyi bulamayan bir sorgu
her zaman "temiz" rapor eder.

**2. Denetim dosya izi ostree `/usr` overlay'inde tutmuyor.**

```bash
auditctl -w /usr/libexec/mfaos/run-exe.sh -p x -k mfaosexe
```

Kural listede gorunuyor, betik gercekten calisiyor (cikis 0, Windows
surumu basildi), ama `ausearch -k mfaosexe` **sifir** kayit veriyor.
Inode tabanli izler overlayfs ile guvenilir degil. Burada dogru kanit
sonucun kendisiydi: Windows surec tablosu ve kum havuzunun gormedigi
yoldan dosyanin yuklenmis olmasi.

**3. `$(gio open ...)` asiliyor.** Komut ikamesi borunun BUTUN
yazicilari kapanana kadar bekler; `gio open` baslattigi uygulamaya
stderr'i miras verdigi icin boru, **uygulama** yasadigi surece acik
kalir. Yani `go="$(gio open app.exe)"` notepad kapanana kadar durur —
`timeout 20` bile kurtarmaz, cunku zaman asimi gio'yu olduruyor,
boruyu tutan notepad'i degil. Ayni tuzak `wineserver -w` icin de
gecerli. Dogrusu:

```bash
setsid timeout 25 gio open "$f" >/tmp/go.out 2>&1 </dev/null &
```

Ortak ders: bir olcum "0" dedigi anda, o aracin **bir seyi bulabildigi
durumu** da gostermek gerekiyor. Yoksa olculen sey sessizlik olur,
yoklugun kaniti degil.

### /mnt/c uzerinden derlemek dosya kiplerini 777 yapiyor

`./test.sh build` yerelde kosunca `verify.sh` su hatayi veriyor:

```
HATA  yapilandirma dosyasinda calistirma biti var:
      .../99-mfaos-hardening.conf .../policy.json ...
```

Depo kusurlu degil. WSL, `/mnt/c` (drvfs) uzerindeki **her dosyayi
777** gosteriyor; podman build context'i oradan okudugu icin butun
yapilandirma dosyalari calistirilabilir olarak imaja giriyor. git
indeksinde kipler dogru (`100644`), o yuzden **CI temiz** — CI git'ten
checkout ediyor.

Yine CRLF tuzagiyla ayni sinif: yerel derleme CI ile ayni seyi
olcmuyor. Ve ters yonde de yaniltici — `files/usr/libexec/mfaos/
run-exe.sh` icin "calistirilabilir mi" denetimi yerelde her zaman
GECER, cunku her sey 777.

CI ile ayni seyi olcmek icin derlemeyi git'in agacindan yap:

```bash
# WSL icinde, native dosya sisteminde (ext4) — kipler git'ten gelir
TREE=$(git -C /mnt/c/.../mfaos write-tree)
rm -rf /tmp/mfaos-ci && mkdir -p /tmp/mfaos-ci
git -C /mnt/c/.../mfaos archive "$TREE" | tar -x -C /tmp/mfaos-ci
cd /tmp/mfaos-ci && ./test.sh build && ./test.sh verify
```

`write-tree` INDEKSI kullaniyor, yani once `git add` etmek gerekiyor;
commit'e gerek yok.

### Exec yolu yanlis olan .desktop SESSIZCE yok sayiliyor

Bir dosya isleyicisi ekledin, `desktop-file-validate` "gecerli" diyor,
`mimeinfo.cache`'te girdi var — ama cift tiklamak hicbir sey yapmiyor
ve hicbir yerde hata yok.

Sebep: GLib, `Exec=` satirindaki program **yoksa** girdiyi tamamen
atliyor. Ne gunluk, ne uyari. VM'de olculdu:

```
Exec=/usr/libexec/mfaos/run-exe.sh %f      (o makinede yok)
  -> gio mime application/vnd.microsoft.portable-executable
     Kayitli uygulamalar: org.winehq.Wine.desktop     # bizimki YOK

Exec=/usr/local/bin/mfaos-run-exe.sh %f    (var)
  -> Kayitli uygulamalar: mfaos-exe.desktop, org.winehq.Wine.desktop
     Onerilen: mfaos-exe.desktop
     ontanimli uygulama: mfaos-exe.desktop
```

Yani `.desktop` dosyasini imajda OLMAYAN bir makinede denemek yanlis
olumsuz uretiyor. Teshis komutu `gio mime <tip>`: isleyici listede yok
ise sebep neredeyse her zaman Exec yolu.

Bu yuzden hem `35-windows.sh` hem `verify.sh` artik `.desktop`'taki
Exec yolunu sarmalayicinin yoluyla karsilastiriyor — binfmt
yorumlayicisi icin yapilan denetimin aynisi.

Yan bulgu: `NoDisplay=true` girdiyi "Onerilen uygulamalar" listesinden
**dusurmuyor**. Yani bir dosya isleyicisi uygulama izgarasinda
gorunmeden "Birlikte Ac" menusunde kalabiliyor — istenen davranis bu.

Ikinci yan bulgu: `org.winehq.Wine` flatpak'i kendini zaten `.exe`
isleyicisi olarak kaydediyor ve kurulunca varsayilan oluyor. Ama onun
kendi isleyicisi kum havuzu iznini genisletmiyor; XDG disi bir klasorde
duran `.exe`'yi acamaz. Bizim isleyicimizin var olma sebebi bu.

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
build_files/35-windows.sh   .exe butunlesmesi (binfmt + MIME) — wine KURMAZ
build_files/40-nvidia.sh    NVIDIA (su an CI'da kapali)
build_files/50-branding.sh  os-release / sistem kimligi
build_files/60-logos.sh     fedora-logos logolari (allowlist) + GDM logosu
build_files/70-locale.sh     Turkce dil ve klavye
build_files/80-gnome.sh      GNOME bagis istekleri (bildirim + About kutucugu)
files/                      imajin kok dizinine oldugu gibi kopyalanir
files/usr/lib/greenboot/    saglik kontrolleri (required.d = geri donus tetikler)
files/usr/lib/systemd/      birimler ve drop-in'ler (mfaos-hostname.service dahil)
files/usr/libexec/mfaos/    imajin kendi yardimci betikleri
files/usr/lib/binfmt.d/     MZ imzasi -> run-exe.sh (./app.exe dogrudan kosar)
files/etc/xdg/mimeapps.list .exe'nin varsayilan isleyicisi (File Roller'dan alindi)
logo/                       logo kaynaklari (imaja girmez)
add-logo.sh                 logo boyutlarini uretir (WHITE= ile beyaz varyant)
preflight.sh                gelistirme ortami kontrolu
test.sh                     build | verify | shell | vm | boot | all
rollback-test.sh            VM ICINDE kosar: geri donus zinciri calisiyor mu
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
