-- Sembunyikan kotak zona setelah ukurannya pas. Paste di Command Bar Studio (bukan mode Play) > Enter.
local zones = workspace:FindFirstChild("Zones")
if zones then
	for _, d in zones:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		end
	end
	print("[hide_zones] Kotak zona disembunyikan")
end
