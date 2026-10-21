-- Senter Kepala: SpotLight di kepala karakter, dinyalain/dimatiin sendiri sama pemain (tombol Senter / F).
-- Dibuat di server biar pemain lain juga lihat cahaya senter kita.
-- Client cuma minta "nyala/mati" lewat RemoteEvent ToggleHeadlamp; server cek punya senter atau nggak,
-- lalu set attribute HeadlampOn. Jangkauan & terang ikut tier di Config.Upgrades.Headlamp.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UpgradeService = require(script.Parent.UpgradeService)

local N = Config.Night
local LEVELS = Config.Upgrades.Headlamp.Levels
local MAX_SPOTLIGHT_RANGE = 60 -- batas bawaan Roblox

local HeadlampService = {}

local lastToggle = {} -- [Player] = os.clock() terakhir nyala/matiin

local function currentLevel(player: Player)
	local tier = player:GetAttribute("Upgrade_Headlamp") or 1
	return LEVELS[math.clamp(tier, 1, #LEVELS)]
end

local function update(player: Player)
	local level = currentLevel(player)
	-- Senter dicopot (misal /senter 1 di Studio): matiin juga
	if level.Value <= 0 and player:GetAttribute("HeadlampOn") then
		player:SetAttribute("HeadlampOn", false)
	end

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local light = head:FindFirstChild("Headlamp") :: SpotLight?
	if level.Value <= 0 then
		if light then
			light:Destroy()
		end
		return
	end

	if not light then
		light = Instance.new("SpotLight")
		light.Name = "Headlamp"
		light.Face = Enum.NormalId.Front
		light.Shadows = true
		light.Parent = head
	end
	light.Range = math.min(level.Value, MAX_SPOTLIGHT_RANGE)
	light.Brightness = level.Brightness
	light.Angle = N.LightAngle
	light.Color = N.LightColor
	light.Enabled = player:GetAttribute("HeadlampOn") == true
end

local function setup(player: Player)
	player:SetAttribute("HeadlampOn", false)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		update(player)
	end)
	player:GetAttributeChangedSignal("HeadlampOn"):Connect(function()
		update(player)
	end)
	player:GetAttributeChangedSignal("Upgrade_Headlamp"):Connect(function()
		update(player)
	end)
	if player.Character then
		update(player)
	end
end

function HeadlampService.start()
	local toggle = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ToggleHeadlamp") :: RemoteEvent
	toggle.OnServerEvent:Connect(function(player: Player, on: any)
		if type(on) ~= "boolean" then
			return
		end
		local now = os.clock()
		if lastToggle[player] and now - lastToggle[player] < N.ToggleCooldown then
			return
		end
		lastToggle[player] = now
		-- Belum punya senter = nggak bisa nyala
		if on and UpgradeService.getValue(player, "Headlamp") <= 0 then
			on = false
		end
		player:SetAttribute("HeadlampOn", on)
	end)

	Players.PlayerAdded:Connect(setup)
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
	end)
end

return HeadlampService
