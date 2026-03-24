--!strict
-- LOCATION: StarterPlayerScripts/MiningController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService") -- ## ADDED ##

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PickaxesConfigurations = require(Modules:WaitForChild("PickaxesConfigurations"))

-- References for Animation, Sounds & UI
local Templates = ReplicatedStorage:WaitForChild("Templates")
local PickaxeAnimation = Templates:WaitForChild("PickaxeAnimation") :: Animation
local TimerGUI_Template = Templates:WaitForChild("TimerGUI") :: BillboardGui
local CrackTemplate = Templates:WaitForChild("Crack") :: Decal 
local globalSounds = Workspace:WaitForChild("Sounds") 

local player = Players.LocalPlayer

local MINING_RANGE = 25 
local lastSwingTime = 0
local activeToolConnection: RBXScriptConnection? = nil
local currentAnimationTrack: AnimationTrack? = nil 

local activeHighlights: {[BasePart]: SelectionBox} = {}
local highlightLoop: RBXScriptConnection? = nil

-- [ JUICE: HIGHLIGHT LOGIC ]
local function clearHighlights()
	for part, box in pairs(activeHighlights) do
		if box then box:Destroy() end
	end
	table.clear(activeHighlights)
end

local function updateHighlights(tool: Tool)
	local config = PickaxesConfigurations.Pickaxes[tool.Name]
	if not config then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	local handle = tool:FindFirstChild("Handle") :: BasePart
	local centerPosition = handle and handle.Position or root.Position

	local bonusRange = player:GetAttribute("BonusRange") or 0
	local radius = (config.Radius or 4) + bonusRange

	local validTargets = {}
	local minesFolder = Workspace:FindFirstChild("Mines")
	if minesFolder then
		for _, child in ipairs(minesFolder:GetChildren()) do
			if child.Name:match("LocalOres_") then
				table.insert(validTargets, child)
			end
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = validTargets
	overlapParams.FilterType = Enum.RaycastFilterType.Include

	local hitParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, overlapParams)
	local currentFrameParts = {}

	for _, hitPart in ipairs(hitParts) do
		if hitPart.Parent and hitPart.Parent.Name:match("LocalOres_") then
			local hp = hitPart:GetAttribute("Health")

			if type(hp) == "number" and hp > 0 and hitPart.Transparency < 1 then
				currentFrameParts[hitPart] = true

				if not activeHighlights[hitPart] then
					local box = Instance.new("SelectionBox")
					box.Adornee = hitPart
					box.Color3 = Color3.fromRGB(255, 255, 255)
					box.LineThickness = 0.05
					box.SurfaceColor3 = Color3.fromRGB(255, 255, 255)
					box.SurfaceTransparency = 0.9 
					box.Parent = hitPart
					activeHighlights[hitPart] = box
				end
			end
		end
	end

	for part, box in pairs(activeHighlights) do
		if not currentFrameParts[part] then
			if box then box:Destroy() end
			activeHighlights[part] = nil
		end
	end
end

-- [ JUICE: SOUND EFFECTS ]
local function playLocalSound(soundName: string)
	local soundTemplate = globalSounds:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local newSound = soundTemplate:Clone()
		newSound.PlaybackSpeed = newSound.PlaybackSpeed * (math.random(90, 110) / 100)
		newSound.Parent = Workspace.CurrentCamera
		newSound:Play()
		Debris:AddItem(newSound, newSound.TimeLength + 0.1)
	end
end

-- [ JUICE: CAMERA SHAKE ]
local function shakeCamera()
	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid") :: Humanoid
	if not humanoid then return end

	task.spawn(function()
		for i = 1, 4 do
			local offsetX = (math.random() - 0.5) * 0.3
			local offsetY = (math.random() - 0.5) * 0.3
			local offsetZ = (math.random() - 0.5) * 0.3
			humanoid.CameraOffset = Vector3.new(offsetX, offsetY, offsetZ)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.new(0, 0, 0)
	end)
end

-- [ JUICE: ORE SHAKE ]
local function shakeOre(orePart: BasePart)
	local origCFrame = orePart:GetAttribute("OriginalCFrame")
	if not origCFrame then
		origCFrame = orePart.CFrame
		orePart:SetAttribute("OriginalCFrame", origCFrame)
	end

	task.spawn(function()
		for i = 1, 4 do
			if not orePart.Parent then break end
			local offsetX = (math.random() - 0.5) * 0.4
			local offsetY = (math.random() - 0.5) * 0.4
			local offsetZ = (math.random() - 0.5) * 0.4
			orePart.CFrame = origCFrame * CFrame.new(offsetX, offsetY, offsetZ)
			task.wait(0.03)
		end
		if orePart.Parent then
			orePart.CFrame = origCFrame
		end
	end)
end

-- [ JUICE: PHYSICAL DEBRIS CHUNKS ]
local function spawnDebris(orePart: BasePart, amount: number)
	local origColor = orePart:GetAttribute("OriginalColor") or orePart.Color

	for i = 1, amount do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(0.6, 0.6, 0.6)
		chunk.Color = origColor
		chunk.Material = Enum.Material.Slate
		chunk.CanCollide = false

		local offset = Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 3, (math.random() - 0.5) * 3)
		chunk.CFrame = orePart.CFrame * CFrame.new(offset)
		chunk.Parent = Workspace

		chunk.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 35, math.random(25, 45), (math.random() - 0.5) * 35)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))

		local shrinkTween = TweenService:Create(
			chunk, 
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.2), 
			{Size = Vector3.new(0, 0, 0)}
		)
		shrinkTween:Play()

		Debris:AddItem(chunk, 0.8)
	end
end

-- [ HELPER: APPLY DAMAGE ]
local function applyDamageToOre(orePart: BasePart, damage: number)
	local currentHp = orePart:GetAttribute("Health")
	local maxHp = orePart:GetAttribute("MaxHealth")

	if type(currentHp) ~= "number" or type(maxHp) ~= "number" then return end

	currentHp -= damage

	local oreFolder = orePart.Parent
	if oreFolder and not oreFolder:GetAttribute("Impacted") then
		oreFolder:SetAttribute("Impacted", true)
	end

	local origColor = orePart:GetAttribute("OriginalColor")
	if not origColor then
		origColor = orePart.Color
		orePart:SetAttribute("OriginalColor", origColor)

		for _, child in ipairs(orePart:GetChildren()) do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:SetAttribute("OriginalColor", child.Color3)
			end
		end
	end

	-- Health Percentage (0 to 1)
	local hpPercent = math.clamp(currentHp / maxHp, 0, 1)

	-- Break the Ore
	if currentHp <= 0 then
		spawnDebris(orePart, math.random(4, 7)) 

		orePart.Transparency = 1
		orePart.CanCollide = false
		Debris:AddItem(orePart, 0.1)
		return 
	else
		orePart:SetAttribute("Health", currentHp)
		shakeOre(orePart)
		spawnDebris(orePart, math.random(1, 2))

		-- CRACK DECAL LOGIC
		if CrackTemplate then
			for _, normalId in ipairs(Enum.NormalId:GetEnumItems()) do
				local crackName = "Crack_" .. normalId.Name
				local crackDecal = orePart:FindFirstChild(crackName) :: Decal

				if not crackDecal then
					crackDecal = CrackTemplate:Clone()
					crackDecal.Name = crackName
					crackDecal.Face = normalId
					crackDecal.Transparency = 1 
					crackDecal.Parent = orePart
				end

				crackDecal.Transparency = hpPercent
			end
		end
	end

	-- Darken Color as it takes damage
	local targetColor = origColor:Lerp(Color3.new(0, 0, 0), 1 - hpPercent)
	orePart.Color = targetColor

	for _, child in ipairs(orePart:GetChildren()) do
		if child:IsA("Texture") or child:IsA("Decal") then
			local texOrigColor = child:GetAttribute("OriginalColor")
			if texOrigColor and not child.Name:match("Crack_") then
				child.Color3 = texOrigColor:Lerp(Color3.new(0, 0, 0), 1 - hpPercent)
			end
		end
	end

	-- Hit Flash Effect
	local originalTransparency = orePart.Transparency
	orePart.Transparency = 0.5
	task.delay(0.1, function()
		if orePart.Parent and orePart.Transparency == 0.5 then 
			orePart.Transparency = originalTransparency 
		end
	end)
end

-- [ CORE MINING LOGIC ]
local function attemptMine(tool: Tool)
	local config = PickaxesConfigurations.Pickaxes[tool.Name]
	if not config then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	-- 1. Check Cooldown
	local now = tick()
	if now - lastSwingTime < config.Cooldown then return end
	lastSwingTime = now

	-- 2. Play Animations & Sounds
	if currentAnimationTrack then
		currentAnimationTrack:Play()
	end
	playLocalSound("Swing") 

	-- TRIGGER COOLDOWN UI
	local handle = tool:FindFirstChild("Handle") :: BasePart
	if handle then
		local timerGui = handle:FindFirstChild("TimerGUI") :: BillboardGui
		if timerGui then
			local bar = timerGui:FindFirstChild("Bar")
			local progress = bar and bar:FindFirstChild("Progress") :: Frame
			local textLbl = bar and bar:FindFirstChild("Text") :: TextLabel

			if progress and textLbl then
				timerGui.Enabled = true

				progress.Size = UDim2.fromScale(1, 1)

				local tweenInfo = TweenInfo.new(config.Cooldown, Enum.EasingStyle.Linear)
				TweenService:Create(progress, tweenInfo, {Size = UDim2.fromScale(0, 1)}):Play()

				task.spawn(function()
					local endTime = tick() + config.Cooldown
					while tick() < endTime do
						if tool.Parent ~= char or not timerGui.Parent then break end 

						local remain = math.max(0, endTime - tick())
						textLbl.Text = string.format("%.1fs", remain)
						task.wait(0.03)
					end

					if timerGui and timerGui.Parent then
						textLbl.Text = "0.0s"
						timerGui.Enabled = false
					end
				end)
			end
		end
	end

	-- 3. Deal Damage
	local centerPosition = handle and handle.Position or root.Position
	local bonusRange = player:GetAttribute("BonusRange") or 0
	local radius = (config.Radius or 4) + bonusRange

	local validTargets = {}
	local minesFolder = Workspace:FindFirstChild("Mines")
	if minesFolder then
		for _, child in ipairs(minesFolder:GetChildren()) do
			if child.Name:match("LocalOres_") then
				table.insert(validTargets, child)
			end
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = validTargets
	overlapParams.FilterType = Enum.RaycastFilterType.Include

	local hitParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, overlapParams)
	local hitAnything = false

	for _, hitPart in ipairs(hitParts) do
		if hitPart.Parent and hitPart.Parent.Name:match("LocalOres_") then
			applyDamageToOre(hitPart, config.Damage)
			hitAnything = true
		end
	end

	if hitAnything then
		shakeCamera()
		playLocalSound("Pickaxe")
	end
end

-- [ TOOL LISTENER ]
local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and PickaxesConfigurations.Pickaxes[child.Name] then

			local handle = child:WaitForChild("Handle", 2) :: BasePart
			if handle then
				local existingTimer = handle:FindFirstChild("TimerGUI")
				if not existingTimer then
					local newTimer = TimerGUI_Template:Clone()
					newTimer.Enabled = false
					newTimer.Parent = handle
				else
					existingTimer.Enabled = false
				end
			end

			currentAnimationTrack = animator:LoadAnimation(PickaxeAnimation)

			if activeToolConnection then activeToolConnection:Disconnect() end

			-- ## FIXED: Use UserInputService to perfectly detect Mobile Taps, PC Clicks, and Console Triggers ##
			activeToolConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
				-- Ignore taps that hit UI buttons or the movement thumbstick
				if gameProcessedEvent then return end 

				if input.UserInputType == Enum.UserInputType.MouseButton1 
					or input.UserInputType == Enum.UserInputType.Touch 
					or input.KeyCode == Enum.KeyCode.ButtonR2 then

					attemptMine(child)
				end
			end)

			if highlightLoop then highlightLoop:Disconnect() end
			highlightLoop = RunService.RenderStepped:Connect(function()
				updateHighlights(child)
			end)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			if activeToolConnection then 
				activeToolConnection:Disconnect() 
				activeToolConnection = nil 
			end
			if currentAnimationTrack then
				currentAnimationTrack:Stop()
				currentAnimationTrack:Destroy()
				currentAnimationTrack = nil
			end

			if highlightLoop then
				highlightLoop:Disconnect()
				highlightLoop = nil
			end
			clearHighlights()
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

print("[MiningController] Juiced Mining + Mobile Tap Support Active!")