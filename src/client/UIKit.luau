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
}
