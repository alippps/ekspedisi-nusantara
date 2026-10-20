-- Titik masuk client. Tiap controller di-start dari sini.
require(script.StaminaController).start()
require(script.ZoneController).start()
require(script.JournalController).start() -- sebelum UIController: tombol Jurnal di HUD manggil ini
require(script.ShopController).start()
require(script.UIController).start()
