-- Jurnal Ekspedisi: daftar semua item di Config.
-- Yang sudah pernah disetor tampil lengkap + jumlah setor; yang belum tampil sebagai siluet "???"
-- dengan petunjuk kapan munculnya. Datanya dari attribute "Journal" & "BagItems" (diisi server).
-- Buka/tutup: tombol Jurnal di HUD, tombol J (PC), Y (controller). Tutup juga pakai B / tap luar panel.
-- Kalau nanti item di Config dikasih field Icon = "rbxassetid://...", gambarnya otomatis dipakai
-- (dan dihitamkan jadi siluet kalau belum ditemukan).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UIKit = require(script.Parent.UIKit)
local ZoneController = require(script.Parent.ZoneController)
local GateController = require(script.Parent.GateController)

local C = UIKit.C
local RARITY_DEEP = UIKit.RARITY_DEEP
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label

local player = Players.LocalPlayer

local JournalController = {}

local CATEGORIES = { "Semua", "Flora", "Fauna", "Batuan", "Artefak" }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local TIME_HINT = {
	Any = "Muncul kapan saja",
	Day = "Muncul siang hari",
	Night = "Muncul malam hari",
}

local CARD_SIZE = Vector2.new(150, 164)
local HEADER_HEIGHT = 40
local TABS_HEIGHT = 34
local SECTION_GAP = 12
local SILHOUETTE = Color3.fromRGB(58, 66, 62)

-- Urutan tampil: zona, lalu rarity, lalu urutan di Config.
local sortedItems = table.clone(Config.Items)
do
	local configIndex = {}
	for i, item in Config.Items do
		configIndex[item.Id] = i
	end
	table.sort(sortedItems, function(a, b)
		if a.Zone ~= b.Zone then
			return a.Zone < b.Zone
		end
		local ra, rb = RARITY_RANK[a.Rarity] or 0, RARITY_RANK[b.Rarity] or 0
		if ra ~= rb then
			return ra < rb
		end
		return configIndex[a.Id] < configIndex[b.Id]
	end)
end

local modal: UIKit.Modal? = nil
local panel: Frame
local progressLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local cards = {} -- [itemId] = { frame, icon, image?, mark, name, rarityPill, rarity, info, hint, stroke }
local currentTab = "Semua"
local isOpen = false

-- ===== Baca data dari attribute =====
local function readJournal(): { [string]: number }
	local result = {}
	local raw = player:GetAttribute("Journal") or ""
	for _, entry in string.split(raw, ",") do
		local id, count = string.match(entry, "^([^=]+)=(%d+)$")
		if id then
			result[id] = tonumber(count) :: number
		end
	end
	return result
end

local function readBagSet(): { [string]: boolean }
	local result = {}
	local raw = player:GetAttribute("BagItems") or ""
	for _, id in string.split(raw, ",") do
		if id ~= "" then
			result[id] = true
		end
	end
	return result
end

-- ===== Bangun tampilan =====
local function buildCard(item, order: number)
	local frame = make("Frame", {
		Name = item.Id,
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, { corner(14), padding(10, 8) })
	local cardStroke = stroke(C.inkMuted, 2, 0.7)
	cardStroke.Parent = frame
	make("UIListLayout", {
		Padding = UDim.new(0, 5),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	local icon = make("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(48, 48),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local image: ImageLabel? = nil
	if type(item.Icon) == "string" and item.Icon ~= "" then
		image = make("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = item.Icon,
			ScaleType = Enum.ScaleType.Fit,
			Parent = icon,
		})
	end
	local mark = label({
		Text = "?",
		FontFace = FONT_TITLE,
		TextSize = 26,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})

	local name = label({
		Text = "???",
		FontFace = FONT_TITLE,
		TextSize = 16,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 2,
		Parent = frame,
	})

	local rarityPill = make("Frame", {
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 10) })
	local rarity = label({
		Text = "???",
		FontFace = FONT_TITLE,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = rarityPill,
	})

	local info = label({
		Text = string.format("%s · Zona %d", item.Category, item.Zone),
		FontFace = FONT_BODY_HEAVY,
		TextSize = 13,
		TextColor3 = C.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 4,
		Parent = frame,
	})

	local hint = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 14,
		TextColor3 = C.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 5,
		Parent = frame,
	})

	cards[item.Id] = {
		frame = frame,
		icon = icon,
		image = image,
		mark = mark,
		name = name,
		rarityPill = rarityPill,
		rarity = rarity,
		info = info,
		hint = hint,
		stroke = cardStroke,
	}
	return frame
end

local function refreshCard(item, count: number?, inBag: boolean)
	local card = cards[item.Id]
	local found = count ~= nil
	local rarityConfig = Config.Rarity[item.Rarity]

	card.frame.Visible = currentTab == "Semua" or currentTab == item.Category

	if found then
		card.icon.BackgroundColor3 = rarityConfig and rarityConfig.Color or C.inkMuted
		card.icon.BackgroundTransparency = if card.image then 0.6 else 0
		card.mark.Visible = false
		card.name.Text = item.Name
		card.rarity.Text = item.Rarity
		card.rarityPill.BackgroundColor3 = RARITY_DEEP[item.Rarity] or C.ink
		card.hint.Text = string.format("Disetor %dx", count :: number)
		card.hint.TextColor3 = C.ink
		card.stroke.Color = rarityConfig and rarityConfig.Color or C.inkMuted
		card.stroke.Transparency = 0
	else
		card.icon.BackgroundColor3 = SILHOUETTE
		card.icon.BackgroundTransparency = if card.image then 1 else 0
		card.mark.Visible = card.image == nil
		card.name.Text = "???"
		card.rarity.Text = "???"
		card.rarityPill.BackgroundColor3 = C.inkMuted
		if inBag then
			card.hint.Text = "Di tas, setor dulu!"
			card.hint.TextColor3 = C.accent
			card.stroke.Color = C.accent
			card.stroke.Transparency = 0
		elseif not ZoneController.isUnlocked(item.Zone) then
			card.hint.Text = "Butuh " .. GateController.missingText(item.Zone)
			card.hint.TextColor3 = C.inkMuted
			card.stroke.Color = C.inkMuted
			card.stroke.Transparency = 0.7
		elseif item.Time == "Night" and Config.Night.NightItemsNeedHeadlamp and (player:GetAttribute("HeadlampRange") or 0) <= 0 then
			card.hint.Text = "Malam · butuh Senter"
			card.hint.TextColor3 = C.inkMuted
			card.stroke.Color = C.inkMuted
			card.stroke.Transparency = 0.7
		else
			card.hint.Text = TIME_HINT[item.Time] or ""
			card.hint.TextColor3 = C.inkMuted
			card.stroke.Color = C.inkMuted
			card.stroke.Transparency = 0.7
		end
	end

	local image = card.image
	if image then
		-- Siluet: gambar dihitamkan sampai item ditemukan.
		image.ImageColor3 = if found then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		image.ImageTransparency = if found then 0 else 0.35
	end
end

local function refresh()
	if not modal then
		return
	end
	local journal = readJournal()
	local bag = readBagSet()

	local total, foundTotal = 0, 0
	local perCategory: { [string]: { found: number, total: number } } = {}
	for _, category in CATEGORIES do
		perCategory[category] = { found = 0, total = 0 }
	end

	for _, item in sortedItems do
		local count = journal[item.Id]
		refreshCard(item, count, bag[item.Id] == true)
		total += 1
		local bucket = perCategory[item.Category]
		if bucket then
			bucket.total += 1
		end
		if count then
			foundTotal += 1
			if bucket then
				bucket.found += 1
			end
		end
	end
	perCategory.Semua = { found = foundTotal, total = total }

	progressLabel.Text = string.format("%d/%d ditemukan", foundTotal, total)
	for category, button in tabButtons do
		local stats = perCategory[category]
		local selected = category == currentTab
		button.Text = string.format("%s %d/%d", category, stats.found, stats.total)
		button.BackgroundColor3 = selected and C.ink or C.cream
		button.TextColor3 = selected and C.cream or C.ink
	end
end

local function buildHeader()
	local header = make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		LayoutOrder = 1,
		Parent = panel,
	})
	-- Judul + progres disusun berjajar; tombol X sendiri nempel di kanan header.
	local titleGroup = make("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(HEADER_HEIGHT + 10), 1, 0),
		Parent = header,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = titleGroup,
	})
	label({
		Text = "Jurnal Ekspedisi",
		FontFace = FONT_TITLE,
		TextSize = 26,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = titleGroup,
	})
	progressLabel = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 17,
		TextColor3 = C.inkMuted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = titleGroup,
	})

	local close = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(HEADER_HEIGHT, HEADER_HEIGHT),
		BackgroundColor3 = C.ink,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = FONT_TITLE,
		Text = "X",
		TextColor3 = C.cream,
		TextSize = 20,
		Parent = header,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	close.Activated:Connect(function()
		JournalController.close()
	end)
end

local function buildTabs()
	local row = make("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, TABS_HEIGHT),
		LayoutOrder = 2,
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, category in CATEGORIES do
		local button = make("TextButton", {
			Name = category,
			Size = UDim2.fromOffset(0, TABS_HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.cream,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			FontFace = FONT_TITLE,
			Text = category,
			TextColor3 = C.ink,
			TextSize = 16,
			LayoutOrder = i,
			Parent = row,
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 14) })
		button.Activated:Connect(function()
			currentTab = category
			refresh()
		end)
		tabButtons[category] = button
	end
end

local function buildGrid()
	local grid = make("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + TABS_HEIGHT + SECTION_GAP * 2)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.inkMuted,
		LayoutOrder = 3,
		Parent = panel,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 10),
		Parent = grid,
	})
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, item in sortedItems do
		buildCard(item, i).Parent = grid
	end
end

local function build()
	modal = UIKit.createModal({
		name = "Journal",
		displayOrder = 10, -- di atas HUD dan kontrol sentuh
		maxSize = Vector2.new(820, 580),
		onBackdrop = function()
			JournalController.close()
		end,
	})
	panel = modal.panel
	make("UIListLayout", {
		Padding = UDim.new(0, SECTION_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	buildHeader()
	buildTabs()
	buildGrid()

	modal.mount(player:WaitForChild("PlayerGui"))
end

-- ===== Input =====
local function onToggleAction(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin then
		JournalController.toggle()
	end
	return Enum.ContextActionResult.Sink
end

local function onCloseAction(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin then
		JournalController.close()
	end
	return Enum.ContextActionResult.Sink
end

-- ===== API publik =====
function JournalController.isOpen(): boolean
	return isOpen
end

function JournalController.open()
	if isOpen or not modal then
		return
	end
	isOpen = true
	refresh()
	modal.show()
	-- Tombol B di controller buat nutup, cuma aktif selama jurnal terbuka.
	ContextActionService:BindAction("CloseJournal", onCloseAction, false, Enum.KeyCode.ButtonB)
end

function JournalController.close()
	if not isOpen then
		return
	end
	isOpen = false
	if modal then
		modal.hide()
	end
	ContextActionService:UnbindAction("CloseJournal")
end

function JournalController.toggle()
	if isOpen then
		JournalController.close()
	else
		JournalController.open()
	end
end

function JournalController.start()
	build()
	ContextActionService:BindAction("ToggleJournal", onToggleAction, false, Enum.KeyCode.J, Enum.KeyCode.ButtonY)

	local function refreshIfOpen()
		if isOpen then
			refresh()
		end
	end
	player:GetAttributeChangedSignal("Journal"):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal("BagItems"):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal("Level"):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal("HeadlampRange"):Connect(refreshIfOpen)
end

return JournalController
