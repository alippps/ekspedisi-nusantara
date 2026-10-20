# Ekspedisi Nusantara — project Rojo

## Setup (sekali saja)
1. Install Rojo: lewat Rokit (`rokit add rojo-rbx/rojo`) atau extension "Rojo" di VS Code.
2. Install plugin Rojo di Roblox Studio (otomatis dari extension VS Code, atau dari Creator Store).
3. Di folder ini jalankan `rojo serve`.
4. Di Studio, buka place lu, klik plugin Rojo, lalu Connect.

## Penyimpanan data (wajib buat tes save di Studio)
Data pemain (Koin, XP, jurnal, isi tas) disimpan pakai ProfileStore di DataStore `PlayerData_v1`.
1. Place harus sudah di-publish ke Roblox (File > Publish to Roblox).
2. Home > Game Settings > Security > nyalakan **Enable Studio Access to API Services**.
3. Saat Play, Output harus menampilkan `[ProfileStore]: Roblox API services available - data will be saved`.
   Kalau yang muncul `... unavailable - data will not be saved`, data cuma tersimpan sementara (hilang tiap Stop).

Jangan ganti nama `PlayerData_v1` di `src/server/DataService.luau` setelah rilis: ganti nama = semua pemain mulai dari nol.

`src/server/Packages/ProfileStore.luau` adalah ProfileStore 1.0.3 dari
https://github.com/MadStudioRoblox/ProfileStore (commit `45c9847`, lisensi Apache-2.0). Jangan diedit langsung.

## Struktur
- `src/shared` → ReplicatedStorage.Shared (Config, dipakai client dan server)
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client

## Tes hari ini
1. Play di Studio.
2. Tahan Shift buat lari, coba manjat TrussPart, coba jalan nanjak.
3. Di Explorer, klik Players > nama lu, lihat attribute `Stamina` (0-1) dan `Exhausted` berubah.
4. Ubah angka di `src/shared/Config.luau` kalau rasanya terlalu cepat/lambat habis.
