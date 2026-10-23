-- Gerbang zona (sisi UI):
-- * Dekat gerbang yang masih terkunci: panel "Gerbang Zona N" berisi checklist syarat dari Config.Zones
--   (centang hijau = terpenuhi, silang merah + nilai pemain sekarang = belum), plus petunjuk di bawahnya.
-- * Semua syarat baru aja terpenuhi: banner "Zona baru terbuka!" (lewat antrean banner FxController).
-- Deteksi dekat gerbang & kapan zona kebuka ada di ZoneController; di sini cuma tampilan.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local ZoneController = require(script.Parent.ZoneController)
local FxController = require(script.Parent.FxController)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.C
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label
local tween = UIKit.tween

local SHOP_NAME = "Pos Ranger"
local ICON_SIZE = 22

local player = Players.LocalPlayer

local GateController = {}

local gui: ScreenGui
local panel: CanvasGroup
local panelTitle: TextLabel
local panelZone: TextLabel
local checkList: Frame
local hintLabel: TextLabel
local shownZone: number? = nil
local panelToken = 0

-- ===== Teks syarat =====
local function upgradeName(upgradeId: string): string
	local upgrade = Config.Upgrades[upgradeId]
	return upgrade.ShortName or upgrade.Name
end

-- "Level 12" / "Senter level 2"
local function checkTitle(check: Progression.ZoneCheck): string
	if check.Kind == "Upgrade" then
		return string.format("%s level %d", upgradeName(check.UpgradeId :: string), check.Need)
	end
	return string.format("Level %d", check.Need)
end

-- "Level kamu masih 8" / "Senter kamu masih level 1"
local function checkDetail(check: Progression.ZoneCheck): string
	if check.Kind == "Upgrade" then
		return string.format("%s kamu masih level %d", upgradeName(check.UpgradeId :: string), check.Have)
	end
	return string.format("Level kamu masih %d", check.Have)
end

-- Syarat yang belum terpenuhi, versi pendek: "Lv 12 + Senter Lv 2". Dipakai toast & Jurnal.
function GateController.missingText(zone: number): string
	local parts = {}
	for _, check in ZoneController.getChecks(zone) do
		if not check.Met then
			if check.Kind == "Upgrade" then
				table.insert(parts, string.format("%s Lv %d", upgradeName(check.UpgradeId :: string), check.Need))
			else
				table.insert(parts, string.format("Lv %d", check.Need))
			end
		end
	end
	return table.concat(parts, " + ")
end

-- Teks papan Penanda di gerbang: "Terbuka" atau "Terkunci · butuh Lv 5 (kamu Lv 3)"
function GateController.signText(zone: number): string
	if ZoneController.isUnlocked(zone) then
		return "Terbuka"
	end
	local parts = {}
	for _, check in ZoneController.getChecks(zone) do
		if not check.Met then
			if check.Kind == "Upgrade" then
				local name = upgradeName(check.UpgradeId :: string)
				table.insert(parts, string.format("%s Lv %d (kamu Lv %d)", name, check.Need, check.Have))
			else
				table.insert(parts, string.format("Lv %d (kamu Lv %d)", check.Need, check.Have))
			end
		end
	end
	return "Terkunci · butuh " .. table.concat(parts, " + ")
end

-- Papan "Penanda" (BillboardGui) di gerbang punya label "Sub": teksnya diganti per pemain, cuma di client ini.
local function refreshSign(gate: Instance, zone: number)
	local sign = gate:FindFirstChild("Penanda", true)
	local sub = sign and sign:FindFirstChild("Sub", true)
	if sub and (sub:IsA("TextLabel") or sub:IsA("TextButton")) then
		sub.Text = GateController.signText(zone)
	end
end

-- Petunjuk di bawah panel: upgrade dulu (jelas harus ngapain), kalau tinggal level baru suruh naik level.
local function hintText(checks: { Progression.ZoneCheck }): string
	for _, check in checks do
		if not check.Met and check.Kind == "Upgrade" then
			return string.format("Upgrade %s di %s.", upgradeName(check.UpgradeId :: string), SHOP_NAME)
		end
	end
	for _, check in checks do
		if not check.Met then
			return string.format("Kumpulkan & setor item sampai Level %d.", check.Need)
		end
	end
	return ""
end

-- ===== Bangun UI =====
local function checkRow(check: Progression.ZoneCheck, order: number)
	local row = make("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = checkList,
	})
	local icon = UIKit.statusIcon(check.Met, ICON_SIZE)
	icon.Position = UDim2.fromOffset(0, 1)
	icon.Parent = row

	local text = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(ICON_SIZE + 10, 0),
		Size = UDim2.new(1, -(ICON_SIZE + 10), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	make("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder, Parent = text })
	label({
		Text = checkTitle(check),
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		TextColor3 = check.Met and C.cream or C.muted,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 1,
		Parent = text,
	})
	if not check.Met then
		label({
			Text = checkDetail(check),
			TextSize = 15,
			TextColor3 = C.tired,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 2,
			Parent = text,
		})
	end
end

local function buildPanel()
	-- CanvasGroup biar panel + petunjuk bisa fade bareng. Padding kecil biar stroke nggak kepotong.
	panel = make("CanvasGroup", {
		Name = "GatePanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = gui,
	}, { padding(4, 4) })
	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	local card = make("Frame", {
		Name = "Card",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = panel,
	}, { corner(16), stroke(C.cream, 2, 0.82), padding(14, 16) })
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

	panelTitle = label({
		Text = "Gerbang Zona",
		FontFace = FONT_TITLE,
		TextSize = 22,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Parent = card,
	})
	panelZone = label({
		Text = "",
		TextSize = 16,
		TextColor3 = C.muted,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2,
		Parent = card,
	})
	checkList = make("Frame", {
		Name = "Checks",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = card,
	}, { padding(6, 0) })
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = checkList })

	-- Petunjuk ala toast di bawah panel
	local hint = make("Frame", {
		Name = "Hint",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = panel,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 16) })
	hintLabel = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextColor3 = C.gold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = hint,
	})
end

-- ===== Panel gerbang =====
local function fillPanel(zone: number)
	local checks = ZoneController.getChecks(zone)
	panelTitle.Text = string.format("Gerbang Zona %d", zone)
	panelZone.Text = Progression.zoneName(zone)
	for _, child in checkList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, check in checks do
		checkRow(check, i)
	end
	hintLabel.Text = hintText(checks)
end

local function showPanel(zone: number?)
	shownZone = zone
	panelToken += 1
	local token = panelToken
	if zone then
		fillPanel(zone)
		panel.Visible = true
		tween(panel, 0.2, { GroupTransparency = 0 })
	elseif panel.Visible then
		local t = tween(panel, 0.25, { GroupTransparency = 1 })
		t.Completed:Wait()
		if token == panelToken then
			panel.Visible = false
		end
	end
end

-- Level/upgrade berubah pas panel lagi kebuka (misal baru beli senter): perbarui checklist
local function refreshPanel()
	if shownZone then
		fillPanel(shownZone)
	end
end

-- ===== Banner zona baru =====
local function itemCount(zone: number): number
	local count = 0
	for _, item in Config.Items do
		if item.Zone == zone then
			count += 1
		end
	end
	return count
end

function GateController.showUnlocked(zone: number)
	local info = Config.Zones[zone] :: any
	FxController.banner({
		title = "Zona baru terbuka!",
		subtitle = string.format("Zona %d · %s", zone, Progression.zoneName(zone)),
		body = if info and info.Teaser
			then string.format("%d item baru, %s.", itemCount(zone), info.Teaser)
			else string.format("%d item baru menunggu di sana.", itemCount(zone)),
		sound = "ZoneUnlocked",
		confetti = 30,
		seconds = Config.ZoneGate.BannerSeconds,
	})
end

local function updateScale(uiScale: UIScale)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.75, 1.25)
end

function GateController.start()
	gui = make("ScreenGui", {
		Name = "GateUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local uiScale = make("UIScale", { Parent = gui })
	buildPanel()
	gui.Parent = player:WaitForChild("PlayerGui")

	updateScale(uiScale)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateScale(uiScale)
	end)

	ZoneController.onNearGate(showPanel)
	ZoneController.onGateRefreshed(refreshSign)
	ZoneController.onZoneUnlocked(GateController.showUnlocked)
	player:GetAttributeChangedSignal("Level"):Connect(refreshPanel)
	for upgradeId in Config.Upgrades do
		player:GetAttributeChangedSignal("Upgrade_" .. upgradeId):Connect(refreshPanel)
	end
end

return GateController
