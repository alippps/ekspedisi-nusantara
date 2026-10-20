-- Titik masuk client. Tiap controller di-start dari sini.
require(script.StaminaController).start()
require(script.JournalController).start() -- sebelum UIController: tombol Jurnal di HUD manggil ini
require(script.UIController).start()
