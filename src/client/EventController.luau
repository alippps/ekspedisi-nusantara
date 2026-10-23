-- Event bencana (sisi tampilan). Semua aturan & deteksi kena ada di EventService (server); di sini cuma gambar:
-- * Banner peringatan dengan hitung mundur. Di zona event = kartu besar, sirine, layar bergetar pelan,
--   suar (pilar cahaya berkedip) di tiap safe zone zona itu, dan panah ke safe zone terdekat.
--   Di zona lain = pil kecil "Badai Petir di Zona 2 · 0:25".
-- * Lingkaran di tanah sebelum sambaran, lalu efek sambarannya (Visual di Config.Events.Types).
-- * Layar gelap "Kamu pingsan!" pas server kirim Notify "Fainted".
-- Status dibaca dari ReplicatedStorage.EventState, safe zone dari ReplicatedStorage.SafeZoneList.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local ZoneMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZoneMath"))
local ZoneController = require(script.Parent.ZoneController)
local FxController = require(script.Parent.FxController)
local UIKit = require(script.Parent.UIKit)
local Waypoint = require(script.Parent.Waypoint)

local C = UIKit.C
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label
local tween = UIKit.tween

local E = Config.Events
local SAFE_COLOR = C.stamina
local SHAKE = { warning = 0.12, active = 0.28 } -- kuat getar kamera (stud) per fase
local BEACON_HEIGHT = 90
local FX_MAX_DISTANCE = 600 -- sambaran lebih jauh dari ini nggak digambar
local THUNDER_DISTANCE = 250 -- suara petir cuma kedengeran sedekat ini
local BOLT_HEIGHT = 160

local player = Players.LocalPlayer

local EventController = {}

type SafeZone = { zone: number, cframe: CFrame, size: Vector3 }

local state: Configuration
local safeZones: { SafeZone } = {}
local fxFolder: Folder -- Part efek lokal (suar, lingkaran, petir)

local gui: ScreenGui
local card: CanvasGroup
local cardStroke: UIStroke
local eyebrowLabel: TextLabel
local titleLabel: TextLabel
local subLabel: TextLabel
local countdownLabel: TextLabel
local hintLabel: TextLabel
local pill: Frame
local pillLabel: TextLabel
local faintGui: ScreenGui
local faintCover: Frame
local faintTitle: TextLabel
local faintBody: TextLabel

local waypoint: Waypoint.Waypoint
local guiding = false
local beacons: { BasePart } = {}
local beaconZone: number? = nil
local lastPhase: string? = nil

local itemById = {}
for _, item in Config.Items do
	itemById[item.Id] = item
end

local function rootPosition(): Vector3?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp.Position else nil
end

local function insideSafeZone(position: Vector3): boolean
	for _, safe in safeZones do
		if ZoneMath.containsBox(safe.cframe, safe.size, position) then
			return true
		end
	end
	return false
end

-- Safe zone terdekat di zona ini (kalau zona itu nggak punya, yang terdekat di mana aja)
local function nearestSafe(zone: number, position: Vector3): SafeZone?
	local best: SafeZone?, bestDistance = nil, math.huge
	local bestAny: SafeZone?, bestAnyDistance = nil, math.huge
	for _, safe in safeZones do
		local distance = (safe.cframe.Position - position).Magnitude
		if safe.zone == zone and distance < bestDistance then
			best, bestDistance = safe, distance
		end
		if distance < bestAnyDistance then
			bestAny, bestAnyDistance = safe, distance
		end
	end
	return best or bestAny
end

local function formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- ===== UI =====
local function buildAlert()
	card = make("CanvasGroup", {
		Name = "EventCard",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, { corner(18) })
	cardStroke = stroke(C.tired, 3, 0)
	cardStroke.Parent = card
	local content = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, { padding(12, 18) })
	make("UIListLayout", {
		Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})
	local function centered(props: { [string]: any }): TextLabel
		props.TextXAlignment = Enum.TextXAlignment.Center
		props.Parent = content
		return label(props)
	end
	eyebrowLabel = centered({ FontFace = FONT_BODY_HEAVY, TextSize = 16, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 })
	titleLabel = centered({ FontFace = FONT_TITLE, TextSize = 30, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2 })
	subLabel = centered({ TextSize = 16, TextColor3 = C.muted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3 })
	countdownLabel = centered({ FontFace = FONT_TITLE, TextSize = 44, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 4 })
	hintLabel = centered({
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
	})

	pill = make("Frame", {
		Name = "EventPill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
		Parent = gui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.tired, 2, 0), padding(0, 16) })
	pillLabel = label({
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = pill,
	})
end

local function buildFaint()
	faintGui = make("ScreenGui", {
		Name = "Faint",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 40,
		Enabled = false,
	})
	faintCover = make("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = faintGui,
	})
	local column = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = faintCover,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})
	faintTitle = label({
		Text = "Kamu pingsan!",
		FontFace = FONT_TITLE,
		TextSize = 44,
		TextColor3 = C.tired,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = 1,
		Parent = column,
	})
	faintBody = label({
		TextSize = 20,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = column,
	})
	faintGui.Parent = player:WaitForChild("PlayerGui")
end

local function showFaint(data)
	local item = data.item and itemById[data.item]
	local lost = if item then string.format("%s hilang dari tas.", item.Name) else "Tas kosong, nggak ada yang hilang."
	faintBody.Text = string.format("Kena %s. %s\nBangun di Pos %d.", data.event or "bencana", lost, data.post or 1)
	faintGui.Enabled = true
	tween(faintCover, 0.3, { BackgroundTransparency = 0 })
	tween(faintTitle, 0.3, { TextTransparency = 0 })
	tween(faintBody, 0.3, { TextTransparency = 0 })
	-- Server mindahin karakter tepat setelah `seconds`; tunggu sedikit lagi biar perpindahannya ketutup layar gelap
	task.delay((data.seconds or E.FaintSeconds) + 0.4, function()
		tween(faintTitle, 0.5, { TextTransparency = 1 })
		tween(faintBody, 0.5, { TextTransparency = 1 })
		tween(faintCover, 0.8, { BackgroundTransparency = 1 }).Completed:Wait()
		faintGui.Enabled = false
	end)
end

-- ===== Suar safe zone =====
local function clearBeacons()
	for _, beacon in beacons do
		beacon:Destroy()
	end
	table.clear(beacons)
	beaconZone = nil
end

local function buildBeacons(zone: number)
	clearBeacons()
	beaconZone = zone
	for _, safe in safeZones do
		if safe.zone == zone then
			local bottom = safe.cframe.Position - Vector3.new(0, safe.size.Y / 2, 0)
			-- Cylinder porosnya X: diputar 90° biar tegak
			local beacon = make("Part", {
				Name = "SuarSafeZone",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(BEACON_HEIGHT, 3, 3),
				CFrame = CFrame.new(bottom + Vector3.new(0, BEACON_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Neon,
				Color = SAFE_COLOR,
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = false,
				Parent = fxFolder,
			})
			make("PointLight", { Color = SAFE_COLOR, Range = 20, Brightness = 3, Parent = beacon })
			table.insert(beacons, beacon)
		end
	end
end

-- ===== Sambaran =====
local function flatDisc(position: Vector3, diameter: number, color: Color3, transparency: number): Part
	return make("Part", {
		Name = "EventCircle",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, diameter, diameter),
		CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = transparency,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = fxFolder,
	})
end

-- Petir: beberapa batang zigzag dari langit ke tanah + kilatan cahaya
local function lightning(position: Vector3)
	local bolt = make("Model", { Name = "Petir", Parent = fxFolder })
	local from = position + Vector3.new(math.random(-12, 12), BOLT_HEIGHT, math.random(-12, 12))
	local segments = 7
	local last = from
	for i = 1, segments do
		local t = i / segments
		local target = from:Lerp(position, t)
		if i < segments then
			target += Vector3.new(math.random(-50, 50) / 10, 0, math.random(-50, 50) / 10)
		end
		local length = (target - last).Magnitude
		make("Part", {
			Size = Vector3.new(0.6, 0.6, length),
			CFrame = CFrame.lookAt((last + target) / 2, target),
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 250, 220),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = bolt,
		})
		last = target
	end
	local flash = make("Part", {
		Size = Vector3.new(1, 1, 1),
		Position = position + Vector3.new(0, 4, 0),
		Transparency = 1,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = bolt,
	})
	make("PointLight", { Color = Color3.fromRGB(255, 245, 210), Range = 40, Brightness = 8, Parent = flash })
	local root = rootPosition()
	if root and (root - position).Magnitude <= THUNDER_DISTANCE then
		FxController.play("Thunder")
	end
	task.delay(0.12, function()
		for _, part in bolt:GetChildren() do
			if part:IsA("BasePart") and part ~= flash then
				tween(part, 0.25, { Transparency = 1 })
			end
		end
	end)
	task.delay(0.4, function()
		bolt:Destroy()
	end)
end

local VISUALS: { [string]: (Vector3) -> () } = {
	lightning = lightning,
}

local function onStrike(typeId: string, position: Vector3, radius: number, impactAt: number)
	local def = E.Types[typeId]
	local camera = workspace.CurrentCamera
	if not def or not camera or (camera.CFrame.Position - position).Magnitude > FX_MAX_DISTANCE then
		return
	end
	local delay = math.max(0, impactAt - workspace:GetServerTimeNow())
	-- Lingkaran luar = area kena; isi tumbuh sampai penuh pas sambaran mendarat
	local outer = flatDisc(position, radius * 2, def.CircleColor, 0.55)
	local inner = flatDisc(position, 0.5, def.CircleColor, 0.25)
	tween(inner, delay, { Size = Vector3.new(0.25, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	task.delay(delay, function()
		outer:Destroy()
		inner:Destroy()
		local visual = VISUALS[def.Visual]
		if visual then
			visual(position)
		end
	end)
end

-- ===== Per frame =====
local function setShake(amount: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if amount <= 0 then
		humanoid.CameraOffset = Vector3.zero
		return
	end
	local t = os.clock() * 18
	humanoid.CameraOffset = Vector3.new(math.noise(t, 0.3) * amount, math.noise(t, 7.1) * amount, math.noise(t, 13.7) * amount)
end

local function setGuiding(on: boolean)
	guiding = on
	if not on then
		waypoint.hide()
	end
end

local function hideAll()
	card.Visible = false
	pill.Visible = false
	clearBeacons()
	setGuiding(false)
	setShake(0)
end

local function update()
	local phase = state:GetAttribute("Phase")
	local zone = state:GetAttribute("Zone")
	if type(phase) ~= "string" or type(zone) ~= "number" then
		if lastPhase then
			hideAll()
		end
		lastPhase = nil
		return
	end
	local name = state:GetAttribute("Name") or "Bencana"
	local remaining = (state:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow()
	local here = ZoneController.getZone() == zone
	local position = rootPosition()
	local safe = position ~= nil and insideSafeZone(position)
	local danger = phase == "warning" or phase == "active"

	if phase ~= lastPhase and phase == "warning" and here then
		FxController.play("Siren")
	end
	lastPhase = phase

	-- Suar cuma selama bahaya, di zona event
	if danger and beaconZone ~= zone then
		buildBeacons(zone)
	elseif not danger and beaconZone then
		clearBeacons()
	end
	if #beacons > 0 then
		local blink = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(os.clock() * 8))
		for _, beacon in beacons do
			beacon.Transparency = blink
		end
	end

	-- Panah ke safe zone terdekat: di zona event, lagi bahaya, belum di dalam safe zone
	local target = if danger and here and position and not safe then nearestSafe(zone, position) else nil
	if target and position then
		setGuiding(true)
		waypoint.show(target.cframe.Position, "Safe zone", (target.cframe.Position - position).Magnitude)
	else
		setGuiding(false)
	end

	setShake(if here and danger then SHAKE[phase] else 0)

	-- Kartu besar di zona event, pil kecil di zona lain
	local zoneText = string.format("Zona %d · %s", zone, Progression.zoneName(zone))
	if not here then
		card.Visible = false
		pill.Visible = true
		if phase == "loot" then
			pillLabel.Text = string.format("Item langka di Zona %d · %s", zone, formatTime(remaining))
		else
			pillLabel.Text = string.format("%s di Zona %d · %s", name, zone, formatTime(remaining))
		end
		return
	end
	pill.Visible = false
	card.Visible = true
	countdownLabel.Text = formatTime(remaining)
	if phase == "loot" then
		local loot = state:GetAttribute("Loot") or 0
		eyebrowLabel.Text = "REDA"
		eyebrowLabel.TextColor3 = C.gold
		cardStroke.Color = C.gold
		titleLabel.Text = "Item langka muncul!"
		subLabel.Text = string.format("%d item langka di %s", loot, zoneText)
		hintLabel.Text = "Cepat ambil sebelum hilang."
		hintLabel.TextColor3 = C.gold
		return
	end
	local color = if phase == "active" then C.tired else C.accent
	eyebrowLabel.Text = if phase == "active" then "BENCANA!" else "PERINGATAN"
	eyebrowLabel.TextColor3 = color
	cardStroke.Color = color
	titleLabel.Text = name
	subLabel.Text = zoneText
	if safe then
		hintLabel.Text = "Kamu aman di safe zone. Tetap di sini!"
		hintLabel.TextColor3 = SAFE_COLOR
	else
		hintLabel.Text = "Lari ke safe zone! Ikuti panah & pilar cahaya hijau."
		hintLabel.TextColor3 = C.cream
	end
end

-- ===== API publik =====
-- True kalau panah safe zone lagi tampil (MissionController nyembunyiin panah Pos Ranger-nya)
function EventController.isGuiding(): boolean
	return guiding
end

local function addSafeZone(entry: Instance)
	local zone, cframe, size = entry:GetAttribute("Zone"), entry:GetAttribute("CFrame"), entry:GetAttribute("Size")
	if type(zone) == "number" and typeof(cframe) == "CFrame" and typeof(size) == "Vector3" then
		table.insert(safeZones, { zone = zone, cframe = cframe, size = size })
		if beaconZone then
			buildBeacons(beaconZone)
		end
	end
end

function EventController.start()
	gui = make("ScreenGui", {
		Name = "EventAlert",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 4, -- di atas HUD, di bawah banner Fx
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local uiScale = make("UIScale", { Parent = gui })
	local function updateScale()
		local vp = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.75, 1.25)
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	buildAlert()
	gui.Parent = player:WaitForChild("PlayerGui")
	buildFaint()
	waypoint = Waypoint.create("SafeZone", SAFE_COLOR)

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "EventFxLocal"
	fxFolder.Parent = workspace

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("EventFx").OnClientEvent:Connect(function(kind: string, ...)
		if kind == "Strike" then
			onStrike(...)
		end
	end)
	remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
		if kind == "Fainted" and type(data) == "table" then
			showFaint(data)
		end
	end)

	task.spawn(function()
		local list = ReplicatedStorage:WaitForChild("SafeZoneList")
		for _, entry in list:GetChildren() do
			addSafeZone(entry)
		end
		list.ChildAdded:Connect(addSafeZone)
	end)
	task.spawn(function()
		state = ReplicatedStorage:WaitForChild("EventState") :: Configuration
		RunService.RenderStepped:Connect(update)
	end)
end

return EventController
