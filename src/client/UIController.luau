-- HUD utama sesuai mockup: stamina + jam, zona, koin + level, tas, popup item, dan toast.
-- Semua ukuran didesain di layar 1280x720, lalu diskalakan otomatis lewat UIScale.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local StaminaController = require(script.Parent.StaminaController)
local JournalController = require(script.Parent.JournalController)
local ZoneController = require(script.Parent.ZoneController)
local NightController = require(script.Parent.NightController)
local UIKit = require(script.Parent.UIKit)

local C = UIKit.C
local RARITY_DEEP = UIKit.RARITY_DEEP
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label
local tween = UIKit.tween
local formatNumber = UIKit.formatNumber

local player = Players.LocalPlayer

local UIController = {}

local BASE_BAG_SLOTS = Config.Upgrades.Bag.Levels[1].Value

local itemById = {}
for _, item in Config.Items do
	itemById[item.Id] = item
end

local function hudPanel(props: { [string]: any })
	local defaults = {
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("Frame", defaults, { corner(16), stroke(C.cream, 2, 0.82) })
end

local function bar(parent: Instance, height: number, color: Color3, order: number)
	local track = make("Frame", {
		Name = "Track",
		BackgroundColor3 = C.cream,
		BackgroundTransparency = 0.84,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = order,
		Parent = parent,
	}, { corner(height // 2) })
	local fill = make("Frame", {
		Name = "Fill",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, { corner(height // 2) })
	return fill
end

-- ===== Bangun HUD =====
local gui: ScreenGui
local staminaFill: Frame
local staminaValue: TextLabel
local timeLabel: TextLabel
local sunIcon: Frame
local moonIcon: Frame
local coinLabel: TextLabel
local levelLabel: TextLabel
local xpFill: Frame
local xpLabel: TextLabel
local bagLabel: TextLabel
local zoneLabel: TextLabel
local journalLabel: TextLabel
local journalHint = ""
local slotRow: Frame
local slots: { Frame } = {}

local popup: CanvasGroup
local popupTitle: TextLabel
local popupRarity: TextLabel
local popupName: TextLabel
local popupMeta: TextLabel
local popupReward: TextLabel
local popupStroke: UIStroke
local popupToken = 0

local toast: CanvasGroup
local toastLabel: TextLabel
local toastToken = 0

local function buildStaminaPanel()
	local panel = hudPanel({
		Name = "StaminaPanel",
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	padding(14, 16).Parent = panel
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = panel })
	label({ Text = "Stamina", FontFace = FONT_TITLE, TextSize = 19, Size = UDim2.fromScale(0.7, 1), Parent = row })
	staminaValue = label({
		Text = "100%",
		FontFace = FONT_TITLE,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.3, 1),
		Position = UDim2.fromScale(0.7, 0),
		Parent = row,
	})

	staminaFill = bar(panel, 12, C.stamina, 2)

	-- Baris jam: ikon matahari (siang) / bulan sabit (malam) + teks jam
	local timeRow = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 3, Parent = panel })
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = timeRow,
	})
	sunIcon = make("Frame", {
		Name = "SunIcon",
		BackgroundColor3 = C.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		LayoutOrder = 1,
		Parent = timeRow,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(Color3.fromRGB(176, 120, 30), 2, 0) })
	-- Bulan sabit = lingkaran krem yang "digigit" lingkaran warna panel
	moonIcon = make("Frame", {
		Name = "MoonIcon",
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		Visible = false,
		LayoutOrder = 1,
		Parent = timeRow,
	}, {
		make("UICorner", { CornerRadius = UDim.new(1, 0) }),
		make("Frame", {
			Name = "Bite",
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(15, 15),
			Position = UDim2.fromOffset(7, -3),
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
	})

	timeLabel = label({
		Text = "Siang · 08:00",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		Size = UDim2.new(1, -26, 1, 0),
		LayoutOrder = 2,
		Parent = timeRow,
	})
end

local function buildZonePill()
	local pill = make("Frame", {
		Name = "ZonePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Parent = gui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.cream, 2, 0.82), padding(0, 22) })
	zoneLabel = label({
		Text = "",
		FontFace = FONT_TITLE,
		TextSize = 18,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = pill,
	})
end

-- Kolom kanan atas: panel koin, lalu tombol Jurnal di bawahnya.
local function buildRightColumn(): Frame
	local column = make("Frame", {
		Name = "RightColumn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = column,
	})
	return column
end

local function buildJournalButton(parent: Frame)
	local button = make("TextButton", {
		Name = "JournalButton",
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 2,
		Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.cream, 2, 0.82), padding(0, 18) })
	-- Di PC kasih petunjuk tombol J; di HP cukup tap.
	local hint = UserInputService.KeyboardEnabled and "  [J]" or ""
	journalLabel = label({
		Text = "Jurnal 0/" .. #Config.Items .. hint,
		FontFace = FONT_TITLE,
		TextSize = 18,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = button,
	})
	journalHint = hint
	button.Activated:Connect(JournalController.toggle)
end

local function buildCoinPanel(parent: Frame)
	local panel = hudPanel({
		Name = "CoinPanel",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = parent,
	})
	padding(14, 16).Parent = panel
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = panel })

	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = panel })
	make("Frame", {
		Name = "CoinIcon",
		BackgroundColor3 = C.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.fromOffset(0, 4),
		Parent = row,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(Color3.fromRGB(176, 120, 30), 2, 0) })
	coinLabel = label({
		Text = "0",
		FontFace = FONT_TITLE,
		TextSize = 26,
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -110, 1, 0),
		Parent = row,
	})
	local levelPill = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Parent = row,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 12) })
	levelLabel = label({
		Text = "Lv 1",
		FontFace = FONT_TITLE,
		TextSize = 16,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = levelPill,
	})

	xpFill = bar(panel, 8, C.accent, 2)
	xpFill.Size = UDim2.fromScale(0, 1)

	xpLabel = label({
		Text = string.format("0 / %d XP", Progression.xpToNext(1)),
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 3,
		Parent = panel,
	})
end

local function buildBagPanel()
	local panel = hudPanel({
		Name = "BagPanel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	padding(0, 16).Parent = panel
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})
	bagLabel = label({
		Text = "Tas 0/10",
		FontFace = FONT_TITLE,
		TextSize = 18,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 1,
		Parent = panel,
	})
	slotRow = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = slotRow,
	})
end

local function buildPopup()
	popup = make("CanvasGroup", {
		Name = "ItemPopup",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		Parent = gui,
	}, { corner(18), padding(10, 16) })
	popupStroke = stroke(Color3.new(1, 1, 1), 4, 0)
	popupStroke.Parent = popup
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = popup })

	local header = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = popup })
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = header,
	})
	popupTitle = label({
		Text = "Nemu item!",
		FontFace = FONT_TITLE,
		TextSize = 20,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = header,
	})
	local rarityPill = make("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = header,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 12) })
	popupRarity = label({
		Text = "Common",
		FontFace = FONT_TITLE,
		TextSize = 16,
		TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = rarityPill,
	})

	popupName = label({
		Text = "",
		FontFace = FONT_TITLE,
		TextSize = 26,
		TextColor3 = C.ink,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 2,
		Parent = popup,
	})
	popupMeta = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 17,
		TextColor3 = C.inkMuted,
		Size = UDim2.new(1, 0, 0, 22),
		Visible = false,
		LayoutOrder = 3,
		Parent = popup,
	})
	popupReward = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 17,
		TextColor3 = C.ink,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 4,
		Parent = popup,
	})
end

local function buildToast()
	toast = make("CanvasGroup", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		Parent = gui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 18) })
	toastLabel = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = toast,
	})
end

-- Tombol Lari & Senter khusus HP. Sengaja di ScreenGui terpisah tanpa UIScale.
-- Posisi dan muncul/hilangnya ngikut JumpButton bawaan Roblox (TouchGui dari PlayerModule):
-- kalau PlayerModule pindah ke mode keyboard, tombol lompat hilang, tombol Lari & Senter ikut hilang.
-- Urutan dari kanan: Lompat, Lari, Senter. Senter cuma muncul kalau udah punya. Di PC pakai tombol F.
local runButton: TextButton? = nil
local headlampButton: TextButton? = nil
local runGui: ScreenGui? = nil
local jumpButton: GuiObject? = nil

local RUN_SIZE_RATIO = 0.85 -- ukuran tombol Lari relatif ke tombol lompat
local RUN_GAP_RATIO = 0.2 -- jarak ke tombol lompat, relatif ke ukuran tombol lompat

-- JumpButton bisa dihancurkan dan dibikin ulang oleh PlayerModule (misal layar diputar),
-- jadi referensinya dicek ulang tiap kali sudah tidak punya Parent.
local function findJumpButton(): (GuiObject?, ScreenGui?)
	local playerGui = player:FindFirstChild("PlayerGui")
	local touchGui = playerGui and playerGui:FindFirstChild("TouchGui")
	if not touchGui or not touchGui:IsA("ScreenGui") then
		return nil, nil
	end
	if not (jumpButton and jumpButton.Parent) then
		local frame = touchGui:FindFirstChild("TouchControlFrame")
		local found = frame and frame:FindFirstChild("JumpButton")
		jumpButton = if found and found:IsA("GuiObject") then found else nil
	end
	return jumpButton, touchGui
end

-- Dipakai tombol Senter (HP) dan tombol F (PC).
local function toggleHeadlamp()
	if not NightController.toggleHeadlamp() then
		UIController.toast(string.format("Belum punya %s, beli di Pos Ranger", Config.Upgrades.Headlamp.Name))
	end
end

local function buildRunButton()
	if not UserInputService.TouchEnabled then
		return
	end
	local touchGui = make("ScreenGui", {
		Name = "TouchControls",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local button = make("TextButton", {
		Name = "RunButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = FONT_TITLE,
		Text = "Lari",
		TextColor3 = C.cream,
		TextSize = 18,
		Parent = touchGui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.cream, 2, 0.6) })

	button.Activated:Connect(function()
		StaminaController.setTouchSprint(not StaminaController.isTouchSprint())
	end)

	local lamp = make("TextButton", {
		Name = "HeadlampButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = FONT_TITLE,
		Text = "Senter",
		TextColor3 = C.cream,
		TextSize = 16,
		Parent = touchGui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(C.cream, 2, 0.6) })
	lamp.Activated:Connect(toggleHeadlamp)

	touchGui.Parent = player:WaitForChild("PlayerGui")
	runButton = button
	headlampButton = lamp
	runGui = touchGui
end

-- Dipanggil tiap frame: tempelkan tombol Lari di kiri tombol lompat, sejajar tengahnya.
local function syncRunButtonToJump(button: TextButton, gui: ScreenGui): boolean
	local jump, touchGui = findJumpButton()
	local shown = jump ~= nil and touchGui ~= nil and touchGui.Enabled and jump.Visible
	if not shown or not jump or not touchGui then
		return false
	end

	-- Samakan inset dengan TouchGui supaya koordinat Absolute-nya satu ruang.
	if gui.IgnoreGuiInset ~= touchGui.IgnoreGuiInset then
		gui.IgnoreGuiInset = touchGui.IgnoreGuiInset
	end
	if gui.ScreenInsets ~= touchGui.ScreenInsets then
		gui.ScreenInsets = touchGui.ScreenInsets
	end

	local pos = jump.AbsolutePosition
	local size = jump.AbsoluteSize
	local runSize = math.floor(size.X * RUN_SIZE_RATIO)
	local gap = size.X * RUN_GAP_RATIO
	button.Size = UDim2.fromOffset(runSize, runSize)
	button.Position = UDim2.fromOffset(pos.X - gap, pos.Y + size.Y / 2)
	-- Senter di kiri tombol Lari, jaraknya sama
	local lamp = headlampButton
	if lamp then
		lamp.Size = UDim2.fromOffset(runSize, runSize)
		lamp.Position = UDim2.fromOffset(pos.X - gap - runSize - gap, pos.Y + size.Y / 2)
	end
	return true
end

local function refreshRunButton()
	local button = runButton
	local gui = runGui
	if not button or not gui then
		return
	end
	local shown = syncRunButtonToJump(button, gui)
	button.Visible = shown
	local lamp = headlampButton
	if lamp then
		lamp.Visible = shown and NightController.hasHeadlamp()
		local lampOn = NightController.isHeadlampOn()
		lamp.BackgroundColor3 = lampOn and C.gold or C.panel
		lamp.TextColor3 = lampOn and C.ink or C.cream
		lamp.BackgroundTransparency = lampOn and 0 or 0.15
	end
	if not shown then
		-- Kontrol sentuh mati (misal pindah ke keyboard): matikan juga mode lari HP.
		if StaminaController.isTouchSprint() then
			StaminaController.setTouchSprint(false)
		end
		return
	end
	local on = StaminaController.isTouchSprint()
	button.BackgroundColor3 = on and C.accent or C.panel
	button.TextColor3 = on and C.ink or C.cream
	button.BackgroundTransparency = on and 0 or 0.15
end

-- ===== Update tampilan =====
-- Tas hasil upgrade bisa sampai 20 slot: di atas 12 slot kotaknya dikecilin
-- supaya panel tas tidak melebar sampai nabrak tombol Lari/lompat di HP.
local COMPACT_SLOTS_ABOVE = 12

local function rebuildSlots()
	local max = player:GetAttribute("BagMax") or BASE_BAG_SLOTS
	local compact = max > COMPACT_SLOTS_ABOVE
	local slotSize = compact and 22 or 30
	local layout = slotRow:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, compact and 4 or 6)
	end
	for _, slot in slots do
		slot:Destroy()
	end
	table.clear(slots)
	for i = 1, max do
		slots[i] = make("Frame", {
			Name = "Slot" .. i,
			Size = UDim2.fromOffset(slotSize, slotSize),
			BackgroundColor3 = C.empty,
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = slotRow,
		}, { corner(8), stroke(C.cream, 2, 0.78) })
	end
end

local function refreshBag()
	local raw = player:GetAttribute("BagItems") or ""
	local ids = raw == "" and {} or string.split(raw, ",")
	local max = player:GetAttribute("BagMax") or BASE_BAG_SLOTS
	if #slots ~= max then
		rebuildSlots()
	end
	for i, slot in slots do
		local item = itemById[ids[i]]
		if item then
			slot.BackgroundColor3 = Config.Rarity[item.Rarity].Color
			slot.BackgroundTransparency = 0
		else
			slot.BackgroundColor3 = C.empty
			slot.BackgroundTransparency = 0.94
		end
	end
	bagLabel.Text = string.format("Tas %d/%d", #ids, max)
	bagLabel.TextColor3 = #ids >= max and C.gold or C.cream
end

-- Sebelum DataLoaded, angka yang masuk adalah data tersimpan (bukan hasil main),
-- jadi langsung dipasang tanpa animasi dan tanpa toast naik level.
local function isDataLoaded(): boolean
	return player:GetAttribute("DataLoaded") == true
end

local coinDisplay = Instance.new("NumberValue")
local function refreshCoins()
	local coins = player:GetAttribute("Coins") or 0
	if isDataLoaded() then
		tween(coinDisplay, 0.6, { Value = coins })
	else
		coinDisplay.Value = coins
	end
end

local function refreshJournalButton()
	local found = player:GetAttribute("JournalCount") or 0
	journalLabel.Text = string.format("Jurnal %d/%d%s", found, #Config.Items, journalHint)
end

local lastLevel = 1
local function refreshXP()
	-- Level dihitung langsung dari XP biar bar & label selalu cocok,
	-- walau attribute XP dan Level dari server nyampenya nggak barengan
	local xp = player:GetAttribute("XP") or 0
	local level, inLevel, need = Progression.levelProgress(xp)
	levelLabel.Text = "Lv " .. level
	xpLabel.Text = string.format("%d / %d XP", inLevel, need)
	tween(xpFill, 0.5, { Size = UDim2.fromScale(inLevel / need, 1) })
	if level > lastLevel and isDataLoaded() then
		local text = "Naik level! Sekarang Lv " .. level
		-- Zona yang syarat levelnya baru kesampaian
		for zone in Config.Zones do
			local minLevel = Progression.zoneMinLevel(zone)
			if minLevel > lastLevel and minLevel <= level then
				text ..= " · " .. Progression.zoneName(zone) .. " terbuka!"
			end
		end
		UIController.toast(text)
	end
	lastLevel = level
end

local function refreshZone(zone: number)
	zoneLabel.Text = string.format("Zona %d · %s", zone, Progression.zoneName(zone))
end

local function zoneLockedText(zone: number): string
	return string.format("%s terbuka di Lv %d", Progression.zoneName(zone), Progression.zoneMinLevel(zone))
end

-- Toast gelap: udah punya senter = suruh nyalain, belum punya = suruh beli
local function darkText(): string
	if NightController.hasHeadlamp() then
		return "Terlalu gelap. Nyalakan Senter untuk melihat item."
	end
	return string.format("Terlalu gelap. Beli %s di Pos Ranger untuk melihat item.", Config.Upgrades.Headlamp.Name)
end

local function refreshFrame()
	local stamina = player:GetAttribute("Stamina") or 1
	local exhausted = player:GetAttribute("Exhausted") == true
	staminaFill.Size = UDim2.fromScale(stamina, 1)
	staminaFill.BackgroundColor3 = exhausted and C.tired or C.stamina
	staminaValue.Text = math.floor(stamina * 100 + 0.5) .. "%"

	local t = Lighting.ClockTime
	local hours = math.floor(t)
	local minutes = math.floor((t - hours) * 60)
	local isDay = t >= Config.DayNight.DayStart and t < Config.DayNight.DayEnd
	timeLabel.Text = string.format("%s · %02d:%02d", isDay and "Siang" or "Malam", hours, minutes)
	sunIcon.Visible = isDay
	moonIcon.Visible = not isDay
	refreshRunButton()
end

local function updateScale(uiScale: UIScale)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local vp = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.75, 1.25)
end

-- ===== API publik =====
function UIController.toast(text: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toast.Visible = true
	tween(toast, 0.2, { GroupTransparency = 0 })
	task.delay(2.5, function()
		if token ~= toastToken then
			return
		end
		local t = tween(toast, 0.3, { GroupTransparency = 1 })
		t.Completed:Wait()
		if token == toastToken then
			toast.Visible = false
		end
	end)
end

function UIController.showItem(itemId: string, isNew: boolean)
	local item = itemById[itemId]
	if not item then
		return
	end
	local rarity = Config.Rarity[item.Rarity]

	popupToken += 1
	local token = popupToken
	popupTitle.Text = isNew and "Penemuan baru!" or "Nemu item!"
	popupRarity.Text = item.Rarity
	;(popupRarity.Parent :: Frame).BackgroundColor3 = RARITY_DEEP[item.Rarity] or C.ink
	popupStroke.Color = rarity.Color
	popupName.Text = item.Name
	local reward = string.format("%s · +%d Koin · +%d XP", item.Category, rarity.Coin, rarity.XP + (isNew and rarity.FirstXP or 0))
	popupReward.Text = reward

	popup.Visible = true
	popup.Position = UDim2.new(0.5, 0, 0, 46)
	popup.GroupTransparency = 1
	tween(popup, 0.3, { Position = UDim2.new(0.5, 0, 0, 70), GroupTransparency = 0 }, Enum.EasingStyle.Back)

	local hold = item.Rarity == "Legendary" and 4 or (item.Rarity == "Epic" and 3 or 1.8)
	task.delay(hold, function()
		if token ~= popupToken then
			return
		end
		local t = tween(popup, 0.3, { GroupTransparency = 1 })
		t.Completed:Wait()
		if token == popupToken then
			popup.Visible = false
		end
	end)
end

function UIController.start()
	gui = make("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local uiScale = make("UIScale", { Parent = gui })

	buildStaminaPanel()
	buildZonePill()
	local rightColumn = buildRightColumn()
	buildCoinPanel(rightColumn)
	buildJournalButton(rightColumn)
	buildBagPanel()
	buildPopup()
	buildToast()
	gui.Parent = player:WaitForChild("PlayerGui")
	buildRunButton()

	updateScale(uiScale)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateScale(uiScale)
	end)

	coinDisplay.Changed:Connect(function(value)
		coinLabel.Text = formatNumber(value)
	end)

	lastLevel = player:GetAttribute("Level") or 1
	rebuildSlots()
	refreshBag()
	refreshXP()
	refreshJournalButton()
	refreshZone(ZoneController.getZone())
	ZoneController.onZoneChanged(refreshZone)
	ZoneController.onGateBlocked(function(zone)
		UIController.toast(zoneLockedText(zone))
	end)
	NightController.onDarkWarning(function()
		UIController.toast(darkText())
	end)
	-- Senter di PC (F) & controller (Y). Tombol HP dibuat di buildRunButton.
	ContextActionService:BindAction("ToggleHeadlamp", function(_name, state, _input)
		if state == Enum.UserInputState.Begin then
			toggleHeadlamp()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
	coinDisplay.Value = player:GetAttribute("Coins") or 0
	coinLabel.Text = formatNumber(coinDisplay.Value)

	player:GetAttributeChangedSignal("BagItems"):Connect(refreshBag)
	player:GetAttributeChangedSignal("BagMax"):Connect(refreshBag)
	player:GetAttributeChangedSignal("Coins"):Connect(refreshCoins)
	player:GetAttributeChangedSignal("XP"):Connect(refreshXP)
	player:GetAttributeChangedSignal("Level"):Connect(refreshXP)
	player:GetAttributeChangedSignal("JournalCount"):Connect(refreshJournalButton)
	RunService.RenderStepped:Connect(refreshFrame)

	local notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")
	notify.OnClientEvent:Connect(function(kind: string, data, extra)
		if kind == "Collected" then
			UIController.showItem(data, extra == true)
		elseif kind == "BagFull" then
			UIController.toast("Tas penuh! Turun dan setor ke Pos Ranger")
		elseif kind == "BagEmpty" then
			UIController.toast("Tas masih kosong, cari item dulu")
		elseif kind == "ZoneLocked" then
			UIController.toast(zoneLockedText(data))
		elseif kind == "Debug" then
			UIController.toast("[Debug] " .. data)
		elseif kind == "NeedHeadlamp" then
			if NightController.hasHeadlamp() then
				UIController.toast(darkText())
			else
				UIController.toast(string.format("Terlalu gelap! %s butuh %s, beli di Pos Ranger", data, Config.Upgrades.Headlamp.Name))
			end
		elseif kind == "DataLoading" then
			UIController.toast("Data kamu masih dimuat, tunggu sebentar ya")
		elseif kind == "Deposited" then
			local text = string.format("Setor %d item: +%d Koin, +%d XP", data.count, data.coins, data.xp)
			if data.newFinds > 0 then
				text ..= string.format(" · %d penemuan baru", data.newFinds)
			end
			UIController.toast(text)
		end
	end)
end

return UIController
