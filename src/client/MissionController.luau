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
local EventController = require(script.Parent.EventController)
local Waypoint = require(script.Parent.Waypoint)
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

local player = Players.LocalPlayer

local MissionController = {}

local panel: Frame
local rowList: Frame
local lastStep: number? = nil

local tutorialEvent: RemoteEvent
local waypoint: Waypoint.Waypoint
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

local function updateWaypoint()
	-- Lagi ada event bencana & panah safe zone tampil: panah itu yang menang
	if EventController.isGuiding() then
		waypoint.hide()
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local post = hrp and hrp:IsA("BasePart") and PostController.nearestFound(hrp.Position)
	if not post or not hrp or not hrp:IsA("BasePart") then
		waypoint.hide()
		return
	end
	local distance = (post.position - hrp.Position).Magnitude
	if distance <= Config.Tutorial.WaypointHideDistance then
		-- Udah sampai: tombol Setor yang ngambil alih
		waypoint.hide()
		return
	end
	waypoint.show(post.position, "Pos " .. post.number, distance)
end

local function refreshWaypoint()
	local wanted = waypointWanted()
	if wanted and not waypointConnection then
		waypointConnection = RunService.RenderStepped:Connect(updateWaypoint)
	elseif not wanted and waypointConnection then
		waypointConnection:Disconnect()
		waypointConnection = nil
		waypoint.hide()
	end
end

function MissionController.start()
	tutorialEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TutorialEvent") :: RemoteEvent
	waypoint = Waypoint.create("PosRanger", C.gold)

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
