--!strict
-- Rumus progres yang dipakai bareng server & client: level dari XP, dan zona sudah terbuka atau belum.
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

function Progression.isZoneUnlocked(level: number, zone: number): boolean
	return level >= Progression.zoneMinLevel(zone)
end

return Progression
