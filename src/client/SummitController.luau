-- Layar "Puncak tercapai": kartu di tengah habis server ngabarin summit (Notify "Summit").
-- Hadiah udah dikasih server; di sini cuma nampilin hasilnya.
-- Tombol "Sembunyikan UI buat foto": semua HUD (punya kita + bawaan Roblox) disembunyikan sampai layar di-tap lagi,
-- kamera tetap bisa diputar (tap = sentuh/klik singkat tanpa geser).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local JournalController = require(script.Parent.JournalController)
local ShopController = require(script.Parent.ShopController)
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
local formatNumber = UIKit.formatNumber

local S = Config.Summit
local TAP_MAX_SECONDS = 0.35 -- sentuhan lebih lama dari ini = geser kamera, bukan tap
local TAP_MAX_MOVE = 12 -- piksel

local player = Players.LocalPlayer

local SummitController = {}

local modal: UIKit.Modal
local timeValue: TextLabel
local bagValue: TextLabel
local countValue: TextLabel
local rewardList: Frame
local isOpen = false

-- Mode foto
local photoMode = false
local photoHint: ScreenGui
local hiddenGuis: { ScreenGui } = {}
local hiddenCore: { Enum.CoreGuiType } = {}
local promptsWereEnabled = true
local tapStart: { [InputObject]: { pos: Vector3, t: number } } = {}

-- 754 detik -> "12:34", 3725 -> "1:02:05"
local function formatDuration(seconds: number?): string
	if not seconds then
		return "-"
	end
	local total = math.floor(seconds)
	local h, m, s = total // 3600, (total // 60) % 60, total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- ===== Bangun kartu =====
local function statTile(parent: Instance, caption: string, order: number): TextLabel
	local tile = make("Frame", {
		Name = caption,
		BackgroundColor3 = C.cream,
		BorderSizePixel = 0,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		LayoutOrder = order,
		Parent = parent,
	}, { corner(14), stroke(C.inkMuted, 2, 0.7), padding(8, 8) })
	make("UIListLayout", {
		Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tile,
	})
	label({
		Text = caption,
		FontFace = FONT_BODY_HEAVY,
		TextSize = 14,
		TextColor3 = C.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = tile,
	})
	return label({
		Text = "",
		FontFace = FONT_TITLE,
		TextSize = 24,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		Parent = tile,
	})
end

local function actionButton(parent: Instance, text: string, primary: boolean, order: number): TextButton
	return make("TextButton", {
		Name = text,
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = primary and C.accent or C.ink,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = FONT_TITLE,
		Text = text,
		TextColor3 = primary and C.ink or C.cream,
		TextSize = 17,
		LayoutOrder = order,
		Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
end

local function build()
	modal = UIKit.createModal({
		name = "Summit",
		displayOrder = 14, -- di atas Toko & Jurnal
		maxSize = Vector2.new(540, 440),
		onBackdrop = function() end, -- sengaja nggak nutup: tutupnya lewat "Lanjut"
	})
	local panel = modal.panel
	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = panel,
	})

	label({
		Text = "Puncak tercapai",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 16,
		TextColor3 = C.inkMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = panel,
	})
	label({
		Text = S.Name .. "!",
		FontFace = FONT_TITLE,
		TextSize = 36,
		TextColor3 = C.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 2,
		Parent = panel,
	})
	local elevationPill = make("Frame", {
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		LayoutOrder = 3,
		Parent = panel,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 16) })
	label({
		Text = formatNumber(S.Elevation) .. " mdpl",
		FontFace = FONT_TITLE,
		TextSize = 18,
		TextColor3 = C.gold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = elevationPill,
	})

	local stats = make("Frame", {
		Name = "Stats",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 74),
		LayoutOrder = 4,
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stats,
	})
	timeValue = statTile(stats, "Waktu mendaki", 1)
	bagValue = statTile(stats, "Isi tas", 2)
	countValue = statTile(stats, "Total summit", 3)

	rewardList = make("Frame", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = panel,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rewardList,
	})

	local buttons = make("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 6,
		Parent = panel,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttons,
	})
	actionButton(buttons, "Sembunyikan UI buat foto", false, 1).Activated:Connect(function()
		SummitController.enterPhotoMode()
	end)
	actionButton(buttons, "Lanjut", true, 2).Activated:Connect(function()
		SummitController.close()
	end)

	modal.mount(player:WaitForChild("PlayerGui"))
end

local function rewardLine(text: string, color: Color3, order: number)
	label({
		Text = text,
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
		Parent = rewardList,
	})
end

local function buildPhotoHint()
	photoHint = make("ScreenGui", {
		Name = "PhotoHint",
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Enabled = false,
	})
	local pill = make("CanvasGroup", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = photoHint,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), padding(0, 18) })
	label({
		Text = "Tap layar buat munculin UI lagi",
		FontFace = FONT_BODY_HEAVY,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = pill,
	})
	photoHint.Parent = player:WaitForChild("PlayerGui")
end

-- ===== Mode foto =====
function SummitController.enterPhotoMode()
	if photoMode then
		return
	end
	photoMode = true
	table.clear(tapStart)

	table.clear(hiddenGuis)
	for _, child in player:WaitForChild("PlayerGui"):GetChildren() do
		if child:IsA("ScreenGui") and child.Enabled and child ~= photoHint then
			child.Enabled = false
			table.insert(hiddenGuis, child)
		end
	end
	table.clear(hiddenCore)
	for _, coreType in Enum.CoreGuiType:GetEnumItems() do
		if coreType ~= Enum.CoreGuiType.All and StarterGui:GetCoreGuiEnabled(coreType) then
			table.insert(hiddenCore, coreType)
		end
	end
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	promptsWereEnabled = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false

	-- Petunjuk singkat, terus hilang biar nggak ikut kefoto
	local pill = photoHint:FindFirstChild("Hint") :: CanvasGroup
	pill.GroupTransparency = 0
	photoHint.Enabled = true
	task.delay(1.5, function()
		if photoMode then
			tween(pill, 0.5, { GroupTransparency = 1 }).Completed:Wait()
		end
		photoHint.Enabled = false
	end)
end

function SummitController.exitPhotoMode()
	if not photoMode then
		return
	end
	photoMode = false
	photoHint.Enabled = false
	for _, gui in hiddenGuis do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(hiddenGuis)
	for _, coreType in hiddenCore do
		StarterGui:SetCoreGuiEnabled(coreType, true)
	end
	table.clear(hiddenCore)
	ProximityPromptService.Enabled = promptsWereEnabled
end

local function isTapInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- ===== API publik =====
function SummitController.show(result)
	JournalController.close()
	ShopController.close()
	SummitController.exitPhotoMode()

	timeValue.Text = formatDuration(result.seconds)
	bagValue.Text = string.format("%d/%d", result.bag or 0, result.bagMax or 0)
	countValue.Text = formatNumber(result.count or 1) .. "x"

	for _, child in rewardList:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	if result.title then
		rewardLine("Title baru: " .. result.title, C.accent, 1)
	end
	if (result.xp or 0) > 0 then
		rewardLine(string.format("+%d XP", result.xp), C.success, 2)
	end
	if (result.coins or 0) > 0 then
		rewardLine(string.format("+%d Koin (bonus harian)", result.coins), C.success, 3)
	else
		rewardLine("Bonus Koin hari ini udah diambil, balik lagi besok", C.inkMuted, 3)
	end

	isOpen = true
	modal.show()
end

function SummitController.close()
	if not isOpen then
		return
	end
	isOpen = false
	SummitController.exitPhotoMode()
	modal.hide()
end

function SummitController.start()
	build()
	buildPhotoHint()

	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify").OnClientEvent:Connect(function(kind: string, data)
		if kind == "Summit" and type(data) == "table" then
			SummitController.show(data)
		end
	end)

	-- Tap (bukan geser kamera) atau tombol A di controller = keluar mode foto
	UserInputService.InputBegan:Connect(function(input)
		if not photoMode then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonA then
			SummitController.exitPhotoMode()
		elseif isTapInput(input) then
			tapStart[input] = { pos = input.Position, t = os.clock() }
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local start = tapStart[input]
		tapStart[input] = nil
		if not photoMode or not start then
			return
		end
		if os.clock() - start.t <= TAP_MAX_SECONDS and (input.Position - start.pos).Magnitude <= TAP_MAX_MOVE then
			SummitController.exitPhotoMode()
		end
	end)
end

return SummitController
