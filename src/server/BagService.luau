-- Tas, koin, XP, dan jurnal per pemain. Datanya disimpan permanen lewat DataService;
-- attribute di Player cuma cermin buat HUD (client tidak pernah ngirim data ke sini).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local UpgradeService = require(script.Parent.UpgradeService)

local BagService = {}

local itemById = {}
for _, item in Config.Items do
	itemById[item.Id] = item
end

local function bagMax(player: Player): number
	return UpgradeService.getValue(player, "Bag")
end

local function countJournal(journal): number
	local count = 0
	for itemId in journal do
		if itemById[itemId] then
			count += 1
		end
	end
	return count
end

-- Jurnal buat client: "itemId=jumlahSetor,itemId=jumlahSetor"
local function encodeJournal(journal): string
	local parts = {}
	for itemId, count in journal do
		if itemById[itemId] then
			table.insert(parts, itemId .. "=" .. count)
		end
	end
	return table.concat(parts, ",")
end

local function syncAttributes(player: Player, data)
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("XP", data.XP)
	player:SetAttribute("Level", Progression.levelFromXP(data.XP))
	player:SetAttribute("BagCount", #data.Bag)
	player:SetAttribute("BagItems", table.concat(data.Bag, ","))
	player:SetAttribute("Journal", encodeJournal(data.Journal))
	player:SetAttribute("JournalCount", countJournal(data.Journal))
end

local function setup(player: Player, data)
	-- Buang item tersimpan yang sudah tidak ada di Config (misal item dihapus/diganti Id).
	local cleaned = {}
	for _, itemId in data.Bag do
		if itemById[itemId] then
			table.insert(cleaned, itemId)
		end
	end
	data.Bag = cleaned

	syncAttributes(player, data)
	-- Paling akhir: tanda buat client kalau semua angka di atas sudah data asli.
	player:SetAttribute("DataLoaded", true)
end

function BagService.isDiscovered(player: Player, itemId: string): boolean
	local data = DataService.get(player)
	return data ~= nil and data.Journal[itemId] ~= nil
end

function BagService.getItem(itemId: string)
	return itemById[itemId]
end

function BagService.tryAdd(player: Player, itemId: string): (boolean, string?)
	local item = itemById[itemId]
	if not item then
		return false, "invalid"
	end
	local data = DataService.get(player)
	if not data then
		return false, "loading"
	end
	-- Kunci zona yang beneran: gerbang di client bisa ditembus exploiter, tapi item tetap tidak bisa diambil.
	local tierOf = function(upgradeId: string): number
		return UpgradeService.getTier(player, upgradeId)
	end
	if not Progression.isZoneUnlocked(item.Zone, Progression.levelFromXP(data.XP), tierOf) then
		return false, "locked"
	end
	-- Item malam: harus punya senter DAN lagi dinyalain (HeadlampOn cuma diset server)
	if item.Time == "Night" and Config.Night.NightItemsNeedHeadlamp then
		if UpgradeService.getValue(player, "Headlamp") <= 0 or player:GetAttribute("HeadlampOn") ~= true then
			return false, "dark"
		end
	end
	if #data.Bag >= bagMax(player) then
		return false, "full"
	end
	table.insert(data.Bag, itemId)
	player:SetAttribute("BagCount", #data.Bag)
	player:SetAttribute("BagItems", table.concat(data.Bag, ","))
	return true, nil
end

function BagService.deposit(player: Player)
	local summary = { count = 0, coins = 0, xp = 0, newFinds = 0 }
	local data = DataService.get(player)
	if not data then
		return summary, "loading"
	end
	if #data.Bag == 0 then
		return summary, nil
	end

	local journal = data.Journal
	for _, itemId in data.Bag do
		local item = itemById[itemId]
		local rarity = item and Config.Rarity[item.Rarity]
		if rarity then
			summary.count += 1
			summary.coins += rarity.Coin
			summary.xp += rarity.XP
			if not journal[itemId] then
				summary.xp += rarity.FirstXP
				summary.newFinds += 1
			end
			journal[itemId] = (journal[itemId] or 0) + 1
		end
	end

	table.clear(data.Bag)
	data.Coins += summary.coins
	data.XP += summary.xp
	syncAttributes(player, data)
	return summary, nil
end

-- Kirim ulang semua angka ke attribute (dipakai DebugService setelah ngubah data langsung).
function BagService.sync(player: Player)
	local data = DataService.get(player)
	if data then
		syncAttributes(player, data)
	end
end

function BagService.start()
	DataService.onLoaded(setup)
end

return BagService
