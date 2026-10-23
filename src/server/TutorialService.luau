-- Misi pemula: ambil item (langsung tercatat di Jurnal) -> buka Jurnal -> setor ke Pos Ranger.
-- Progres disimpan di data (TutorialStep, TutorialPicked) dan dicerminkan ke attribute dengan nama sama buat panel Misi.
-- Langkah ambil & setor dinaikkan server sendiri (dipanggil BagService). Cuma "buka Jurnal" yang dilaporin client
-- lewat remote TutorialEvent; aman karena cuma ngubah panel petunjuk, nggak ngasih hadiah apa pun.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local T = Config.Tutorial

local TutorialService = {}

-- Nomor langkah (sama dengan yang dibaca MissionController)
TutorialService.PICK = 1
TutorialService.JOURNAL = 2
TutorialService.DEPOSIT = 3
TutorialService.DONE = 4

local function sync(player: Player, data)
	player:SetAttribute("TutorialStep", data.TutorialStep)
	player:SetAttribute("TutorialPicked", data.TutorialPicked)
end

local function setup(player: Player, data)
	-- Data lama belum punya field ini. Yang udah pernah setor (Jurnal ada isinya) dianggap udah lewat tutorial.
	if data.TutorialStep == nil then
		data.TutorialStep = if next(data.Journal) then TutorialService.DONE else TutorialService.PICK
	end
	data.TutorialPicked = data.TutorialPicked or 0
	sync(player, data)
end

-- Dipanggil BagService tiap item berhasil masuk tas.
function TutorialService.onPicked(player: Player, data)
	if data.TutorialStep ~= TutorialService.PICK then
		return -- termasuk nil: setup belum sempat jalan
	end
	data.TutorialPicked += 1
	if data.TutorialPicked >= T.PickCount then
		data.TutorialStep = TutorialService.JOURNAL
	end
	sync(player, data)
end

-- Dipanggil BagService tiap setoran yang ada isinya. Setor di langkah sebelumnya nggak ngubah apa-apa:
-- pemain tetap bisa lanjut ambil item & buka Jurnal, jadi nggak nyangkut.
function TutorialService.onDeposited(player: Player, data)
	if data.TutorialStep ~= TutorialService.DEPOSIT then
		return
	end
	data.TutorialStep = TutorialService.DONE
	sync(player, data)
end

-- Khusus DebugService: ulang misi pemula dari awal.
function TutorialService.debugReset(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	data.TutorialStep = TutorialService.PICK
	data.TutorialPicked = 0
	sync(player, data)
	return true
end

function TutorialService.start()
	DataService.onLoaded(setup)

	local event = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TutorialEvent") :: RemoteEvent
	event.OnServerEvent:Connect(function(player: Player, action: any)
		local data = DataService.get(player)
		if not data or action ~= "JournalOpened" or data.TutorialStep ~= TutorialService.JOURNAL then
			return
		end
		data.TutorialStep = TutorialService.DEPOSIT
		sync(player, data)
	end)
end

return TutorialService
