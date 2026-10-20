-- Zona: deteksi pemain lagi di zona mana (buat pill di HUD) dan gerbang zona yang terkunci level.
-- Setup di Studio:
--   Workspace > Zones (Folder) > "Zone1", "Zone2", ... = Part transparan yang nutup area tiap zona
--     (boleh juga Model/Folder bernama ZoneN berisi beberapa Part kalau bentuk areanya ribet).
--   Workspace > ZoneGates (Folder) > "Gate2", ... = Part (atau Model) yang nutup jalan masuk zona itu,
--     Anchored + CanCollide nyala.
-- Gerbang dibuka cuma di client ini (tembus + tak terlihat) saat level cukup. Kunci yang beneran ada di server
-- (BagService nolak ambil item di zona yang belum terbuka).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))

local player = Players.LocalPlayer

local ZoneController = {}

local CHECK_INTERVAL = 0.25 -- detik antar cek posisi
local BLOCKED_COOLDOWN = 3 -- detik antar toast "zona terkunci" waktu nabrak gerbang

local currentZone = 1
local zoneChangedCallbacks: { (number) -> () } = {}
local gateBlockedCallbacks: { (number) -> () } = {}
local gates = {} -- [Instance gerbang] = nomor zona
local lastBlocked = 0

local function currentLevel(): number
	return player:GetAttribute("Level") or 1
end

-- Part-part milik satu zona/gerbang (dirinya sendiri kalau Part, atau semua Part di dalamnya).
local function partsOf(instance: Instance): { BasePart }
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

local function contains(part: BasePart, point: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

-- ===== Deteksi zona =====
local function detectZone(position: Vector3): number?
	local folder = workspace:FindFirstChild("Zones")
	if not folder then
		return nil
	end
	-- Kalau volume zona tumpang tindih, ambil nomor zona paling tinggi.
	local found: number? = nil
	for _, child in folder:GetChildren() do
		local zone = tonumber(string.match(child.Name, "^Zone(%d+)$"))
		if zone and (not found or zone > found) then
			for _, part in partsOf(child) do
				if contains(part, position) then
					found = zone
					break
				end
			end
		end
	end
	return found
end

local function setZone(zone: number)
	if zone == currentZone then
		return
	end
	currentZone = zone
	for _, callback in zoneChangedCallbacks do
		task.spawn(callback, zone)
	end
end

-- ===== Gerbang =====
local function applyGate(gate: Instance, zone: number)
	local open = Progression.isZoneUnlocked(currentLevel(), zone)
	for _, part in partsOf(gate) do
		-- Perubahan ini cuma berlaku di client ini; karakter disimulasikan di client jadi bisa tembus.
		part.CanCollide = not open
		part.LocalTransparencyModifier = open and 1 or 0
	end
	for _, descendant in gate:GetDescendants() do
		if descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.LocalTransparencyModifier = open and 1 or 0
		end
	end
end

local function onGateTouched(zone: number, hit: BasePart)
	local character = player.Character
	if not character or not hit:IsDescendantOf(character) then
		return
	end
	if Progression.isZoneUnlocked(currentLevel(), zone) then
		return
	end
	local now = os.clock()
	if now - lastBlocked < BLOCKED_COOLDOWN then
		return
	end
	lastBlocked = now
	for _, callback in gateBlockedCallbacks do
		task.spawn(callback, zone)
	end
end

local function registerGate(gate: Instance)
	local zone = tonumber(string.match(gate.Name, "^Gate(%d+)$"))
	if not zone or gates[gate] then
		return
	end
	gates[gate] = zone
	for _, part in partsOf(gate) do
		part.Touched:Connect(function(hit)
			onGateTouched(zone, hit)
		end)
	end
	applyGate(gate, zone)
end

local function refreshGates()
	for gate, zone in gates do
		if gate.Parent then
			applyGate(gate, zone)
		else
			gates[gate] = nil
		end
	end
end

-- ===== API publik =====
function ZoneController.getZone(): number
	return currentZone
end

-- callback(zoneBaru) tiap kali pemain pindah zona.
function ZoneController.onZoneChanged(callback: (number) -> ())
	table.insert(zoneChangedCallbacks, callback)
end

-- callback(zona) waktu pemain nabrak gerbang zona yang belum terbuka.
function ZoneController.onGateBlocked(callback: (number) -> ())
	table.insert(gateBlockedCallbacks, callback)
end

function ZoneController.start()
	-- Gerbang bisa muncul belakangan (map belum kebaca / StreamingEnabled), jadi tunggu folder-nya di background.
	task.spawn(function()
		local folder = workspace:WaitForChild("ZoneGates", 30)
		if not folder then
			return
		end
		for _, gate in folder:GetChildren() do
			registerGate(gate)
		end
		folder.ChildAdded:Connect(registerGate)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(refreshGates)

	task.spawn(function()
		while true do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local zone = detectZone(hrp.Position)
				if zone then
					setZone(zone)
				end
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return ZoneController
