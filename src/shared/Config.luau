--!strict
-- Semua angka balancing ada di sini. Ubah di file ini, jangan di logic.
local Config = {}

Config.Stamina = {
	Max = 100,
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

Config.Bag = {
	BaseSlots = 10,
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

Config.Level = {
	XPPerLevel = 100, -- sementara linear, nanti diganti kurva
}

Config.Rarity = {
	Common = { Weight = 60, Coin = 5, XP = 2, FirstXP = 10, Color = Color3.fromRGB(154, 163, 160) },
	Uncommon = { Weight = 25, Coin = 15, XP = 5, FirstXP = 25, Color = Color3.fromRGB(93, 182, 90) },
	Rare = { Weight = 10, Coin = 50, XP = 15, FirstXP = 60, Color = Color3.fromRGB(62, 142, 222) },
	Epic = { Weight = 4, Coin = 150, XP = 40, FirstXP = 150, Color = Color3.fromRGB(155, 92, 214) },
	Legendary = { Weight = 1, Coin = 500, XP = 120, FirstXP = 400, Color = Color3.fromRGB(232, 178, 46) },
}

-- Prototype: 10 item Zona 1. Zona 2 dan 3 ditambah di fase MVP.
-- Time: "Any" | "Day" | "Night"
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
}

return Config
