--!strict
-- Malam hari & senter (sisi client):
-- * Dunia jadi gelap pas malam, dan JAUH lebih gelap di zona DarkNight (Zona 3). Balik normal pas siang/keluar zona.
-- * Item cuma kelihatan dalam jarak pandang: jangkauan senter kalau lagi nyala, kalau nggak Config.Night.EyeRange.
-- * Jalur & pagar yang di-tag Config.Night.GuideTag tetap samar kelihatan pas gelap.
-- * Nyala/matiin senter: minta ke server lewat ToggleHeadlamp (server yang set attribute HeadlampOn).
-- Semua tampilan cuma di client ini; aturan "item malam butuh senter nyala" tetap dicek server.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeOfDay = require(Shared:WaitForChild("TimeOfDay"))
local ZoneController = require(script.Parent.ZoneController)

local N = Config.Night
local DEEP = N.Deep
local DARK_AT = 0.5 -- nightness segini ke atas dianggap "gelap" buat toast
local player = Players.LocalPlayer

local NightController = {}

-- Setelan Lighting asli dari map, dipakai lagi pas siang.
local original = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	Brightness = Lighting.Brightness,
	ExposureCompensation = Lighting.ExposureCompensation,
}
local colorCorrection: ColorCorrectionEffect
local deepBlend = 0 -- 0..1, pelan-pelan ngejar target pas masuk/keluar zona gelap
local lastNightness, lastDeep = -1, -1
local toggleRemote: RemoteEvent
local guides: { [Instance]: Highlight } = {}
local darkWarningCallbacks: { () -> () } = {}
local wasWarning = false
local lastWarning = -math.huge

-- ===== Senter =====
function NightController.hasHeadlamp(): boolean
	return (player:GetAttribute("HeadlampRange") or 0) > 0
end

function NightController.isHeadlampOn(): boolean
	return player:GetAttribute("HeadlampOn") == true
end

-- Return false kalau belum punya senter (biar UI bisa kasih tahu harus beli dulu).
function NightController.toggleHeadlamp(): boolean
	if not NightController.hasHeadlamp() then
		return false
	end
	toggleRemote:FireServer(not NightController.isHeadlampOn())
	return true
end

-- callback() pas mulai gelap tapi senter mati (dibatasi Config.Night.DarkToastCooldown).
function NightController.onDarkWarning(callback: () -> ())
	table.insert(darkWarningCallbacks, callback)
end

-- ===== Lighting =====
local function isDarkZone(zone: number): boolean
	local info = Config.Zones[zone]
	return info ~= nil and info.DarkNight == true
end

local function applyLighting(nightness: number, deep: number)
	if math.abs(nightness - lastNightness) < 0.001 and math.abs(deep - lastDeep) < 0.001 then
		return
	end
	lastNightness, lastDeep = nightness, deep

	-- Malam biasa dulu, lalu ditarik lagi ke setelan Deep sebanyak `deep`
	local ambient = original.Ambient:Lerp(N.Ambient, nightness):Lerp(DEEP.Ambient, deep)
	local outdoor = original.OutdoorAmbient:Lerp(N.OutdoorAmbient, nightness):Lerp(DEEP.OutdoorAmbient, deep)
	local brightness = original.Brightness + (N.Brightness - original.Brightness) * nightness
	brightness += (DEEP.Brightness - brightness) * deep
	local exposureOffset = N.ExposureOffset * nightness
	exposureOffset += (DEEP.ExposureOffset - exposureOffset) * deep

	Lighting.Ambient = ambient
	Lighting.OutdoorAmbient = outdoor
	Lighting.Brightness = brightness
	Lighting.ExposureCompensation = original.ExposureCompensation + exposureOffset

	colorCorrection.Enabled = deep > 0
	colorCorrection.Saturation = DEEP.Saturation * deep
	colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(DEEP.TintColor, deep)

	-- Jalur & pagar: makin gelap, garis pinggirnya makin kelihatan
	for _, highlight in guides do
		highlight.Enabled = deep > 0
		highlight.OutlineTransparency = 1 - (1 - N.GuideOutline) * deep
		highlight.FillTransparency = 1 - (1 - N.GuideFill) * deep
	end
end

local function addGuide(instance: Instance)
	if guides[instance] or not (instance:IsA("Model") or instance:IsA("BasePart")) then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "JalurMalamHighlight"
	highlight.Adornee = instance
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.OutlineColor = N.GuideColor
	highlight.FillColor = N.GuideColor
	highlight.Enabled = false
	highlight.Parent = instance
	guides[instance] = highlight
	lastDeep = -1 -- paksa applyLighting ngatur highlight baru ini
end

local function removeGuide(instance: Instance)
	local highlight = guides[instance]
	if highlight then
		highlight:Destroy()
		guides[instance] = nil
	end
end

-- ===== Item =====
local function viewRange(): number
	if NightController.isHeadlampOn() then
		return math.max(N.EyeRange, player:GetAttribute("HeadlampRange") or 0)
	end
	return N.EyeRange
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

-- ===== Toast "Terlalu gelap" =====
local function warnIfDark(nightness: number, force: boolean)
	if player:GetAttribute("DataLoaded") ~= true then
		return -- belum tahu punya senter atau nggak
	end
	local warning = nightness >= DARK_AT and not NightController.isHeadlampOn()
	local rising = warning and (force or not wasWarning)
	wasWarning = warning
	local now = os.clock()
	if rising and now - lastWarning >= N.DarkToastCooldown then
		lastWarning = now
		for _, callback in darkWarningCallbacks do
			task.spawn(callback)
		end
	end
end

function NightController.start()
	toggleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ToggleHeadlamp") :: RemoteEvent

	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "MalamGelap"
	colorCorrection.Enabled = false
	colorCorrection.Parent = Lighting

	CollectionService:GetInstanceAddedSignal(N.GuideTag):Connect(addGuide)
	CollectionService:GetInstanceRemovedSignal(N.GuideTag):Connect(removeGuide)
	for _, instance in CollectionService:GetTagged(N.GuideTag) do
		addGuide(instance)
	end

	-- Masuk zona gelap pas malam = ingetin lagi (tetap kena cooldown)
	ZoneController.onZoneChanged(function(zone)
		if isDarkZone(zone) then
			warnIfDark(TimeOfDay.nightness(Lighting.ClockTime), true)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local nightness = TimeOfDay.nightness(Lighting.ClockTime)
		local target = if isDarkZone(ZoneController.getZone()) then nightness else 0
		if deepBlend < target then
			deepBlend = math.min(target, deepBlend + DEEP.BlendSpeed * dt)
		else
			deepBlend = math.max(target, deepBlend - DEEP.BlendSpeed * dt)
		end
		applyLighting(nightness, deepBlend)
		applyItems(nightness)
		warnIfDark(nightness, false)
	end)
end

return NightController
