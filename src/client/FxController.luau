-- Efek & poles UI (tampilan aja, nggak ngubah aturan game):
-- * Intro logo pas masuk game, lalu fade ke HUD
-- * Banner nama zona di tengah atas tiap pindah zona
-- * Banner besar (naik level, zona terbuka) dengan kilau + konfeti, antre satu-satu biar nggak numpuk
-- * Koin terbang ke panel koin, kilau di kartu, denyut angka
-- * Semua tombol membesar pas disentuh/hover, mengecil pas ditekan
-- * Efek suara pendek (ID di Config.Sounds)
-- Ringan buat HP: cuma Tween + beberapa Frame kecil yang langsung dihapus, konfeti dikurangi di layar sentuh.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))
local ZoneController = require(script.Parent.ZoneController)
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

local player = Players.LocalPlayer

local FxController = {}

-- Tombol di ScreenGui ini yang dapat efek membesar/mengecil (punya Roblox seperti TouchGui nggak disentuh)
local BOUNCE_GUIS = { HUD = true, TouchControls = true, Journal = true, Shop = true, Summit = true }
local CONFETTI_COLORS = { C.gold, C.accent, C.stamina, Color3.fromRGB(110, 170, 235), C.cream }
local ZONE_BANNER_SECONDS = 2
local ZONE_BANNER_REPEAT = 10 -- detik: zona yang sama nggak diumumkan lagi kalau bolak-balik di perbatasan
local INTRO_MAX_SECONDS = 6 -- intro nunggu data dimuat, tapi paling lama segini
local IS_TOUCH = UserInputService.TouchEnabled

local fxGui: ScreenGui -- pakai UIScale (banner)
local absGui: ScreenGui -- tanpa UIScale (koin terbang & konfeti, pakai posisi layar asli)
local sounds: { [string]: Sound } = {}

local banner: CanvasGroup
local bannerTitle: TextLabel
local bannerSubtitle: TextLabel
local bannerBody: TextLabel
local bannerStroke: UIStroke
local bannerQueue = {}
local bannerBusy = false

local zoneBanner: CanvasGroup
local zoneBannerEyebrow: TextLabel
local zoneBannerName: TextLabel
local zoneBannerToken = 0
local lastZoneShown: { [number]: number } = {}
local introDone = false

local function screenScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local vp = camera.ViewportSize
	return math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.75, 1.25)
end

local function bindScale(gui: ScreenGui)
	local uiScale = make("UIScale", { Parent = gui })
	local function update()
		uiScale.Scale = screenScale()
	end
	update()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
end

-- UIScale khusus efek (satu per objek, dipakai bareng denyut & tombol)
local function fxScale(target: GuiObject): UIScale
	local scale = target:FindFirstChild("FxScale") :: UIScale?
	if not scale then
		scale = make("UIScale", { Name = "FxScale", Parent = target })
	end
	return scale :: UIScale
end

-- ===== Suara =====
function FxController.play(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

local function loadSounds()
	for name, id in Config.Sounds do
		if type(id) == "string" and id ~= "" then
			sounds[name] = make("Sound", {
				Name = "Fx_" .. name,
				SoundId = id,
				Volume = Config.Sounds.Volume,
				Parent = SoundService,
			})
		end
	end
end

-- ===== Efek kecil =====
-- Objek membesar sebentar lalu balik (buat ikon, panel, popup)
function FxController.pulse(target: GuiObject, peak: number?)
	local scale = fxScale(target)
	scale.Scale = peak or 1.2
	tween(scale, 0.3, { Scale = 1 })
end

-- Angka berdenyut: TextSize naik sebentar + kedip warna (label rata kiri tetap di tempat)
function FxController.pulseText(target: TextLabel, color: Color3?)
	local base = target:GetAttribute("FxBaseSize") or target.TextSize
	local baseColor = target:GetAttribute("FxBaseColor") or target.TextColor3
	target:SetAttribute("FxBaseSize", base)
	target:SetAttribute("FxBaseColor", baseColor)
	target.TextSize = base * 1.25
	target.TextColor3 = color or C.gold
	tween(target, 0.35, { TextSize = base, TextColor3 = baseColor })
end

-- Garis kilau lewat dari kiri ke kanan. container harus CanvasGroup (biar kilaunya kepotong rapi di sudut)
-- dan nggak punya UIListLayout langsung di dalamnya.
function FxController.shine(container: GuiObject, times: number?, color: Color3?)
	task.spawn(function()
		for i = 1, times or 1 do
			if not container.Parent then
				return
			end
			local bar = make("Frame", {
				Name = "Shine",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(-0.25, 0.5),
				Size = UDim2.new(0, 60, 3, 0),
				Rotation = 20,
				BackgroundColor3 = color or Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 50,
				Parent = container,
			}, {
				make("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0.35),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			})
			tween(bar, 0.6, { Position = UDim2.fromScale(1.25, 0.5) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut).Completed:Wait()
			bar:Destroy()
			if i < (times or 1) then
				task.wait(0.12)
			end
		end
	end)
end

-- Konfeti kecil meledak dari titik layar (piksel asli), lalu jatuh & memudar
function FxController.confetti(origin: Vector2, count: number, colors: { Color3 }?)
	local palette = colors or CONFETTI_COLORS
	local scale = screenScale()
	local n = math.max(4, math.floor(count * (IS_TOUCH and 0.6 or 1)))
	for _ = 1, n do
		local piece = make("Frame", {
			Name = "Confetti",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(origin.X, origin.Y),
			Size = UDim2.fromOffset(math.random(6, 9) * scale, math.random(10, 14) * scale),
			Rotation = math.random(0, 360),
			BackgroundColor3 = palette[math.random(1, #palette)],
			BorderSizePixel = 0,
			Parent = absGui,
		})
		local angle = math.rad(math.random(200, 340)) -- ke atas, nyebar kiri-kanan
		local speed = math.random(90, 190) * scale
		local peak = origin + Vector2.new(math.cos(angle), math.sin(angle)) * speed
		local fall = peak + Vector2.new(math.random(-30, 30) * scale, math.random(110, 190) * scale)
		task.spawn(function()
			tween(piece, 0.35, { Position = UDim2.fromOffset(peak.X, peak.Y) }).Completed:Wait()
			tween(piece, 0.9, {
				Position = UDim2.fromOffset(fall.X, fall.Y),
				Rotation = piece.Rotation + math.random(-240, 240),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			piece:Destroy()
		end)
	end
end

local function centerOf(target: GuiObject): Vector2
	return target.AbsolutePosition + target.AbsoluteSize / 2
end

-- Koin terbang dari tengah layar ke `target` (ikon koin di HUD). onArrive dipanggil tiap koin nyampe.
function FxController.flyCoins(target: GuiObject, amount: number, onArrive: (() -> ())?)
	local scale = screenScale()
	local count = math.clamp(math.ceil(amount / 15), 3, IS_TOUCH and 7 or 10)
	local from = absGui.AbsoluteSize / 2
	for i = 1, count do
		task.delay((i - 1) * 0.06, function()
			local size = 22 * scale
			local coin = make("Frame", {
				Name = "FlyingCoin",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(from.X, from.Y),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = C.gold,
				BorderSizePixel = 0,
				Parent = absGui,
			}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(Color3.fromRGB(176, 120, 30), 2, 0) })
			-- Nyebar dikit dulu, baru meluncur ke panel koin
			local angle = math.rad(math.random(0, 359))
			local spread = from + Vector2.new(math.cos(angle), math.sin(angle)) * math.random(30, 70) * scale
			tween(coin, 0.18, { Position = UDim2.fromOffset(spread.X, spread.Y) }).Completed:Wait()
			local to = centerOf(target)
			tween(coin, 0.45, {
				Position = UDim2.fromOffset(to.X, to.Y),
				Size = UDim2.fromOffset(size * 0.7, size * 0.7),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Wait()
			coin:Destroy()
			FxController.pulse(target, 1.3)
			if onArrive then
				onArrive()
			end
		end)
	end
end

-- ===== Tombol =====
local function isTapInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function attachBounce(button: GuiButton)
	if button.Name == "Backdrop" or button:FindFirstChild("FxScale") then
		return
	end
	local scale = fxScale(button)
	local hovered, pressed = false, false
	local function settle()
		tween(scale, 0.12, { Scale = if pressed then 0.93 elseif hovered then 1.05 else 1 })
	end
	button.MouseEnter:Connect(function()
		hovered = true
		settle()
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		settle()
	end)
	button.InputBegan:Connect(function(input)
		if isTapInput(input) then
			pressed = true
			settle()
		end
	end)
	button.InputEnded:Connect(function(input)
		if not isTapInput(input) then
			return
		end
		pressed = false
		if input.UserInputType == Enum.UserInputType.Touch then
			hovered = false -- di HP nggak ada hover: lepas = mantul dikit lalu normal
			scale.Scale = 1.06
		end
		settle()
	end)
end

local function watchButtons(playerGui: PlayerGui)
	local function consider(inst: Instance)
		if inst:IsA("GuiButton") then
			local screen = inst:FindFirstAncestorOfClass("ScreenGui")
			if screen and BOUNCE_GUIS[screen.Name] then
				attachBounce(inst)
			end
		end
	end
	for _, inst in playerGui:GetDescendants() do
		consider(inst)
	end
	playerGui.DescendantAdded:Connect(consider)
end

-- ===== Banner besar (antre) =====
local function buildBanner()
	-- CanvasGroup: kilau kepotong rapi di sudut membulat
	banner = make("CanvasGroup", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		Parent = fxGui,
	}, { corner(18) })
	bannerStroke = stroke(C.gold, 3, 0)
	bannerStroke.Parent = banner
	local content = make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = banner,
	}, { padding(16, 22) })
	make("UIListLayout", {
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = content,
	})
	bannerTitle = label({
		FontFace = FONT_TITLE,
		TextSize = 30,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 1,
		Parent = content,
	})
	bannerSubtitle = label({
		FontFace = FONT_TITLE,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		Parent = content,
	})
	bannerBody = label({
		TextSize = 17,
		TextColor3 = C.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = content,
	})
end

export type BannerOptions = {
	title: string,
	subtitle: string,
	body: string?,
	accent: Color3?,
	sound: string?,
	confetti: number?,
	seconds: number,
}

local function showBanner(options: BannerOptions)
	local accent = options.accent or C.gold
	bannerTitle.Text = options.title
	bannerTitle.TextColor3 = accent
	bannerStroke.Color = accent
	bannerSubtitle.Text = options.subtitle
	bannerBody.Text = options.body or ""
	bannerBody.Visible = options.body ~= nil

	banner.Visible = true
	banner.Position = UDim2.fromScale(0.5, 0.26)
	banner.GroupTransparency = 1
	if options.sound then
		FxController.play(options.sound)
	end
	tween(banner, 0.35, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.3) }, Enum.EasingStyle.Back).Completed:Wait()
	FxController.shine(banner, 2)
	if options.confetti then
		FxController.confetti(centerOf(banner), options.confetti)
	end
	task.wait(options.seconds)
	tween(banner, 0.4, { GroupTransparency = 1 }).Completed:Wait()
	banner.Visible = false
end

local function runBanners()
	if bannerBusy then
		return
	end
	bannerBusy = true
	while #bannerQueue > 0 do
		showBanner(table.remove(bannerQueue, 1))
	end
	bannerBusy = false
end

-- Banner besar di tengah atas. Kalau ada yang lagi tampil, nunggu giliran.
function FxController.banner(options: BannerOptions)
	table.insert(bannerQueue, options)
	task.spawn(runBanners)
end

function FxController.levelUp(level: number)
	FxController.banner({
		title = "Naik level!",
		subtitle = "Sekarang Lv " .. level,
		sound = "LevelUp",
		confetti = 24,
		seconds = 2,
	})
end

-- ===== Banner masuk zona =====
local function buildZoneBanner()
	zoneBanner = make("CanvasGroup", {
		Name = "ZoneEnter",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 72),
		Size = UDim2.fromOffset(700, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = fxGui,
	}, { padding(4, 4) })
	make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = zoneBanner })
	zoneBannerEyebrow = label({
		FontFace = FONT_BODY_HEAVY,
		TextSize = 18,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = zoneBanner,
	})
	make("UIStroke", { Color = C.panel, Thickness = 2, Transparency = 0.3, Parent = zoneBannerEyebrow })
	zoneBannerName = label({
		FontFace = FONT_TITLE,
		TextSize = 46,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 52),
		LayoutOrder = 2,
		Parent = zoneBanner,
	})
	-- Garis pinggir teks gelap biar kebaca di langit terang maupun malam
	make("UIStroke", { Color = C.panel, Thickness = 3, Transparency = 0.2, Parent = zoneBannerName })
end

function FxController.zoneEnter(zone: number)
	zoneBannerToken += 1
	local token = zoneBannerToken
	lastZoneShown[zone] = os.clock()
	zoneBannerEyebrow.Text = string.format("ZONA %d", zone)
	zoneBannerName.Text = Progression.zoneName(zone)
	zoneBanner.Visible = true
	zoneBanner.Position = UDim2.new(0.5, 0, 0, 60)
	zoneBanner.GroupTransparency = 1
	tween(zoneBanner, 0.35, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 72) })
	task.delay(ZONE_BANNER_SECONDS, function()
		if token ~= zoneBannerToken then
			return
		end
		tween(zoneBanner, 0.6, { GroupTransparency = 1 }).Completed:Wait()
		if token == zoneBannerToken then
			zoneBanner.Visible = false
		end
	end)
end

local function onZoneChanged(zone: number)
	if not introDone then
		return -- habis intro zona sekarang diumumkan sekali
	end
	local last = lastZoneShown[zone]
	if last and os.clock() - last < ZONE_BANNER_REPEAT then
		return
	end
	FxController.zoneEnter(zone)
end

-- ===== Intro =====
-- Satu baris huruf yang muncul satu-satu (naik + pop)
local function letterRow(parent: Instance, text: string, size: number, color: Color3, gap: number, order: number)
	local row = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, size + 8),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
	})
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local letters = {}
	for i = 1, #text do
		local cell = make("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, size + 8),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
			Parent = row,
		})
		letters[i] = label({
			Text = string.sub(text, i, i),
			FontFace = FONT_TITLE,
			TextSize = size,
			TextColor3 = color,
			TextTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, size + 8),
			Position = UDim2.fromOffset(0, 24),
			Parent = cell,
		})
	end
	return letters
end

local function playIntro()
	local intro = make("ScreenGui", {
		Name = "Intro",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 50,
	})
	bindScale(intro)
	local background = make("Frame", {
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = intro,
	})
	local center = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(900, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = intro,
	})
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = center,
	})
	-- Logo nama game, lalu nama dunia kecil di bawahnya
	local top = letterRow(center, "HIKE & COLLECT", 68, C.cream, 2, 1)
	local bottom = letterRow(center, "EKSPEDISI NUSANTARA", 22, C.gold, 5, 2)
	local underline = make("Frame", {
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 4),
		LayoutOrder = 3,
		Parent = center,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local tagline = label({
		Text = "Jelajahi gunung, isi Jurnal Ekspedisi",
		TextSize = 18,
		TextColor3 = C.muted,
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(600, 30),
		LayoutOrder = 4,
		Parent = center,
	})
	intro.Parent = player:WaitForChild("PlayerGui")

	local started = os.clock()
	for i, letter in top do
		task.delay(0.15 + i * 0.04, function()
			tween(letter, 0.45, { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		end)
	end
	for i, letter in bottom do
		task.delay(0.65 + i * 0.02, function()
			tween(letter, 0.35, { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		end)
	end
	task.delay(1.1, function()
		tween(underline, 0.4, { Size = UDim2.fromOffset(320, 4) })
		tween(tagline, 0.4, { TextTransparency = 0 })
	end)

	-- Minimal sampai animasi logo selesai, lalu tunggu data (biar HUD udah angka asli), maksimal INTRO_MAX_SECONDS
	task.wait(1.9)
	while player:GetAttribute("DataLoaded") ~= true and os.clock() - started < INTRO_MAX_SECONDS do
		task.wait(0.1)
	end

	tween(background, 0.6, { BackgroundTransparency = 1 })
	tween(underline, 0.4, { BackgroundTransparency = 1 })
	tween(tagline, 0.4, { TextTransparency = 1 })
	for _, letter in top do
		tween(letter, 0.4, { TextTransparency = 1 })
	end
	for _, letter in bottom do
		tween(letter, 0.4, { TextTransparency = 1 })
	end
	task.wait(0.6)
	intro:Destroy()

	introDone = true
	FxController.zoneEnter(ZoneController.getZone())
end

function FxController.start()
	local playerGui = player:WaitForChild("PlayerGui")
	fxGui = make("ScreenGui", {
		Name = "Fx",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 5, -- di atas HUD, di bawah Jurnal/Toko
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	bindScale(fxGui)
	-- IgnoreGuiInset sama dengan HUD, jadi AbsolutePosition panel koin bisa langsung dipakai
	absGui = make("ScreenGui", {
		Name = "FxScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	buildBanner()
	buildZoneBanner()
	fxGui.Parent = playerGui
	absGui.Parent = playerGui

	loadSounds()
	watchButtons(playerGui)
	ZoneController.onZoneChanged(onZoneChanged)
	task.spawn(playIntro)
end

return FxController
