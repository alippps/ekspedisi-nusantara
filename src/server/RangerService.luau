-- Pos Ranger: tempat setor isi tas jadi Koin + XP, dan toko upgrade gear.
-- Setup di Studio: satu Part (Anchored) bernama "PosRanger" di Workspace.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BagService = require(script.Parent.BagService)
local UpgradeService = require(script.Parent.UpgradeService)

local RangerService = {}

local anchor: BasePart? = nil

local function isNearPost(player: Player): boolean
	local post = anchor
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not post or not hrp or not hrp:IsA("BasePart") then
		return false
	end
	return (hrp.Position - post.Position).Magnitude <= Config.Shop.MaxDistance
end

function RangerService.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local notify = remotes:WaitForChild("Notify")
	local buyUpgrade = remotes:WaitForChild("BuyUpgrade")

	-- Dipasang duluan supaya InvokeServer dari client tidak nunggu selamanya
	-- walaupun PosRanger belum ada di map.
	buyUpgrade.OnServerInvoke = function(player: Player, upgradeId: any)
		if not isNearPost(player) then
			return false, "far"
		end
		local ok, reason = UpgradeService.buy(player, upgradeId)
		return ok, reason
	end

	local post = workspace:WaitForChild("PosRanger", 10)
	if not post then
		warn("[RangerService] Part Workspace.PosRanger tidak ditemukan")
		return
	end
	local part = post:IsA("BasePart") and post or post:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		warn("[RangerService] PosRanger harus berupa Part atau Model yang berisi Part")
		return
	end
	anchor = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Setor"
	prompt.ObjectText = "Pos Ranger"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		local summary, reason = BagService.deposit(player)
		if reason == "loading" then
			notify:FireClient(player, "DataLoading")
		elseif summary.count == 0 then
			notify:FireClient(player, "BagEmpty")
		else
			notify:FireClient(player, "Deposited", summary)
		end
	end)

	-- Tombol kedua buat buka toko. Digeser ke bawah supaya tidak numpuk dengan "Setor".
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.Name = "UpgradePrompt"
	shopPrompt.ActionText = "Upgrade"
	shopPrompt.ObjectText = "Pos Ranger"
	shopPrompt.HoldDuration = 0
	shopPrompt.KeyboardKeyCode = Enum.KeyCode.F
	shopPrompt.GamepadKeyCode = Enum.KeyCode.ButtonR1
	shopPrompt.MaxActivationDistance = Config.Shop.PromptDistance
	shopPrompt.UIOffset = Vector2.new(0, 72)
	shopPrompt.Parent = part

	shopPrompt.Triggered:Connect(function(player: Player)
		notify:FireClient(player, "OpenShop")
	end)
end

return RangerService
