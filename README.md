# Dynamic Island untuk Windows

Overlay "pill" ala Dynamic Island untuk Windows 10/11: musik, notifikasi, baterai, performa (CPU/RAM/GPU), kalender, cuaca, alarm, dan tema Liquid Glass.
Developer: **AjarHer08**

## Pasang (pengguna biasa)
1. Unduh `dynamic-island-<versi>-setup.exe` dari halaman [Releases](https://github.com/AjarHer08/dynamic-island/releases).
2. Jalankan installer, ikuti langkahnya.
3. Buka **Dynamic Island** dari Start Menu. Ikonnya muncul di tray (kanan bawah). Klik kanan tray untuk **Show / DND / Exit**.

> Jika Windows SmartScreen memperingatkan: klik **More info > Run anyway** (installer belum ditandatangani).

## Fitur khusus Windows
- Sembunyi otomatis saat tidak dipakai, dan **seketika** saat aplikasi layar penuh (film, anime, YouTube fullscreen, game).
- Baterai laptop dan perangkat Bluetooth, performa CPU/RAM/GPU.
- Cek pembaruan otomatis ke GitHub (bisa dimatikan di Pengaturan).

Belum tersedia di Windows: kontrol musik (MPRIS hanya Linux), balas pesan WA Web via xdotool.

## Build dari source
Kebutuhan:
- Flutter SDK (mis. `D:\flutter`) dan tambahkan `...\flutter\bin` ke PATH
- Visual Studio Build Tools 2022: workload **Desktop development with C++** (MSVC v142, CMake, Windows 10/11 SDK). Pasang dengan PowerShell **Administrator**
- Windows **Developer Mode** aktif (Settings > For developers), untuk symlink
- Inno Setup 6 (`winget install JRSoftware.InnoSetup`)

Jalankan satu per satu:
```powershell
cd D:\dynamic_island
flutter pub get
flutter run -d windows
```
Buat installer:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
```
Hasil: `dist\dynamic-island-<versi>-setup.exe`

Jika `iscc` tidak ditemukan (Inno Setup terpasang per-user):
```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" installer\dynamic_island.iss
```

## Masalah umum
| Masalah | Solusi |
|---|---|
| `flutter` tidak dikenali | Tambahkan folder `bin` Flutter ke PATH, buka PowerShell baru |
| Error symlink saat `pub get` | Aktifkan Developer Mode |
| Error VS / CMake tidak ada | Modify Build Tools, centang workload C++, jalankan sebagai Admin |
| Island tidak terlihat | Mungkin tersembunyi otomatis: gerakkan kursor ke posisinya atau tray > Show |
| Island hilang saat nonton | Itu fitur; matikan di Pengaturan > "Sembunyi seketika saat nonton" |

## Hapus
Settings > Apps > Dynamic Island > Uninstall.
