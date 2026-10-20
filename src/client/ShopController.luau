-- Toko upgrade gear di Pos Ranger. Dibuka lewat tombol "Upgrade" di Pos Ranger (server kirim "OpenShop").
-- Client cuma minta "beli X" lewat RemoteFunction BuyUpgrade; harga, koin, dan jarak divalidasi server.
-- Panel nutup sendiri kalau pemain jalan menjauh dari Pos Ranger.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local UIKit = require(script.Parent.UIKit)
local JournalController = require(script.Parent.JournalController)

local C = UIKit.C
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local corner = UIKit.corner
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label
local formatNumber = UIKit.formatNumber

local player = Players.LocalPlayer

local ShopController = {}

local HEADER_HEIGHT = 40
local STATUS_HEIGHT = 20
local SECTION_GAP = 12

local REASON_TEXT = {
	coins = "Koin kamu belum cukup",
	max = "Sudah tier maksimal",
	level = "Level kamu belum cukup",
	far = "Kejauhan dari Pos Ranger",
	loading = "Data kamu masih dimuat, tunggu sebentar ya",
	cooldown = "Pelan-pelan, tunggu sebentar",
	invalid = "Upgrade tidak dikenal",
	error = "Gagal nyambung ke server, coba lagi",
}

-- Urutan kartu sesuai Order di Config.
local sortedUpgrades = {}
for id, upgrade in Config.Upgrades do
	table.insert(sortedUpgrades, { id = id, upgrade = upgrade })
end
table.sort(sortedUpgrades, function(a, b)
	return (a.upgrade.Order or 0) < (b.upgrade.Order or 0)
end)

local modal: UIKit.Modal? = nil
local coinLabel: TextLabel
local statusLabel: TextLabel
local cards = {} -- [upgradeId] = { tier, dots, stat, nextStat, req, button }
local isOpen = false
local busy = false
local statusToken = 0
local postPart: BasePart? = nil
local distanceConnection: RBXScriptConnection? = nil
local buyRemote: RemoteFunction

local function getTier(upgradeId: string): number
	return player:GetAttribute("Upgrade_" .. upgradeId) or 1
end

local function setStatus(text: string, color: Color3)
	statusToken += 1
	local token = statusToken
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	task.delay(2.5, function()
		if token == statusToken then
			statusLabel.Text = ""
		end
	end)
end

-- ===== Update tampilan =====
local function refresh()
	if not modal then
		return
	end
	local coins = player:GetAttribute("Coins") or 0
	local level = player:GetAttribute("Level") or 1
	coinLabel.Text = formatNumber(coins)

	for _, entry in sortedUpgrades do
		local id, upgrade = entry.id, entry.upgrade
		local card = cards[id]
		local levels = upgrade.Levels
		local tier = math.clamp(getTier(id), 1, #levels)
		local nextLevel = levels[tier + 1]

		card.tier.Text = string.format("Tier %d/%d", tier, #levels)
		for i, dot in card.dots do
			dot.BackgroundColor3 = if i <= tier then C.accent else C.muted
		end
		-- Value 0 = gear-nya belum punya (contoh: tier 1 Senter Kepala)
		local value = levels[tier].Value
		card.stat.Text = if value == 0 then "Belum punya" else string.format("%s: %d", upgrade.Stat, value)

		local button: TextButton = card.button
		if not nextLevel then
			card.nextStat.Text = "Sudah paling mantap!"
			card.req.Visible = false
			button.Text = "MAX"
			button.BackgroundColor3 = C.success
			button.TextColor3 = C.cream
		else
			card.nextStat.Text = string.format("Berikutnya: %d", nextLevel.Value)
			local levelOk = not nextLevel.MinLevel or level >= nextLevel.MinLevel
			card.req.Visible = not levelOk
			card.req.Text = if nextLevel.MinLevel then string.format("Butuh Lv %d", nextLevel.MinLevel) else ""
			local canBuy = levelOk and coins >= nextLevel.Price
			button.Text = if busy then "..." else string.format("Beli · %s Koin", formatNumber(nextLevel.Price))
			button.BackgroundColor3 = if canBuy then C.accent else C.muted
			button.TextColor3 = if canBuy then C.ink else C.inkMuted
		end
	end
end

local function buy(upgradeId: string)
	if busy then
		return
	end
	local upgrade = Config.Upgrades[upgradeId]
	local newTier = getTier(upgradeId) + 1
	busy = true
	refresh()

	local ok, success, reason = pcall(function()
		return buyRemote:InvokeServer(upgradeId)
	end)
	busy = false
	if not ok then
		success, reason = false, "error"
	end

	if success then
		setStatus(string.format("%s naik ke Tier %d!", upgrade.Name, newTier), C.success)
	else
		setStatus(REASON_TEXT[reason] or REASON_TEXT.error, C.danger)
	end
	refresh()
end

-- ===== Bangun tampilan =====
local function buildHeader(panel: Frame)
	local header = make("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		LayoutOrder = 1,
		Parent = panel,
	})
	local titleGroup = make("Frame", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(HEADER_HEIGHT + 10), 1, 0),
		Parent = header,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = titleGroup,
	})
	label({
		Text = "Upgrade Gear",
		FontFace = FONT_TITLE,
		TextSize = 26,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = titleGroup,
	})
	-- Koin yang dimiliki, biar kelihatan cukup atau tidak.
	make("Frame", {
		Name = "CoinIcon",
		BackgroundColor3 = C.gold,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(18, 18),
		LayoutOrder = 2,
		Parent = titleGroup,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(Color3.fromRGB(176, 120, 30), 2, 0) })
	coinLabel = label({
		Text = "0",
		FontFace = FONT_TITLE,
		TextSize = 20,
		TextColor3 = C.ink,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 3,
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
		ShopController.close()
	end)
end

local function buildCard(parent: Frame, id: string, upgrade, order: number)
	local frame = make("Frame", {
		Name = id,
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
		Size = UDim2.new(1 / #sortedUpgrades, -8, 1, 0),
		LayoutOrder = order,
		Parent = parent,
	}, { corner(16), padding(14, 14), stroke(C.inkMuted, 2, 0.7) })
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	label({
		Text = upgrade.Name,
		FontFace = FONT_TITLE,
		TextSize = 22,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 1,
		Parent = frame,
	})
	local tier = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 15,
		TextColor3 = C.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = frame,
	})

	local dotRow = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 12),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 3,
		Parent = frame,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = dotRow,
	})
	local dots = {}
	for i = 1, #upgrade.Levels do
		dots[i] = make("Frame", {
			Size = UDim2.fromOffset(12, 12),
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = dotRow,
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end

	local stat = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 4,
		Parent = frame,
	})
	local nextStat = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 5,
		Parent = frame,
	})
	local req = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 15,
		TextColor3 = C.danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		Visible = false,
		LayoutOrder = 6,
		Parent = frame,
	})

	local button = make("TextButton", {
		Name = "Buy",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = FONT_TITLE,
		Text = "",
		TextColor3 = C.ink,
		TextSize = 18,
		LayoutOrder = 7,
		Parent = frame,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	button.Activated:Connect(function()
		buy(id)
	end)

	cards[id] = { tier = tier, dots = dots, stat = stat, nextStat = nextStat, req = req, button = button }
end

local function build()
	modal = UIKit.createModal({
		name = "Shop",
		displayOrder = 12, -- di atas Jurnal
		maxSize = Vector2.new(860, 380), -- 3 kartu sejajar
		onBackdrop = function()
			ShopController.close()
		end,
	})
	local panel = modal.panel
	make("UIListLayout", {
		Padding = UDim.new(0, SECTION_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	buildHeader(panel)

	local row = make("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + STATUS_HEIGHT + SECTION_GAP * 2)),
		LayoutOrder = 2,
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, entry in sortedUpgrades do
		buildCard(row, entry.id, entry.upgrade, i)
	end

	statusLabel = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, STATUS_HEIGHT),
		LayoutOrder = 3,
		Parent = panel,
	})

	modal.mount(player:WaitForChild("PlayerGui"))
end

-- Part Pos Ranger = parent dari tombol "Upgrade" yang dipasang server.
local function findPostPart(): BasePart?
	local post = workspace:FindFirstChild("PosRanger")
	local prompt = post and post:FindFirstChild("UpgradePrompt", true)
	local part = prompt and prompt.Parent
	return if part and part:IsA("BasePart") then part else nil
end

local function onCloseAction(_name: string, state: Enum.UserInputState, _input: InputObject)
	if state == Enum.UserInputState.Begin then
		ShopController.close()
	end
	return Enum.ContextActionResult.Sink
end

-- ===== API publik =====
function ShopController.open()
	if isOpen or not modal then
		return
	end
	JournalController.close()
	isOpen = true
	statusLabel.Text = ""
	refresh()
	modal.show()
	ContextActionService:BindAction("CloseShop", onCloseAction, false, Enum.KeyCode.ButtonB)

	-- Jalan menjauh dari Pos Ranger = toko nutup sendiri.
	postPart = findPostPart()
	distanceConnection = RunService.Heartbeat:Connect(function()
		local part = postPart
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if part and hrp and (hrp.Position - part.Position).Magnitude > Config.Shop.CloseDistance then
			ShopController.close()
		end
	end)
end

function ShopController.close()
	if not isOpen then
		return
	end
	isOpen = false
	if modal then
		modal.hide()
	end
	ContextActionService:UnbindAction("CloseShop")
	if distanceConnection then
		distanceConnection:Disconnect()
		distanceConnection = nil
	end
end

function ShopController.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	buyRemote = remotes:WaitForChild("BuyUpgrade") :: RemoteFunction
	build()

	remotes:WaitForChild("Notify").OnClientEvent:Connect(function(kind: string)
		if kind == "OpenShop" then
			ShopController.open()
		end
	end)

	local function refreshIfOpen()
		if isOpen then
			refresh()
		end
	end
	player:GetAttributeChangedSignal("Coins"):Connect(refreshIfOpen)
	player:GetAttributeChangedSignal("Level"):Connect(refreshIfOpen)
	for _, entry in sortedUpgrades do
		player:GetAttributeChangedSignal("Upgrade_" .. entry.id):Connect(refreshIfOpen)
	end
end

return ShopController
