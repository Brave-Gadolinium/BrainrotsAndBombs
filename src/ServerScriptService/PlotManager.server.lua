--!strict
-- LOCATION: ServerScriptService/PlotManager

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

-- Modules
local PlayerController = require(ServerScriptService.Controllers.PlayerController)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local SpawnUtils = require(ServerScriptService.Modules.SpawnUtils)
local PlotRuntimeBridge = require(ServerScriptService.Modules.PlotRuntimeBridge)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local BoosterService = require(ServerScriptService.Modules.BoosterService)

-- Assets
local Templates = ReplicatedStorage:WaitForChild("Templates")
local PlotTemplate = Templates:WaitForChild("Plot")
local PlotEmptyTemplate = Templates:WaitForChild("PlotEmpty")
local PlotsFolder = Workspace:WaitForChild("Plots")
local Events = ReplicatedStorage:WaitForChild("Events")

local COLLECT_ALL_GAMEPASS = ProductConfigurations.GamePasses.CollectAll or 1783037385
local COLLECT_ALL_COOLDOWN = 0.8
local COLLECT_ALL_BUTTON_NAME = "CollectAll"
local UPGRADE_SLOTS_BUTTON_NAME = "UpgradeSlotsButton"
local UPGRADE_BASE_TEMPLATE_NAME = "UpgradeBase"
local UPGRADE_BASE_EFFECT_NAME = "_UpgradeBaseEffect"
local UPGRADE_BASE_EFFECT_DURATION = 2
local UPGRADE_BASE_EFFECT_LIFT = 0.05
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()
local TUTORIAL_PLACE_BRAINROT_STEP = math.max(1, math.floor(tonumber(TutorialConfiguration.PlotSpawnUnlockStep) or 5))

-- State
local occupiedPlots = {}
local activePlotModels = {}
local activeEmptyPlotModels = {}
local collectAllDebounce = {}

local PlotManager = {}

function PlotManager.GetPrice(unlockedSlots: number)
	local upgradeData = SlotUnlockConfigurations.GetUpgradeData(unlockedSlots)
	return upgradeData and upgradeData.money_req or 0
end

function PlotManager.GetMaxLevel()
	return #SlotUnlockConfigurations.new_slots
end

local function getOnboardingStepForSpawn(player: Player): number
	local attributeStep = tonumber(player:GetAttribute("OnboardingStep"))
	if attributeStep then
		return attributeStep
	end

	local profile = PlayerController:GetProfile(player)
	if profile and profile.Data then
		return tonumber(profile.Data.OnboardingStep) or 1
	end

	return 1
end

local function getPlotLocator(index: number): BasePart?
	local locator = PlotsFolder:FindFirstChild(tostring(index))
	if locator and locator:IsA("BasePart") then
		return locator
	end

	return nil
end

local function getPlotIndices(): {number}
	local indices = {}

	for _, child in ipairs(PlotsFolder:GetChildren()) do
		local index = tonumber(child.Name)
		if index and child:IsA("BasePart") then
			table.insert(indices, index)
		end
	end

	table.sort(indices)
	return indices
end

local function isPlotIndexOccupied(index: number): boolean
	for _, occupiedIndex in pairs(occupiedPlots) do
		if occupiedIndex == index then
			return true
		end
	end

	return false
end

local function getFreePlotIndex(): number?
	for _, index in ipairs(getPlotIndices()) do
		if not isPlotIndexOccupied(index) then
			return index
		end
	end
	return nil
end

local function pivotInstanceToCFrame(instance: Instance, cframe: CFrame)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	else
		warn(`[PlotManager] Unsupported plot template class "{instance.ClassName}"`)
	end
end

local function destroyEmptyPlot(index: number)
	local existing = activeEmptyPlotModels[index]
	if existing then
		existing:Destroy()
		activeEmptyPlotModels[index] = nil
	end
end

local function spawnEmptyPlot(index: number)
	if activeEmptyPlotModels[index] or isPlotIndexOccupied(index) then
		return
	end

	local locator = getPlotLocator(index)
	if not locator then
		warn(`[PlotManager] Locator {index} not found for empty plot`)
		return
	end

	local emptyPlot = PlotEmptyTemplate:Clone()
	emptyPlot.Name = PlotEmptyTemplate.Name
	emptyPlot:SetAttribute("BaseNumber", index)
	emptyPlot:SetAttribute("IsEmptyPlot", true)
	emptyPlot.Parent = Workspace
	pivotInstanceToCFrame(emptyPlot, locator.CFrame)

	activeEmptyPlotModels[index] = emptyPlot
end

local function refreshEmptyPlots()
	for _, index in ipairs(getPlotIndices()) do
		if isPlotIndexOccupied(index) then
			destroyEmptyPlot(index)
		else
			spawnEmptyPlot(index)
		end
	end
end

local function hasBrainrotTool(container: Instance?): boolean
	if not container then
		return false
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Mutation") ~= nil then
			return true
		end
	end

	return false
end

local function hasBrainrotInSavedInventory(player: Player): boolean
	local profile = PlayerController:GetProfile(player)
	local inventory = profile and profile.Data and profile.Data.Inventory
	if type(inventory) ~= "table" then
		return false
	end

	for _, itemData in pairs(inventory) do
		if type(itemData) == "table" and itemData.Mutation ~= nil then
			return true
		end
	end

	return false
end

local function hasTutorialBrainrot(player: Player): boolean
	local character = player.Character
	if character then
		if character:FindFirstChild("StackItem") or character:FindFirstChild("HeadStackItem") then
			return true
		end

		if hasBrainrotTool(character) then
			return true
		end
	end

	return hasBrainrotTool(player:FindFirstChild("Backpack")) or hasBrainrotInSavedInventory(player)
end

local function shouldUseMineSpawnForEarlyTutorial(player: Player): boolean
	local onboardingStep = getOnboardingStepForSpawn(player)
	return onboardingStep <= TUTORIAL_PLACE_BRAINROT_STEP and not hasTutorialBrainrot(player)
end

local function getRotationOnly(cf: CFrame): CFrame
	return cf - cf.Position
end

local function findUpgradeBaseAnchorPart(root: Instance): BasePart?
	local bestPart: BasePart? = nil
	local bestScore = -math.huge

	local function considerPart(part: BasePart)
		local areaScore = part.Size.X * part.Size.Z
		local nameScore = 0
		local lowerName = string.lower(part.Name)

		if string.find(lowerName, "floor", 1, true) then
			nameScore += 1000000
		end

		if string.find(lowerName, "base", 1, true) then
			nameScore += 500000
		end

		if part.Transparency >= 1 then
			nameScore -= 250000
		end

		local score = areaScore + nameScore
		if score > bestScore then
			bestScore = score
			bestPart = part
		end
	end

	if root:IsA("BasePart") then
		considerPart(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			considerPart(descendant)
		end
	end

	return bestPart
end

local function getUpgradeBaseAnchor(plotModel: Model): (CFrame, number)
	local explicitAnchor = plotModel:FindFirstChild("UpgradeBasePrimary", true)
	if explicitAnchor and explicitAnchor:IsA("BasePart") then
		return explicitAnchor.CFrame, explicitAnchor.Size.Y
	end

	local floorRoot = plotModel:FindFirstChild("Floor1") or plotModel
	local floorPart = findUpgradeBaseAnchorPart(floorRoot)

	if floorPart then
		return floorPart.CFrame, floorPart.Size.Y
	end

	return plotModel:GetPivot(), 0
end

local function prepareUpgradeBaseEffect(effectInstance: Instance)
	local partsToPrepare: { BasePart } = {}

	if effectInstance:IsA("BasePart") then
		table.insert(partsToPrepare, effectInstance)
	end

	for _, descendant in ipairs(effectInstance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(partsToPrepare, descendant)
		end
	end

	for _, part in ipairs(partsToPrepare) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
	end
end

local function showUpgradeBaseEffect(plotModel: Model)
	local effectTemplate = Templates:FindFirstChild(UPGRADE_BASE_TEMPLATE_NAME, true)
	if not effectTemplate then
		warn(`[PlotManager] Missing template "{UPGRADE_BASE_TEMPLATE_NAME}" for base upgrade effect`)
		return
	end

	local existingEffect = plotModel:FindFirstChild(UPGRADE_BASE_EFFECT_NAME)
	if existingEffect then
		existingEffect:Destroy()
	end

	local effectClone = effectTemplate:Clone()
	effectClone.Name = UPGRADE_BASE_EFFECT_NAME
	prepareUpgradeBaseEffect(effectClone)

	local effectHeight = 0
	local templateRotation = CFrame.new()

	if effectClone:IsA("Model") then
		local pivot = effectClone:GetPivot()
		local success, _, boundingSize = pcall(function()
			return effectClone:GetBoundingBox()
		end)
		if not success or not boundingSize then
			warn(`[PlotManager] "{UPGRADE_BASE_TEMPLATE_NAME}" model has no bounding box and cannot be placed`)
			effectClone:Destroy()
			return
		end
		effectHeight = boundingSize.Y
		templateRotation = getRotationOnly(pivot)
	elseif effectClone:IsA("BasePart") then
		effectHeight = effectClone.Size.Y
		templateRotation = getRotationOnly(effectClone.CFrame)
	else
		warn(`[PlotManager] Unsupported "{UPGRADE_BASE_TEMPLATE_NAME}" template class "{effectClone.ClassName}"`)
		effectClone:Destroy()
		return
	end

	local anchorCFrame, anchorHeight = getUpgradeBaseAnchor(plotModel)
	local targetPosition = (anchorCFrame * CFrame.new(0, (anchorHeight * 0.5) + (effectHeight * 0.5) + UPGRADE_BASE_EFFECT_LIFT, 0)).Position
	local targetCFrame = CFrame.new(targetPosition) * getRotationOnly(anchorCFrame) * templateRotation

	effectClone.Parent = plotModel

	if effectClone:IsA("Model") then
		effectClone:PivotTo(targetCFrame)
	else
		effectClone.CFrame = targetCFrame
	end

	Debris:AddItem(effectClone, UPGRADE_BASE_EFFECT_DURATION)
end

local function normalizeSlotPartCollision(plotModel: Model)
	for _, child in ipairs(plotModel:GetChildren()) do
		local floorNumber = tonumber(child.Name:match("^Floor(%d+)$"))
		if floorNumber then
			local slotsFolder = child:FindFirstChild("Slots")
			if slotsFolder then
				for _, slotModel in ipairs(slotsFolder:GetChildren()) do
					if slotModel:IsA("Model") then
						for _, slotChild in ipairs(slotModel:GetChildren()) do
							if slotChild:IsA("BasePart") and slotChild.Name == "Part" then
								if slotChild:GetAttribute("OriginalTransparency") == nil then
									slotChild:SetAttribute("OriginalTransparency", slotChild.Transparency)
								end
								slotChild:SetAttribute("OriginalCanCollide", false)
								slotChild.CanCollide = false
							end
						end
					end
				end
			end
		end
	end
end

local function storeOriginalProperties(model: Instance)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if child:GetAttribute("OriginalTransparency") == nil then
				child:SetAttribute("OriginalTransparency", child.Transparency)
				child:SetAttribute("OriginalCanCollide", child.CanCollide)
			end
		end
	end
end

local function setModelVisibility(model: Instance, isVisible: boolean)
	for _, child in ipairs(model:GetDescendants()) do
		if child:IsA("BasePart") then
			if isVisible then
				child.Transparency = child:GetAttribute("OriginalTransparency") or 0
				local collide = child:GetAttribute("OriginalCanCollide")
				if collide == nil then
					collide = true
				end
				child.CanCollide = collide
			else
				child.Transparency = 1
				child.CanCollide = false
			end
		end
	end
end

local function setStandVisibility(slotModel: Model, isVisible: boolean)
	local standModel = slotModel:FindFirstChild("Stand")
	if not standModel then
		standModel = nil
	end

	if standModel then
		storeOriginalProperties(standModel)
		setModelVisibility(standModel, isVisible)
	end

	local collectTouch = slotModel:FindFirstChild("CollectTouch")
	if collectTouch and collectTouch:IsA("BasePart") then
		if collectTouch:GetAttribute("OriginalTransparency") == nil then
			collectTouch:SetAttribute("OriginalTransparency", collectTouch.Transparency)
			collectTouch:SetAttribute("OriginalCanCollide", collectTouch.CanCollide)
		end

		if isVisible then
			collectTouch.Transparency = collectTouch:GetAttribute("OriginalTransparency") or 0
			local originalCanCollide = collectTouch:GetAttribute("OriginalCanCollide")
			if originalCanCollide == nil then
				originalCanCollide = true
			end
			collectTouch.CanCollide = originalCanCollide
		else
			collectTouch.Transparency = 1
			collectTouch.CanCollide = false
		end
	end
end

local function updateCollectSlotLabel(slotModel: Model)
	local collectPart = slotModel:FindFirstChild("CollectTouch")
	local gui = collectPart and collectPart:FindFirstChild("CollectGUI")
	local frame = gui and gui:FindFirstChild("CollectFrame")
	local label = frame and frame:FindFirstChild("Price")
	if label and label:IsA("TextLabel") then
		label.Text = "$0"
	end
end

local function collectAllFromPlot(player: Player, plotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile or not profile.Data or not profile.Data.Plots then
		return
	end

	local totalCollected = 0
	local multiplier = if player:GetAttribute("DoubleMoney") == true then 2 else 1

	for floorName, floorSlots in pairs(profile.Data.Plots) do
		for slotName, slotData in pairs(floorSlots) do
			if type(slotData) == "table" and slotData.Item then
				local stored = tonumber(slotData.Stored) or 0
				if stored > 0 then
					local amount = math.floor(stored)
					totalCollected += amount * multiplier
					slotData.Stored = 0
				end

				local floorModel = plotModel:FindFirstChild(floorName)
				local slotsFolder = floorModel and floorModel:FindFirstChild("Slots")
				local slotModel = slotsFolder and slotsFolder:FindFirstChild(slotName)
				if slotModel and slotModel:IsA("Model") then
					updateCollectSlotLabel(slotModel)
				end
			end
		end
	end

	local notif = Events:FindFirstChild("ShowNotification")
	if totalCollected > 0 then
		AnalyticsEconomyService:FlushBombIncome(player)
		PlayerController:AddMoney(player, totalCollected)
		AnalyticsEconomyService:LogCashSource(player, totalCollected, TRANSACTION_TYPES.Gameplay, "CollectAll", {
			feature = "collect_all",
			content_id = "CollectAll",
			context = "base",
		})
		TutorialService:HandleManualCollect(player, totalCollected)

		local popupEvent = Events:FindFirstChild("ShowCashPopUp")
		if popupEvent then
			popupEvent:FireClient(player, totalCollected)
		end

		if notif then
			notif:FireClient(player, "Collected $" .. NumberFormatter.Format(totalCollected), "Success")
		end
	else
		if notif then
			notif:FireClient(player, "No money to collect yet", "Error")
		end
	end
end

local function connectCollectAllButton(plotModel: Model, owner: Player)
	local button = plotModel:FindFirstChild(COLLECT_ALL_BUTTON_NAME, true)
	if not button or not button:IsA("BasePart") then
		return
	end

	if button:GetAttribute("CollectAllConnected") then
		return
	end
	button:SetAttribute("CollectAllConnected", true)

	button.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		if not character then
			return
		end

		local triggerPlayer = Players:GetPlayerFromCharacter(character)
		if triggerPlayer ~= owner then
			return
		end

		local now = tick()
		local last = collectAllDebounce[owner] or 0
		if now - last < COLLECT_ALL_COOLDOWN then
			return
		end
		collectAllDebounce[owner] = now

		local success, ownsPass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(owner.UserId, COLLECT_ALL_GAMEPASS)
		end)

		if success and ownsPass then
			collectAllFromPlot(owner, plotModel)
		else
			if BoosterService and BoosterService.RecordManualCollect then
				BoosterService:RecordManualCollect(owner)
			end
			MarketplaceService:PromptGamePassPurchase(owner, COLLECT_ALL_GAMEPASS)
		end
	end)
end

local function getAllSlotEntries(plotModel: Model)
	local slotEntries = {}

	for _, child in ipairs(plotModel:GetChildren()) do
		local floorNumber = tonumber(child.Name:match("^Floor(%d+)$"))
		if floorNumber then
			local slotsFolder = child:FindFirstChild("Slots")
			if slotsFolder then
				for _, slotModel in ipairs(slotsFolder:GetChildren()) do
					if slotModel:IsA("Model") then
						local slotNumber = tonumber(slotModel.Name:match("(%d+)")) or 0
						table.insert(slotEntries, {
							FloorNumber = floorNumber,
							SlotNumber = slotNumber,
							FloorModel = child,
							Model = slotModel,
						})
					end
				end
			end
		end
	end

	table.sort(slotEntries, function(a, b)
		if a.FloorNumber == b.FloorNumber then
			return a.SlotNumber < b.SlotNumber
		end
		return a.FloorNumber < b.FloorNumber
	end)

	return slotEntries
end

local function getEffectiveMaxSlots(plotModel: Model): number
	local slotEntries = getAllSlotEntries(plotModel)
	return math.min(#slotEntries, SlotUnlockConfigurations.MaxSlots)
end

local function getUpgradeSlotsFrame(plotModel: Model): Frame?
	local upgradeModel = plotModel:FindFirstChild(UPGRADE_SLOTS_BUTTON_NAME, true)
	local mainGui = upgradeModel and upgradeModel:FindFirstChild("MainGUI")
	local surfaceGui = mainGui and mainGui:FindFirstChild("SurfaceGuiA")
	local frame = surfaceGui and surfaceGui:FindFirstChild("FrameB")

	if frame and frame:IsA("Frame") then
		return frame
	end

	return nil
end

local function updateUpgradeSlotsButton(player: Player, plotModel: Model)
	
	local frame = getUpgradeSlotsFrame(plotModel)
	if not frame then
		return
	end

	local unlockedSlots = PlayerController:GetUnlockedSlots(player)
	local effectiveMaxSlots = getEffectiveMaxSlots(plotModel)
	local upgradeData = if unlockedSlots >= effectiveMaxSlots then nil else SlotUnlockConfigurations.GetUpgradeData(unlockedSlots)

	local countSlotsLabel = frame:FindFirstChild("CountSlots")
	if countSlotsLabel and countSlotsLabel:IsA("TextLabel") then
		countSlotsLabel.Text = tostring(math.min(unlockedSlots, effectiveMaxSlots)) .. "/" .. tostring(effectiveMaxSlots)
	end

	local headerLabel = frame:FindFirstChild("TextLabel")
	if headerLabel and headerLabel:IsA("TextLabel") then
		headerLabel.Text = "Upgrade Slots"
	end

	local upgradeButton = frame:FindFirstChild("UpgradeButton")
	if not upgradeButton or not upgradeButton:IsA("TextButton") then
		return
	end

	local costLabel = upgradeButton:FindFirstChild("CostText")
	if not upgradeData then
		upgradeButton.Active = false
		upgradeButton.AutoButtonColor = false
		upgradeButton.Text = "MAX"
		if costLabel and costLabel:IsA("TextLabel") then
			--costLabel.Text = "MAX SLOTS"
		end
		return
	end

	upgradeButton.Active = true
	upgradeButton.AutoButtonColor = true
	--upgradeButton.Text = "UPGRADE"
	if costLabel and costLabel:IsA("TextLabel") then
		local isTutorialFree = TutorialService.IsTutorialBaseUpgradeFreeAvailable
			and TutorialService:IsTutorialBaseUpgradeFreeAvailable(player)
		if isTutorialFree then
			costLabel.Text = "Build - FREE"
		else
			costLabel.Text = "Build - $" .. NumberFormatter.Format(upgradeData.money_req)
		end
	end
end

local function updatePlotVisuals(player: Player)
	local plotModel = activePlotModels[player]
	if not plotModel then
		return
	end

	normalizeSlotPartCollision(plotModel)
	storeOriginalProperties(plotModel)

	local unlockedSlots = PlayerController:GetUnlockedSlots(player)
	local effectiveMaxSlots = getEffectiveMaxSlots(plotModel)
	local slotEntries = getAllSlotEntries(plotModel)
	local visibleSlots = math.min(unlockedSlots, effectiveMaxSlots)
	local unlockedFloorCount = math.max(1, math.ceil(visibleSlots / 10))

	for _, child in ipairs(plotModel:GetChildren()) do
		local floorNumber = tonumber(child.Name:match("^Floor(%d+)$"))
		if floorNumber then
			local isFloorUnlocked = floorNumber <= unlockedFloorCount
			setModelVisibility(child, isFloorUnlocked)

			local buyFloor = child:FindFirstChild("BuyFloor")
			if buyFloor then
				setModelVisibility(buyFloor, false)
			end
		end
	end

	for index, entry in ipairs(slotEntries) do
		local isUnlocked = index <= visibleSlots
		entry.Model:SetAttribute("IsUnlocked", isUnlocked)

		local isFloorUnlocked = entry.FloorNumber <= unlockedFloorCount
		if isFloorUnlocked then
			setStandVisibility(entry.Model, isUnlocked)
		else
			setStandVisibility(entry.Model, false)
		end
	end

	updateUpgradeSlotsButton(player, plotModel)
end

function PlotManager.RefreshPlayerPlot(player: Player)
	updatePlotVisuals(player)
end

PlotRuntimeBridge.SetRefreshHandler(function(player: Player)
	PlotManager.RefreshPlayerPlot(player)
end)

local function purchaseSlotUpgrade(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then
		return
	end

	local plotModel = activePlotModels[player]
	if not plotModel then
		return
	end

	local unlockedSlots = PlayerController:GetUnlockedSlots(player)
	local effectiveMaxSlots = getEffectiveMaxSlots(plotModel)
	local upgradeData = if unlockedSlots >= effectiveMaxSlots then nil else SlotUnlockConfigurations.GetUpgradeData(unlockedSlots)
	local notif = Events:FindFirstChild("ShowNotification")

	if not upgradeData then
		if notif then
			notif:FireClient(player, "All slots are already unlocked!", "Error")
		end
		updateUpgradeSlotsButton(player, plotModel)
		return
	end

	AnalyticsEconomyService:FlushBombIncome(player)
	local isTutorialFree = TutorialService.IsTutorialBaseUpgradeFreeAvailable
		and TutorialService:IsTutorialBaseUpgradeFreeAvailable(player)
	local price = if isTutorialFree then 0 else upgradeData.money_req

	if isTutorialFree or PlayerController:DeductMoney(player, price) then
		local newUnlockedSlots = PlayerController:AddUnlockedSlots(player, upgradeData.new_slots)
		if not isTutorialFree and price > 0 then
			AnalyticsEconomyService:LogCashSink(
				player,
				price,
				TRANSACTION_TYPES.Shop,
				`SlotUnlock:{unlockedSlots}->{newUnlockedSlots}`,
				{
					feature = "slot_unlock",
					content_id = tostring(newUnlockedSlots),
					context = "base",
				}
			)
		end
		AnalyticsFunnelsService:HandleExtraSlotsBought(player, newUnlockedSlots)
		TutorialService:HandlePostTutorialBaseUpgradePurchased(player)
		updatePlotVisuals(player)
		showUpgradeBaseEffect(plotModel)

		if notif then
			notif:FireClient(player, "Unlocked slots: " .. tostring(newUnlockedSlots), "Success")
		end
	else
		if notif then
			notif:FireClient(player, "Not enough Money!", "Error")
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "SlotUnlock",
		})
	end
end

local function spawnPlot(player: Player)
	local index = getFreePlotIndex()
	if not index then
		player:Kick("No plots available.")
		return
	end

	local locator = getPlotLocator(index)
	if not locator then
		warn(`[PlotManager] Locator {index} not found`)
		return
	end

	destroyEmptyPlot(index)
	occupiedPlots[player] = index

	local newPlot = PlotTemplate:Clone()
	newPlot.Name = "Plot_" .. player.Name
	newPlot:SetAttribute("OwnerUserId", player.UserId)
	newPlot:SetAttribute("OwnerName", player.Name)
	newPlot:SetAttribute("OwnerDisplayName", player.DisplayName)
	newPlot:SetAttribute("BaseNumber", index)
	newPlot.Parent = Workspace
	newPlot:SetPrimaryPartCFrame(locator.CFrame)

	local spawnPart = newPlot:FindFirstChild("Spawn")
	if spawnPart then
		local plotGui = spawnPart:FindFirstChild("PlotGUI")
		if plotGui and plotGui:IsA("SurfaceGui") then
			plotGui.Enabled = false
		end
	end

	activePlotModels[player] = newPlot
	connectCollectAllButton(newPlot, player)
	updatePlotVisuals(player)
end

local function handleCharacterSpawn(player: Player, character: Model)
	local plotModel = activePlotModels[player]
	local spawnCFrame = if shouldUseMineSpawnForEarlyTutorial(player)
		then SpawnUtils.GetNewPlayerSpawnCFrame(3)
		else SpawnUtils.GetCharacterSpawnCFrame(plotModel, getOnboardingStepForSpawn(player), 3)

	if spawnCFrame then
		character:PivotTo(spawnCFrame)
	end
end

refreshEmptyPlots()

Players.PlayerAdded:Connect(function(player)
	repeat
		task.wait()
	until PlayerController:GetProfile(player)

	spawnPlot(player)

	player.CharacterAdded:Connect(function(char)
		task.wait(0.1)
		handleCharacterSpawn(player, char)
	end)

	if player.Character then
		handleCharacterSpawn(player, player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local index = occupiedPlots[player]
	if activePlotModels[player] then
		activePlotModels[player]:Destroy()
		activePlotModels[player] = nil
	end
	occupiedPlots[player] = nil
	collectAllDebounce[player] = nil

	if type(index) == "number" then
		spawnEmptyPlot(index)
	end
end)

local requestSlotPurchase = Events:FindFirstChild("RequestSlotPurchase")
if not requestSlotPurchase then
	requestSlotPurchase = Instance.new("RemoteEvent")
	requestSlotPurchase.Name = "RequestSlotPurchase"
	requestSlotPurchase.Parent = Events
end

requestSlotPurchase.OnServerEvent:Connect(function(player)
	purchaseSlotUpgrade(player)
end)

print("[PlotManager] Active (Slot Upgrade Logic)")

return PlotManager
