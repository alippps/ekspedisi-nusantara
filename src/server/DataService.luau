-- Simpan data pemain secara permanen pakai ProfileStore: Koin, XP, jurnal, dan isi tas.
-- Level sengaja tidak disimpan: selalu dihitung dari XP, jadi aman kalau kurva level diganti.
-- Service lain baca/tulis lewat DataService.get(player); ProfileStore yang urus auto-save.
local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Packages.ProfileStore)

-- Nama "laci" penyimpanan di DataStore Roblox. Jangan diganti setelah rilis:
-- ganti nama = semua pemain mulai dari nol lagi.
local STORE_NAME = "PlayerData_v1"

local TEMPLATE = {
	Coins = 0,
	XP = 0,
	Journal = {}, -- [itemId] = berapa kali item itu sudah disetor
	Bag = {}, -- { itemId, ... } isi tas yang belum disetor
	DataVersion = 1, -- naikkan kalau format data berubah dan butuh migrasi
}

local DataService = {}

local store = ProfileStore.New(STORE_NAME, TEMPLATE)
local profiles = {} -- [Player] = Profile
local loadedCallbacks: { (Player, any) -> () } = {}

local function loadPlayer(player: Player)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			player:Kick("Gagal memuat data kamu. Coba masuk lagi ya!")
		end
		return
	end

	profile:AddUserId(player.UserId) -- wajib buat GDPR
	profile:Reconcile() -- isi field baru dari TEMPLATE kalau data lama belum punya

	-- Session berakhir: pemain keluar, atau datanya diambil server lain (join di server lain).
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Data kamu sedang dipakai di server lain. Coba masuk lagi ya!")
	end)

	if player.Parent ~= Players then
		-- Keburu keluar saat loading
		profile:EndSession()
		return
	end

	profiles[player] = profile
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile.Data)
	end
end

-- Data pemain, atau nil kalau belum selesai dimuat / sudah keluar.
function DataService.get(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data
end

-- Panggil callback(player, data) tiap kali data pemain selesai dimuat
-- (termasuk pemain yang datanya sudah dimuat sebelum callback didaftarkan).
function DataService.onLoaded(callback: (Player, any) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile.Data)
	end
end

function DataService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerAdded:Connect(loadPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile:EndSession() -- simpan terakhir dan lepas kunci session
		end
	end)
end

return DataService
