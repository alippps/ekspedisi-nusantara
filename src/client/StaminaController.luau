--!strict
-- Stamina: habis saat lari, manjat, atau nanjak. Pulih saat diam/jalan santai.
-- Nilai stamina (0-1) ditaruh di attribute "Stamina" pada Player, nanti dibaca UIController.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local S = Config.Stamina

local player = Players.LocalPlayer
local BASE_MAX = Config.Upgrades.Stamina.Levels[1].Value

local StaminaController = {}

-- Stamina maks dari upgrade Sepatu Gunung (attribute StaminaMax diisi server).
local function maxStamina(): number
	return player:GetAttribute("StaminaMax") or BASE_MAX
end

local stamina = maxStamina()
local exhausted = false
local sprintHeld = false
local touchSprint = false -- tombol Lari di HP (mode toggle)
local humanoid: Humanoid? = nil
local root: BasePart? = nil

local function onCharacter(character: Model)
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	stamina = maxStamina()
	exhausted = false
end

local function handleSprint(_actionName: string, inputState: Enum.UserInputState, _input: InputObject)
	if inputState == Enum.UserInputState.Begin then
		sprintHeld = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		sprintHeld = false
	end
	return Enum.ContextActionResult.Sink
end

local function step(dt: number)
	local hum = humanoid
	local hrp = root
	if not hum or not hrp or hum.Health <= 0 then
		return
	end

	local moving = hum.MoveDirection.Magnitude > 0.1
	local climbing = hum:GetState() == Enum.HumanoidStateType.Climbing
	local uphill = moving and hrp.AssemblyLinearVelocity.Y > S.UphillMinRise
	local sprinting = (sprintHeld or touchSprint) and moving and not exhausted

	if climbing then
		stamina -= S.ClimbDrain * dt
	elseif sprinting then
		stamina -= S.SprintDrain * dt
	elseif uphill then
		stamina -= S.UphillDrain * dt
	elseif moving then
		stamina += S.RegenWalk * dt
	else
		stamina += S.RegenIdle * dt
	end
	local max = maxStamina()
	stamina = math.clamp(stamina, 0, max)

	if stamina <= 0 then
		exhausted = true
		touchSprint = false -- stamina habis: tombol Lari otomatis mati
	elseif exhausted and stamina >= S.RecoverAt then
		exhausted = false
	end

	if exhausted then
		hum.WalkSpeed = S.TiredSpeed
	elseif sprinting then
		hum.WalkSpeed = S.SprintSpeed
	else
		hum.WalkSpeed = S.WalkSpeed
	end

	player:SetAttribute("Stamina", stamina / max)
	player:SetAttribute("Exhausted", exhausted)
end

function StaminaController.setTouchSprint(on: boolean)
	touchSprint = on and not exhausted
end

function StaminaController.isTouchSprint(): boolean
	return touchSprint
end

function StaminaController.start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Habis upgrade Sepatu Gunung (atau data selesai dimuat): stamina langsung diisi penuh.
	player:GetAttributeChangedSignal("StaminaMax"):Connect(function()
		stamina = maxStamina()
		exhausted = false
	end)

	-- Shift di PC, L3 di controller. Tombol Lari untuk HP dibuat oleh UIController.
	ContextActionService:BindAction("Sprint", handleSprint, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)

	RunService.Heartbeat:Connect(step)
end

return StaminaController
