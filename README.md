# Dynamic Island

Dynamic Island untuk desktop Linux & Windows, dibuat dengan Flutter. Ringan (dioptimalkan untuk RAM 4 GB / Intel HD).

**Developer:** [AjarHer08](https://github.com/AjarHer08)

## Fitur

- Pill kecil di atas layar yang membesar menjadi panel: musik + visualizer, lirik, notifikasi, cuaca & alarm, kalender, pengingat/DND, baterai, performa, dan pengaturan.
- **Liquid Glass**: efek kaca yang bisa dipadukan dengan gaya iOS 17, macOS Notch, Material You, maupun Gaming (sakelar di Pengaturan).
- **Performa**: CPU, RAM, dan GPU (NVIDIA, AMD, Intel) beserta riwayat CPU.
- **Baterai** laptop tampil langsung di pill.
- **Balas pesan** dari notifikasi. WhatsApp Web di Firefox dikirim langsung lewat ekstensi
  `wa_bridge_extension` (lihat README di dalamnya) tanpa membuka browser.

## Menjalankan

```bash
flutter pub get
flutter run -d linux      # atau: flutter run -d windows
```

Linux: `sudo apt install xdotool` (dipakai untuk balas pesan ke aplikasi desktop, X11).

## Fitur tambahan

- **Geser kiri/kanan** untuk pindah tab (mouse, touchpad, atau sentuh); ikon tab tetap bisa diklik.
- **Kalender** bulanan dengan penanda alarm.
- **Baterai**: laptop (`/sys/class/power_supply`) dan perangkat Bluetooth (BlueZ `Battery1`).
  Bila headset tidak melaporkan baterai, aktifkan `Experimental = true` di
  `/etc/bluetooth/main.conf` lalu `sudo systemctl restart bluetooth`.
- **Balas pesan** dari tab Notifikasi: teks disalin, jendela aplikasi (WhatsApp/Telegram/LINE/dll)
  diaktifkan dan ditempel lewat `xdotool` (`sudo apt install xdotool`, X11). Enter otomatis
  bisa dinyalakan di Settings.
- **Ukuran & sudut** pill/panel diatur lewat Settings.

## Membuat installer

- **Linux (.deb):** `bash scripts/build_deb.sh` → `dist/dynamic-island_<versi>_amd64.deb`
- **Windows (.exe):** di Windows, `powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1`
  → `dist\dynamic-island-<versi>-setup.exe` (butuh Inno Setup 6)
- **Otomatis:** push tag `v*` dan workflow `.github/workflows/release.yml` membuat keduanya
  lalu melampirkannya ke GitHub Release.

## Musik offline (file lokal)

- File tanpa tag tetap tampil: judul/artis diambil dari nama file (`01 - Artis - Judul.mp3`).
- Cover diambil dari folder lagu (`cover.jpg`, `folder.png`, dll.).
- Lirik offline: taruh `NamaLagu.lrc` (tersinkron) atau `NamaLagu.txt` di folder yang sama dengan lagunya.
- Lirik yang sudah pernah dicari online disimpan di cache (`~/.cache/dynamic_island/lyrics`),
  jadi tetap muncul saat internet mati.
- Pembacaan musik memakai MPRIS, jadi baru jalan di Linux (VLC, Rhythmbox, Spotify, dll.).

## Pembaruan & sembunyi otomatis (v1.1.0)
- **Cek pembaruan**: memeriksa rilis terbaru di `github.com/AjarHer08/dynamic-island` (Pengaturan). Jika repo/rilis belum ada, tampil "Belum ada rilis".
- **Sembunyi saat tidak dipakai**: hilang setelah N detik; muncul lagi saat ada notifikasi/alarm, kursor diarahkan ke posisi island, atau menu tray > Show.
- **Sembunyi seketika saat nonton**: layar penuh (Windows: SHQueryUserNotificationState; Linux X11: butuh `xprop`, paket `x11-utils`) atau video terdeteksi lewat MPRIS (VLC/mpv/browser). Alarm tetap muncul.
