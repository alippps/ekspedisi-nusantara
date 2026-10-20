-- Senter Kepala: SpotLight di kepala karakter, nyala sendiri pas mulai gelap.
-- Dibuat di server biar pemain lain juga lihat cahaya senter kita.
-- Jangkauannya dari attribute HeadlampRange (diisi UpgradeService).
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local TimeOfDay = require(ReplicatedStorage.Shared.TimeOfDay)

local N = Config.Night
local MAX_SPOTLIGHT_RANGE = 60 -- batas bawaan Roblox
local UPDATE_INTERVAL = 0.5

local HeadlampService = {}

local function update(player: Player, isDark: boolean)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local range = player:GetAttribute("HeadlampRange") or 0
	local light = head:FindFirstChild("Headlamp") :: SpotLight?
	if range <= 0 then
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
	light.Range = math.min(range, MAX_SPOTLIGHT_RANGE)
	light.Angle = N.LightAngle
	light.Brightness = N.LightBrightness
	light.Color = N.LightColor
	light.Enabled = isDark
end

function HeadlampService.start()
	-- Cek berkala: otomatis beres buat respawn, upgrade baru, dan pergantian siang/malam.
	task.spawn(function()
		while true do
			local isDark = TimeOfDay.nightness(Lighting.ClockTime) > 0
			for _, player in Players:GetPlayers() do
				update(player, isDark)
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return HeadlampService
