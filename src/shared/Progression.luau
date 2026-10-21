--!strict
-- Rumus progres yang dipakai bareng server & client: level dari XP, dan zona sudah terbuka atau belum
-- (syarat level + tier upgrade dari Config.Zones).
-- Angkanya tetap di Config; di sini cuma rumusnya.
local Config = require(script.Parent.Config)

local Progression = {}

-- XP yang dibutuhkan buat naik dari `level` ke `level + 1`
function Progression.xpToNext(level: number): number
	local cfg = Config.Level
	local raw = cfg.BaseXP * level ^ cfg.Growth
	return math.max(1, math.floor(raw / cfg.RoundTo + 0.5) * cfg.RoundTo)
end

-- Level sekarang, XP yang udah dikumpulin di level ini, dan XP yang dibutuhkan buat naik
function Progression.levelProgress(xp: number): (number, number, number)
	local level = 1
	local need = Progression.xpToNext(level)
	-- Batas 1000 level cuma pengaman biar nggak loop selamanya kalau Config ngaco
	while xp >= need and level < 1000 do
		xp -= need
		level += 1
		need = Progression.xpToNext(level)
	end
	return level, xp, need
end

-- Total XP minimal buat ada di `level` (Lv 1 = 0 XP)
function Progression.totalXPForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += Progression.xpToNext(l)
	end
	return total
end

function Progression.levelFromXP(xp: number): number
	return (Progression.levelProgress(xp))
end

function Progression.zoneMinLevel(zone: number): number
	local info = Config.Zones[zone]
	return if info then info.MinLevel else 1
end

function Progression.zoneName(zone: number): string
	local info = Config.Zones[zone]
	return if info then info.Name else ("Zona " .. zone)
end

-- Satu syarat buka zona. Kind "Level" atau "Upgrade" (UpgradeId diisi, Need/Have = tier).
export type ZoneCheck = {
	Kind: string,
	UpgradeId: string?,
	Need: number,
	Have: number,
	Met: boolean,
}

-- Semua syarat zona dari Config.Zones: level dulu, lalu upgrade urut Order-nya.
-- tierOf(upgradeId) = tier upgrade pemain sekarang (server baca dari data, client dari attribute).
function Progression.zoneChecks(zone: number, level: number, tierOf: (string) -> number): { ZoneCheck }
	local minLevel = Progression.zoneMinLevel(zone)
	local checks: { ZoneCheck } = {
		{ Kind = "Level", Need = minLevel, Have = level, Met = level >= minLevel },
	}
	local info = Config.Zones[zone] :: any
	local upgrades = if info then info.Upgrades else nil
	if upgrades then
		local ids = {}
		for upgradeId in upgrades do
			table.insert(ids, upgradeId)
		end
		table.sort(ids, function(a, b)
			return Config.Upgrades[a].Order < Config.Upgrades[b].Order
		end)
		for _, upgradeId in ids do
			local need, have = upgrades[upgradeId], tierOf(upgradeId)
			table.insert(checks, { Kind = "Upgrade", UpgradeId = upgradeId, Need = need, Have = have, Met = have >= need })
		end
	end
	return checks
end

function Progression.isZoneUnlocked(zone: number, level: number, tierOf: (string) -> number): boolean
	for _, check in Progression.zoneChecks(zone, level, tierOf) do
		if not check.Met then
			return false
		end
	end
	return true
end

return Progression
