-- Tas, koin, XP, dan jurnal per pemain. Sementara disimpan di memori (hilang saat keluar).
-- Nanti diganti DataService + ProfileStore supaya tersimpan permanen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local BagService = {}

local itemById = {}
for _, item in Config.Items do
	itemById[item.Id] = item
end

local bags = {} -- [Player] = { itemId, ... }
local journals = {} -- [Player] = { [itemId] = true }

local function setup(player: Player)
	bags[player] = {}
	journals[player] = {}
	player:SetAttribute("Coins", 0)
	player:SetAttribute("XP", 0)
	player:SetAttribute("Level", 1)
	player:SetAttribute("BagCount", 0)
	player:SetAttribute("BagMax", Config.Bag.BaseSlots)
	player:SetAttribute("JournalCount", 0)
	player:SetAttribute("BagItems", "")
end

function BagService.isDiscovered(player: Player, itemId: string): boolean
	local journal = journals[player]
	return journal ~= nil and journal[itemId] == true
end

function BagService.getItem(itemId: string)
	return itemById[itemId]
end

function BagService.tryAdd(player: Player, itemId: string): (boolean, string?)
	local bag = bags[player]
	if not bag or not itemById[itemId] then
		return false, "invalid"
	end
	if #bag >= (player:GetAttribute("BagMax") or Config.Bag.BaseSlots) then
		return false, "full"
	end
	table.insert(bag, itemId)
	player:SetAttribute("BagCount", #bag)
	player:SetAttribute("BagItems", table.concat(bag, ","))
	return true, nil
end

function BagService.deposit(player: Player)
	local bag = bags[player]
	local journal = journals[player]
	local summary = { count = 0, coins = 0, xp = 0, newFinds = 0 }
	if not bag or #bag == 0 then
		return summary
	end

	for _, itemId in bag do
		local item = itemById[itemId]
		local rarity = item and Config.Rarity[item.Rarity]
		if rarity then
			summary.count += 1
			summary.coins += rarity.Coin
			summary.xp += rarity.XP
			if not journal[itemId] then
				journal[itemId] = true
				summary.xp += rarity.FirstXP
				summary.newFinds += 1
			end
		end
	end

	table.clear(bag)
	local xp = (player:GetAttribute("XP") or 0) + summary.xp
	local journalCount = 0
	for _ in journal do
		journalCount += 1
	end

	player:SetAttribute("Coins", (player:GetAttribute("Coins") or 0) + summary.coins)
	player:SetAttribute("XP", xp)
	player:SetAttribute("Level", 1 + math.floor(xp / Config.Level.XPPerLevel))
	player:SetAttribute("BagCount", 0)
	player:SetAttribute("BagItems", "")
	player:SetAttribute("JournalCount", journalCount)
	return summary
end

function BagService.start()
	for _, player in Players:GetPlayers() do
		setup(player)
	end
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		bags[player] = nil
		journals[player] = nil
	end)
end

return BagService
