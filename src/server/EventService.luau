-- Event bencana (server). Semua keputusan ada di sini: kapan, zona mana, titik sambaran, siapa kena, siapa bertahan.
-- Alur satu event: "warning" (peringatan) -> "active" (bencana) -> "loot" (item langka) -> selesai.
-- * Status dicerminkan ke ReplicatedStorage.EventState (attribute Type, Name, Zone, Loot, PhaseEndsAt = server time, Phase)
--   biar EventController di client bisa nampilin hitung mundur, termasuk buat pemain yang join di tengah event.
-- * Daftar safe zone dicerminkan ke ReplicatedStorage.SafeZoneList (Zone, CFrame, Size) buat suar & panah di client
--   (Part safe zone-nya sendiri bisa belum ke-stream di client).
-- * Efek visual ke semua client lewat remote EventFx: ("Strike", typeId, posisiTanah, radius, impactAt server time).
-- * Kena = pingsan: Notify "Fainted" ke pemain itu, hilang 1 item acak dari tas, muncul di pos terakhir yang ditemukan.
-- * Bertahan (ada di zona pas bencana mulai & selesai, nggak pingsan) = Koin bonus + Notify "EventSurvived".
-- Pemain baru bebas event selama Config.Events.NewPlayerGrace detik sejak join (tiap sesi).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ZoneMath = require(ReplicatedStorage.Shared.ZoneMath)
local DataService = require(script.Parent.DataService)
local BagService = require(script.Parent.BagService)
local SpawnService = require(script.Parent.SpawnService)
local RangerService = require(script.Parent.RangerService)
local SummitService = require(script.Parent.SummitService)

local E = Config.Events
local PHASE_CHECK = 0.25 -- detik antar cek event masih jalan (buat /event stop)
local TARGET_TRIES = 6 -- percobaan cari titik sambaran yang bukan safe zone & ada tanahnya

local EventService = {}

type Run = {
	typeId: string,
	def: any,
	zone: number,
	fainted: { [Player]: boolean },
	presentAtStart: { [Player]: boolean },
	activeUntil: number, -- os.clock() bencana selesai
}

local notify: RemoteEvent
local fx: RemoteEvent
local state: Configuration
local safeList: Folder
local listedSafe: { [Instance]: boolean } = {}
local current: Run? = nil
local nextEventAt = 0
local joinedAt: { [Player]: number } = {}
local graceSkipped: { [Player]: boolean } = {} -- pemicu /event: masa aman dilewati

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not hrp or not hrp:IsA("BasePart") then
		return nil
	end
	return hrp
end

local function scheduleNext()
	nextEventAt = os.clock() + math.random(E.IntervalMin, E.IntervalMax)
end

-- Pemain boleh kena event: data udah dimuat & masa amannya udah lewat
local function eligible(player: Player): boolean
	if not DataService.get(player) then
		return false
	end
	if graceSkipped[player] then
		return true
	end
	local joined = joinedAt[player]
	return joined ~= nil and os.clock() - joined >= E.NewPlayerGrace
end

-- [Player] = HumanoidRootPart, buat pemain eligible yang masih hidup dan lagi di zona ini
local function playersInZone(zone: number): { [Player]: BasePart }
	local result = {}
	for _, player in Players:GetPlayers() do
		local hrp = rootOf(player)
		if hrp and eligible(player) and ZoneMath.zoneAt(hrp.Position) == zone then
			result[player] = hrp
		end
	end
	return result
end

-- ===== Status buat client =====
local function publish(run: Run?, phase: string, seconds: number)
	if phase ~= "loot" then
		state:SetAttribute("Loot", nil) -- jumlah item langka cuma berlaku di fase loot (diisi runEvent)
	end
	state:SetAttribute("Type", if run then run.typeId else nil)
	state:SetAttribute("Name", if run then run.def.Name else nil)
	state:SetAttribute("Zone", if run then run.zone else nil)
	state:SetAttribute("PhaseEndsAt", workspace:GetServerTimeNow() + seconds)
	state:SetAttribute("Phase", if phase ~= "" then phase else nil) -- paling akhir: client bereaksi ke Phase
end

local function stop()
	current = nil
	publish(nil, "", 0)
	scheduleNext()
end

-- Tunggu `seconds`. Return false kalau event ini keburu dihentikan (/event stop atau diganti event lain).
local function waitPhase(run: Run, seconds: number): boolean
	local untilAt = os.clock() + seconds
	while os.clock() < untilAt do
		task.wait(PHASE_CHECK)
		if current ~= run then
			return false
		end
	end
	return true
end

-- ===== Kena bencana =====
local function faint(run: Run, player: Player)
	run.fainted[player] = true
	local character = player.Character
	local hrp = rootOf(player)
	if not character or not hrp then
		return
	end
	local lost = BagService.removeRandom(player)
	local postNumber = RangerService.lastFoundPost(player)
	notify:FireClient(player, "Fainted", {
		event = run.def.Name,
		item = lost,
		post = postNumber,
		seconds = E.FaintSeconds,
	})
	hrp.Anchored = true -- diam di tempat selama layar gelap
	print(string.format("[Event] %s pingsan (%s), hilang: %s", player.Name, run.def.Name, lost or "-"))

	task.delay(E.FaintSeconds, function()
		if player.Character == character and character.Parent then
			local cframe = RangerService.arrivalFor(postNumber, character)
			if cframe then
				character:PivotTo(cframe)
			end
			SummitService.cancelClimb(player)
		end
		if hrp.Parent then
			hrp.Anchored = false
		end
	end)
end

-- Sambaran mendarat: pemain eligible di zona event, dalam radius, di luar safe zone = pingsan
local function impact(run: Run, position: Vector3)
	if current ~= run then
		return
	end
	for player, hrp in playersInZone(run.zone) do
		if not run.fainted[player] then
			local offset = hrp.Position - position
			local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if flat <= run.def.Radius and math.abs(offset.Y) <= E.HitHeight and not ZoneMath.inSafeZone(hrp.Position) then
				faint(run, player)
			end
		end
	end
end

-- ===== Cari titik sasaran =====
local function randomFlat(spread: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * spread
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Titik tanah di bawah `position` (karakter & item diabaikan), nil kalau nggak ada
local function groundBelow(position: Vector3): Vector3?
	local ignore = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local items = workspace:FindFirstChild("SpawnedItems")
	if items then
		table.insert(ignore, items)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- kotak zona & safe zone (CanCollide mati) ditembus
	local hit = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return hit and hit.Position
end

-- Sebagian ngincar dekat pemain yang lagi terbuka (bukan di safe zone), sisanya titik spawn acak di zona itu
local function strikeTarget(run: Run): Vector3?
	local def = run.def
	local exposed = {}
	for player, hrp in playersInZone(run.zone) do
		if not run.fainted[player] and not ZoneMath.inSafeZone(hrp.Position) then
			table.insert(exposed, hrp)
		end
	end
	local points = SpawnService.getPoints(run.zone)
	for _ = 1, TARGET_TRIES do
		local base: Vector3
		if #exposed > 0 and math.random() < def.AimAtPlayers then
			base = exposed[math.random(1, #exposed)].Position
		elseif #points > 0 then
			base = points[math.random(1, #points)].Position
		else
			return nil
		end
		local ground = groundBelow(base + randomFlat(def.AimSpread))
		if ground and not ZoneMath.inSafeZone(ground + Vector3.new(0, 3, 0)) then
			return ground
		end
	end
	return nil
end

-- ===== Pola serangan (Config.Events.Types[*].Pattern) =====
local PATTERNS: { [string]: (Run) -> () } = {}

-- Sambaran bergelombang: lingkaran dulu (Telegraph detik), baru kena
PATTERNS.strike = function(run: Run)
	local def = run.def
	while current == run and os.clock() < run.activeUntil do
		for _ = 1, def.StrikesPerWave do
			local target = strikeTarget(run)
			if target then
				fx:FireAllClients("Strike", run.typeId, target, def.Radius, workspace:GetServerTimeNow() + def.Telegraph)
				task.delay(def.Telegraph, impact, run, target)
			end
		end
		task.wait(def.StrikeEvery)
	end
end

-- ===== Satu event =====
local function runEvent(run: Run)
	local def = run.def
	print(string.format("[Event] %s di Zona %d: peringatan %d detik", def.Name, run.zone, E.WarningSeconds))
	publish(run, "warning", E.WarningSeconds)
	if not waitPhase(run, E.WarningSeconds) then
		return
	end

	for player in playersInZone(run.zone) do
		run.presentAtStart[player] = true
	end
	run.activeUntil = os.clock() + E.ActiveSeconds
	publish(run, "active", E.ActiveSeconds)
	task.spawn(PATTERNS[def.Pattern], run)
	if not waitPhase(run, E.ActiveSeconds) then
		return
	end

	-- Reda: bonus buat yang bertahan (ada di zona dari awal sampai akhir bencana, nggak pingsan)
	for player in playersInZone(run.zone) do
		if run.presentAtStart[player] and not run.fainted[player] and BagService.addCoins(player, def.SurviveCoins) then
			notify:FireClient(player, "EventSurvived", { event = def.Name, coins = def.SurviveCoins })
		end
	end
	local loot = SpawnService.spawnBonus(run.zone, E.LootCount, E.LootMinRarity, E.LootSeconds)
	state:SetAttribute("Loot", loot)
	publish(run, "loot", E.LootSeconds)
	if not waitPhase(run, E.LootSeconds) then
		return
	end
	stop()
end

local function start(typeId: string, zone: number)
	local run: Run = {
		typeId = typeId,
		def = E.Types[typeId],
		zone = zone,
		fainted = {},
		presentAtStart = {},
		activeUntil = 0,
	}
	current = run
	task.spawn(runEvent, run)
end

-- Event acak buat jadwal otomatis: zona yang lagi ada pemain eligible-nya, lalu event yang boleh di zona itu
local function pickRandom(): (string?, number?)
	local choices = {}
	for zone in Config.Zones do
		if next(playersInZone(zone)) then
			local types = {}
			for typeId, def in E.Types do
				if table.find(def.Zones, zone) then
					table.insert(types, typeId)
				end
			end
			if #types > 0 then
				table.insert(choices, { zone = zone, types = types })
			end
		end
	end
	if #choices == 0 then
		return nil, nil
	end
	local choice = choices[math.random(1, #choices)]
	return choice.types[math.random(1, #choice.types)], choice.zone
end

-- ===== Safe zone buat client =====
local function listSafeZone(instance: Instance)
	if listedSafe[instance] then
		return
	end
	local zone = instance:GetAttribute("Zone")
	if not instance:IsA("BasePart") or type(zone) ~= "number" or not Config.Zones[zone] then
		warn(string.format(
			"[EventService] %s: safe zone harus Part ber-Tag %s dengan attribute Zone 1-%d",
			instance:GetFullName(),
			E.SafeZoneTag,
			#Config.Zones
		))
		return
	end
	listedSafe[instance] = true
	local entry = Instance.new("Configuration")
	entry.Name = "SafeZone"
	entry:SetAttribute("Zone", zone)
	entry:SetAttribute("CFrame", instance.CFrame)
	entry:SetAttribute("Size", instance.Size)
	entry.Parent = safeList
end

-- ===== API debug =====
-- Khusus DebugService: mulai event sekarang (event yang lagi jalan dihentikan). Pemicunya dilewati masa amannya.
-- Zona = zona pemain sekarang kalau event itu boleh di sana, kalau nggak zona pertama event itu.
-- Return nomor zona, atau nil kalau typeId nggak ada.
function EventService.debugStart(player: Player, typeId: string): number?
	local def = E.Types[typeId]
	if not def then
		return nil
	end
	if current then
		stop()
	end
	graceSkipped[player] = true
	local hrp = rootOf(player)
	local here = hrp and ZoneMath.zoneAt(hrp.Position)
	local zone = if here and table.find(def.Zones, here) then here else def.Zones[1]
	start(typeId, zone)
	return zone
end

-- Khusus DebugService: hentikan event yang lagi jalan. Return false kalau nggak ada.
function EventService.debugStop(): boolean
	if not current then
		return false
	end
	stop()
	return true
end

function EventService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	notify = remotes:WaitForChild("Notify")
	fx = remotes:WaitForChild("EventFx")

	state = Instance.new("Configuration")
	state.Name = "EventState"
	state.Parent = ReplicatedStorage
	safeList = Instance.new("Folder")
	safeList.Name = "SafeZoneList"
	safeList.Parent = ReplicatedStorage

	for _, instance in CollectionService:GetTagged(E.SafeZoneTag) do
		listSafeZone(instance)
	end
	CollectionService:GetInstanceAddedSignal(E.SafeZoneTag):Connect(listSafeZone)
	task.delay(10, function()
		if not next(listedSafe) then
			warn("[EventService] Nggak ada Part ber-Tag " .. E.SafeZoneTag .. ": semua pemain di zona event bisa kena")
		end
	end)

	for _, player in Players:GetPlayers() do
		joinedAt[player] = os.clock()
	end
	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
		graceSkipped[player] = nil
	end)

	-- Jadwal otomatis. Nggak ada pemain eligible = siklus ini dilewati, dijadwal ulang.
	scheduleNext()
	task.spawn(function()
		while true do
			task.wait(1)
			if not current and os.clock() >= nextEventAt then
				local typeId, zone = pickRandom()
				if typeId and zone then
					start(typeId, zone)
				else
					scheduleNext()
				end
			end
		end
	end)
end

return EventService
