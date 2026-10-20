-- Siklus siang/malam. Service lain cek DayNightService.isDay().
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local D = Config.DayNight

local DayNightService = {}

function DayNightService.isDay(): boolean
	local t = Lighting.ClockTime
	return t >= D.DayStart and t < D.DayEnd
end

function DayNightService.start()
	Lighting.ClockTime = D.StartClock
	RunService.Heartbeat:Connect(function(dt)
		Lighting.ClockTime = (Lighting.ClockTime + dt * 24 / D.CycleSeconds) % 24
	end)
end

return DayNightService
