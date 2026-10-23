-- Cek struktur map (graybox) cocok sama yang dibutuhkan kode: zona, titik spawn, gerbang, semua Pos Ranger, puncak.
-- Cara pakai: Studio (JANGAN mode Play) > View > Command Bar > paste seluruh isi file ini > Enter. Lihat Output.
-- Cuma baca, nggak ngubah apa pun di map. File ini tidak disinkron Rojo (di luar folder src), cuma alat bantu.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local errors, warnings = 0, 0
local function ok(msg)
	print("  OK    " .. msg)
end
local function warnMsg(msg)
	warnings += 1
	warn("  CEK   " .. msg)
end
local function err(msg)
	errors += 1
	warn("  ERROR " .. msg)
end

local function partsOf(inst)
	local parts = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function contains(part, point)
	local rel = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

local function inZone(zoneInst, point)
	for _, p in partsOf(zoneInst) do
		if contains(p, point) then
			return true
		end
	end
	return false
end

local zoneCount = #Config.Zones
print(string.format("[check_map] Cek map buat %d zona...", zoneCount))

-- ===== Zones =====
print("Zones")
local zones = workspace:FindFirstChild("Zones")
if not zones then
	err("Folder Workspace.Zones nggak ada")
else
	for i = 1, zoneCount do
		local z = zones:FindFirstChild("Zone" .. i)
		if not z then
			err("Zones/Zone" .. i .. " nggak ada")
		else
			local parts = partsOf(z)
			if #parts == 0 then
				err("Zones/Zone" .. i .. " nggak punya Part")
			else
				local solid = 0
				for _, p in parts do
					if p.CanCollide then
						solid += 1
					end
				end
				if solid > 0 then
					err(string.format("Zones/Zone%d: %d part masih CanCollide (pemain bakal nabrak kotak zona)", i, solid))
				else
					ok(string.format("Zones/Zone%d (%d part)", i, #parts))
				end
			end
		end
	end
end

-- Map BuildGunung: zona ditumpuk berdasarkan ketinggian (Zone1 paling bawah). Cek rentang Y tiap zona & celahnya.
-- Batas Y dunia satu Part (ikut rotasi)
local function yRange(p)
	local cf, size = p.CFrame, p.Size
	local half = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
	return p.Position.Y - half, p.Position.Y + half
end
if zones then
	local ranges = {}
	for i = 1, zoneCount do
		local z = zones:FindFirstChild("Zone" .. i)
		local lo, hi = math.huge, -math.huge
		for _, p in (z and partsOf(z) or {}) do
			local a, b = yRange(p)
			lo, hi = math.min(lo, a), math.max(hi, b)
		end
		if lo < hi then
			ranges[i] = { lo, hi }
			ok(string.format("Zones/Zone%d: Y %.0f sampai %.0f", i, lo, hi))
		end
	end
	for i = 1, zoneCount - 1 do
		local below, above = ranges[i], ranges[i + 1]
		if below and above then
			if below[2] < above[1] - 0.5 then
				warnMsg(string.format("Celah Y %.0f-%.0f antara Zone%d dan Zone%d: di situ pill zona nggak ganti", below[2], above[1], i, i + 1))
			elseif above[1] < below[1] then
				warnMsg(string.format("Zone%d mulai lebih rendah dari Zone%d: urutan ketinggian kebalik?", i + 1, i))
			end
		end
	end
end

-- StreamingEnabled: kotak zona yang jauh bisa belum ada di client, pill zona & malam pekat Zona 3 jadi salah
if workspace.StreamingEnabled and zones then
	if zones:IsA("Model") and zones.ModelStreamingMode == Enum.ModelStreamingMode.Persistent then
		ok("Zones = Model Persistent (aman dengan StreamingEnabled)")
	else
		warnMsg("StreamingEnabled nyala tapi Zones bukan Model dengan ModelStreamingMode = Persistent: kotak zona bisa belum ke-stream di client")
	end
end

-- ===== Lereng =====
print("Lereng")
local slope = game:GetService("StarterPlayer").CharacterMaxSlopeAngle
if math.abs(slope - 45) > 0.01 then
	err(string.format("StarterPlayer.CharacterMaxSlopeAngle = %g, harus 45 (biar pemain nggak bisa manjat tebing)", slope))
else
	ok("CharacterMaxSlopeAngle = 45")
end

-- ===== SpawnPoints =====
print("SpawnPoints")
local spawnRoot = workspace:FindFirstChild("SpawnPoints")
if not spawnRoot then
	err("Folder Workspace.SpawnPoints nggak ada")
else
	for i = 1, zoneCount do
		local folder = spawnRoot:FindFirstChild("Zone" .. i)
		if not folder then
			err("SpawnPoints/Zone" .. i .. " nggak ada")
		else
			local count, outside = 0, 0
			local zoneInst = zones and zones:FindFirstChild("Zone" .. i)
			for _, point in folder:GetChildren() do
				if point:IsA("BasePart") then
					count += 1
					if zoneInst and not inZone(zoneInst, point.Position) then
						outside += 1
					end
				end
			end
			if count == 0 then
				err("SpawnPoints/Zone" .. i .. " kosong (titik spawn harus Part langsung di folder ini)")
			else
				ok(string.format("SpawnPoints/Zone%d: %d titik", i, count))
			end
			if outside > 0 then
				warnMsg(string.format("SpawnPoints/Zone%d: %d titik di luar kotak Zones/Zone%d (geser titiknya ke dalam kotak zona)", i, outside, i))
			end
		end
	end
end

-- ===== ZoneGates =====
print("ZoneGates")
local gates = workspace:FindFirstChild("ZoneGates")
if not gates then
	err("Folder Workspace.ZoneGates nggak ada")
else
	for i = 2, zoneCount do
		local gate = gates:FindFirstChild("Gate" .. i)
		if not gate then
			err("ZoneGates/Gate" .. i .. " nggak ada")
		else
			local sign = gate:FindFirstChild("Penanda", true)
			local sub = sign and sign:FindFirstChild("Sub", true)
			if not (sign and sign:IsA("BillboardGui") and sub and sub:IsA("TextLabel")) then
				warnMsg("ZoneGates/Gate" .. i .. " nggak punya BillboardGui Penanda berisi TextLabel Sub (teks syarat nggak tampil)")
			end
			local barriers = {}
			for _, p in partsOf(gate) do
				if p.Name == "Barrier" or p.Name == "Palang" then
					table.insert(barriers, p)
				end
			end
			if #barriers == 0 then
				warnMsg("ZoneGates/Gate" .. i .. " nggak punya part Barrier/Palang: SEMUA part gerbang bakal hilang pas kebuka")
			else
				local bad = 0
				for _, b in barriers do
					if not b.Anchored or not b.CanCollide then
						bad += 1
					end
				end
				if bad > 0 then
					warnMsg(string.format("ZoneGates/Gate%d: %d Barrier/Palang belum Anchored + CanCollide", i, bad))
				else
					ok(string.format("ZoneGates/Gate%d (%d Barrier/Palang)", i, #barriers))
				end
			end
		end
	end
end

-- ===== Pos Ranger =====
-- Tiap pos: Model ber-Tag Config.Posts.Tag + attribute PosNumber & Zone. Model lama "PosRanger" tanpa attribute = Pos 1.
print("Pos Ranger")
local CollectionService = game:GetService("CollectionService")
local sources = {}
for _, inst in CollectionService:GetTagged(Config.Posts.Tag) do
	sources[inst] = true
end
local legacy = workspace:FindFirstChild("PosRanger")
if legacy then
	sources[legacy] = true
end

local anchor -- PromptAnchor Pos 1 (Basecamp)
local byNumber = {}
for post in sources do
	local name = post:GetFullName()
	local number = post:GetAttribute("PosNumber")
	if number == nil and post.Name == "PosRanger" then
		number = 1
	end
	local zone = post:GetAttribute("Zone")
	if zone == nil and number == 1 then
		zone = 1
	end
	local postAnchor
	if post:IsA("BasePart") then
		postAnchor = post
	else
		local a = post:FindFirstChild("PromptAnchor", true)
		if a and a:IsA("BasePart") then
			postAnchor = a
		else
			postAnchor = post:FindFirstChildWhichIsA("BasePart", true)
			warnMsg(name .. " nggak punya part PromptAnchor, dipakai part pertama: " .. (postAnchor and postAnchor:GetFullName() or "-"))
		end
	end

	if type(number) ~= "number" or number < 1 or number ~= math.floor(number) then
		err(name .. ": attribute PosNumber belum diisi / bukan angka bulat")
	elseif byNumber[number] then
		err(string.format("PosNumber %d dipakai dua kali: %s dan %s", number, byNumber[number]:GetFullName(), name))
	elseif type(zone) ~= "number" or not Config.Zones[zone] then
		err(string.format("%s: attribute Zone harus angka 1-%d", name, zoneCount))
	elseif not postAnchor then
		err(name .. " nggak punya Part")
	elseif not postAnchor.Anchored then
		err(postAnchor:GetFullName() .. " belum Anchored")
	else
		byNumber[number] = post
		if not CollectionService:HasTag(post, Config.Posts.Tag) and number ~= 1 then
			warnMsg(name .. " belum dikasih Tag " .. Config.Posts.Tag .. " (nggak bakal kepasang)")
		end
		local zoneInst = zones and zones:FindFirstChild("Zone" .. zone)
		if zoneInst and not inZone(zoneInst, postAnchor.Position) then
			warnMsg(string.format("%s di luar kotak Zones/Zone%d", name, zone))
		end
		local point = post:FindFirstChild("TeleportPoint", true)
		if point and not point:IsA("BasePart") then
			warnMsg(name .. ": TeleportPoint harus Part")
		elseif not point and number ~= 1 then
			warnMsg(string.format("Pos %d nggak punya Part TeleportPoint: muncul %d stud di depan PromptAnchor (cek nggak nabrak tembok)", number, Config.Posts.TeleportOffset))
		end
		if number == 1 then
			anchor = postAnchor
		end
		ok(string.format("Pos %d (Zona %d) di %s", number, zone, postAnchor:GetFullName()))
	end
end
if not byNumber[1] then
	err("Pos 1 (Basecamp) nggak ada: kasih Tag " .. Config.Posts.Tag .. " + attribute PosNumber 1, Zone 1 ke Model Pos Ranger")
end

-- Spawn pemain harus di dalam Basecamp, biar timer pendakian jalan dari awal
if anchor then
	local spawns = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d.Enabled then
			table.insert(spawns, d)
		end
	end
	if #spawns == 0 then
		warnMsg("Nggak ada SpawnLocation: pemain muncul di titik asal map")
	end
	for _, s in spawns do
		local dist = (s.Position - anchor.Position).Magnitude
		if dist > Config.Summit.BasecampRadius then
			warnMsg(string.format(
				"%s %.0f stud dari Pos 1 (> BasecampRadius %d): summit pertama baru kehitung setelah mampir Basecamp",
				s:GetFullName(), dist, Config.Summit.BasecampRadius
			))
		else
			ok(string.format("%s di dalam Basecamp (%.0f stud)", s:GetFullName(), dist))
		end
	end
end

-- ===== Safe zone (event bencana) =====
print("SafeZone")
local safeByZone = {}
for _, inst in CollectionService:GetTagged(Config.Events.SafeZoneTag) do
	local zone = inst:GetAttribute("Zone")
	if not inst:IsA("BasePart") then
		err(inst:GetFullName() .. " di-tag " .. Config.Events.SafeZoneTag .. " tapi bukan Part")
	elseif type(zone) ~= "number" or not Config.Zones[zone] then
		err(string.format("%s: attribute Zone harus angka 1-%d", inst:GetFullName(), zoneCount))
	else
		safeByZone[zone] = (safeByZone[zone] or 0) + 1
		if inst.CanCollide then
			warnMsg(inst:GetFullName() .. " masih CanCollide (safe zone harusnya volume tembus)")
		end
	end
end
for i = 1, zoneCount do
	if safeByZone[i] then
		ok(string.format("SafeZone Zona %d: %d part", i, safeByZone[i]))
	else
		warnMsg(string.format("Zona %d belum punya SafeZone: pas event di sana nggak ada tempat berlindung", i))
	end
end

-- ===== SummitTrigger =====
print("SummitTrigger")
local trigger = workspace:FindFirstChild("SummitTrigger", true)
if not trigger then
	err("Part SummitTrigger nggak ada")
else
	local p = trigger:IsA("BasePart") and trigger or trigger:FindFirstChildWhichIsA("BasePart", true)
	if not p then
		err("SummitTrigger bukan Part dan nggak berisi Part")
	else
		if not p.Anchored then
			err("SummitTrigger belum Anchored (bakal jatuh)")
		end
		if not p.CanTouch then
			err("SummitTrigger CanTouch mati (nggak bakal kepicu)")
		end
		if p.CanCollide then
			warnMsg("SummitTrigger masih CanCollide (pemain nabrak/berdiri di atasnya; biasanya dimatiin)")
		end
		local zoneInst = zones and zones:FindFirstChild("Zone" .. Config.Summit.Zone)
		if zoneInst and not inZone(zoneInst, p.Position) then
			warnMsg("SummitTrigger di luar kotak Zones/Zone" .. Config.Summit.Zone)
		end
		if anchor and (p.Position - anchor.Position).Magnitude <= Config.Summit.BasecampRadius then
			err("SummitTrigger masih di dalam radius Basecamp")
		end
		ok("SummitTrigger di " .. p:GetFullName())
	end
end

print(string.format("[check_map] Selesai: %d error, %d perlu dicek", errors, warnings))
