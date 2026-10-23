-- Penanda arah ke satu titik di dunia: papan di atas titiknya (kelihatan tembus tembok)
-- + panah di pinggir layar kalau titiknya lagi di luar layar.
-- Dipakai MissionController (ke Pos Ranger) dan EventController (ke safe zone).
-- Cara pakai: local wp = Waypoint.create("Nama", warna); tiap frame wp.show(posisi, judul, jarak) atau wp.hide().
local Players = game:GetService("Players")

local UIKit = require(script.Parent.UIKit)

local C = UIKit.C
local FONT_TITLE = UIKit.FONT_TITLE
local FONT_BODY_HEAVY = UIKit.FONT_BODY_HEAVY
local make = UIKit.make
local stroke = UIKit.stroke
local padding = UIKit.padding
local label = UIKit.label

local EDGE_MARGIN = 56 -- jarak panah dari pinggir layar (piksel)

local player = Players.LocalPlayer

local Waypoint = {}

export type Waypoint = {
	show: (position: Vector3, title: string, distance: number) -> (),
	hide: () -> (),
}

function Waypoint.create(name: string, color: Color3): Waypoint
	local playerGui = player:WaitForChild("PlayerGui")

	-- Papan di atas titik, kelihatan tembus tembok
	local markerGui = make("BillboardGui", {
		Name = name .. "Marker",
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
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(color, 2, 0), padding(0, 14) })
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pill,
	})
	local titleLabel = label({
		Text = "",
		FontFace = FONT_TITLE,
		TextSize = 17,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 1,
		Parent = pill,
	})
	local distanceLabel = label({
		Text = "",
		FontFace = FONT_BODY_HEAVY,
		TextSize = 15,
		TextColor3 = color,
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
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = markerGui,
	})
	markerGui.Parent = playerGui
	-- Part lokal tak terlihat di posisi titik (Model aslinya bisa belum ke-stream)
	local anchor = make("Part", {
		Name = name .. "MarkerAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		Parent = workspace,
	})
	markerGui.Adornee = anchor

	-- Panah di pinggir layar (tanpa UIScale, pakai piksel layar asli)
	local edgeGui = make("ScreenGui", {
		Name = name .. "Waypoint",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
	})
	local edgeArrow = make("Frame", {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = edgeGui,
	}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke(color, 2, 0) })
	-- Chevron ">" dari dua batang; seluruh lingkaran diputar ke arah titik
	for _, rotation in { 40, -40 } do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(24, 22 + (if rotation > 0 then -5 else 5)),
			Size = UDim2.fromOffset(16, 4),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = edgeArrow,
		}, { make("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	edgeGui.Parent = playerGui

	local waypoint = {} :: Waypoint

	function waypoint.hide()
		markerGui.Enabled = false
		edgeGui.Enabled = false
	end

	function waypoint.show(position: Vector3, title: string, distance: number)
		local camera = workspace.CurrentCamera
		if not camera then
			waypoint.hide()
			return
		end
		anchor.Position = position
		markerGui.Enabled = true
		titleLabel.Text = title
		distanceLabel.Text = string.format("%dm", math.floor(distance))

		local point, inFront = camera:WorldToViewportPoint(position)
		local vp = camera.ViewportSize
		local onScreen = inFront and point.X >= 0 and point.X <= vp.X and point.Y >= 0 and point.Y <= vp.Y
		edgeGui.Enabled = not onScreen
		if onScreen then
			return
		end
		-- Arah dari tengah layar ke titik (kalau di belakang kamera, arahnya dibalik)
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

	return waypoint
end

return Waypoint
