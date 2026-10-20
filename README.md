# Ekspedisi Nusantara — project Rojo

## Setup (sekali saja)
1. Install Rojo: lewat Rokit (`rokit add rojo-rbx/rojo`) atau extension "Rojo" di VS Code.
2. Install plugin Rojo di Roblox Studio (otomatis dari extension VS Code, atau dari Creator Store).
3. Di folder ini jalankan `rojo serve`.
4. Di Studio, buka place lu, klik plugin Rojo, lalu Connect.

## Struktur
- `src/shared` → ReplicatedStorage.Shared (Config, dipakai client dan server)
- `src/server` → ServerScriptService.Server
- `src/client` → StarterPlayer.StarterPlayerScripts.Client

## Tes hari ini
1. Play di Studio.
2. Tahan Shift buat lari, coba manjat TrussPart, coba jalan nanjak.
3. Di Explorer, klik Players > nama lu, lihat attribute `Stamina` (0-1) dan `Exhausted` berubah.
4. Ubah angka di `src/shared/Config.luau` kalau rasanya terlalu cepat/lambat habis.
