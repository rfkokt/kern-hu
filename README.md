# kern-hu

Debloat + tuning headunit Android generik **MediaTek AC8227L** (`alps / 8227L_demo`, Android 8.1, RAM 1 GB, layar 1024×600) lewat ADB, plus setup CarPlay / Android Auto.

Semua perubahan **reversible**: app gak dihapus dari `/system`, cuma di-hide dari user 0 (`pm uninstall -k --user 0`) dan dicatat di `hu-removed.txt`. Balikin pakai `./hu-debloat.sh restore`.

> ⚠️ Tes semuanya dalam kondisi **mobil parkir**: kamera mundur, tombol setir, radio, Bluetooth telpon. Kalau ada yang mati, jalanin `restore`.

---

## 1. Persiapan (sekali aja, di Mac)

```bash
brew install android-platform-tools   # dapet adb
git clone https://github.com/rfkokt/kern-hu.git && cd kern-hu
chmod +x hu-debloat.sh
```

## 2. Konek ke HU

ADB di HU ini **udah nyala lewat WiFi di port 8555** (`service.adb.tcp.port=8555`, `init.svc.adbd=running`).

1. Sambungin HU dan Mac ke WiFi yang sama (bisa hotspot HP). **Jangan pakai WiFi publik**, karena ADB yang terbuka bisa diakses siapa aja di jaringan itu.
2. Cari IP HU: *Settings → WiFi → (nama WiFi) → IP address*.
3. Konek:
   ```bash
   adb connect 192.168.x.x:8555
   adb devices          # harus muncul "device", bukan "unauthorized"
   ```
4. Kalau muncul `unauthorized`, liat layar HU, centang *Always allow*, lalu tap **Allow** (HU ini pakai `ro.adb.secure=1`).

Kalau IP-nya berubah-ubah, pakai `DEVICE=192.168.x.x:8555 ./hu-debloat.sh ...`.

## 3. Cek kondisi dulu

```bash
./hu-debloat.sh diag        # RAM, CPU, suhu, proses berat  → hu-diag-*.txt
./hu-debloat.sh scan        # semua paket + label           → hu-packages-*.txt
./hu-debloat.sh linkcheck   # app CarPlay/AA bawaan + USB host
./hu-debloat.sh rootcheck   # ada /system/xbin/su, siapa tau kepake
```

Paket dengan label `review` / `3RD-PARTY` di `hu-packages-*.txt` biasanya app bawaan seller. Yang mau dibuang ditulis ke `hu-extra.txt` (satu paket per baris), lalu jalanin `./hu-debloat.sh extra`.

## 4. Pilih profil

### Profil A — CarPlay-first (paling enteng, rekomendasi buat iPhone)

Maps, Spotify, dan YouTube jalan **di iPhone**, HU cuma jadi layar. Google Play Services boleh dibuang, dan itu penghemat RAM paling gede.

```bash
./hu-debloat.sh apply --nogms
./hu-debloat.sh tune
./hu-debloat.sh install      # isi ./apk dengan AutoKit (lihat bagian 5), NewPipe opsional
adb reboot
```

### Profil B — Standalone (HU jalan sendiri tanpa HP)

Google Play Services tetap ada karena Google Maps butuh. Play Store, app Google lain, dan YouTube bawaan dibuang.

```bash
./hu-debloat.sh apply --minimal
./hu-debloat.sh tune
./hu-debloat.sh install      # isi ./apk dengan Maps, Spotify, NewPipe
adb reboot
```

Mau lebih enteng lagi? Pakai `--nogms` dan ganti Google Maps dengan **Organic Maps** (offline, tanpa Google, tapi gak ada info macet).

## 5. APK yang dipakai

Taruh di folder `./apk/`. File `.apk` tunggal langsung ditaruh. Split APK (`.apkm`/`.xapk`) diekstrak dulu ke subfolder, misalnya `apk/maps/`, lalu `install` otomatis pakai `install-multiple`.

Ambil varian **armeabi-v7a** (HU ini 32-bit), **nodpi**, dan **minimal Android ≤ 8.0**.

| App | Sumber | Catatan |
|---|---|---|
| NewPipe | F-Droid / GitHub NewPipe | YouTube tanpa Google, bisa putar di background, min Android 6 |
| Spotify | APKMirror | min Android 7. Login pakai email/password, **bukan** "Continue with Google" |
| Google Maps | APKMirror | **butuh Google Play Services**, jadi cuma buat Profil B |
| Organic Maps | F-Droid / GitHub | alternatif Maps tanpa Google, peta offline |
| AutoKit | carlinkit.com / app store dongle | cuma kalau pakai dongle Carlinkit (bagian 6) |

## 6. CarPlay & Android Auto

HU generik **gak punya CarPlay/AA bawaan dari Android**. Butuh app "phone link" yang berlisensi, atau dongle. Jalanin `./hu-debloat.sh linkcheck` dulu.

**Kalau `linkcheck` nemu app bawaan** (`zlink`, `easyconn`, `carbit`, `tlink`, dll.)
- Pakai app itu, karena itu yang lisensinya nempel di HU. Script ini **gak akan pernah menghapusnya** (masuk daftar protected).
- Biasanya CarPlay kabel: colok iPhone ke port USB HU pakai kabel data original, lalu buka app-nya.
- Wireless cuma jalan kalau app/firmware-nya mendukung.
- Jangan sideload ZLink/TLink dari internet. App itu butuh aktivasi per perangkat, jadi biasanya cuma muncul layar "activation".

**Kalau gak ada app bawaan → dongle Carlinkit**
- Beli versi **"for Android head unit"** (misalnya CPC200-CCPA), **bukan** versi buat mobil yang udah ada CarPlay pabrikan.
- Colok dongle ke port USB HU (jangan lewat hub), lalu install app **AutoKit** dan buka.
- Di AutoKit: *Settings → environment test*. Ketiganya harus centang hijau.
- iPhone: CarPlay **wireless**. Pair Bluetooth ke dongle (PIN `0000`), WiFi dan Bluetooth HP harus nyala.
- Android: Android Auto lewat **kabel** ke dongle.
- Layar hitam? Di AutoKit pilih mode *Compatible*, rendering *Others*, matiin cek rem tangan, lalu clear cache AutoKit.

**Android Auto dari HP Android tanpa dongle:** *Headunit Reloaded* (berbayar, Android Auto kabel lewat USB). Gak relevan buat iPhone.

Dengan RAM 1 GB, jangan jalanin Maps/Spotify di HU **sambil** CarPlay. Biarin semuanya jalan dari iPhone.

## 7. Perintah lain

```bash
./hu-debloat.sh bgoff com.foo.bar     # larang app jalan di background
./hu-debloat.sh compile               # precompile app (lama, sekali aja)
./hu-debloat.sh restore               # balikin semua yang pernah dihapus
FORCE=1 ./hu-debloat.sh extra         # paksa hapus paket "protected" dari hu-extra.txt (hati-hati)
```

## Catatan

- Yang **gak pernah disentuh** script ini: servis mobil MTK/Autochips (kamera mundur, AVIN, MCU, tombol setir, CAN), Bluetooth/telpon, radio, launcher, app phone-link/CarPlay, WebView, dan Chrome (di Android 8.1 Chrome bisa jadi WebView sistem).
- KlikDash (`ashafizullah/klikdash`) dibikin buat NWD K2401 1280×720. Di HU ini (1024×600, MTK) tampilannya bisa kepotong dan tweak khusus NWD-nya gak jalan.
- Uninstall per-user hilang kalau HU di-*factory reset*. Tinggal jalanin ulang script-nya.
