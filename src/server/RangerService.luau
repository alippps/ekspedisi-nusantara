-- Pos Ranger: setor isi tas jadi Koin + XP, toko upgrade gear, dan teleport antar pos.
-- Setup di Studio (tiap pos):
--   Model dengan Tag "PosRanger" (Config.Posts.Tag) + attribute PosNumber (1, 2, ...) dan Zone (nomor zona),
--   berisi Part "PromptAnchor" = tempat tombol Setor & Menu Pos. Opsional:
--     Part "TeleportPoint" = titik muncul pas teleport ke pos ini (kalau nggak ada: di depan PromptAnchor)
--     attribute PosName (string) = nama pos di menu (default: Pos 1 "Basecamp", lainnya nama zona)
--   Model/Part lama bernama "PosRanger" tanpa attribute tetap jalan sebagai Pos 1 di Zona 1.
-- Pos 1 = Basecamp, selalu terbuka. Pos lain baru "ditemukan" pas pemain pertama kali sampai di dekatnya
-- (Config.Posts.DiscoverRadius) dan zonanya udah terbuka buat dia. Tersimpan di data.FoundPosts.
-- Setor, menu, dan teleport cuma jalan di pos yang udah ditemukan; semuanya dicek di sini.
-- Daftar pos dicerminkan ke ReplicatedStorage.PosList (satu Configuration per pos: Zone, Label, Position)
-- biar client tetap tahu semua pos walau Model-nya belum ke-stream.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local BagService = require(script.Parent.BagService)
local UpgradeService = require(script.Parent.UpgradeService)

local P = Config.Posts
local BASECAMP = 1
local DISCOVER_INTERVAL = 0.5 -- detik antar cek pemain yang baru sampai di pos
local ARRIVAL_HEIGHT = 3.5 -- tinggi HumanoidRootPart dari tanah pas muncul habis teleport

local RangerService = {}

type Post = {
	number: number,
	zone: number,
	label: string,
	anchor: BasePart,
	arrival: BasePart?, -- Part TeleportPoint
	source: Instance, -- Model/Part yang di-tag
}

local posts: { [number]: Post } = {}
local registered: { [Instance]: boolean } = {}
local lastTeleport = {} -- [Player] = os.clock() teleport terakhir
local teleportedCallbacks: { (Player, number) -> () } = {}
local notify: RemoteEvent
local listFolder: Folder

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function distanceToPost(player: Player, post: Post): number
	local hrp = rootOf(player)
	return if hrp then (hrp.Position - post.anchor.Position).Magnitude else math.huge
end

local function isFound(data, number: number): boolean
	return number == BASECAMP or data.FoundPosts[tostring(number)] ~= nil
end

local function zoneOpen(player: Player, data, zone: number): boolean
	local tierOf = function(upgradeId: string): number
		return UpgradeService.getTier(player, upgradeId)
	end
	return Progression.isZoneUnlocked(zone, Progression.levelFromXP(data.XP), tierOf)
end

-- Attribute "FoundPosts" = "1,2,3" (nomor pos yang udah ditemukan, urut)
local function syncFound(player: Player, data)
	local numbers = { BASECAMP }
	for key in data.FoundPosts do
		local number = tonumber(key)
		if number and number ~= BASECAMP then
			table.insert(numbers, number)
		end
	end
	table.sort(numbers)
	player:SetAttribute("FoundPosts", table.concat(numbers, ","))
end

-- Catat pos sebagai ditemukan kalau pemain lagi di dekatnya & zonanya udah terbuka.
-- Return true kalau pos ini (udah) ditemukan.
local function tryDiscover(player: Player, data, post: Post): boolean
	if isFound(data, post.number) then
		return true
	end
	if distanceToPost(player, post) > P.DiscoverRadius or not zoneOpen(player, data, post.zone) then
		return false
	end
	data.FoundPosts[tostring(post.number)] = os.time()
	syncFound(player, data)
	notify:FireClient(player, "PostFound", post.number)
	return true
end

-- Pos yang udah ditemukan & paling dekat dengan pemain (dalam maxDistance), atau nil
local function nearbyFoundPost(player: Player, data, maxDistance: number): Post?
	local best: Post?, bestDistance = nil, maxDistance
	for number, post in posts do
		local distance = distanceToPost(player, post)
		if distance <= bestDistance and isFound(data, number) then
			best, bestDistance = post, distance
		end
	end
	return best
end

-- ===== Teleport =====
-- Titik muncul: TeleportPoint kalau ada, kalau nggak di depan PromptAnchor. Ditempelkan ke tanah, hadap ke pos.
local function arrivalCFrame(post: Post, character: Model): CFrame
	local anchor = post.anchor
	local position: Vector3
	if post.arrival then
		position = post.arrival.Position
	else
		local look = anchor.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, -1)
		end
		position = anchor.Position + flat.Unit * P.TeleportOffset
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	if hit then
		position = hit.Position
	end
	position += Vector3.new(0, ARRIVAL_HEIGHT, 0)

	local facing = Vector3.new(anchor.Position.X, position.Y, anchor.Position.Z)
	if (facing - position).Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, facing)
end

-- Alasan gagal: "invalid" | "loading" | "locked" | "far" | "here" | "cooldown" | "coins"
local function teleport(player: Player, target: any): (boolean, string?)
	local post = if type(target) == "number" then posts[target] else nil
	if not post then
		return false, "invalid"
	end
	local data = DataService.get(player)
	if not data then
		return false, "loading"
	end
	if not isFound(data, post.number) or not zoneOpen(player, data, post.zone) then
		return false, "locked"
	end
	local from = nearbyFoundPost(player, data, Config.Shop.MaxDistance)
	if not from then
		return false, "far"
	end
	if from == post then
		return false, "here"
	end
	local now = os.clock()
	if lastTeleport[player] and now - lastTeleport[player] < P.TeleportCooldown then
		return false, "cooldown"
	end
	if data.Coins < P.TeleportCost then
		return false, "coins"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, "invalid"
	end

	lastTeleport[player] = now
	if P.TeleportCost > 0 then
		data.Coins -= P.TeleportCost
		BagService.sync(player)
	end
	humanoid.Sit = false
	character:PivotTo(arrivalCFrame(post, character))
	for _, callback in teleportedCallbacks do
		task.spawn(callback, player, post.number)
	end
	return true, nil
end

-- ===== Pasang pos dari map =====
local function resolveAnchor(source: Instance): BasePart?
	if source:IsA("BasePart") then
		return source
	end
	local promptAnchor = source:FindFirstChild("PromptAnchor", true)
	if promptAnchor and promptAnchor:IsA("BasePart") then
		return promptAnchor
	end
	return source:FindFirstChildWhichIsA("BasePart", true)
end

local function onDeposit(player: Player, post: Post)
	local data = DataService.get(player)
	if not data then
		notify:FireClient(player, "DataLoading")
		return
	end
	if not tryDiscover(player, data, post) then
		notify:FireClient(player, "ZoneLocked", post.zone)
		return
	end
	local summary, reason = BagService.deposit(player)
	if reason == "loading" then
		notify:FireClient(player, "DataLoading")
	elseif summary.count == 0 then
		notify:FireClient(player, "BagEmpty")
	else
		notify:FireClient(player, "Deposited", summary)
	end
end

local function onMenu(player: Player, post: Post)
	local data = DataService.get(player)
	if not data then
		notify:FireClient(player, "DataLoading")
		return
	end
	if not tryDiscover(player, data, post) then
		notify:FireClient(player, "ZoneLocked", post.zone)
		return
	end
	notify:FireClient(player, "OpenShop", post.number)
end

local function registerPost(source: Instance)
	if registered[source] then
		return
	end
	local number = source:GetAttribute("PosNumber")
	if number == nil and source.Name == "PosRanger" then
		number = BASECAMP -- Model lama tanpa attribute
	end
	if type(number) ~= "number" or number < 1 or number ~= math.floor(number) then
		warn(string.format("[RangerService] %s: attribute PosNumber harus angka bulat 1 ke atas", source:GetFullName()))
		return
	end
	local zone = source:GetAttribute("Zone")
	if zone == nil and number == BASECAMP then
		zone = 1
	end
	if type(zone) ~= "number" or not Config.Zones[zone] then
		warn(string.format("[RangerService] %s: attribute Zone harus nomor zona 1-%d", source:GetFullName(), #Config.Zones))
		return
	end
	local existing = posts[number]
	if existing then
		warn(string.format(
			"[RangerService] PosNumber %d dipakai dua kali (%s dan %s), yang kedua diabaikan",
			number,
			existing.source:GetFullName(),
			source:GetFullName()
		))
		return
	end
	local anchor = resolveAnchor(source)
	if not anchor then
		warn(string.format("[RangerService] %s harus berupa Part atau Model berisi Part (idealnya PromptAnchor)", source:GetFullName()))
		return
	end
	registered[source] = true

	local customName = source:GetAttribute("PosName")
	local arrival = source:FindFirstChild("TeleportPoint", true)
	local post: Post = {
		number = number,
		zone = zone,
		label = if type(customName) == "string" and customName ~= ""
			then customName
			elseif number == BASECAMP then "Basecamp"
			else Progression.zoneName(zone),
		anchor = anchor,
		arrival = if arrival and arrival:IsA("BasePart") then arrival else nil,
		source = source,
	}
	posts[number] = post
	local objectText = string.format("Pos %d · %s", number, post.label)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ActionText = "Setor"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player: Player)
		onDeposit(player, post)
	end)

	-- Tombol kedua buat buka menu pos (upgrade + teleport). Digeser ke bawah supaya tidak numpuk dengan "Setor".
	local menuPrompt = Instance.new("ProximityPrompt")
	menuPrompt.Name = "UpgradePrompt"
	menuPrompt.ActionText = "Menu Pos"
	menuPrompt.ObjectText = objectText
	menuPrompt.HoldDuration = 0
	menuPrompt.KeyboardKeyCode = Enum.KeyCode.F
	menuPrompt.GamepadKeyCode = Enum.KeyCode.ButtonR1
	menuPrompt.MaxActivationDistance = Config.Shop.PromptDistance
	menuPrompt.UIOffset = Vector2.new(0, 72)
	menuPrompt.Parent = anchor
	menuPrompt.Triggered:Connect(function(player: Player)
		onMenu(player, post)
	end)

	local entry = Instance.new("Configuration")
	entry.Name = tostring(number)
	entry:SetAttribute("Zone", zone)
	entry:SetAttribute("Label", post.label)
	entry:SetAttribute("Position", anchor.Position)
	entry.Parent = listFolder
end

-- ===== API publik =====
-- Part Pos 1 (pusat Basecamp), nil kalau belum ketemu di map.
function RangerService.getPost(): BasePart?
	local post = posts[BASECAMP]
	return post and post.anchor
end

-- callback(player, nomorPosTujuan) tiap pemain berhasil teleport (SummitService: pendakian batal).
function RangerService.onTeleported(callback: (Player, number) -> ())
	table.insert(teleportedCallbacks, callback)
end

-- Khusus DebugService: tandai pos ditemukan tanpa harus jalan ke sana. Return false kalau pos/data nggak ada.
function RangerService.debugFind(player: Player, number: number): boolean
	local data = DataService.get(player)
	if not data or not posts[number] then
		return false
	end
	if not isFound(data, number) then
		data.FoundPosts[tostring(number)] = os.time()
		syncFound(player, data)
		notify:FireClient(player, "PostFound", number)
	end
	return true
end

-- Titik muncul di Pos N (sama dengan teleport biasa), nil kalau pos nggak ada. Dipakai /tp & pingsan event.
function RangerService.arrivalFor(number: number, character: Model): CFrame?
	local post = posts[number]
	return if post then arrivalCFrame(post, character) else nil
end

-- Nomor pos yang paling akhir ditemukan pemain (dan ada di map). Basecamp kalau belum nemu pos lain.
function RangerService.lastFoundPost(player: Player): number
	local data = DataService.get(player)
	local best, bestTime = BASECAMP, -math.huge
	if data then
		for key, foundAt in data.FoundPosts do
			local number = tonumber(key)
			if number and posts[number] and type(foundAt) == "number" and foundAt > bestTime then
				best, bestTime = number, foundAt
			end
		end
	end
	return best
end

-- Khusus DebugService: lupakan semua pos (kecuali Basecamp).
function RangerService.debugReset(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	table.clear(data.FoundPosts)
	syncFound(player, data)
	return true
end

function RangerService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	notify = remotes:WaitForChild("Notify")
	local buyUpgrade = remotes:WaitForChild("BuyUpgrade") :: RemoteFunction
	local teleportRemote = remotes:WaitForChild("TeleportPost") :: RemoteFunction

	-- Dipasang duluan supaya InvokeServer dari client tidak nunggu selamanya walaupun pos belum ada di map.
	buyUpgrade.OnServerInvoke = function(player: Player, upgradeId: any)
		local data = DataService.get(player)
		if data and not nearbyFoundPost(player, data, Config.Shop.MaxDistance) then
			return false, "far"
		end
		local ok, reason = UpgradeService.buy(player, upgradeId)
		return ok, reason
	end
	teleportRemote.OnServerInvoke = teleport

	listFolder = Instance.new("Folder")
	listFolder.Name = "PosList"
	listFolder.Parent = ReplicatedStorage

	DataService.onLoaded(syncFound)
	Players.PlayerRemoving:Connect(function(player)
		lastTeleport[player] = nil
	end)

	for _, source in CollectionService:GetTagged(P.Tag) do
		registerPost(source)
	end
	CollectionService:GetInstanceAddedSignal(P.Tag):Connect(registerPost)

	task.spawn(function()
		-- Model lama "PosRanger" tanpa tag = Pos 1
		local legacy = workspace:WaitForChild("PosRanger", 10)
		if legacy then
			registerPost(legacy)
		end
		if not posts[BASECAMP] then
			warn("[RangerService] Pos 1 (Basecamp) tidak ditemukan: kasih Tag PosRanger + PosNumber 1 ke Model Pos Ranger")
		end
	end)

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data then
					for _, post in posts do
						tryDiscover(player, data, post)
					end
				end
			end
			task.wait(DISCOVER_INTERVAL)
		end
	end)
end

return RangerService
