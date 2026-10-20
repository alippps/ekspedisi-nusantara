--!strict
-- Seberapa malam sekarang, dipakai bareng server (senter nyala) & client (gelapnya dunia).
-- Angkanya di Config.DayNight; di sini cuma rumusnya.
local Config = require(script.Parent.Config)

local D = Config.DayNight

local TimeOfDay = {}

-- 0 = siang penuh, 1 = malam penuh. Di sekitar DayStart/DayEnd berubah halus selama TransitionHours.
function TimeOfDay.nightness(clock: number): number
	local span = math.max(D.TransitionHours, 0.001)
	local half = span / 2
	local dawn = math.clamp((clock - (D.DayStart - half)) / span, 0, 1) -- 0 sebelum subuh, 1 setelah terang
	local dusk = math.clamp((clock - (D.DayEnd - half)) / span, 0, 1) -- 0 sebelum senja, 1 setelah gelap
	return 1 - math.min(dawn, 1 - dusk)
end

return TimeOfDay
