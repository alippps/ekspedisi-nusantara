-- Titik masuk server: bikin remote, lalu start semua service berurutan.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local notify = Instance.new("RemoteEvent")
notify.Name = "Notify"
notify.Parent = remotes
local buyUpgrade = Instance.new("RemoteFunction")
buyUpgrade.Name = "BuyUpgrade"
buyUpgrade.Parent = remotes
remotes.Parent = ReplicatedStorage

require(script.DayNightService).start()
require(script.DataService).start() -- harus sebelum Upgrade & Bag
require(script.UpgradeService).start() -- sebelum BagService: BagMax harus sudah terisi sebelum DataLoaded
require(script.BagService).start()
require(script.SpawnService).start()
require(script.RangerService).start()

print("[Ekspedisi Nusantara] server siap")
