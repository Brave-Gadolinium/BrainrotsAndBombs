--!strict
-- LOCATION: ServerScriptService/PlotManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

-- Modules
local PlayerController = require(ServerScriptService.Controllers.PlayerController)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local SlotUnlockConfigurations = require(ReplicatedStorage.Modules.SlotUnlockConfigurations)

-- Assets
local Templates = ReplicatedStorage:WaitForChild("Templates")
local PlotTemplate = Templates:WaitForChild("Plot")
local PlotsFolder = Workspace:WaitForChild("Plots")
local Events = ReplicatedStorage:WaitForChild("Events")

local COLLECT_ALL_GAMEPASS = 1736841051
local COLLECT_ALL_COOLDOWN = 0.8
local COLLECT_ALL_BUTTON_NAME = "CollectAll"
local UPGRADE_SLOTS_BUTTON_NAME = "UpgradeSlotsButton"

-- State
local occupiedPlots = {}
local activePlotModels = {}
local collectAllDebounce = {}

local PlotManager = {}

function PlotManager.GetPrice(unlockedSlots: number)
	local upgradeData = SlotUnlockConfigurations.GetUpgradeData(unlockedSlots)
	return upgradeData and upgradeData.money_req or 0
end

function PlotManager.GetMaxLevel()
	return #SlotUnlockConfigurations.new_slots
end

local function getFreePlotIndex(): number?
	for i = 1, 5 do
		local taken = false
		for _, index in pairs(occupiedPlots) do
			if index == i then
				taken = true
				break
			end
		end
		if not taken then
			return i
		end
	end
	return nil
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
		PlayerController:AddMoney(player, totalCollected)

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
			costLabel.Text = "MAX SLOTS"
		end
		return
	end

	upgradeButton.Active = true
	upgradeButton.AutoButtonColor = true
	upgradeButton.Text = "UPGRADE"
	if costLabel and costLabel:IsA("TextLabel") then
		costLabel.Text = "Build - $" .. NumberFormatter.Format(upgradeData.money_req)
	end
end

local function updatePlotVisuals(player: Player)
	local plotModel = activePlotModels[player]
	if not plotModel then
		return
	end

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

	if PlayerController:DeductMoney(player, upgradeData.money_req) then
		local newUnlockedSlots = PlayerController:AddUnlockedSlots(player, upgradeData.new_slots)
		updatePlotVisuals(player)

		if notif then
			notif:FireClient(player, "Unlocked slots: " .. tostring(newUnlockedSlots), "Success")
		end
	else
		if notif then
			notif:FireClient(player, "Not enough Money!", "Error")
		end
	end
end

local function spawnPlot(player: Player)
	local index = getFreePlotIndex()
	if not index then
		player:Kick("No plots available.")
		return
	end

	occupiedPlots[player] = index

	local locator = PlotsFolder:FindFirstChild(tostring(index))
	if not locator then
		warn("Locator not found")
		return
	end

	local newPlot = PlotTemplate:Clone()
	newPlot.Name = "Plot_" .. player.Name
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
	if plotModel and plotModel.PrimaryPart then
		character:WaitForChild("HumanoidRootPart").CFrame = plotModel.PrimaryPart.CFrame + Vector3.new(0, 3, 0)
	end
end

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
	if activePlotModels[player] then
		activePlotModels[player]:Destroy()
		activePlotModels[player] = nil
	end
	occupiedPlots[player] = nil
	collectAllDebounce[player] = nil
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
