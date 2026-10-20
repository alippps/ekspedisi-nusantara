--!strict
-- Rumus progres yang dipakai bareng server & client: level dari XP, dan zona sudah terbuka atau belum.
-- Angkanya tetap di Config; di sini cuma rumusnya.
local Config = require(script.Parent.Config)

local Progression = {}

function Progression.levelFromXP(xp: number): number
	return 1 + math.floor(xp / Config.Level.XPPerLevel)
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
