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

## Setup map di Studio
Map gunung dibangun BuildGunung (v4). Yang dibaca kode (nama harus persis):
- Pos Ranger: Model ber-Tag `PosRanger` dengan attribute `PosNumber` (1, 2, 3) dan `Zone`, berisi Part `PromptAnchor`
  (tempat tombol Setor & Menu Pos). Opsional Part `TeleportPoint` = titik muncul pas teleport ke pos itu.
  Pos 1 = Basecamp. Boleh di mana aja di Workspace.
- `Workspace > SpawnPoints > Zone1, Zone2, ...` (Folder): Part kecil di tanah sebagai titik munculnya item.
- `Workspace > Zones > Zone1, Zone2, ...`: kotak transparan per zona, ditumpuk berdasarkan ketinggian
  (Zone1 di bawah Y 55, Zone2 Y 55-125, Zone3 Y 125 ke atas). Kalau tumpang tindih, nomor zona paling besar yang dipakai.
  CanCollide/CanTouch/CanQuery off. Kalau StreamingEnabled nyala, jadikan Model dengan ModelStreamingMode = Persistent.
- `Workspace > ZoneGates > Gate2, Gate3`: Model gerbang, boleh miring. Cuma part bernama `Barrier`/`Palang` yang dibuka.
- Dinding cincin zona (sekarang di `Workspace.Vulkan.DindingZona`): Part ber-Tag `ZoneBarrier` dengan attribute `Zone` (2 atau 3).
  Tembus & hilang per pemain begitu zonanya terbuka (syarat sama dengan gerbang, dari `Config.Zones`).
- `SummitTrigger`: Part di puncak (sekarang di `Workspace.Gunung`, dicari di mana aja).
- `StarterPlayer.CharacterMaxSlopeAngle = 45`: jangan diubah, ini yang bikin pemain nggak bisa manjat tebing.

Cek semuanya sekaligus: paste isi `tools/check_map.lua` ke Command Bar (bukan mode Play), lihat Output.

## Struktur
- `src/shared` → ReplicatedStorage.Shared (Config, dipakai client dan server)
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client

## Tes hari ini
1. Play di Studio.
2. Tahan Shift buat lari, coba manjat TrussPart, coba jalan nanjak.
3. Di Explorer, klik Players > nama lu, lihat attribute `Stamina` (0-1) dan `Exhausted` berubah.
4. Ubah angka di `src/shared/Config.luau` kalau rasanya terlalu cepat/lambat habis.
