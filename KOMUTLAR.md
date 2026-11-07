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

Bunlar **VM'in icinde** calisiyor — `./test.sh boot` ile acilan
pencerede, host'ta degil. Betigi VM'e almak icin (sshd bilerek kapali,
depo public):

```bash
curl -sSLO https://raw.githubusercontent.com/McahitKutsal/mfaos/main/rollback-test.sh
chmod +x rollback-test.sh
```

### 0. Guncelleme kaynagini duzelt — atlarsan 2. adim patlar

VM yerelde derlenmis imajdan kuruldugu icin bootc'nin kayitli kaynagi
`localhost/mfaos:44` ve bu VM icinden **cozulemez**. Bir kez:

```bash
sudo bootc switch ghcr.io/mcahitkutsal/mfaos:44
sudo systemctl reboot
```

Bu adim bedavaya **imza zincirini de** sinar: `policy.json`
sigstoreSigned istiyor, ortak anahtar `/etc/pki/containers/mfaos.pub`.
Imaj reddedilirse zincirde sorun var ve bunu burada ogrenirsin.

### 1. Zincir ayakta mi

```bash
sudo ./rollback-test.sh status
```

Deployment'lari, greenboot servislerini, saglik kontrolunun bu
acilista gercekten kosup kostugunu ve GRUB'un `boot_success` /
`boot_counter` degiskenlerini raporluyor.

### 2. ELLE geri donus

```bash
sudo bootc upgrade && bootc status     # yeni surum "staged" gorunmeli
sudo systemctl reboot
# Ayarlar > Sistem Hakkinda: yeni surum
sudo bootc rollback && sudo systemctl reboot
```

### 3. OTOMATIK geri donus — asil test

Ikisi ayri sey: elle geri donus calisiyor diye otomatigi calisiyor
sanma. Otomatik olan GRUB'un `boot_counter`'i kalici yazmasina bagli.

```bash
sudo ./rollback-test.sh arm      # kasitli basarisiz saglik kontrolu
sudo bootc upgrade
sudo systemctl reboot
```

Beklenen: yeni deployment 3 kez acilmayi dener, her denemede
`boot_counter` iner, sifira varinca **onceki deployment** acilir.
Sonra:

```bash
sudo ./rollback-test.sh status
sudo ./rollback-test.sh disarm
```

Kontrol 3 basarisizliktan sonra kendini kapatiyor, yani VM saglikli
bir acilisa mutlaka ulasiyor — kilitlenme yok. `disarm` yine de
gerekli: sayac /var'da duruyor.

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

---

## CI ve yayin

Push sonrasi GitHub Actions: derle -> **dogrula** -> ghcr'ye gonder ->
cosign ile imzala. Dogrulama push'tan once; gecmezse imaj registry'ye
hic cikmaz.

```bash
gh run watch                                   # calisan derlemeyi izle
gh run view --log-failed                       # patlayan adimin logu
podman pull ghcr.io/mcahitkutsal/mfaos:44      # yayinlanani cek
cosign verify --key cosign.pub ghcr.io/mcahitkutsal/mfaos:44
```
