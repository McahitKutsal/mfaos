# Komutlar

Hizli basvuru kagidi. *Neden* oyle oldugu `README.md` ve `DEVAM.md`'de;
burada sadece yazilacak komut var.

---

## Derle ve QEMU'da gor

WSL icinde, tek komut:

```bash
cd ~/mfaos && ./test.sh boot
```

Sirayla: imaji derler -> icerigini dogrular -> qcow2 uretir -> QEMU
penceresini acar.

| | |
|---|---|
| VM girisi | **test** / **test** (`disk-config.test.toml`) |
| QEMU'dan cikis | pencereyi kapat, ya da terminalde `Ctrl-C` |
| Ilk calistirma | 20-40 dakika (taban imaj ~8GB indirilecek) |
| Sonraki | podman katman onbellegi + qcow2 onbellegi devreye girer |

Parola sorusu derlemenin ortasinda cikmasin: `vm` adimi `sudo`
istiyor ama ona ancak derleme bittikten sonra geliyor. Basta tazele:

```bash
sudo -v && ./test.sh boot
```

PowerShell'den tek satirda:

```powershell
wsl -d Ubuntu -- bash -lc "cd ~/mfaos && sudo -v && ./test.sh boot"
```

---

## Degisiklik Windows tarafinda kaldiysa

Asil kopya `~/mfaos`. Windows tarafindaki
`C:\Users\mucah\Desktop\Projects\mfaos` ayri bir klon — orada yapilan
degisiklik WSL'e kendiliginden gecmez. **`/mnt/c` uzerinde derleme
yapma**, 10 kat yavas.

Commit ederek (normal yol):

```powershell
git add -A; git commit -m "<ne degistiyse>"; git push   # Windows
```
```bash
cd ~/mfaos && git pull && ./test.sh boot     # WSL
```

Commit etmeden hizlica denemek icin:

```bash
rsync -a --delete --exclude output/ --exclude .git/ \
  /mnt/c/Users/mucah/Desktop/Projects/mfaos/ ~/mfaos/
```

---

## Tek tek adimlar

```bash
./preflight.sh      # ortam kontrolu — eksikse kurulum komutunu yazar
./test.sh build     # sadece derle
./test.sh verify    # imajin icerigini dogrula (saniyeler surer)
./test.sh all       # build + verify
./test.sh shell     # imajin icine bak (konteyner olarak)
./test.sh vm        # mevcut imajtan qcow2 uret + QEMU
./test.sh boot      # hepsi: build + verify + vm
```

`verify` adimini atlama. Derlemenin basarili bitmesi istedigin seyin
imaja girdigi anlamina gelmiyor — scriptlerdeki `|| true` ifadeleri
hatalari yutar. `verify.sh` sonunda kac kontrolden kaci gectigini
kendisi yaziyor.

### Ortam degiskenleri

```bash
VARIANT=nvidia ./test.sh boot   # NVIDIA varyanti (CI'da simdilik kapali)
SECURE_BOOT=1  ./test.sh vm     # Secure Boot acik firmware ile boot
REBUILD_DISK=1 ./test.sh vm     # qcow2'yi onbellekten degil yeniden uret
DISK_CONFIG=disk-config.toml ./test.sh vm   # gercek kurulum duzeniyle
```

---

## Katman 4: guncelleme ve geri donus testi

> **Bu bolumun TAMAMI VM'in icinde calisir.** WSL'de (`~/mfaos`)
> denersen `sudo: 'bootc': command not found` alirsin — orada bootc
> yok, olmamasi da normal. VM'i acmak: `./test.sh boot`, giris
> **test / test**.

### 0. VM'de rahat bir terminal (atlamak isteyebilirsin ama atlama)

QEMU penceresinde kaydirma da kopyala-yapistir da yok; uzun komutlari
elle yazmak zorunda kalirsin. VM icinde **bir kez**:

```bash
sudo systemctl enable --now sshd
```

Bu komut **QEMU penceresinde** yazilir; ssh henuz calismadigi icin tek
giris yolu o. Ancak ondan sonra host'tan baglanabilirsin — port
yonlendirmesi `test.sh` icinde hazir:

```bash
wsl -d Ubuntu                      # DUZ `wsl` yazma, asagiya bak
ssh -p 2222 test@localhost         # parola: test
```

**`-d Ubuntu` sart.** Docker Desktop kuruluysa varsayilan WSL
distrosu `docker-desktop` olabiliyor; duz `wsl` seni BusyBox kabuguna
atar ve `-ash: ssh: not found` alirsin. Kontrol: `wsl -l -v`, yildiz
hangisindeyse varsayilan o. Kalicisi: `wsl --set-default Ubuntu`.

PowerShell'den de denenebilir (Windows'un kendi OpenSSH'i, WSL2
localhost yonlendirmesi uzerinden): `ssh -p 2222 test@localhost`.

`sshd` imajda bilerek kapali (`20-hardening.sh`). Feda edilebilir test
VM'inde acmak sorun degil; gercek makinede acma.

### Betigi VM'e almak

VM'de depo klonu yok, o yuzden indiriyoruz:

```bash
curl -sSLO https://raw.githubusercontent.com/McahitKutsal/mfaos/main/rollback-test.sh
chmod +x rollback-test.sh
```

**WSL tarafinda `curl` kullanma.** `~/mfaos` deponun klonu; dosya
zaten `git pull` ile geliyor ve indirilen kopya `git pull`'u bloklar
("untracked working tree files would be overwritten"). Oldu ise:
`rm rollback-test.sh && git pull`.

### 1. Dogru yerde miyim + zincir ayakta mi

```bash
sudo ./rollback-test.sh status
```

Yanlis makinedeysen **bu komut hemen durur ve soyler** — ilk adim
olarak bunu kosmanin sebebi bu. Dogru yerdeysen deployment'lari,
greenboot servislerini, saglik kontrolunun bu acilista gercekten
kosup kostugunu ve GRUB'un `boot_success` / `boot_counter`
degiskenlerini raporlar.

### 2. Guncelleme kaynagini duzelt — atlarsan 3. adim patlar

VM yerelde derlenmis imajdan kuruldugu icin bootc'nin kayitli kaynagi
`localhost/mfaos:44` ve bu VM icinden **cozulemez**. 1. adim bunu
tespit edip zaten soyluyor. Bir kez:

```bash
sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44
sudo systemctl reboot
```

Bu adim bedavaya **imza zincirini de** sinar: `policy.json`
sigstoreSigned istiyor, ortak anahtar `/etc/pki/containers/mfaos.pub`.
Imaj reddedilirse zincirde sorun var ve bunu burada ogrenirsin.

### 3. ELLE geri donus

```bash
sudo bootc upgrade && bootc status     # yeni surum "staged" gorunmeli
sudo systemctl reboot
# Ayarlar > Sistem Hakkinda: yeni surum
sudo bootc rollback && sudo systemctl reboot
```

### 4. OTOMATIK geri donus — asil test

Ikisi ayri sey: elle geri donus calisiyor diye otomatigi calisiyor
sanma.

> **Baslamadan:** bu test uc-dort yeniden baslatma demek. Laptop arada
> uyursa misafirin saat kaynagi bozuluyor, acilis `clocksource: Watchdog
> remote CPU N read timed out` satirinda takiliyor ve test yarida
> kaliyor. Makinenin uyumayacagindan emin ol.

Penceresiz kosturmak daha rahat: butun acilis gunlugu host'ta birikir,
VM ssh'a hic gelmese bile okunabilir.

```bash
MFAOS_HEADLESS=1 ./test.sh vm        # WSL'de
tail -f output/serial.log            # baska bir terminalde
```

VM'in icinde, bu sirayla — sira onemli, `arm` artik bunu zorluyor:

```bash
sudo ./rollback-test.sh arm          # kasitli basarisiz saglik kontrolu
sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44
sudo bootc status                    # 'staged' DOLU olmali
sudo systemctl reboot
```

`upgrade` degil `switch`: guncelleme kaynagi `localhost/mfaos:44`
kaldiysa `bootc upgrade` hicbir sey stage etmiyor, tetikleyici hic
kurulmuyor ve test sessizce bos koser.

Beklenen: yeni deployment 3 kez acilmayi dener, her denemede
`boot_counter` iner, sifira varinca **onceki deployment** acilir.
Sonra:

```bash
sudo ./rollback-test.sh status
sudo ./rollback-test.sh disarm
```

`status` hukmu kendisi veriyor: `arm` aninda hangi imajda oldugunu
kaydediyor ve acilista onunla karsilastiriyor. "Sonunda acildi" olcu
degil — kontrol 3 basarisizliktan sonra kendini kapattigi icin geri
donus olsa da olmasa da sistem sonunda aciliyor.

Hangi acilisin hangi deployment'ta oldugunu kesin gormek icin:

```bash
for b in -4 -3 -2 -1 0; do
    echo "$b: $(sudo journalctl -b $b -k -o cat | grep -m1 -o 'ostree=[^ ]*')"
done
```

Kontrol kendini kapattigi icin VM kilitlenmiyor. `disarm` yine de
gerekli: sayac `/var`'da duruyor ve `/var` deployment'lar arasinda
paylasiliyor.

---

## Logolari yeniden uret

Sadece logo kaynagi degistiginde gerekiyor; cikti depoya commit ediliyor.

```bash
WHITE=logo/simge/simge-beyaz-1024.png \
  ./add-logo.sh logo.png logo/kilit/yatay-kilit-mercan-2048.png
```

`WHITE=` olmadan calistirirsan koyu zemin slotlarina (GDM giris ekrani,
plymouth acilis ekrani) renkli arma gider ve logo gorunmez olabilir;
derleme bunu `UYARI` olarak yazar ama durmaz.

---

## Sik takildiklar

| Belirti | Cozum |
|---|---|
| `/dev/kvm` yok | `.wslconfig`'de ic ice sanallastirma; sonra PowerShell'den `wsl --shutdown` |
| `/dev/kvm` var ama erisemiyorsun | `sudo usermod -aG kvm $USER` + `wsl --shutdown` (oturum kapatmak yetmez) |
| `OVMF bulunamadi` | `sudo apt install -y ovmf` |
| `image not found` (image-builder) | `./test.sh vm` imaji root deposuna kendi aktariyor; once `./test.sh build` kosmus olmali |
| QEMU penceresi acilmiyor | `echo $DISPLAY` bos ise WSLg yok; `wsl --update` |
| Disk doluyor | En az 50GB bos gerekiyor: taban ~8GB, katmanlar ~2GB, qcow2 ~15GB |
| Eski sistemi goruyorsun | `REBUILD_DISK=1 ./test.sh vm` — qcow2 onbellekten geliyordu |
| `bootc: command not found` | WSL'desin, VM'de degilsin. Katman 4 komutlari VM icinde kosar: `./test.sh boot` |
| `untracked working tree files would be overwritten` | `~/mfaos`'ta `curl` ile dosya indirmissin; orada gerek yok: `rm rollback-test.sh && git pull` |
| `rollback-test.sh` "ostree degil" diyor | Dogru davranis — gelistirme makinesinde kosuyorsun, VM'de kos |
| `-ash: ssh: not found`, prompt `MSI:~#` | Docker Desktop'in WSL distrosundasin, Ubuntu degil: `wsl -d Ubuntu` |
| `ssh -p 2222` cevap vermiyor, asili kaliyor | VM acik ama icinde `sshd` kapali. QEMU baglantiyi kabul edip misafire ulasamadigi icin REDDETMIYOR, asiyor. QEMU penceresinden gir ve `sudo systemctl enable --now sshd` |
| `ssh -p 2222` → `Connection refused` | VM hic calismiyor: `./test.sh boot` |
| `grub2-editenv ... set` sessizce basarisiz (cikis 1, mesaj yok) | `/boot` salt okunur bagli: `sudo mount -o remount,rw /boot`, degistir, `sudo mount -o remount,ro /boot` |
| ssh gelmiyor ve acilis takilmis gorunuyor | `output/serial.log`'a bak — gunluk diske yazilmadan takilan acilislarin tek kaynagi o. QEMU'yu `-serial` olmadan baslattiysan bu dosya yok |
| GRUB'da yalnizca iki `MFAOS 0.1 (ostree:N)` satiri var | Normal: ostree iki deployment tutuyor, `bootc switch` en eskiyi buduyor |
| Geri donusten/gecisten sonra ssh yok | `/etc` deployment basina ayri. Yeni deployment'ta tekrar: `sudo systemctl enable --now sshd` ve `sudo firewall-cmd --permanent --add-service=ssh && sudo firewall-cmd --reload` |
| `arm` "bekleyen bir geri donus var" diyor | Dogru davranis: ustte bekleyen gecis varken test hukum vermez. `sudo bootc rollback && sudo systemctl reboot`, sonra tekrar `arm` |

---

## CI ve yayin

Push sonrasi GitHub Actions **iki is** kosuyor ve birbirlerini
ENGELLEMIYOR:

- `build`: derle -> `verify.sh` ile dogrula -> ghcr'ye gonder ->
  cosign ile imzala. `verify.sh` push'tan ONCE kosuyor, yani gecmezse
  imaj registry'ye hic cikmaz.
- `lint`: `bash -n` + shellcheck. Bu is **dusse bile** imaj derlenip
  push'lanmaya devam ediyor.

Yani "CI kirmizi" otomatik olarak "yeni imaj yok" demiyor — bir kez
tam olarak bu oldu (lint dustu, imaj yine yayinlandi). Ikisine ayri
ayri bakmak gerekiyor:

```bash
gh run watch                                   # calisan derlemeyi izle
gh run view --log-failed                       # patlayan adimin logu
gh run view <id> --log | grep 'Successfully pushed'   # imaj cikti mi
podman pull ghcr.io/mcahitkutsal/mfaos:44      # yayinlanani cek
cosign verify --key cosign.pub ghcr.io/mcahitkutsal/mfaos:44
```

Push etmeden once lint'in sozdizimi adimini yerelde kosturabilirsin.
shellcheck bu makinede kurulu DEGIL (WSL'de sudo parola istiyor), o
yuzden shellcheck uyarilarini ancak CI gosteriyor:

```bash
git ls-files -z '*.sh' | xargs -0 -n1 bash -n
```
