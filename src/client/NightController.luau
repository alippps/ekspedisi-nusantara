--!strict
-- Malam hari: dunia jadi gelap, dan item cuma kelihatan dalam jarak pandang.
-- Jarak pandang = jangkauan Senter Kepala (attribute HeadlampRange), atau Config.Night.EyeRange kalau belum punya.
-- Semua ini cuma tampilan di client ini; aturan "item malam butuh senter" tetap dicek server.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeOfDay = require(Shared:WaitForChild("TimeOfDay"))

local N = Config.Night
local player = Players.LocalPlayer

local NightController = {}

-- Setelan Lighting asli dari map, dipakai lagi pas siang.
local original = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
	ExposureCompensation = Lighting.ExposureCompensation,
}
local lastNightness = -1

local function applyLighting(nightness: number)
	if math.abs(nightness - lastNightness) < 0.001 then
		return
	end
	lastNightness = nightness
	Lighting.Ambient = original.Ambient:Lerp(N.Ambient, nightness)
	Lighting.OutdoorAmbient = original.OutdoorAmbient:Lerp(N.OutdoorAmbient, nightness)
	Lighting.Brightness = original.Brightness + (N.Brightness - original.Brightness) * nightness
	Lighting.ExposureCompensation = original.ExposureCompensation + N.ExposureOffset * nightness
end

local function viewRange(): number
	return math.max(N.EyeRange, player:GetAttribute("HeadlampRange") or 0)
end

-- Item di luar jarak pandang memudar sampai hilang, makin malam makin kerasa.
local function applyItems(nightness: number)
	local folder = workspace:FindFirstChild("SpawnedItems")
	if not folder then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local range = viewRange()
	for _, part in folder:GetChildren() do
		if part:IsA("BasePart") then
			local hidden = 0
			if nightness > 0 and root then
				local distance = (part.Position - root.Position).Magnitude
				local visible = math.clamp((range - distance) / N.FadeDistance, 0, 1)
				hidden = (1 - visible) * nightness
			end
			part.LocalTransparencyModifier = hidden
		end
	end
end

function NightController.start()
	RunService.RenderStepped:Connect(function()
		local nightness = TimeOfDay.nightness(Lighting.ClockTime)
		applyLighting(nightness)
		applyItems(nightness)
	end)
end

return NightController
