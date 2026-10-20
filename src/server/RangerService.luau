-- Pos Ranger: tempat setor isi tas jadi Koin + XP.
-- Setup di Studio: satu Part (Anchored) bernama "PosRanger" di Workspace.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BagService = require(script.Parent.BagService)

local RangerService = {}

function RangerService.start()
	local notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notify")
	local post = workspace:WaitForChild("PosRanger", 10)
	if not post then
		warn("[RangerService] Part Workspace.PosRanger tidak ditemukan")
		return
	end
	local anchor = post:IsA("BasePart") and post or post:FindFirstChildWhichIsA("BasePart", true)
	if not anchor then
		warn("[RangerService] PosRanger harus berupa Part atau Model yang berisi Part")
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Setor"
	prompt.ObjectText = "Pos Ranger"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.Parent = anchor

	prompt.Triggered:Connect(function(player: Player)
		local summary = BagService.deposit(player)
		if summary.count == 0 then
			notify:FireClient(player, "BagEmpty")
		else
			notify:FireClient(player, "Deposited", summary)
		end
	end)
end

return RangerService
