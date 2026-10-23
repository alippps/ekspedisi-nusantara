-- Mode terbang buat perintah debug /fly (cuma Studio). DebugService (server) yang nyalain lewat attribute DebugFly;
-- di sini cuma geraknya:
-- * PC: WASD searah kamera (datar), Space naik, Ctrl turun.
-- * HP: joystick searah kamera, termasuk naik/turun kalau kamera nunduk/mendongak.
-- Gravitasi dimatiin: LinearVelocity tanpa batas gaya nahan karakter, jadi diam = melayang.
-- Kecepatan = attribute DebugSpeed (/speed N), kalau belum diset pakai Config.Stamina.WalkSpeed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local player = Players.LocalPlayer

local DebugController = {}

type Flight = {
	attachment: Attachment,
	velocity: LinearVelocity,
	align: AlignOrientation,
	humanoid: Humanoid,
}

local controls: any = nil -- ControlModule bawaan Roblox: arah joystick HP / gamepad
local flight: Flight? = nil

-- Arah tombol PC, format sama dengan GetMoveVector: X = kanan, Z = belakang
local KEY_MOVES = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.Up] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.Down] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.Left] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
	[Enum.KeyCode.Right] = Vector3.new(1, 0, 0),
}

local function keyboardMove(): Vector3
	local move = Vector3.zero
	for key, direction in KEY_MOVES do
		if UserInputService:IsKeyDown(key) then
			move += direction
		end
	end
	return move
end

-- Arah input (X = kanan, Z = belakang): tombol PC dibaca langsung; joystick dari ControlModule,
-- kalau itu nol/nggak ada, terakhir dari Humanoid.MoveDirection (diubah balik relatif kamera).
local function inputMove(humanoid: Humanoid, flatLook: Vector3, flatRight: Vector3): Vector3
	if not UserInputService:GetFocusedTextBox() then
		local keys = keyboardMove()
		if keys.Magnitude > 0 then
			return keys
		end
	end
	if controls then
		local move: Vector3 = controls:GetMoveVector()
		if move.Magnitude > 0.01 then
			return move
		end
	end
	local world = humanoid.MoveDirection
	return Vector3.new(world:Dot(flatRight), 0, -world:Dot(flatLook))
end

local function flySpeed(): number
	local speed = player:GetAttribute("DebugSpeed")
	return if type(speed) == "number" then speed else Config.Stamina.WalkSpeed
end

local function usesTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function stopFlying()
	local current = flight
	if not current then
		return
	end
	flight = nil
	current.attachment:Destroy() -- LinearVelocity & AlignOrientation ikut kehapus
	if current.humanoid.Parent then
		current.humanoid.PlatformStand = false
		current.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function startFlying()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if flight or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DebugFly"
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = math.huge
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = attachment
	-- Badan tetap tegak, hadap ke arah kamera
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = root.CFrame.Rotation
	align.Parent = attachment
	attachment.Parent = root

	humanoid.PlatformStand = true -- Humanoid berhenti jalan/lompat sendiri selama terbang
	flight = { attachment = attachment, velocity = velocity, align = align, humanoid = humanoid }
end

local function refresh()
	if player:GetAttribute("DebugFly") == true then
		startFlying()
	else
		stopFlying()
	end
end

local function step()
	local current = flight
	if not current then
		return
	end
	if not current.attachment.Parent or current.humanoid.Health <= 0 then
		stopFlying()
		return
	end

	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local flatRight = Vector3.new(right.X, 0, right.Z)
	flatRight = if flatRight.Magnitude > 0.01 then flatRight.Unit else Vector3.new(1, 0, 0)

	local move = inputMove(current.humanoid, flatLook, flatRight) -- maju = Z negatif
	local direction: Vector3
	if usesTouch() then
		direction = look * -move.Z + right * move.X
	else
		direction = flatLook * -move.Z + flatRight * move.X
		if not UserInputService:GetFocusedTextBox() then -- lagi ngetik di chat: Space/Ctrl jangan dihitung
			if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
				direction += Vector3.yAxis
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
				direction -= Vector3.yAxis
			end
		end
	end
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end

	current.velocity.VectorVelocity = direction * flySpeed()
	current.align.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
end

function DebugController.start()
	if not RunService:IsStudio() then
		return
	end
	task.spawn(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		local ok, result = pcall(function()
			return (require(playerModule :: ModuleScript) :: any):GetControls()
		end)
		if ok and result then
			controls = result
		else
			warn("[DebugController] ControlModule nggak kebaca, joystick terbang pakai Humanoid.MoveDirection:", result)
		end
	end)

	player:GetAttributeChangedSignal("DebugFly"):Connect(refresh)
	-- Respawn pas lagi terbang: karakter baru langsung terbang lagi
	player.CharacterAdded:Connect(function(character)
		stopFlying()
		character:WaitForChild("Humanoid")
		character:WaitForChild("HumanoidRootPart")
		refresh()
	end)
	refresh()
	RunService.RenderStepped:Connect(step)
end

return DebugController
