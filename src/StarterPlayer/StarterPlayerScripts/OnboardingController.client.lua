--!strict
-- LOCATION: StarterPlayerScripts/OnboardingController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [ ASSETS ]
local Templates = ReplicatedStorage:WaitForChild("Templates")
local BeamTemplate = Templates:WaitForChild("OnboardingBeam")
local Events = ReplicatedStorage:WaitForChild("Events")
local SetStepEvent = Events:WaitForChild("SetOnboardingStep")

-- [ UI REFERENCES ]
local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local notifFrame = frames:WaitForChild("Notifications")
local instructionsLabel = notifFrame:WaitForChild("Instructions") :: TextLabel

-- [ CONFIG ]
local MAX_SEARCH_DIST = 500

-- [ STATE ]
local currentStep = 0
local activeBeam: Beam?
local activeAttachment0: Attachment?
local activeAttachment1: Attachment?
local targetItem: Model?
local savedItemName: string = "Item" 

print("[OnboardingController] Initialized (2-Step Fast Track - Pickaxe Ignored)")

-- [ HELPERS ]

local function getCharacter()
	return player.Character or player.CharacterAdded:Wait()
end

local function findClosestItem(): Model?
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return nil end

	local closestItem = nil
	local minDist = MAX_SEARCH_DIST

	local spawners = Workspace:WaitForChild("Mines")

	-- Loop through every mine zone
	for _, spawner in ipairs(spawners:GetChildren()) do
		-- Loop through every item inside that mine zone
		for _, item in ipairs(spawner:GetChildren()) do
			if item.Name == "SpawnedItem" and item:IsA("Model") and item:GetAttribute("IsSpawnedItem") then
				local prim = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
				if prim then
					local dist = (prim.Position - root.Position).Magnitude
					if dist < minDist then
						minDist = dist
						closestItem = item
					end
				end
			end
		end
	end

	return closestItem
end

local function cleanupVisuals()
	if activeBeam then activeBeam:Destroy() end
	if activeAttachment0 then activeAttachment0:Destroy() end
	if activeAttachment1 then activeAttachment1:Destroy() end

	activeBeam = nil
	activeAttachment0 = nil
	activeAttachment1 = nil
	targetItem = nil

	instructionsLabel.Visible = false
end

local function setupBeam(targetPart: BasePart)
	local char = getCharacter()
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart

	cleanupVisuals()

	local att0 = Instance.new("Attachment")
	att0.Name = "OnboardingAtt0"
	att0.Parent = root
	activeAttachment0 = att0

	local att1 = Instance.new("Attachment")
	att1.Name = "OnboardingAtt1"
	att1.Parent = targetPart
	activeAttachment1 = att1

	local beam = BeamTemplate:Clone()
	beam.Attachment0 = att1 -- Target
	beam.Attachment1 = att0 -- Player
	beam.Parent = root
	activeBeam = beam
end

-- ## FIXED: Now explicitly checks for the "Mutation" attribute so it ignores Pickaxes! ##
local function hasPickedUpItem(): boolean
	local char = player.Character
	if char then
		-- Check if carrying it physically
		if char:FindFirstChild("HeadStackItem") or char:FindFirstChild("StackItem") then return true end

		-- Check if holding it (must be a Tycoon Item, not a Pickaxe)
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then return true end
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		-- Check if it's in the backpack (must be a Tycoon Item, not a Pickaxe)
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then return true end
		end
	end

	return false
end

-- Checks if the player has successfully placed an item on their plot
local function hasPlacedItem(): boolean
	local plotName = "Plot_" .. player.Name
	local plot = Workspace:FindFirstChild(plotName)
	if not plot then return false end

	local floor1 = plot:FindFirstChild("Floor1")
	local slots = floor1 and floor1:FindFirstChild("Slots")
	if slots then
		for _, slot in ipairs(slots:GetChildren()) do
			local sp = slot:FindFirstChild("Spawn")
			if sp and sp:FindFirstChild("VisualItem") then
				return true
			end
		end
	end
	return false
end

-- [ FORWARD DECLARATIONS ]
local startStep1, startStep2

-- [ STEP 1: PICK UP ITEM ]

startStep1 = function()
	currentStep = 1

	-- If they already placed an item somehow, skip the whole tutorial!
	if hasPlacedItem() then
		print("[Onboarding] Already placed an item. Skipping.")
		SetStepEvent:FireServer(6)
		currentStep = 6
		return
	end

	-- If they already have an item, go straight to step 2
	if hasPickedUpItem() then
		print("[Onboarding] Step 1 Auto-Complete")
		SetStepEvent:FireServer(2)
		startStep2()
		return
	end

	local target = findClosestItem()
	if not target then
		task.delay(1, startStep1)
		return
	end

	targetItem = target
	savedItemName = targetItem:GetAttribute("OriginalName") or "Item"

	local targetPart = targetItem.PrimaryPart or targetItem:FindFirstChildWhichIsA("BasePart")
	if not targetPart then return end

	setupBeam(targetPart)

	instructionsLabel.Text = "Pick up a " .. savedItemName .. "!"
	instructionsLabel.Visible = true

	task.spawn(function()
		while currentStep == 1 do
			if hasPickedUpItem() then
				print("[Onboarding] Step 1 Complete")
				cleanupVisuals()
				SetStepEvent:FireServer(2) 
				startStep2()
				break
			end

			if targetItem and not targetItem.Parent then
				task.wait(0.1) 
				if hasPickedUpItem() then
					print("[Onboarding] Step 1 Complete")
					cleanupVisuals()
					SetStepEvent:FireServer(2)
					startStep2()
					break
				else
					print("[Onboarding] Item lost, finding new one...")
					cleanupVisuals()
					startStep1()
					break
				end
			end

			task.wait(0.2)
		end
	end)
end

-- [ STEP 2: PLACE ON PLOT ]

startStep2 = function()
	currentStep = 2

	if hasPlacedItem() then
		print("[Onboarding] Step 2 Auto-Complete")
		cleanupVisuals()
		SetStepEvent:FireServer(6) -- 6 triggers the end & Group rewards on the server!
		currentStep = 6
		return
	end

	local plotName = "Plot_" .. player.Name
	local plot = Workspace:WaitForChild(plotName, 10)
	if not plot then return end

	local floor1 = plot:WaitForChild("Floor1", 10)
	local slots = floor1 and floor1:WaitForChild("Slots", 10)
	local slot1 = slots and slots:WaitForChild("Slot1", 10)
	local spawnPart = slot1 and slot1:WaitForChild("Spawn", 10) :: BasePart

	if spawnPart then setupBeam(spawnPart) end

	instructionsLabel.Text = "Place " .. savedItemName .. " on your plot!"
	instructionsLabel.Visible = true

	task.spawn(function()
		while currentStep == 2 do
			if hasPlacedItem() then
				print("[Onboarding] ALL STEPS COMPLETE")
				cleanupVisuals()
				SetStepEvent:FireServer(6) -- We use 6 so the Server's GroupReward check still fires
				currentStep = 6
				break
			end

			-- If they drop it or sell it before placing it, send them back to step 1
			if not hasPickedUpItem() then
				print("[Onboarding] Player lost item, returning to Step 1")
				cleanupVisuals()
				SetStepEvent:FireServer(1)
				startStep1()
				break
			end

			task.wait(0.2)
		end
	end)
end

-- [ INIT ]

local function initializeOnboarding()
	local savedStep = player:GetAttribute("OnboardingStep")

	if not savedStep then
		task.spawn(function()
			while not savedStep do
				task.wait(0.5)
				savedStep = player:GetAttribute("OnboardingStep")
			end
			initializeOnboarding() 
		end)
		return
	end

	print("[Onboarding] Starting from Step:", savedStep)

	if savedStep == 1 then startStep1()
	elseif savedStep == 2 then startStep2()
	else
		print("[Onboarding] Already Completed.")
	end
end

task.spawn(function()
	task.wait(2)
	initializeOnboarding()
end)

player.CharacterAdded:Connect(function()
	task.wait(1)
	cleanupVisuals()

	if currentStep == 1 then startStep1()
	elseif currentStep == 2 then startStep2()
	end
end)