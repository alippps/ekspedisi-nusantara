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
--   /stamina           nyala/matiin stamina tak terbatas
--   /fly               nyala/matiin terbang (geraknya di DebugController client)
--   /speed N|reset     kecepatan jalan & terbang (reset = balik normal, lari & capek jalan lagi)
--   /tp puncak|basecamp|gate2|gate3   teleport cepat (gateN = di depan gerbang, sisi zona bawah)
--   /event <jenis>|stop  mulai event bencana sekarang di zonamu (jenis = kunci Config.Events.Types, misal petir).
--                        Masa aman pemain baru kamu dilewati. stop = hentikan event yang lagi jalan.
-- /stamina, /fly, /speed cuma nyetel attribute Debug*; client juga baru baca attribute itu kalau di Studio.
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
local EventService = require(script.Parent.EventService)

local D = Config.DayNight
local MAX_LEVEL = 100
local MAX_SPEED = 500
local ARRIVAL_HEIGHT = 3.5 -- tinggi HumanoidRootPart dari tanah habis /tp (sama dengan RangerService)
local GATE_TP_OFFSET = 8 -- /tp gateN: muncul sejauh ini (stud) di depan gerbang

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

-- Attribute boolean nyala/mati. Mati = dihapus (nil), biar sama dengan pemain yang nggak pernah pakai debug.
local function toggle(player: Player, attribute: string): boolean
	local on = player:GetAttribute(attribute) ~= true
	player:SetAttribute(attribute, if on then true else nil)
	return on
end

COMMANDS.stamina = function(player)
	return if toggle(player, "DebugInfiniteStamina") then "Stamina tak terbatas: NYALA" else "Stamina tak terbatas: mati"
end

COMMANDS.fly = function(player)
	if toggle(player, "DebugFly") then
		return "Terbang: NYALA (PC: WASD, Space naik, Ctrl turun · HP: joystick + arah kamera)"
	end
	return "Terbang: mati"
end

COMMANDS.speed = function(player, arg)
	if arg == "reset" then
		player:SetAttribute("DebugSpeed", nil)
		return string.format("Kecepatan balik normal (jalan %d, lari %d)", Config.Stamina.WalkSpeed, Config.Stamina.SprintSpeed)
	end
	local speed = parseInt(arg, 1)
	if not speed or speed > MAX_SPEED then
		return string.format("Pakai: /speed 1-%d atau /speed reset (normal = %d)", MAX_SPEED, Config.Stamina.WalkSpeed)
	end
	player:SetAttribute("DebugSpeed", speed)
	return string.format("Kecepatan jalan & terbang di-set ke %d", speed)
end

-- ===== /tp =====
-- Titik tanah di bawah `position`, nil kalau nggak ada tanah sampai 100 stud ke bawah
local function groundBelow(position: Vector3, character: Model): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true -- kotak zona & trigger (CanCollide mati) ditembus
	local hit = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -110, 0), params)
	return hit and hit.Position
end

-- Berdiri di `ground`, hadap ke `target` (cuma arah datar)
local function standAt(ground: Vector3, target: Vector3): CFrame
	local position = ground + Vector3.new(0, ARRIVAL_HEIGHT, 0)
	local facing = Vector3.new(target.X, position.Y, target.Z)
	if (facing - position).Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, facing)
end

local function summitArrival(character: Model): (CFrame?, string?)
	local trigger = workspace:FindFirstChild("SummitTrigger", true)
	local part = trigger and (if trigger:IsA("BasePart") then trigger else trigger:FindFirstChildWhichIsA("BasePart", true))
	if not part then
		return nil, "SummitTrigger nggak ada di map"
	end
	local ground = groundBelow(part.Position, character) or part.Position
	return standAt(ground, part.Position)
end

-- Di depan gerbang ZoneGates/GateN, di sisi yang tanahnya lebih rendah (zona bawah, gerbangnya masih di depan mata)
local function gateArrival(zone: number, character: Model): (CFrame?, string?)
	local folder = workspace:FindFirstChild("ZoneGates")
	local gate = folder and folder:FindFirstChild("Gate" .. zone)
	if not gate then
		return nil, string.format("ZoneGates/Gate%d nggak ada di map", zone)
	end
	local center: CFrame, size: Vector3
	if gate:IsA("Model") then
		center, size = gate:GetBoundingBox()
	elseif gate:IsA("BasePart") then
		center, size = gate.CFrame, gate.Size
	else
		return nil, string.format("ZoneGates/Gate%d harus Model atau Part", zone)
	end
	-- Sumbu paling tipis (X atau Z lokal) = arah orang lewat gerbang
	local through = if size.X < size.Z then center.RightVector else center.LookVector
	local offset = math.min(size.X, size.Z) / 2 + GATE_TP_OFFSET
	local best: Vector3? = nil
	for _, side in { 1, -1 } do
		local ground = groundBelow(center.Position + through * side * offset, character)
		if ground and (not best or ground.Y < best.Y) then
			best = ground
		end
	end
	if not best then
		return nil, string.format("Nggak nemu tanah di depan Gate%d", zone)
	end
	return standAt(best, center.Position)
end

COMMANDS.tp = function(player, arg)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return "Karakter kamu belum ada"
	end
	local gateZone = tonumber(string.match(arg or "", "^gate(%d+)$"))
	local cframe: CFrame?, problem: string?
	if arg == "puncak" then
		cframe, problem = summitArrival(character)
	elseif arg == "basecamp" then
		cframe = RangerService.arrivalFor(1, character)
		problem = "Pos 1 (Basecamp) nggak ada di map"
	elseif gateZone and Config.Zones[gateZone] and gateZone >= 2 then
		cframe, problem = gateArrival(gateZone, character)
	else
		return string.format("Pakai: /tp puncak | basecamp | gate2-%d", #Config.Zones)
	end
	if not cframe then
		return problem or "Gagal teleport"
	end
	humanoid.Sit = false
	character:PivotTo(cframe)
	SummitService.cancelClimb(player) -- teleport = pendakian batal, sama dengan teleport antar pos
	return "Teleport ke " .. arg
end

-- ===== /event =====
COMMANDS.event = function(player, arg)
	local names = {}
	for typeId in Config.Events.Types do
		table.insert(names, typeId)
	end
	table.sort(names)
	local usage = string.format("Pakai: /event %s|stop", table.concat(names, "|"))
	if arg == "stop" then
		return if EventService.debugStop() then "Event dihentikan" else "Nggak ada event yang lagi jalan"
	end
	if not arg then
		return usage
	end
	local zone = EventService.debugStart(player, arg)
	if not zone then
		return string.format("Event '%s' belum ada. %s", arg, usage)
	end
	return string.format("%s dimulai di Zona %d (peringatan %d detik)", Config.Events.Types[arg].Name, zone, Config.Events.WarningSeconds)
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
	print("[Debug] perintah chat aktif (Studio): /zona /jam /level /senter /koin /puncak /misi /pos /stamina /fly /speed /tp /event")
end

return DebugService
