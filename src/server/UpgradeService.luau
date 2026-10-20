-- Upgrade gear (Tas Carrier, Sepatu Gunung). Tier tersimpan di data.Upgrades, harga & nilai di Config.Upgrades.
-- Pembelian cuma lewat UpgradeService.buy, yang dipanggil RangerService setelah cek jarak ke Pos Ranger.
-- Hasilnya dicerminkan ke attribute: "Upgrade_<Id>" = tier, plus stat-nya (BagMax, StaminaMax).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)

local UpgradeService = {}

-- Attribute stat yang diisi tiap upgrade.
local STAT_ATTRIBUTE = {
	Bag = "BagMax",
	Stamina = "StaminaMax",
}

local lastBuy = {} -- [Player] = os.clock() pembelian terakhir

local function tierOf(data, upgradeId: string): number
	local upgrade = Config.Upgrades[upgradeId]
	local tier = data and data.Upgrades and data.Upgrades[upgradeId] or 1
	return math.clamp(tier, 1, #upgrade.Levels)
end

local function apply(player: Player, data)
	for upgradeId, upgrade in Config.Upgrades do
		local tier = tierOf(data, upgradeId)
		player:SetAttribute("Upgrade_" .. upgradeId, tier)
		local attribute = STAT_ATTRIBUTE[upgradeId]
		if attribute then
			player:SetAttribute(attribute, upgrade.Levels[tier].Value)
		end
	end
end

-- Nilai stat upgrade pemain sekarang (pakai tier 1 kalau data belum siap).
function UpgradeService.getValue(player: Player, upgradeId: string): number
	local upgrade = Config.Upgrades[upgradeId]
	return upgrade.Levels[tierOf(DataService.get(player), upgradeId)].Value
end

-- Coba beli tier berikutnya. Return (berhasil, alasanGagal?, tierBaru?).
-- Alasan: "invalid" | "loading" | "cooldown" | "max" | "level" | "coins"
function UpgradeService.buy(player: Player, upgradeId: any): (boolean, string?, number?)
	local upgrade = type(upgradeId) == "string" and Config.Upgrades[upgradeId]
	if not upgrade then
		return false, "invalid"
	end
	local data = DataService.get(player)
	if not data then
		return false, "loading"
	end

	local now = os.clock()
	if lastBuy[player] and now - lastBuy[player] < Config.Shop.BuyCooldown then
		return false, "cooldown"
	end
	lastBuy[player] = now

	local tier = tierOf(data, upgradeId)
	local nextLevel = upgrade.Levels[tier + 1]
	if not nextLevel then
		return false, "max"
	end
	if nextLevel.MinLevel and Progression.levelFromXP(data.XP) < nextLevel.MinLevel then
		return false, "level"
	end
	if data.Coins < nextLevel.Price then
		return false, "coins"
	end

	data.Coins -= nextLevel.Price
	data.Upgrades[upgradeId] = tier + 1
	player:SetAttribute("Coins", data.Coins)
	apply(player, data)
	return true, nil, tier + 1
end

function UpgradeService.start()
	DataService.onLoaded(function(player, data)
		data.Upgrades = data.Upgrades or {}
		apply(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
	end)
end

return UpgradeService
