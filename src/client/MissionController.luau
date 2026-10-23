-- Petunjuk buat pemain baru:
-- * Panel "Misi" di bawah panel stamina. Misi pemula langkah demi langkah (TutorialStep dari TutorialService),
--   setelah selesai lanjut ke target zona berikutnya ("Capai Lv 3 untuk membuka Zona 2"), hilang kalau semua zona terbuka.
-- * Penanda arah ke Pos Ranger terdekat (yang udah ditemukan) pas langkah "Setor" atau tas penuh:
--   papan di atas pos + panah di pinggir layar kalau posnya lagi di luar layar.
-- * Langkah "Buka Jurnal": pas Jurnal dibuka, kartu item yang udah ketemu berdenyut.
-- Semua di sini cuma tampilan; progres misi dinaikkan server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local ZoneController = require(script.Parent.ZoneController)
local GateController = require(script.Parent.GateController)
local JournalController = require(script.Parent.JournalController)
local FxController = require(script.Parent.FxController)
local PostController = require(script.Parent.PostController)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.C
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label

-- Sama dengan TutorialService
local STEP_JOURNAL, STEP_DEPOSIT, STEP_DONE = 2, 3, 4
local ICON_SIZE = 18
local EDGE_MARGIN = 56 -- jarak panah dari pinggir layar (piksel)

local player = Players.LocalPlayer

local MissionController = {}

local panel: Frame
local rowList: Frame
local lastStep: number? = nil

local tutorialEvent: RemoteEvent
local markerGui: BillboardGui
local markerTitle: TextLabel
local markerDistance: TextLabel
local markerAnchor: Part -- Part lokal tak terlihat di posisi pos (Model pos-nya bisa belum ke-stream)
local edgeGui: ScreenGui
local edgeArrow: Frame
local waypointConnection: RBXScriptConnection? = nil

local function step(): number?
	return player:GetAttribute("TutorialStep")
end

-- ===== Panel Misi =====
-- Ikon langkah: centang hijau (selesai), lingkaran oranye (sekarang), lingkaran redup (nanti)
local function stepIcon(state: string): Frame
	if state == "done" then
		return UIKit.statusIcon(true, ICON_SIZE)
	end
	return make("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
	}, {
		make("UICorner", { CornerRadius = UDim.new(1, 0) }),
		stroke(if state == "current" then C.accent else C.muted, 2, if state == "current" then 0 else 0.5),
	})
end

local function row(text: string, state: string, order: number, detail: string?)
	local frame = make("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = rowList,
	})
	local icon = stepIcon(state)
	icon.Position = UDim2.fromOffset(0, 2)
	icon.Parent = frame
	local textColumn = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(ICON_SIZE + 10, 0),
		Size = UDim2.new(1, -(ICON_SIZE + 10), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = textColumn })
	label({
		Text = text,
		FontFace = if state == "current" then FONT_BODY_HEAVY else UIKit.FONT_BODY,
		TextSize = 16,
		TextColor3 = if state == "current" then C.cream else C.muted,
		TextTransparency = if state == "next" then 0.35 else 0,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = textColumn,
	})
	if detail then
		label({
			Text = detail,
			TextSize = 14,
			TextColor3 = C.gold,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 2,
			Parent = textColumn,
		})
	end
end

-- Zona terkunci pertama, atau nil kalau semua udah terbuka
local function nextLockedZone(): number?
	for zone in Config.Zones do
		if not ZoneController.isUnlocked(zone) then
			return zone
		end
	end
	return nil
end

local function refreshPanel()
	if not panel then
		return
	end
	local current = step()
	for _, child in rowList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if current == nil then
		panel.Visible = false -- data belum dimuat
		return
	end

	if current < STEP_DONE then
		local journalKey = if UserInputService.KeyboardEnabled then "tekan J atau tombol Jurnal" else "tombol Jurnal"
		local picked = math.min(player:GetAttribute("TutorialPicked") or 0, Config.Tutorial.PickCount)
		local steps = {
			string.format("Ambil %d item (%d/%d)", Config.Tutorial.PickCount, picked, Config.Tutorial.PickCount),
			string.format("Lihat temuanmu di Jurnal (%s)", journalKey),
			"Setor isi tas ke Pos Ranger buat dapat Koin & XP",
		}
		for i, text in steps do
			local state = if i < current then "done" elseif i == current then "current" else "next"
			row(text, state, i)
		end
		panel.Visible = true
	else
		local zone = nextLockedZone()
		if not zone then
			panel.Visible = false
			return
		end
		local level = player:GetAttribute("Level") or 1
		row(
			string.format("Capai %s untuk membuka Zona %d", GateController.missingText(zone), zone),
			"current",
			1,
			string.format("Sekarang Lv %d", level)
		)
		panel.Visible = true
	end

	-- Langkah naik (bukan pas pertama muncul): panel berdenyut
	if lastStep and current > lastStep then
		FxController.pulse(panel, 1.06)
	end
	lastStep = current
end

-- Dipanggil UIController buat naruh panel di kolom kiri (di bawah stamina).
function MissionController.mount(parent: Instance, order: number)
	panel = make("Frame", {
		Name = "MissionPanel",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	}, { corner(16), stroke(C.cream, 2, 0.82), padding(12, 16) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })
	label({
		Text = "Misi",
		FontFace = FONT_TITLE,
		TextSize = 19,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = panel,
	})
	rowList = make("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = panel,
	})
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rowList })
	refreshPanel()
end

-- ===== Penanda arah ke Pos Ranger =====
local function waypointWanted(): boolean
	if step() == STEP_DEPOSIT then
		return true
	end
	local count = player:GetAttribute("BagCount") or 0
	local max = player:GetAttribute("BagMax") or 0
	return max > 0 and count >= max
end

local function buildWaypoint()
	-- Papan di atas Pos Ranger, kelihatan tembus tembok
	markerGui = make("BillboardGui", {
		Name = "PosRangerMarker",
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(150, 62),
		StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
		Enabled = false,
		ResetOnSpawn = false,
	})
	local pill = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = markerGui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.gold, 2, 0), padding(0, 14) })
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pill,
	})
	markerTitle = label({
		Text = "Pos Ranger",
		FontFace = FONT_TITLE,
		TextSize = 17,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = pill,
	})
	markerDistance = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 15,
		TextColor3 = C.gold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = pill,
	})
	-- Segitiga kecil ke bawah (kotak diputar 45°, setengahnya ketutup pill)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundColor3 = C.gold,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = markerGui,
	})
	markerGui.Parent = player:WaitForChild("PlayerGui")
	markerAnchor = make("Part", {
		Name = "PosRangerMarkerAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		Parent = workspace,
	})
	markerGui.Adornee = markerAnchor

	-- Panah di pinggir layar (tanpa UIScale, pakai piksel layar asli)
	edgeGui = make("ScreenGui", {
		Name = "Waypoint",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
	})
	edgeArrow = make("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = edgeGui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.gold, 2, 0) })
	-- Chevron ">" dari dua batang; seluruh lingkaran diputar ke arah Pos Ranger
	for _, rotation in { 40, -40 } do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(24, 22 + (if rotation > 0 then -5 else 5)),
			Size = UDim2.fromOffset(16, 4),
			Rotation = rotation,
			BackgroundColor3 = C.gold,
			BorderSizePixel = 0,
			Parent = edgeArrow,
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	edgeGui.Parent = player:WaitForChild("PlayerGui")
end

local function updateWaypoint()
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	local post = hrp and hrp:IsA("BasePart") and PostController.nearestFound(hrp.Position)
	if not post or not hrp or not hrp:IsA("BasePart") or not camera then
		markerGui.Enabled = false
		edgeGui.Enabled = false
		return
	end
	local distance = (post.position - hrp.Position).Magnitude
	if distance <= Config.Tutorial.WaypointHideDistance then
		-- Udah sampai: tombol Setor yang ngambil alih
		markerGui.Enabled = false
		edgeGui.Enabled = false
		return
	end
	markerAnchor.Position = post.position
	markerGui.Enabled = true
	markerTitle.Text = "Pos " .. post.number
	markerDistance.Text = string.format("%dm", math.floor(distance))

	local point, inFront = camera:WorldToViewportPoint(post.position)
	local vp = camera.ViewportSize
	local onScreen = inFront and point.X >= 0 and point.X <= vp.X and point.Y >= 0 and point.Y <= vp.Y
	edgeGui.Enabled = not onScreen
	if onScreen then
		return
	end
	-- Arah dari tengah layar ke Pos Ranger (kalau di belakang kamera, arahnya dibalik)
	local center = vp / 2
	local dir = Vector2.new(point.X, point.Y) - center
	if not inFront then
		dir = -dir
	end
	if dir.Magnitude < 1 then
		dir = Vector2.new(0, 1)
	end
	local half = center - Vector2.new(EDGE_MARGIN, EDGE_MARGIN)
	local scale = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Y / math.max(math.abs(dir.Y), 1e-3))
	local pos = center + dir * scale
	edgeArrow.Position = UDim2.fromOffset(pos.X, pos.Y)
	edgeArrow.Rotation = math.deg(math.atan2(dir.Y, dir.X))
end

local function refreshWaypoint()
	local wanted = waypointWanted()
	if wanted and not waypointConnection then
		waypointConnection = RunService.RenderStepped:Connect(updateWaypoint)
	elseif not wanted and waypointConnection then
		waypointConnection:Disconnect()
		waypointConnection = nil
		markerGui.Enabled = false
		edgeGui.Enabled = false
	end
end

function MissionController.start()
	tutorialEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TutorialEvent") :: RemoteEvent
	buildWaypoint()

	JournalController.onOpened(function()
		if step() == STEP_JOURNAL then
			tutorialEvent:FireServer("JournalOpened")
			JournalController.celebrate(JournalController.foundIds())
		end
	end)

	local function onChange()
		refreshPanel()
		refreshWaypoint()
	end
	for _, attribute in { "TutorialStep", "TutorialPicked", "Level", "BagCount", "BagMax" } do
		player:GetAttributeChangedSignal(attribute):Connect(onChange)
	end
	for upgradeId in Config.Upgrades do
		player:GetAttributeChangedSignal("Upgrade_" .. upgradeId):Connect(refreshPanel)
	end
	onChange()
end

return MissionController
