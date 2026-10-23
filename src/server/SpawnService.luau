-- Memunculkan item di titik spawn. Pengambilan divalidasi di server.
-- Setup di Studio: Workspace > SpawnPoints (Folder) > Zone1 (Folder) > Part-part kecil di tanah.
-- Selain item biasa (muncul lagi setelah diambil), ada item bonus dari event bencana (spawnBonus) yang hilang sendiri.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DayNightService = require(script.Parent.DayNightService)
local BagService = require(script.Parent.BagService)

local S = Config.Spawn
local SpawnService = {}

local notify: RemoteEvent
local itemsFolder: Folder
local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local rarityRank = {}
for i, name in rarityOrder do
	rarityRank[name] = i
end
local pointsByZone: { [number]: { BasePart } } = {}

-- Item acak di zona ini (sesuai siang/malam), rarity minimal minRarity kalau diisi.
local function pickItem(zone: number, minRarity: string?)
	local isDay = DayNightService.isDay()
	local minRank = if minRarity then rarityRank[minRarity] or 1 else 1
	local byRarity = {}
	for _, item in Config.Items do
		local timeOk = item.Time == "Any" or (item.Time == "Day" and isDay) or (item.Time == "Night" and not isDay)
		if item.Zone == zone and timeOk and rarityRank[item.Rarity] >= minRank then
			byRarity[item.Rarity] = byRarity[item.Rarity] or {}
			table.insert(byRarity[item.Rarity], item)
		end
	end

	-- Pilih rarity dulu berdasarkan bobot, baru pilih item acak di rarity itu.
	local total = 0
	for _, name in rarityOrder do
		if byRarity[name] then
			total += Config.Rarity[name].Weight
		end
	end
	if total == 0 then
		return nil
	end
	local roll = math.random() * total
	for _, name in rarityOrder do
		local list = byRarity[name]
		if list then
			roll -= Config.Rarity[name].Weight
			if roll <= 0 then
				return list[math.random(1, #list)]
			end
		end
	end
	return nil
end

-- Bikin item yang bisa diambil di `position`. onTaken() dipanggil sekali pas berhasil diambil.
local function createItem(item, position: Vector3, onTaken: (() -> ())?): BasePart
	local part = Instance.new("Part")
	part.Name = item.Id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Material = Enum.Material.Neon
	part.Color = Config.Rarity[item.Rarity].Color
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("ItemId", item.Id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ambil"
	prompt.ObjectText = item.Name .. " · " .. item.Rarity
	prompt.HoldDuration = S.HoldDuration
	prompt.MaxActivationDistance = S.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		if part:GetAttribute("Taken") or not part.Parent then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - part.Position).Magnitude > S.PromptDistance + 4 then
			return
		end

		local ok, reason, firstXP = BagService.tryAdd(player, item.Id)
		if not ok then
			if reason == "full" then
				notify:FireClient(player, "BagFull")
			elseif reason == "loading" then
				notify:FireClient(player, "DataLoading")
			elseif reason == "locked" then
				notify:FireClient(player, "ZoneLocked", item.Zone)
			elseif reason == "dark" then
				notify:FireClient(player, "NeedHeadlamp", item.Name)
			end
			return
		end

		part:SetAttribute("Taken", true)
		part:Destroy()
		-- firstXP ada = penemuan pertama (udah tercatat di Jurnal + XP-nya udah masuk)
		notify:FireClient(player, "Collected", item.Id, firstXP)
		if onTaken then
			onTaken()
		end
	end)

	part.Parent = itemsFolder
	return part
end

local spawnAt

local function scheduleRespawn(point: BasePart, zone: number)
	task.delay(math.random(S.RespawnMin, S.RespawnMax), spawnAt, point, zone)
end

spawnAt = function(point: BasePart, zone: number)
	local item = pickItem(zone)
	if not item then
		scheduleRespawn(point, zone)
		return
	end
	createItem(item, point.Position + Vector3.new(0, 1.5, 0), function()
		scheduleRespawn(point, zone)
	end)
end

-- Item langka bonus (event bencana): `count` item rarity >= minRarity di titik spawn acak zona ini,
-- hilang sendiri setelah `seconds` kalau belum diambil. Return jumlah yang berhasil dimunculkan.
function SpawnService.spawnBonus(zone: number, count: number, minRarity: string, seconds: number): number
	local points = table.clone(pointsByZone[zone] or {})
	local spawned = 0
	while spawned < count and #points > 0 do
		local point = table.remove(points, math.random(1, #points))
		local item = pickItem(zone, minRarity)
		if not item then
			break -- nggak ada item langka yang cocok jam segini
		end
		-- Agak di atas & samping titik biasa biar nggak numpuk sama item yang udah ada
		local offset = Vector3.new(math.random(-20, 20) / 10, 1.5, math.random(-20, 20) / 10)
		local part = createItem(item, point.Position + offset)
		part:SetAttribute("Bonus", true)
		local light = Instance.new("PointLight")
		light.Color = Config.Rarity[item.Rarity].Color
		light.Range = 12
		light.Brightness = 2
		light.Parent = part
		task.delay(seconds, function()
			if part.Parent then
				part:Destroy()
			end
		end)
		spawned += 1
	end
	return spawned
end

-- Titik spawn zona ini (dipakai EventService buat sasaran acak)
function SpawnService.getPoints(zone: number): { BasePart }
	return pointsByZone[zone] or {}
end

function SpawnService.start()
	notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")
	itemsFolder = Instance.new("Folder")
	itemsFolder.Name = "SpawnedItems"
	itemsFolder.Parent = workspace

	local root = workspace:WaitForChild("SpawnPoints", 10)
	if not root then
		warn("[SpawnService] Folder Workspace.SpawnPoints tidak ditemukan")
		return
	end

	for _, zoneFolder in root:GetChildren() do
		local zone = tonumber(string.match(zoneFolder.Name, "%d+"))
		if zone then
			pointsByZone[zone] = pointsByZone[zone] or {}
			for _, point in zoneFolder:GetChildren() do
				if point:IsA("BasePart") then
					point.Anchored = true
					point.CanCollide = false
					point.Transparency = 1
					table.insert(pointsByZone[zone], point)
					spawnAt(point, zone)
				end
			end
		end
	end
end

return SpawnService
