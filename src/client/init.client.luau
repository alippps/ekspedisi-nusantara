-- Titik masuk client. Tiap controller di-start dari sini.
require(script.StaminaController).start()
require(script.ZoneController).start()
require(script.FxController).start() -- intro langsung main; efek tombol & banner
require(script.PostController).start() -- daftar Pos Ranger + banner "Pos N ditemukan!"
require(script.NightController).start()
require(script.GateController).start()
require(script.JournalController).start() -- sebelum UIController: tombol Jurnal di HUD manggil ini
require(script.ShopController).start()
require(script.SummitController).start()
require(script.EventController).start() -- sebelum MissionController: panah safe zone ngalahin panah Pos Ranger
require(script.MissionController).start()
require(script.UIController).start()

-- Mode terbang /fly cuma di Studio, sama seperti DebugService di server
if game:GetService("RunService"):IsStudio() then
	require(script.DebugController).start()
end
