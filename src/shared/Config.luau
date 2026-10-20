--!strict
-- Semua angka balancing ada di sini. Ubah di file ini, jangan di logic.
local Config = {}

Config.Stamina = {
	-- Stamina maks ada di Config.Upgrades.Stamina (tier 1 = awal)
	SprintDrain = 18, -- per detik saat lari
	ClimbDrain = 12, -- per detik saat manjat tangga/truss
	UphillDrain = 6, -- per detik saat jalan nanjak
	UphillMinRise = 2, -- kecepatan naik (stud/detik) yang dianggap nanjak
	RegenIdle = 20, -- per detik saat diam
	RegenWalk = 8, -- per detik saat jalan datar/turun
	RecoverAt = 30, -- setelah habis, harus pulih sampai sini baru bisa lari lagi
	WalkSpeed = 16,
	SprintSpeed = 24,
	TiredSpeed = 10,
}

-- Upgrade gear di Pos Ranger. Levels[1] = kondisi awal (gratis).
-- Value = nilai stat di tier itu, Price = harga koin buat naik ke tier itu.
-- MinLevel (opsional) = level pemain minimal buat beli tier itu, contoh: { Value = 17, Price = 900, MinLevel = 4 }
Config.Upgrades = {
	Bag = {
		Name = "Tas Carrier",
		Stat = "Slot tas",
		Order = 1,
		Levels = {
			{ Value = 10, Price = 0 },
			{ Value = 12, Price = 150 },
			{ Value = 14, Price = 400 },
			{ Value = 17, Price = 900 },
			{ Value = 20, Price = 1800 },
		},
	},
	Stamina = {
		Name = "Sepatu Gunung",
		Stat = "Stamina maks",
		Order = 2,
		Levels = {
			{ Value = 100, Price = 0 },
			{ Value = 120, Price = 120 },
			{ Value = 140, Price = 350 },
			{ Value = 165, Price = 800 },
			{ Value = 200, Price = 1600 },
		},
	},
}

Config.Shop = {
	PromptDistance = 10, -- jarak tombol "Upgrade" di Pos Ranger (stud)
	MaxDistance = 16, -- server nolak beli kalau pemain lebih jauh dari ini dari Pos Ranger
	CloseDistance = 14, -- panel toko otomatis nutup kalau pemain menjauh sejauh ini
	BuyCooldown = 0.3, -- jeda minimal antar pembelian (detik), anti spam klik
}

Config.Spawn = {
	RespawnMin = 20, -- detik sebelum item baru muncul di titik yang sama
	RespawnMax = 45,
	PromptDistance = 8, -- jarak maksimal tombol "Ambil" (stud)
	HoldDuration = 0.3, -- lama tahan tombol "Ambil" (detik)
}

Config.DayNight = {
	CycleSeconds = 720, -- satu putaran siang-malam = 12 menit
	StartClock = 8, -- jam saat server mulai
	DayStart = 6,
	DayEnd = 18,
}

-- Kurva XP: XP buat naik dari Lv L ke L+1 = BaseXP * L^Growth, dibulatkan ke kelipatan RoundTo.
-- Dengan angka di bawah:
--   Lv 1→2: 100   (total 100)    Lv 4→5: 605   (total 1365)
--   Lv 2→3: 245   (total 345)    Lv 5→6: 810   (total 2175)
--   Lv 3→4: 415   (total 760)    Lv 9→10: 1740 (total 7690)
-- Lv 3 (Hutan Lumut) kira-kira kebuka pas Jurnal Zona 1 hampir penuh (~260 XP dari temuan pertama).
-- Level nggak disimpan, selalu dihitung dari XP, jadi aman diubah kapan aja.
Config.Level = {
	BaseXP = 100,
	Growth = 1.3, -- 1 = linear, makin besar makin curam
	RoundTo = 5,
}

-- Zona gunung. Index = nomor zona (sama dengan folder SpawnPoints/ZoneN, Zones/ZoneN, ZoneGates/GateN).
-- MinLevel = level pemain minimal buat masuk & ambil item di zona itu.
Config.Zones = {
	{ Name = "Kaki Gunung", MinLevel = 1 },
	{ Name = "Hutan Lumut", MinLevel = 3 },
}

Config.Rarity = {
	Common = { Weight = 60, Coin = 5, XP = 2, FirstXP = 10, Color = Color3.fromRGB(154, 163, 160) },
	Uncommon = { Weight = 25, Coin = 15, XP = 5, FirstXP = 25, Color = Color3.fromRGB(93, 182, 90) },
	Rare = { Weight = 10, Coin = 50, XP = 15, FirstXP = 60, Color = Color3.fromRGB(62, 142, 222) },
	Epic = { Weight = 4, Coin = 150, XP = 40, FirstXP = 150, Color = Color3.fromRGB(155, 92, 214) },
	Legendary = { Weight = 1, Coin = 500, XP = 120, FirstXP = 400, Color = Color3.fromRGB(232, 178, 46) },
}

-- Time: "Any" | "Day" | "Night"
-- Icon (opsional): "rbxassetid://..." buat gambar di Jurnal
Config.Items = {
	{ Id = "pakis_hutan", Name = "Pakis Hutan", Category = "Flora", Rarity = "Common", Zone = 1, Time = "Any" },
	{ Id = "kupu_biru", Name = "Kupu-kupu Biru", Category = "Fauna", Rarity = "Common", Zone = 1, Time = "Day" },
	{ Id = "tupai_pohon", Name = "Tupai Pohon", Category = "Fauna", Rarity = "Common", Zone = 1, Time = "Day" },
	{ Id = "batu_kali", Name = "Batu Kali", Category = "Batuan", Rarity = "Common", Zone = 1, Time = "Any" },
	{ Id = "anggrek_tanah", Name = "Anggrek Tanah", Category = "Flora", Rarity = "Uncommon", Zone = 1, Time = "Any" },
	{ Id = "burung_cucak", Name = "Burung Cucak", Category = "Fauna", Rarity = "Uncommon", Zone = 1, Time = "Day" },
	{ Id = "kristal_kuarsa", Name = "Kristal Kuarsa", Category = "Batuan", Rarity = "Uncommon", Zone = 1, Time = "Any" },
	{ Id = "kunang_kunang", Name = "Kunang-kunang", Category = "Fauna", Rarity = "Uncommon", Zone = 1, Time = "Night" },
	{ Id = "kantong_semar", Name = "Kantong Semar", Category = "Flora", Rarity = "Rare", Zone = 1, Time = "Any" },
	{ Id = "koin_kuno", Name = "Koin Kuno", Category = "Artefak", Rarity = "Rare", Zone = 1, Time = "Night" },

	-- Zona 2 · Hutan Lumut (daftar sementara, boleh diganti)
	{ Id = "lumut_hutan", Name = "Lumut Hutan", Category = "Flora", Rarity = "Common", Zone = 2, Time = "Any" },
	{ Id = "jamur_merah", Name = "Jamur Merah", Category = "Flora", Rarity = "Common", Zone = 2, Time = "Any" },
	{ Id = "kodok_pohon", Name = "Kodok Pohon", Category = "Fauna", Rarity = "Common", Zone = 2, Time = "Night" },
	{ Id = "cantigi_gunung", Name = "Cantigi Gunung", Category = "Flora", Rarity = "Uncommon", Zone = 2, Time = "Any" },
	{ Id = "kumbang_tanduk", Name = "Kumbang Tanduk", Category = "Fauna", Rarity = "Uncommon", Zone = 2, Time = "Any" },
	{ Id = "batu_obsidian", Name = "Batu Obsidian", Category = "Batuan", Rarity = "Uncommon", Zone = 2, Time = "Any" },
	{ Id = "lutung_jawa", Name = "Lutung Jawa", Category = "Fauna", Rarity = "Rare", Zone = 2, Time = "Day" },
	{ Id = "burung_celepuk", Name = "Burung Celepuk", Category = "Fauna", Rarity = "Rare", Zone = 2, Time = "Night" },
	{ Id = "elang_jawa", Name = "Elang Jawa", Category = "Fauna", Rarity = "Epic", Zone = 2, Time = "Day" },
	{ Id = "arca_batu", Name = "Arca Batu Kecil", Category = "Artefak", Rarity = "Epic", Zone = 2, Time = "Night" },
}

return Config
