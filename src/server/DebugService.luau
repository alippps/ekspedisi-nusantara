-- Perintah debug lewat chat, buat ngetes UI tanpa harus jalan ke mana-mana.
-- CUMA jalan di Studio: init.server nggak nge-require modul ini di server publik, dan start() ngecek lagi.
-- Semua perubahan lewat data server + sinkron attribute, jadi alurnya sama dengan game asli.
-- Catatan: Koin/XP/tier yang diubah di sini ikut tersimpan ke save kamu (ProfileStore), sama kayak beli di Studio.
--
-- Perintah:
--   /zona 1|2|3|auto   paksa zona aktif di HUD (auto = balik ke deteksi posisi)
--   /jam siang|malam   atur jam (atau angka 0-24, contoh /jam 17.5)
--   /level N           set level (XP di-set ke XP minimal level itu)
--   /senter N          set tier Senter Kepala (1 = belum punya)
--   /koin N            set jumlah koin
--   /puncak [reset]    paksa summit sekarang (reset = hapus title, jumlah summit, bonus harian)
--   /misi reset        ulang misi pemula dari langkah pertama
--   /pos N|reset       tandai Pos N ditemukan (reset = lupakan semua pos kecuali Basecamp)
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local BagService = require(script.Parent.BagService)
local UpgradeService = require(script.Parent.UpgradeService)
local SummitService = require(script.Parent.SummitService)
local TutorialService = require(script.Parent.TutorialService)
local RangerService = require(script.Parent.RangerService)

local D = Config.DayNight
local MAX_LEVEL = 100

local DebugService = {}

local notify: RemoteEvent

-- Angka bulat >= min, atau nil kalau bukan angka
local function parseInt(arg: string?, min: number): number?
	local n = tonumber(arg)
	if not n or n ~= math.floor(n) or n < min then
		return nil
	end
	return n
end

-- [nama] = function(player, arg) -> teks balasan
local COMMANDS: { [string]: (Player, string?) -> string } = {}

COMMANDS.zona = function(player, arg)
	if arg == "auto" then
		player:SetAttribute("DebugZone", nil)
		return "Zona balik ke deteksi otomatis"
	end
	local zone = parseInt(arg, 1)
	if not zone or not Config.Zones[zone] then
		return string.format("Pakai: /zona 1-%d atau /zona auto", #Config.Zones)
	end
	player:SetAttribute("DebugZone", zone)
	return string.format("Zona dipaksa ke %d · %s", zone, Progression.zoneName(zone))
end

COMMANDS.jam = function(_player, arg)
	local clock
	if arg == "siang" then
		clock = (D.DayStart + D.DayEnd) / 2
	elseif arg == "malam" then
		clock = ((D.DayEnd + D.DayStart + 24) / 2) % 24
	else
		clock = tonumber(arg)
	end
	if not clock or clock < 0 or clock >= 24 then
		return "Pakai: /jam siang, /jam malam, atau /jam 0-24"
	end
	Lighting.ClockTime = clock
	return string.format("Jam di-set ke %.1f", clock)
end

COMMANDS.level = function(player, arg)
	local level = parseInt(arg, 1)
	if not level or level > MAX_LEVEL then
		return string.format("Pakai: /level 1-%d", MAX_LEVEL)
	end
	local data = DataService.get(player)
	if not data then
		return "Data kamu belum siap"
	end
	data.XP = Progression.totalXPForLevel(level)
	BagService.sync(player)
	return string.format("Level di-set ke %d (%d XP)", level, data.XP)
end

COMMANDS.senter = function(player, arg)
	local levels = Config.Upgrades.Headlamp.Levels
	local tier = parseInt(arg, 1)
	if not tier or tier > #levels then
		return string.format("Pakai: /senter 1-%d (1 = belum punya)", #levels)
	end
	if not UpgradeService.setTier(player, "Headlamp", tier) then
		return "Data kamu belum siap"
	end
	return string.format("Senter di-set ke Tier %d (jangkauan %d)", tier, levels[tier].Value)
end

COMMANDS.puncak = function(player, arg)
	if arg == "reset" then
		if not SummitService.debugReset(player) then
			return "Data kamu belum siap"
		end
		return "Progres summit dihapus (title, jumlah summit, bonus harian)"
	end
	SummitService.debugSummit(player)
	return "Summit dipaksa"
end

COMMANDS.misi = function(player, arg)
	if arg ~= "reset" then
		return "Pakai: /misi reset"
	end
	if not TutorialService.debugReset(player) then
		return "Data kamu belum siap"
	end
	return "Misi pemula diulang dari awal"
end

COMMANDS.pos = function(player, arg)
	if arg == "reset" then
		if not RangerService.debugReset(player) then
			return "Data kamu belum siap"
		end
		return "Semua pos dilupakan (Basecamp tetap terbuka)"
	end
	local number = parseInt(arg, 1)
	if not number then
		return "Pakai: /pos N atau /pos reset"
	end
	if not RangerService.debugFind(player, number) then
		return string.format("Pos %d nggak ada di map (atau data belum siap)", number)
	end
	return string.format("Pos %d ditandai ditemukan", number)
end

COMMANDS.koin = function(player, arg)
	local coins = parseInt(arg, 0)
	if not coins then
		return "Pakai: /koin N (angka 0 ke atas)"
	end
	local data = DataService.get(player)
	if not data then
		return "Data kamu belum siap"
	end
	data.Coins = coins
	BagService.sync(player)
	return string.format("Koin di-set ke %d", coins)
end

local function run(player: Player, text: string)
	local name, arg = string.match(string.lower(text), "^/(%S+)%s*(%S*)")
	local command = name and COMMANDS[name]
	if not command then
		return -- bukan perintah debug (misal /e dance), diamkan aja
	end
	local reply = command(player, if arg ~= "" then arg else nil)
	print(string.format("[Debug] %s: %s → %s", player.Name, text, reply))
	notify:FireClient(player, "Debug", reply)
end

function DebugService.start()
	if not RunService:IsStudio() then
		return
	end
	notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		-- Chat baru: tiap perintah jadi TextChatCommand, pesannya nggak ikut tampil di chat
		local folder = Instance.new("Folder")
		folder.Name = "DebugCommands"
		for name in COMMANDS do
			local command = Instance.new("TextChatCommand")
			command.Name = "Debug_" .. name
			command.PrimaryAlias = "/" .. name
			command.Triggered:Connect(function(source: TextSource, text: string)
				local player = Players:GetPlayerByUserId(source.UserId)
				if player then
					run(player, text)
				end
			end)
			command.Parent = folder
		end
		folder.Parent = TextChatService
	else
		-- Chat lama (LegacyChatService)
		local function hook(player: Player)
			player.Chatted:Connect(function(message)
				run(player, message)
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end
	print("[Debug] perintah chat aktif (Studio): /zona /jam /level /senter /koin /puncak /misi /pos")
end

return DebugService
