-- Gaya dan helper UI yang dipakai bareng HUD (UIController) dan Jurnal (JournalController).
local TweenService = game:GetService("TweenService")

-- ===== Gaya =====
local C = {
	panel = Color3.fromRGB(18, 32, 26),
	cream = Color3.fromRGB(246, 235, 211),
	muted = Color3.fromRGB(207, 196, 172),
	ink = Color3.fromRGB(36, 48, 42),
	inkMuted = Color3.fromRGB(90, 101, 95),
	card = Color3.fromRGB(255, 248, 234),
	accent = Color3.fromRGB(232, 135, 58),
	stamina = Color3.fromRGB(123, 200, 106),
	tired = Color3.fromRGB(232, 96, 58),
	gold = Color3.fromRGB(242, 181, 68),
	empty = Color3.fromRGB(246, 235, 211),
	success = Color3.fromRGB(46, 125, 50), -- teks/tombol berhasil di atas latar krem
	danger = Color3.fromRGB(192, 72, 40), -- teks gagal di atas latar krem
}

-- Warna gelap untuk label rarity (teks putih tetap terbaca).
local RARITY_DEEP = {
	Common = Color3.fromRGB(95, 104, 100),
	Uncommon = Color3.fromRGB(46, 125, 50),
	Rare = Color3.fromRGB(44, 111, 184),
	Epic = Color3.fromRGB(123, 63, 181),
	Legendary = Color3.fromRGB(138, 97, 0),
}

local FONT_TITLE = Font.fromEnum(Enum.Font.FredokaOne)
local FONT_BODY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.Bold)
local FONT_BODY_HEAVY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.ExtraBold)

-- ===== Helper pembuat instance =====
local function make(className: string, props: { [string]: any }, children: { Instance }?)
	local inst = Instance.new(className)
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(radius: number)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color: Color3, thickness: number, transparency: number)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(vertical: number, horizontal: number)
	return make("UIPadding", {
		PaddingTop = UDim.new(0, vertical),
		PaddingBottom = UDim.new(0, vertical),
		PaddingLeft = UDim.new(0, horizontal),
		PaddingRight = UDim.new(0, horizontal),
	})
end

local function label(props: { [string]: any })
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = FONT_BODY,
		TextColor3 = C.cream,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults)
end

local function tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- 1250 -> "1.250"
local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if formatted:sub(1, 1) == "." then
		formatted = formatted:sub(2)
	end
	return formatted
end

-- Lingkaran hijau isi centang, atau merah isi silang (digambar pakai Frame, nggak butuh gambar/emoji).
-- Dipakai checklist gerbang & panel Misi.
local function statusIcon(met: boolean, size: number): Frame
	local icon = make("Frame", {
		Name = "Icon",
		BackgroundColor3 = met and C.stamina or C.tired,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local k = size / 22 -- digambar di ukuran 22, lalu diskalakan
	local function stick(width: number, x: number, y: number, rotation: number)
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x * k, y * k),
			Size = UDim2.fromOffset(width * k, math.max(2, 3 * k)),
			Rotation = rotation,
			Parent = icon,
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	if met then
		stick(7, 8, 12.5, 45)
		stick(12, 13, 10.5, -50)
	else
		stick(12, 11, 11, 45)
		stick(12, 11, 11, -45)
	end
	return icon
end

-- ===== Modal (Jurnal, Toko) =====
-- Panel di tengah layar + latar gelap. Latar sengaja di ScreenGui sendiri tanpa UIScale
-- dan tanpa inset, supaya selalu nutup satu layar penuh (termasuk topbar dan notch HP).
-- Tap di latar = onBackdrop(). Isi panel (layout dll.) diatur pemanggil.
export type Modal = {
	gui: ScreenGui,
	panel: Frame,
	show: () -> (),
	hide: () -> (),
	mount: (parent: Instance) -> (),
}

local function createModal(options: {
	name: string,
	displayOrder: number,
	maxSize: Vector2,
	onBackdrop: () -> (),
}): Modal
	local gui = make("ScreenGui", {
		Name = options.name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = options.displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	local uiScale = make("UIScale", { Parent = gui })

	local backdropGui = make("ScreenGui", {
		Name = options.name .. "Backdrop",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ClipToDeviceSafeArea = false,
		DisplayOrder = options.displayOrder - 1, -- tepat di bawah panelnya
		Enabled = false,
	})
	local backdrop = make("TextButton", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Parent = backdropGui,
	})
	backdrop.Activated:Connect(function()
		options.onBackdrop()
	end)

	local panel = make("Frame", {
		Name = "Panel",
		Active = true, -- tahan klik supaya tidak tembus ke Backdrop
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.92, 0.9),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		Parent = gui,
	}, {
		corner(20),
		padding(18, 20),
		stroke(C.ink, 3, 0.4),
		make("UISizeConstraint", { MaxSize = options.maxSize }),
	})

	local function updateScale()
		local camera = workspace.CurrentCamera
		if camera then
			local vp = camera.ViewportSize
			uiScale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.85, 1.25)
		end
	end
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	local modal = {} :: Modal
	modal.gui = gui
	modal.panel = panel
	function modal.show()
		backdropGui.Enabled = true
		gui.Enabled = true
		panel.Position = UDim2.new(0.5, 0, 0.5, 24)
		tween(panel, 0.25, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	end
	function modal.hide()
		gui.Enabled = false
		backdropGui.Enabled = false
	end
	function modal.mount(parent: Instance)
		backdropGui.Parent = parent
		gui.Parent = parent
	end
	return modal
end

return {
	C = C,
	RARITY_DEEP = RARITY_DEEP,
	FONT_TITLE = FONT_TITLE,
	FONT_BODY = FONT_BODY,
	FONT_BODY_HEAVY = FONT_BODY_HEAVY,
	make = make,
	corner = corner,
	stroke = stroke,
	padding = padding,
	label = label,
	tween = tween,
	formatNumber = formatNumber,
	statusIcon = statusIcon,
	createModal = createModal,
}
