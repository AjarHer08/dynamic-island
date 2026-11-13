# Dynamic Island WA Bridge (Firefox)

Supaya balasan dari island langsung terkirim ke WhatsApp Web tanpa membuka Firefox.

## Pasang (sementara)
1. Buka `about:debugging#/runtime/this-firefox` di Firefox.
2. Klik **Load Temporary Add-on...** lalu pilih `manifest.json` di folder ini.
3. Muat ulang tab web.whatsapp.com.

Add-on sementara hilang saat Firefox ditutup. Untuk permanen: tanda tangani lewat
AMO (unlisted, gratis) dengan `npx web-ext sign`, atau pakai Firefox Developer
Edition/Nightly dengan `xpinstall.signatures.required = false` lalu pasang zip-nya.

## Cara kerja
Island membuka WebSocket di 127.0.0.1:48721. Ekstensi tersambung ke sana, menerima
perintah, dan mengisi + mengirim pesan di tab WA Web lewat DOM. Tidak ada data
yang keluar dari komputermu.

Bila ekstensi tidak tersambung, island kembali ke cara lama (xdotool).

## Panggilan masuk (v1.1)
Saat WhatsApp Web menampilkan popup panggilan masuk, ekstensi melaporkannya ke
island. Tombol **Terima** / **Tolak** di island menekan tombol yang sama di
WhatsApp Web. Syaratnya: tab web.whatsapp.com terbuka di Firefox dan ekstensi
v1.1 terpasang (muat ulang add-on + tab WA Web setelah memperbarui).

Tombol dikenali dari labelnya (Accept/Answer/Terima/Jawab dan
Decline/Reject/Tolak), jadi bila WhatsApp mengubah tampilannya dan tombol tidak
terdeteksi, panggilan tetap bisa dijawab langsung di tab WhatsApp Web. Untuk
menerima panggilan, Firefox mungkin meminta izin mikrofon/kamera sekali.
