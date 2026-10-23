-- Puncak: pemain nyentuh Part "SummitTrigger" = summit. Semua hadiah dihitung & dicek di sini (server).
-- * Waktu mendaki dihitung sejak keluar dari Basecamp (Config.Summit.BasecampRadius dari Pos 1).
-- * Satu pendakian cuma dihitung sekali: habis summit harus balik ke Basecamp dulu.
-- * Teleport antar pos membatalkan pendakian: summit cuma dihitung kalau jalan kaki dari Basecamp.
-- * Summit pertama: title Config.Summit.FirstTitle + FirstXP. Tiap hari: DailyCoins, sekali per hari.
-- Hasilnya dikirim ke client lewat Notify "Summit" buat ditampilin SummitController.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local BagService = require(script.Parent.BagService)
local UpgradeService = require(script.Parent.UpgradeService)
local RangerService = require(script.Parent.RangerService)

local S = Config.Summit
local CHECK_INTERVAL = 0.5 -- detik antar cek posisi Basecamp
local FIND_TIMEOUT = 30 -- detik nyari SummitTrigger di map sebelum nyerah

local SummitService = {}

local notify: RemoteEvent
local inBasecamp = {} -- [Player] = true kalau cek terakhir masih di Basecamp
local climbStart = {} -- [Player] = os.clock() pas keluar Basecamp; nil = belum mulai / udah summit

-- Nomor hari buat bonus harian (ganti jam 00:00 di zona waktu Config.Summit.DayResetUTCOffset)
local function dayNumber(): number
	return (os.time() + S.DayResetUTCOffset * 3600) // 86400
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

-- Jarak titik ke permukaan Part (0 kalau di dalam)
local function distanceTo(part: BasePart, point: Vector3): number
	local relative = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(relative.X, -half.X, half.X),
		math.clamp(relative.Y, -half.Y, half.Y),
		math.clamp(relative.Z, -half.Z, half.Z)
	)
	return (relative - clamped).Magnitude
end

-- ===== Basecamp =====
local function updateBasecamp(player: Player)
	local post = RangerService.getPost()
	local hrp = rootOf(player)
	if not post or not hrp then
		return
	end
	local inside = (hrp.Position - post.Position).Magnitude <= S.BasecampRadius
	if inside then
		climbStart[player] = nil
	elseif inBasecamp[player] then
		climbStart[player] = os.clock() -- baru aja keluar Basecamp: pendakian mulai
	end
	inBasecamp[player] = inside
end

-- ===== Summit =====
-- Kasih hadiah & kirim hasil ke client. seconds = waktu mendaki (nil kalau nggak diketahui).
local function award(player: Player, seconds: number?)
	local data = DataService.get(player)
	if not data then
		return
	end
	local result = {
		seconds = seconds,
		bag = #data.Bag,
		bagMax = player:GetAttribute("BagMax") or 0,
		xp = 0,
		coins = 0,
	}

	data.SummitCount += 1
	result.count = data.SummitCount

	if not data.Titles[S.FirstTitle] then
		data.Titles[S.FirstTitle] = os.time()
		data.XP += S.FirstXP
		result.title = S.FirstTitle
		result.xp = S.FirstXP
	end

	local today = dayNumber()
	if data.LastSummitDay ~= today then
		data.LastSummitDay = today
		data.Coins += S.DailyCoins
		result.coins = S.DailyCoins
	end

	BagService.sync(player)
	notify:FireClient(player, "Summit", result)
	print(string.format("[Summit] %s summit ke-%d (+%d XP, +%d Koin)", player.Name, result.count, result.xp, result.coins))
end

local function tryTouch(player: Player, trigger: BasePart)
	local start = climbStart[player]
	if not start then
		return -- belum keluar Basecamp, atau pendakian ini udah dihitung
	end
	local data = DataService.get(player)
	local hrp = rootOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Touched bisa dipalsukan exploiter, jadi cek jarak & syarat zona di sini juga
	if distanceTo(trigger, hrp.Position) > S.TriggerMaxDistance then
		return
	end
	local tierOf = function(upgradeId: string): number
		return UpgradeService.getTier(player, upgradeId)
	end
	if not Progression.isZoneUnlocked(S.Zone, Progression.levelFromXP(data.XP), tierOf) then
		return
	end

	climbStart[player] = nil
	award(player, os.clock() - start)
end

local function hookTrigger(trigger: Instance)
	local parts = if trigger:IsA("BasePart") then { trigger } else {}
	for _, descendant in trigger:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		warn("[SummitService] SummitTrigger harus berupa Part atau Model yang berisi Part")
		return
	end
	for _, part in parts do
		part.Touched:Connect(function(hit)
			local model = hit:FindFirstAncestorOfClass("Model")
			local player = model and Players:GetPlayerFromCharacter(model)
			if player then
				tryTouch(player, part)
			end
		end)
	end
end

-- Khusus DebugService: anggap summit sekarang juga (tanpa cek jarak/zona), lewat jalur hadiah yang sama.
function SummitService.debugSummit(player: Player)
	local start = climbStart[player]
	climbStart[player] = nil
	award(player, if start then os.clock() - start else nil)
end

-- Khusus DebugService: hapus progres summit biar bisa ngetes summit pertama & bonus harian lagi.
function SummitService.debugReset(player: Player): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	data.Titles[S.FirstTitle] = nil
	data.SummitCount = 0
	data.LastSummitDay = -1
	return true
end

function SummitService.start()
	notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				updateBasecamp(player)
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		inBasecamp[player] = nil
		climbStart[player] = nil
	end)
	-- Teleport = pendakian batal. inBasecamp dikosongin biar teleport keluar Basecamp nggak dianggap mulai mendaki;
	-- teleport ke Pos 1 langsung kebaca masuk Basecamp lagi di cek berikutnya.
	RangerService.onTeleported(function(player)
		climbStart[player] = nil
		inBasecamp[player] = false
	end)

	-- SummitTrigger boleh ada di dalam Model zona, jadi dicari rekursif (map bisa kebaca belakangan)
	task.spawn(function()
		local deadline = os.clock() + FIND_TIMEOUT
		local trigger = workspace:FindFirstChild("SummitTrigger", true)
		while not trigger and os.clock() < deadline do
			task.wait(1)
			trigger = workspace:FindFirstChild("SummitTrigger", true)
		end
		if trigger then
			hookTrigger(trigger)
		else
			warn("[SummitService] Part SummitTrigger tidak ditemukan di Workspace")
		end
	end)
end

return SummitService
