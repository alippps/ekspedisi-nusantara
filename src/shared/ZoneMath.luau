--!strict
-- Rumus posisi vs Part (boleh miring) yang dipakai bareng server & client:
-- titik di dalam kotak, jarak ke kotak, zona di suatu titik, dan safe zone.
-- Map: Workspace.Zones/ZoneN (kotak per zona), Part ber-Tag Config.Events.SafeZoneTag (attribute Zone).
local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)

local ZoneMath = {}

-- Part-part milik satu instance (dirinya sendiri kalau Part, atau semua Part di dalamnya)
function ZoneMath.partsOf(instance: Instance): { BasePart }
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- Titik di dalam kotak (cframe, size)? Dipakai juga buat kotak yang cuma dikenal dari data (client, safe zone).
function ZoneMath.containsBox(cframe: CFrame, size: Vector3, point: Vector3): boolean
	local relative = cframe:PointToObjectSpace(point)
	local half = size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

function ZoneMath.contains(part: BasePart, point: Vector3): boolean
	return ZoneMath.containsBox(part.CFrame, part.Size, point)
end

-- Jarak titik ke permukaan Part (0 kalau di dalam)
function ZoneMath.distanceTo(part: BasePart, point: Vector3): number
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(relative.X, -half.X, half.X),
		math.clamp(relative.Y, -half.Y, half.Y),
		math.clamp(relative.Z, -half.Z, half.Z)
	)
	return (relative - clamped).Magnitude
end

-- Nomor zona di titik ini dari Workspace.Zones, atau nil (di luar semua kotak / map belum ada).
-- Kalau kotak zona tumpang tindih, nomor zona paling besar yang menang.
function ZoneMath.zoneAt(point: Vector3): number?
	local folder = workspace:FindFirstChild("Zones")
	if not folder then
		return nil
	end
	local found: number? = nil
	for _, child in folder:GetChildren() do
		local zone = tonumber(string.match(child.Name, "^Zone(%d+)$"))
		if zone and (not found or zone > found) then
			for _, part in ZoneMath.partsOf(child) do
				if ZoneMath.contains(part, point) then
					found = zone
					break
				end
			end
		end
	end
	return found
end

-- Titik di dalam safe zone mana pun? Baca Part ber-Tag langsung, jadi cuma akurat di server
-- (di client part-nya bisa belum ke-stream; client pakai ReplicatedStorage.SafeZoneList).
function ZoneMath.inSafeZone(point: Vector3): boolean
	for _, instance in CollectionService:GetTagged(Config.Events.SafeZoneTag) do
		if instance:IsA("BasePart") and ZoneMath.contains(instance, point) then
			return true
		end
	end
	return false
end

return ZoneMath
