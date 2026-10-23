-- Zona: deteksi pemain lagi di zona mana (buat pill di HUD) dan gerbang zona yang terkunci.
-- Syarat gerbang (level + tier upgrade) dibaca dari Config.Zones lewat Progression.zoneChecks.
-- Setup di Studio:
--   Workspace > Zones (Folder) > "Zone1", "Zone2", ... = Part transparan yang nutup area tiap zona
--     (boleh juga Model/Folder bernama ZoneN berisi beberapa Part kalau bentuk areanya ribet).
--   Workspace > ZoneGates (Folder) > "Gate2", ... = Part (atau Model) yang nutup jalan masuk zona itu,
--     Anchored + CanCollide nyala. Kalau Model punya part bernama "Barrier" / "Palang", cuma itu yang dibuka
--     (tiang/papan gerbang tetap kelihatan); kalau nggak ada, semua part di Model dibuka.
--     Teks papan "Penanda" di gerbang diatur GateController lewat onGateRefreshed.
--   Dinding cincin zona: Part ber-Tag Config.ZoneGate.BarrierTag + attribute Zone (contoh: Workspace.Vulkan.DindingZona).
--     Zona terbuka = dindingnya Transparency 1, CanCollide & CanQuery mati. Setelan asli disimpan buat nutup lagi.
-- Gerbang & dinding dibuka cuma di client ini (tembus + tak terlihat) saat semua syarat terpenuhi. Kunci yang beneran ada di server
-- (BagService nolak ambil item di zona yang belum terbuka).
-- Dekat gerbang yang masih terkunci (Config.ZoneGate.PanelDistance) = GateController munculin panel syarat.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Progression = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Progression"))

local player = Players.LocalPlayer

local ZoneController = {}

local CHECK_INTERVAL = 0.25 -- detik antar cek posisi

local currentZone = 1
local nearGate: number? = nil -- zona dari gerbang terkunci yang lagi didekati
local zoneChangedCallbacks: { (number) -> () } = {}
local nearGateCallbacks: { (number?) -> () } = {}
local unlockedCallbacks: { (number) -> () } = {}
local gateRefreshedCallbacks: { (Instance, number) -> () } = {}
local gates = {} -- [Instance gerbang] = nomor zona
type WallOriginal = { Transparency: number, CanCollide: boolean, CanQuery: boolean }
local walls: { [BasePart]: WallOriginal } = {} -- [Part dinding] = setelan asli dari map
local unlocked: { [number]: boolean }? = nil -- status terakhir tiap zona, diisi setelah DataLoaded

local function currentLevel(): number
	return player:GetAttribute("Level") or 1
end

local function tierOf(upgradeId: string): number
	return player:GetAttribute("Upgrade_" .. upgradeId) or 1
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

-- Part yang dibuka pas zona terbuka: penghalang & palangnya
local BARRIER_NAMES = { Barrier = true, Palang = true }

-- Part penghalang gerbang: yang bernama Barrier/Palang kalau ada, kalau nggak semua part gerbang.
local function barriersOf(gate: Instance): { BasePart }
	local barriers = {}
	for _, part in partsOf(gate) do
		if BARRIER_NAMES[part.Name] then
			table.insert(barriers, part)
		end
	end
	return if #barriers > 0 then barriers else partsOf(gate)
end

local function contains(part: BasePart, point: Vector3): boolean
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Y) <= half.Y and math.abs(relative.Z) <= half.Z
end

-- Jarak titik ke permukaan Part (0 kalau di dalam)
local function distanceTo(part: BasePart, point: Vector3): number
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(relative.X, -half.X, half.X),
		math.clamp(relative.Y, -half.Y, half.Y),
		math.clamp(relative.Z, -half.Z, half.Z)
	)
	return (relative - clamped).Magnitude
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
local function isUnlocked(zone: number): boolean
	return Progression.isZoneUnlocked(zone, currentLevel(), tierOf)
end

local function applyGate(gate: Instance, zone: number)
	local open = isUnlocked(zone)
	for _, part in barriersOf(gate) do
		-- Perubahan ini cuma berlaku di client ini; karakter disimulasikan di client jadi bisa tembus.
		part.CanCollide = not open
		part.LocalTransparencyModifier = open and 1 or 0
		for _, child in part:GetChildren() do
			if child:IsA("Decal") or child:IsA("Texture") then
				child.LocalTransparencyModifier = open and 1 or 0
			end
		end
	end
	for _, callback in gateRefreshedCallbacks do
		task.spawn(callback, gate, zone)
	end
end

local function registerGate(gate: Instance)
	local zone = tonumber(string.match(gate.Name, "^Gate(%d+)$"))
	if not zone then
		return
	end
	if gates[gate] then
		applyGate(gate, zone) -- ke-stream ulang: setelan lokal (CanCollide dll) balik ke asli, pasang lagi
		return
	end
	gates[gate] = zone
	applyGate(gate, zone)
	-- StreamingEnabled: part Barrier/Palang bisa nyusul belakangan (atau ke-stream ulang). Tiap ada part baru,
	-- gerbangnya dipasang ulang biar gerbang yang udah kebuka nggak tiba-tiba nutup lagi.
	gate.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and gates[gate] then
			applyGate(gate, zone)
		end
	end)
end

-- ===== Dinding cincin zona =====
local function applyWall(part: BasePart)
	local original = walls[part]
	local zone = part:GetAttribute("Zone")
	if not original or type(zone) ~= "number" then
		return
	end
	local open = isUnlocked(zone)
	part.Transparency = if open then 1 else original.Transparency
	-- CanCollide dulu: Roblox cuma ngizinin CanQuery mati kalau CanCollide udah mati
	part.CanCollide = if open then false else original.CanCollide
	part.CanQuery = if open then false else original.CanQuery
end

local function registerWall(instance: Instance)
	if not instance:IsA("BasePart") then
		warn(string.format("[ZoneController] %s di-tag %s tapi bukan Part", instance:GetFullName(), Config.ZoneGate.BarrierTag))
		return
	end
	local zone = instance:GetAttribute("Zone")
	if type(zone) ~= "number" or not Config.Zones[zone] then
		warn(string.format("[ZoneController] %s: attribute Zone harus nomor zona 1-%d", instance:GetFullName(), #Config.Zones))
		return
	end
	-- Part yang sama ke-stream ulang: setelan asli udah kesimpan, jangan ketimpa nilai yang lagi dibuka
	if not walls[instance] then
		walls[instance] = {
			Transparency = instance.Transparency,
			CanCollide = instance.CanCollide,
			CanQuery = instance.CanQuery,
		}
		instance.Destroying:Connect(function()
			walls[instance] = nil
		end)
	end
	applyWall(instance)
end

-- Zona yang baru kebuka sejak cek terakhir = callback onZoneUnlocked.
-- Baseline diambil pas DataLoaded, jadi zona yang udah kebuka dari save nggak dianggap baru.
local function checkUnlocks()
	if player:GetAttribute("DataLoaded") ~= true then
		return
	end
	local previous = unlocked
	local now = {}
	for zone in Config.Zones do
		now[zone] = isUnlocked(zone)
		if previous and now[zone] and not previous[zone] then
			for _, callback in unlockedCallbacks do
				task.spawn(callback, zone)
			end
		end
	end
	unlocked = now
end

local function refreshGates()
	for gate, zone in gates do
		if gate.Parent then
			applyGate(gate, zone)
		else
			gates[gate] = nil
		end
	end
	for part in walls do
		applyWall(part)
	end
	checkUnlocks()
end

-- Gerbang terkunci terdekat dalam jarak panel, atau nil
local function findNearGate(position: Vector3): number?
	local best: number?, bestDistance = nil, Config.ZoneGate.PanelDistance
	for gate, zone in gates do
		if gate.Parent and not isUnlocked(zone) then
			for _, part in barriersOf(gate) do
				local distance = distanceTo(part, position)
				if distance <= bestDistance then
					best, bestDistance = zone, distance
				end
			end
		end
	end
	return best
end

local function setNearGate(zone: number?)
	if zone == nearGate then
		return
	end
	nearGate = zone
	for _, callback in nearGateCallbacks do
		task.spawn(callback, zone)
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

-- Semua syarat zona + nilai pemain sekarang (buat panel gerbang & teks "terkunci").
function ZoneController.getChecks(zone: number): { Progression.ZoneCheck }
	return Progression.zoneChecks(zone, currentLevel(), tierOf)
end

function ZoneController.isUnlocked(zone: number): boolean
	return isUnlocked(zone)
end

-- callback(zona atau nil) waktu pemain mulai/berhenti dekat gerbang zona yang masih terkunci.
function ZoneController.onNearGate(callback: (number?) -> ())
	table.insert(nearGateCallbacks, callback)
end

-- callback(gerbang, zona) tiap gerbang dipasang/diperbarui (level/upgrade berubah). Buat papan Penanda.
function ZoneController.onGateRefreshed(callback: (Instance, number) -> ())
	table.insert(gateRefreshedCallbacks, callback)
	for gate, zone in gates do
		task.spawn(callback, gate, zone)
	end
end

-- callback(zona) waktu semua syarat zona baru aja terpenuhi (bukan pas join).
function ZoneController.onZoneUnlocked(callback: (number) -> ())
	table.insert(unlockedCallbacks, callback)
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
	-- Dinding cincin: AddedSignal juga jalan pas Part ke-stream masuk (lagi)
	local wallTag = Config.ZoneGate.BarrierTag
	CollectionService:GetInstanceAddedSignal(wallTag):Connect(registerWall)
	for _, instance in CollectionService:GetTagged(wallTag) do
		registerWall(instance)
	end
	-- Level & tier upgrade (termasuk Senter) berubah = gerbang + dinding dicek ulang
	player:GetAttributeChangedSignal("Level"):Connect(refreshGates)
	for upgradeId in Config.Upgrades do
		player:GetAttributeChangedSignal("Upgrade_" .. upgradeId):Connect(refreshGates)
	end
	player:GetAttributeChangedSignal("DataLoaded"):Connect(checkUnlocks)
	checkUnlocks()

	task.spawn(function()
		local isStudio = RunService:IsStudio()
		while true do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			-- /zona dari DebugService (cuma Studio) ngalahin deteksi posisi
			local forced = isStudio and player:GetAttribute("DebugZone")
			if type(forced) == "number" then
				setZone(forced)
			elseif hrp and hrp:IsA("BasePart") then
				local zone = detectZone(hrp.Position)
				if zone then
					setZone(zone)
				end
			end
			setNearGate(if hrp and hrp:IsA("BasePart") then findNearGate(hrp.Position) else nil)
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return ZoneController
