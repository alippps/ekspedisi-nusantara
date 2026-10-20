-- Atur ukuran & posisi kotak zona (Workspace.Zones.ZoneN) otomatis dari titik spawn.
-- Cara pakai: Studio (JANGAN mode Play) > View > Command Bar > paste seluruh isi file ini > Enter.
-- Aman dijalankan berulang kali (misal habis nambah/mindahin titik spawn): kotak lama diperbarui.
-- File ini tidak disinkron Rojo (di luar folder src), cuma alat bantu.

local PAD_SIDE = 30 -- lebih lebar dari titik spawn terluar (stud) ke kiri/kanan/depan/belakang
local PAD_DOWN = 15 -- di bawah titik spawn terendah
local PAD_UP = 40 -- di atas titik spawn tertinggi (biar karakter yang lompat/manjat tetap kehitung)
local SHOW = 0.8 -- transparansi sementara biar kotaknya kelihatan; nanti jalankan hide_zones.lua

local COLORS = {
	Color3.fromRGB(90, 200, 90),
	Color3.fromRGB(80, 140, 230),
	Color3.fromRGB(230, 180, 60),
	Color3.fromRGB(200, 90, 200),
}

local spawnRoot = workspace:FindFirstChild("SpawnPoints")
if not spawnRoot then
	warn("[fit_zones] Folder Workspace.SpawnPoints tidak ada")
	return
end

local zones = workspace:FindFirstChild("Zones")
if not zones then
	zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = workspace
end

for _, zoneFolder in spawnRoot:GetChildren() do
	local n = tonumber(string.match(zoneFolder.Name, "^Zone(%d+)$"))
	if n then
		local points = {}
		for _, d in zoneFolder:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(points, d.Position)
			end
		end
		-- Pos Ranger ikut masuk Zona 1
		if n == 1 then
			local post = workspace:FindFirstChild("PosRanger")
			local part = post and (post:IsA("BasePart") and post or post:FindFirstChildWhichIsA("BasePart", true))
			if part then
				table.insert(points, part.Position)
			end
		end

		local existing = zones:FindFirstChild(zoneFolder.Name)
		if #points == 0 then
			warn("[fit_zones] " .. zoneFolder.Name .. " belum punya titik spawn, dilewati")
		elseif existing and not existing:IsA("BasePart") then
			warn("[fit_zones] Zones." .. zoneFolder.Name .. " bukan Part (Model/Folder?), tidak diubah")
		else
			local minV = Vector3.new(math.huge, math.huge, math.huge)
			local maxV = -minV
			for _, p in points do
				minV = minV:Min(p)
				maxV = maxV:Max(p)
			end
			minV -= Vector3.new(PAD_SIDE, PAD_DOWN, PAD_SIDE)
			maxV += Vector3.new(PAD_SIDE, PAD_UP, PAD_SIDE)

			local box = existing or Instance.new("Part")
			box.Name = zoneFolder.Name
			box.Anchored = true
			box.CanCollide = false
			box.CanTouch = false
			box.CanQuery = false
			box.CastShadow = false
			box.Material = Enum.Material.SmoothPlastic
			box.Color = COLORS[(n - 1) % #COLORS + 1]
			box.Transparency = SHOW
			box.Size = maxV - minV
			box.CFrame = CFrame.new((minV + maxV) / 2)
			box.Parent = zones
			print(string.format("[fit_zones] %s: %d titik, ukuran %d x %d x %d", box.Name, #points, math.floor(box.Size.X), math.floor(box.Size.Y), math.floor(box.Size.Z)))
		end
	end
end

print("[fit_zones] Selesai. Cek kotaknya, kalau sudah pas jalankan hide_zones.lua")
