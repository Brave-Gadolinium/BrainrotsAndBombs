--!strict
-- LOCATION: ReplicatedStorage/Modules/Fireworks

local Fireworks = {}

--[ Services ]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace") -- ## ADDED ##

--[ Variables ]--
local FireworkAssets = ReplicatedStorage:WaitForChild("Particles")

-- ## ADDED: Sound References ##
local SoundFolder = Workspace:WaitForChild("Sounds")
local FireworkSound = SoundFolder:WaitForChild("Fireworks") :: Sound

--[ Utils ]--
local RNG = Random.new()
local Colors = {
	Color3.fromRGB(255, 49, 49),
	Color3.fromRGB(255, 179, 55),
	Color3.fromRGB(255, 255, 53),
	Color3.fromRGB(105, 255, 79),
	Color3.fromRGB(70, 252, 255),
	Color3.fromRGB(193, 85, 255),
	Color3.fromRGB(255, 169, 225) 
}

local function MakeFirework(position: CFrame)
	if not position then return end

	task.spawn(function()
		local RandomColor = Colors[RNG:NextInteger(1, #Colors)]

		local NewPart = Instance.new("Part")
		NewPart.CanCollide = false
		NewPart.Anchored = true
		NewPart.CFrame = position
		NewPart.Size = Vector3.new()
		NewPart.Transparency = 1
		NewPart.Name = "Firework"
		NewPart.Parent = game.Workspace

		local Trail = FireworkAssets:FindFirstChild("Trail")
		if Trail then
			local newTrail = Trail:Clone()
			newTrail.Parent = NewPart
			task.delay(1, function()
				if newTrail then newTrail.Enabled = false end
			end)
		end

		local Time = RNG:NextNumber(8, 11)
		local Height = RNG:NextNumber(4, 7)

		local tween = TweenService:Create(NewPart, TweenInfo.new(Time / 10, Enum.EasingStyle.Linear), {CFrame = position + Vector3.new(0, Height, 0)})
		tween:Play()

		task.wait(1)

		local ExplosionParticle = FireworkAssets:FindFirstChild("Explosion")
		if ExplosionParticle then
			local newExplosion = ExplosionParticle:Clone() :: ParticleEmitter
			newExplosion.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, RandomColor), ColorSequenceKeypoint.new(1, RandomColor) })
			newExplosion.Parent = NewPart
			newExplosion:Emit(25)
		end

		-- ## ADDED: Play Sound at Explosion ##
		if FireworkSound then
			local soundClone = FireworkSound:Clone()
			soundClone.Parent = NewPart -- Parent to part so it destroys with it
			soundClone:Play()
		end

		Debris:AddItem(NewPart, 4)
	end)
end

function Fireworks.PlayFireworks(object: BasePart)
	if not object then return end

	local NumberOfFireworks = RNG:NextInteger(4, 6)
	local WhenToStop = 0

	while WhenToStop < NumberOfFireworks do
		MakeFirework(object.CFrame * CFrame.new(RNG:NextNumber(-4, 4), -2, RNG:NextNumber(-4, 4)))
		WhenToStop += 1
	end
end

return Fireworks