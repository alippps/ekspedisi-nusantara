-- Memunculkan item di titik spawn. Pengambilan divalidasi di server.
-- Setup di Studio: Workspace > SpawnPoints (Folder) > Zone1 (Folder) > Part-part kecil di tanah.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DayNightService = require(script.Parent.DayNightService)
local BagService = require(script.Parent.BagService)

local S = Config.Spawn
local SpawnService = {}

local notify: RemoteEvent
local itemsFolder: Folder
local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local function pickItem(zone: number)
	local isDay = DayNightService.isDay()
	local byRarity = {}
	for _, item in Config.Items do
		local timeOk = item.Time == "Any" or (item.Time == "Day" and isDay) or (item.Time == "Night" and not isDay)
		if item.Zone == zone and timeOk then
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

	local part = Instance.new("Part")
	part.Name = item.Id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Material = Enum.Material.Neon
	part.Color = Config.Rarity[item.Rarity].Color
	part.Anchored = true
	part.CanCollide = false
	part.Position = point.Position + Vector3.new(0, 1.5, 0)
	part:SetAttribute("ItemId", item.Id)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ambil"
	prompt.ObjectText = item.Name .. " · " .. item.Rarity
	prompt.HoldDuration = S.HoldDuration
	prompt.MaxActivationDistance = S.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		if part:GetAttribute("Taken") then
			return
		end
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or (hrp.Position - part.Position).Magnitude > S.PromptDistance + 4 then
			return
		end

		local isNew = not BagService.isDiscovered(player, item.Id)
		local ok, reason = BagService.tryAdd(player, item.Id)
		if not ok then
			if reason == "full" then
				notify:FireClient(player, "BagFull")
			elseif reason == "loading" then
				notify:FireClient(player, "DataLoading")
			elseif reason == "locked" then
				notify:FireClient(player, "ZoneLocked", item.Zone)
			end
			return
		end

		part:SetAttribute("Taken", true)
		part:Destroy()
		notify:FireClient(player, "Collected", item.Id, isNew)
		scheduleRespawn(point, zone)
	end)

	part.Parent = itemsFolder
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
			for _, point in zoneFolder:GetChildren() do
				if point:IsA("BasePart") then
					point.Anchored = true
					point.CanCollide = false
					point.Transparency = 1
					spawnAt(point, zone)
				end
			end
		end
	end
end

return SpawnService
