--!strict
-- LOCATION: ServerScriptService/Modules/SlotManager

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local SlotManager = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local EconomyValueUtils = require(ServerScriptService.Modules.EconomyValueUtils)
local PlayerController -- Lazy load
local ItemManager -- Lazy load
local LuckyBlockManager -- Lazy load
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- [ ASSETS ]
local Templates = ReplicatedStorage:WaitForChild("Templates")
local LuckyBlocksFolder = ReplicatedStorage:WaitForChild("Luckyblocks")
local UpgradeGUI_Template = Templates:WaitForChild("UpgradeGUI")
local CollectGUI_Template = Templates:WaitForChild("CollectGUI")
local MoneyTemplate = Templates:WaitForChild("Money")
local Events = ReplicatedStorage:WaitForChild("Events")

-- [ CONSTANTS ]
local UPGRADE_COST_MULTIPLIER = 1.5
local DEBOUNCE_TIME = 0.5
local INTERACTION_COOLDOWN = 0.8
local BRAINROT_SLOT_UPGRADES_VISIBLE = false
local LUCKY_BLOCK_VISUAL_VERTICAL_OFFSET = 0

-- [ STATE ]
local lastUpgradeTime = {}

-- [ HELPERS ]
local function getUpgradeCost(baseIncome: number, level: number): number
	return math.floor(baseIncome * 20 * (UPGRADE_COST_MULTIPLIER ^ (level - 1)))
end

local function getSlotContentType(slotData)
	if type(slotData) ~= "table" then
		return nil
	end

	if slotData.ContentType == "LuckyBlock" and slotData.LuckyBlock then
		return "LuckyBlock"
	end

	if slotData.Item then
		return "Item"
	end

	return nil
end

local function clearVisualItem(spawnPart: BasePart)
	local existingItem = spawnPart:FindFirstChild("VisualItem")
	if existingItem then
		existingItem:Destroy()
	end
end

local function spawnLuckyBlockVisual(spawnPart: BasePart, blockId: string)
	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig then
		warn("[SlotManager] Missing lucky block config:", blockId)
		return
	end

	local blockTemplate = LuckyBlocksFolder:FindFirstChild(blockConfig.ModelName)
	if not blockTemplate or not blockTemplate:IsA("Model") then
		warn("[SlotManager] Missing lucky block model:", blockConfig.ModelName)
		return
	end

	local model = blockTemplate:Clone()
	model.Name = "VisualItem"
	model:ScaleTo(blockConfig.Scale)
	model:SetAttribute("LuckyBlockId", blockConfig.Id)
	model:SetAttribute("Rarity", blockConfig.Rarity)
	model:SetAttribute("IsLuckyBlock", true)

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local extents = model:GetExtentsSize()
	local offset = Vector3.new(0, (extents.Y / 2) + LUCKY_BLOCK_VISUAL_VERTICAL_OFFSET, 0)
	model:PivotTo(spawnPart.CFrame + offset)
	model.Parent = spawnPart
end

local function updateSlotVisuals(slotModel: Model, slotData, rebirths: number, isVip: boolean?)
	local contentType = getSlotContentType(slotData)
	local itemData = contentType == "Item" and slotData.Item or nil
	local luckyBlockData = contentType == "LuckyBlock" and slotData.LuckyBlock or nil
	local isOpening = slotData and slotData.IsOpening == true
	local level = (slotData and slotData.Level) or 1
	local stored = (slotData and slotData.Stored) or 0

	local collectPart = slotModel:FindFirstChild("CollectTouch") :: BasePart
	if collectPart then
		local gui = collectPart:FindFirstChild("CollectGUI") :: SurfaceGui
		if not gui then
			gui = CollectGUI_Template:Clone()
			gui.Name = "CollectGUI"
			gui.Parent = collectPart
		end

		local frame = gui:FindFirstChild("CollectFrame")
		local label = frame and frame:FindFirstChild("Price") :: TextLabel

		if itemData then
			gui.Enabled = true
			if label then
				label.Text = "$" .. NumberFormatter.Format(stored)
			end
		else
			gui.Enabled = false
		end
	end

	local upgradePart = slotModel:FindFirstChild("UpgradePart") :: BasePart
	if upgradePart then
		local gui = upgradePart:FindFirstChild("UpgradeGUI") :: SurfaceGui
		if not gui then
			gui = UpgradeGUI_Template:Clone()
			gui.Name = "UpgradeGUI"
			gui.Parent = upgradePart
			gui:SetAttribute("SlotName", slotModel.Name)
			gui:SetAttribute("FloorName", slotModel.Parent and slotModel.Parent.Parent.Name)
		end

		local button = gui:FindFirstChild("UpgradeButton") :: TextButton
		if button then
			button.Visible = BRAINROT_SLOT_UPGRADES_VISIBLE
			button.Active = BRAINROT_SLOT_UPGRADES_VISIBLE
			button.AutoButtonColor = BRAINROT_SLOT_UPGRADES_VISIBLE
		end

		if not BRAINROT_SLOT_UPGRADES_VISIBLE then
			gui.Enabled = false
		elseif itemData and button then
			gui.Enabled = true
			local levelsLabel = button:FindFirstChild("Levels") :: TextLabel
			local priceLabel = button:FindFirstChild("Price") :: TextLabel
			local itemConf = ItemConfigurations.GetItemData(itemData.Name)
			local baseIncome = itemConf and itemConf.Income or 10
			local cost = getUpgradeCost(baseIncome, level)
			if levelsLabel then
				levelsLabel.Text = "Level " .. tostring(level) .. " > Level " .. tostring(level + 1)
			end
			if priceLabel then
				priceLabel.Text = "$" .. NumberFormatter.Format(cost)
			end
		else
			gui.Enabled = false
		end
	end

	local spawnPart = slotModel:FindFirstChild("Spawn") :: BasePart
	if spawnPart then
		clearVisualItem(spawnPart)

		if itemData then
			ItemManager.SpawnVisualItem(spawnPart, itemData.Name, itemData.Mutation, itemData.Rarity, level, rebirths, isVip)
		elseif luckyBlockData then
			spawnLuckyBlockVisual(spawnPart, luckyBlockData.Id)
		end

		local prompt = spawnPart:FindFirstChild("ProximityPrompt") :: ProximityPrompt
		if prompt then
			if itemData then
				prompt.ActionText = "Pick Up / Swap"
			elseif luckyBlockData then
				prompt.ActionText = isOpening and "Opening..." or "Pick Up Lucky Block"
			else
				prompt.ActionText = "Place Item"
			end
		end
	else
		if slotModel.Parent then
			warn("[SlotManager] Visual Update Failed: 'Spawn' part missing in " .. slotModel.Name)
		end
	end
end

local function startLuckyBlockOpening(player: Player, floorName: string, slotName: string, slotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local floorData = profile.Data.Plots[floorName]
	local slotData = floorData and floorData[slotName]
	if not slotData or getSlotContentType(slotData) ~= "LuckyBlock" then return end
	if slotData.IsOpening ~= true then return end

	local luckyBlockId = slotData.LuckyBlock and slotData.LuckyBlock.Id
	if not luckyBlockId then return end

	AnalyticsFunnelsService:HandleLuckyBlockOpenStarted(player, luckyBlockId)

	local spawnPart = slotModel:FindFirstChild("Spawn") :: BasePart
	local visualModel = spawnPart and spawnPart:FindFirstChild("VisualItem")
	if not spawnPart or not visualModel or not visualModel:IsA("Model") then
		warn("[SlotManager] Missing lucky block visual for opening:", floorName, slotName)
		slotData.IsOpening = false
		updateSlotVisuals(slotModel, slotData, profile.Data.Rebirths or 0, PlayerController:IsVIP(player))
		return
	end

	local rolledReward = LuckyBlockManager.RollReward(luckyBlockId)
	if not rolledReward then
		slotData.IsOpening = false
		updateSlotVisuals(slotModel, slotData, profile.Data.Rebirths or 0, PlayerController:IsVIP(player))
		return
	end

	LuckyBlockManager.PlayOpeningAnimation(visualModel)
	if visualModel.Parent then
		visualModel:Destroy()
	end

	local latestProfile = PlayerController:GetProfile(player)
	if not latestProfile then return end
	local latestFloorData = latestProfile.Data.Plots[floorName]
	local latestSlotData = latestFloorData and latestFloorData[slotName]
	if not latestSlotData or getSlotContentType(latestSlotData) ~= "LuckyBlock" then return end

	latestFloorData[slotName] = {
		ContentType = "Item",
		Item = {
			Name = rolledReward.ItemName,
			Mutation = "Normal",
			Rarity = rolledReward.ItemData.Rarity,
		},
		LuckyBlock = nil,
		Level = 1,
		Stored = 0,
		IsOpening = false,
	}
	PlayerController:IncrementBrainrotsCollected(player, 1)

	local finalItemValueBalance = AnalyticsEconomyService:EstimateItemValueBalance(player)
	local rewardItemValue = EconomyValueUtils.GetItemReferencePrice(rolledReward.ItemName, "Normal", 1)
	AnalyticsEconomyService:LogItemValueSinkForLuckyBlock(
		player,
		luckyBlockId,
		TRANSACTION_TYPES.Gameplay,
		`LuckyBlock:{luckyBlockId}`,
		{
			feature = "lucky_block",
			content_id = luckyBlockId,
			context = "lucky_block_open",
		},
		math.max(0, finalItemValueBalance - rewardItemValue)
	)
	AnalyticsEconomyService:LogItemValueSourceForItem(
		player,
		rolledReward.ItemName,
		"Normal",
		1,
		TRANSACTION_TYPES.Gameplay,
		`Item:{rolledReward.ItemName}`,
		{
			feature = "lucky_block",
			content_id = rolledReward.ItemName,
			context = "lucky_block_open",
			rarity = rolledReward.ItemData.Rarity,
			mutation = "Normal",
		},
		finalItemValueBalance
	)
	AnalyticsFunnelsService:HandleLuckyBlockOpenReward(player, luckyBlockId, rolledReward.ItemName, rolledReward.ItemData.Rarity)

	local isVip = PlayerController:IsVIP(player)
	updateSlotVisuals(slotModel, latestFloorData[slotName], latestProfile.Data.Rebirths or 0, isVip)

	local notif = Events:FindFirstChild("ShowNotification")
	if notif then
		notif:FireClient(player, "You got " .. rolledReward.ItemName .. "!", "Success")
	end
end

-- [ ACTIONS ]
function SlotManager.RefreshAllSlots(player: Player)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local rebirths = profile.Data.Rebirths or 0
	local isVip = PlayerController:IsVIP(player)
	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then return end

	for _, floorModel in ipairs(plot:GetChildren()) do
		if not floorModel:IsA("Model") then
			continue
		end

		local floorName = floorModel.Name
		local slotsFolder = floorModel:FindFirstChild("Slots")
		if not slotsFolder then
			continue
		end

		local floorSlots = profile.Data.Plots[floorName]
		if type(floorSlots) ~= "table" then
			floorSlots = {}
		end

		for _, slotModel in ipairs(slotsFolder:GetChildren()) do
			if slotModel:IsA("Model") then
				local slotData = floorSlots[slotModel.Name]
				if type(slotData) == "table" and type(slotData.Stored) ~= "number" then
					slotData.Stored = 0
				end

				updateSlotVisuals(slotModel, slotData, rebirths, isVip)
			end
		end
	end
end

function SlotManager.HandleInteraction(player: Player, floorName: string, slotName: string, slotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile then
		warn("[SlotManager] No profile for " .. player.Name)
		return
	end

	local floorData = profile.Data.Plots[floorName]
	if not floorData then
		warn("[SlotManager] CRITICAL: Floor data missing for '" .. floorName .. "'.")
		return
	end

	local currentSlotData = floorData[slotName]
	local currentContentType = getSlotContentType(currentSlotData)
	local isOccupied = currentContentType ~= nil

	local character = player.Character
	local heldTool = character and character:FindFirstChildWhichIsA("Tool")
	local heldItemName = heldTool and heldTool:GetAttribute("OriginalName")
	local heldLuckyBlockId = heldTool and heldTool:GetAttribute("LuckyBlockId")

	if isOccupied then
		if currentContentType == "Item" then
			if currentSlotData.Stored > 0 then
				local storedAmount = math.floor(currentSlotData.Stored)
				AnalyticsEconomyService:FlushBombIncome(player)
				PlayerController:AddMoney(player, storedAmount)
				AnalyticsEconomyService:LogCashSource(player, storedAmount, TRANSACTION_TYPES.Gameplay, `SlotCollect:{floorName}_{slotName}`, {
					feature = "slot_collect",
					content_id = slotName,
					context = "slot_interaction",
				})
				currentSlotData.Stored = 0
			end

			ItemManager.GiveItemToPlayer(
				player,
				currentSlotData.Item.Name,
				currentSlotData.Item.Mutation,
				currentSlotData.Item.Rarity,
				currentSlotData.Level
			)

			if heldTool and heldItemName then
				currentSlotData.ContentType = "Item"
				currentSlotData.Item = {
					Name = heldItemName,
					Mutation = heldTool:GetAttribute("Mutation"),
					Rarity = heldTool:GetAttribute("Rarity"),
				}
				currentSlotData.LuckyBlock = nil
				currentSlotData.Level = heldTool:GetAttribute("Level") or 1
				currentSlotData.Stored = 0
				currentSlotData.IsOpening = false
				heldTool:Destroy()
			elseif heldTool and heldLuckyBlockId then
				currentSlotData.ContentType = "LuckyBlock"
				currentSlotData.Item = nil
				currentSlotData.LuckyBlock = {
					Id = heldLuckyBlockId,
				}
				currentSlotData.Level = 1
				currentSlotData.Stored = 0
				currentSlotData.IsOpening = true
				heldTool:Destroy()
			else
				floorData[slotName] = { Item = nil, Level = 1, Stored = 0 }
			end
		elseif currentContentType == "LuckyBlock" then
			if currentSlotData.IsOpening then
				local notif = Events:FindFirstChild("ShowNotification")
				if notif then
					notif:FireClient(player, "Lucky block is opening!", "Error")
				end
				return
			end

			if heldTool then
				local notif = Events:FindFirstChild("ShowNotification")
				if notif then
					notif:FireClient(player, "Pick up the lucky block first!", "Error")
				end
				return
			end

			ItemManager.GiveLuckyBlockToPlayer(player, currentSlotData.LuckyBlock.Id)
			floorData[slotName] = { Item = nil, Level = 1, Stored = 0 }
		end
	else
		if heldTool then
			if heldItemName then
				floorData[slotName] = {
					ContentType = "Item",
					Item = {
						Name = heldItemName,
						Mutation = heldTool:GetAttribute("Mutation"),
						Rarity = heldTool:GetAttribute("Rarity"),
					},
					LuckyBlock = nil,
					Level = heldTool:GetAttribute("Level") or 1,
					Stored = 0,
					IsOpening = false,
				}
				heldTool:Destroy()
				TutorialService:HandleBrainrotPlaced(player)
				AnalyticsFunnelsService:HandlePlaceBrainrot(player)
			elseif heldLuckyBlockId then
				floorData[slotName] = {
					ContentType = "LuckyBlock",
					Item = nil,
					LuckyBlock = {
						Id = heldLuckyBlockId,
					},
					Level = 1,
					Stored = 0,
					IsOpening = true,
				}
				heldTool:Destroy()
			else
				warn("[SlotManager] Tool held has no slot-supported attributes! Cannot place.")
				local notif = Events:FindFirstChild("ShowNotification")
				if notif then
					notif:FireClient(player, "Invalid Item! (No Data)", "Error")
				end
				return
			end
		else
			local notif = Events:FindFirstChild("ShowNotification")
			if notif then
				notif:FireClient(player, "Equip an item to place it!", "Error")
			end
			return
		end
	end

	local isVip = PlayerController:IsVIP(player)
	local newData = floorData[slotName]
	updateSlotVisuals(slotModel, newData, profile.Data.Rebirths or 0, isVip)

	if newData and getSlotContentType(newData) == "LuckyBlock" and newData.IsOpening == true then
		task.spawn(startLuckyBlockOpening, player, floorName, slotName, slotModel)
	end
end

function SlotManager.UpgradeItem(player: Player, floorName: string, slotName: string)
	local debounceKey = player.Name .. "_" .. floorName .. "_" .. slotName
	local now = tick()
	if lastUpgradeTime[debounceKey] and (now - lastUpgradeTime[debounceKey] < DEBOUNCE_TIME) then
		return
	end
	lastUpgradeTime[debounceKey] = now

	local profile = PlayerController:GetProfile(player)
	if not profile then return end
	local floorData = profile.Data.Plots[floorName]
	if not floorData then return end
	local slotData = floorData[slotName]
	if not slotData or getSlotContentType(slotData) ~= "Item" or not slotData.Item then return end

	local itemConf = ItemConfigurations.GetItemData(slotData.Item.Name)
	local baseIncome = itemConf and itemConf.Income or 10
	local cost = getUpgradeCost(baseIncome, slotData.Level)
	local upgradeId = floorName .. "_" .. slotName

	AnalyticsEconomyService:FlushBombIncome(player)
	if PlayerController:DeductMoney(player, cost) then
		slotData.Level += 1
		AnalyticsEconomyService:LogCashSink(player, cost, TRANSACTION_TYPES.Shop, `SlotUpgrade:{upgradeId}`, {
			feature = "slot_upgrade",
			content_id = upgradeId,
			context = "base",
		})
		AnalyticsFunnelsService:HandleSlotUpgraded(player, floorName, slotName, upgradeId)
		local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
		if plot then
			local floor = plot:FindFirstChild(floorName)
			local slots = floor and floor:FindFirstChild("Slots")
			local slotModel = slots and slots:FindFirstChild(slotName)
			local isVip = PlayerController:IsVIP(player)
			if slotModel then
				updateSlotVisuals(slotModel, slotData, profile.Data.Rebirths or 0, isVip)
			end
		end

		local notif = Events:FindFirstChild("ShowNotification")
		if notif then
			notif:FireClient(player, "Slot Upgraded!", "Success")
		end
	else
		local notif = Events:FindFirstChild("ShowNotification")
		if notif then
			notif:FireClient(player, "Not enough money!", "Error")
		end
		AnalyticsFunnelsService:LogFailure(player, "not_enough_money", {
			zone = "base",
			funnel = "SlotUpgrade",
			upgrade_id = upgradeId,
		})
	end
end

function SlotManager.CollectMoney(player: Player, floorName: string, slotName: string, slotModel: Model)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end
	local slotData = profile.Data.Plots[floorName] and profile.Data.Plots[floorName][slotName]
	if not slotData then return end
	if getSlotContentType(slotData) ~= "Item" then return end
	if type(slotData.Stored) ~= "number" then slotData.Stored = 0 end
	if slotData.Stored <= 0 then return end

	local amount = math.floor(slotData.Stored)
	slotData.Stored = 0

	AnalyticsEconomyService:FlushBombIncome(player)
	PlayerController:AddMoney(player, amount)
	AnalyticsEconomyService:LogCashSource(player, amount, TRANSACTION_TYPES.Gameplay, `SlotCollect:{floorName}_{slotName}`, {
		feature = "slot_collect",
		content_id = slotName,
		context = "base",
	})
	AnalyticsFunnelsService:HandleManualCollect(player, amount)

	local collectPart = slotModel:FindFirstChild("CollectTouch")
	if collectPart then
		local gui = collectPart:FindFirstChild("CollectGUI")
		local frame = gui and gui:FindFirstChild("CollectFrame")
		local label = frame and frame:FindFirstChild("Price") :: TextLabel
		if label then
			label.Text = "$0"
		end
	end

	local popupEvent = Events:FindFirstChild("ShowCashPopUp")
	if popupEvent then
		popupEvent:FireClient(player, amount)
	end

	if collectPart then
		local moneyEffect = MoneyTemplate:Clone()
		moneyEffect.Parent = collectPart
		for _, child in ipairs(moneyEffect:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				child:Emit(child:GetAttribute("EmitCount") or 10)
			end
		end
		Debris:AddItem(moneyEffect, 3)
	end
end

function SlotManager.RefreshSlot(player: Player, floorName: string, slotName: string)
	local profile = PlayerController:GetProfile(player)
	if not profile then return end

	local slotData = profile.Data.Plots[floorName] and profile.Data.Plots[floorName][slotName]

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if plot then
		local isVip = PlayerController:IsVIP(player)
		local floor = plot:FindFirstChild(floorName)
		local slots = floor and floor:FindFirstChild("Slots")
		local slotModel = slots and slots:FindFirstChild(slotName)
		if slotModel then
			updateSlotVisuals(slotModel, slotData, profile.Data.Rebirths or 0, isVip)
		end
	end
end

-- [ SETUP LOGIC ]
local function setupSingleSlot(player: Player, floorName: string, slotName: string, slotModel: Model)
	local spawnPart = slotModel:WaitForChild("Spawn", 5)
	local upgradePart = slotModel:WaitForChild("UpgradePart", 5)
	local collectPart = slotModel:WaitForChild("CollectTouch", 5)

	if not spawnPart or not upgradePart or not collectPart then
		warn("[SlotManager] Slot Setup Failed for: " .. slotName .. " (Missing Parts)")
		return
	end

	if not spawnPart:FindFirstChild("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Place Item"
		prompt.ObjectText = "Slot"
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = spawnPart

		prompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true

		slotModel:GetAttributeChangedSignal("IsUnlocked"):Connect(function()
			prompt.Enabled = slotModel:GetAttribute("IsUnlocked") == true
		end)

		local lastTriggerTime = 0

		prompt.Triggered:Connect(function(triggerPlayer)
			if triggerPlayer == player then
				local now = tick()
				if now - lastTriggerTime < INTERACTION_COOLDOWN then return end
				lastTriggerTime = now
				SlotManager.HandleInteraction(player, floorName, slotName, slotModel)
			end
		end)
	end

	if not collectPart:GetAttribute("Connected") then
		collectPart:SetAttribute("Connected", true)
		local db = false
		collectPart.Touched:Connect(function(hit)
			if db then return end
			local char = hit.Parent
			local hum = char and char:FindFirstChild("Humanoid")
			if hum and Players:GetPlayerFromCharacter(char) == player then
				db = true
				SlotManager.CollectMoney(player, floorName, slotName, slotModel)
				task.wait(0.5)
				db = false
			end
		end)
	end

	task.spawn(function()
		local profile = PlayerController:GetProfile(player)
		local retries = 0
		while not profile and retries < 20 do
			task.wait(0.5)
			profile = PlayerController:GetProfile(player)
			retries += 1
		end

		if profile then
			local isVip = PlayerController:IsVIP(player)
			if not profile.Data.Plots[floorName] then
				profile.Data.Plots[floorName] = {}
			end
			local data = profile.Data.Plots[floorName][slotName]
			if data and type(data.Stored) ~= "number" then
				data.Stored = 0
			end
			updateSlotVisuals(slotModel, data, profile.Data.Rebirths or 0, isVip)
		end
	end)
end

local function monitorFloor(player: Player, floorModel: Model)
	local slotsFolder = floorModel:WaitForChild("Slots", 5)
	if not slotsFolder then return end

	for _, slot in ipairs(slotsFolder:GetChildren()) do
		setupSingleSlot(player, floorModel.Name, slot.Name, slot)
	end
	slotsFolder.ChildAdded:Connect(function(child)
		setupSingleSlot(player, floorModel.Name, child.Name, child)
	end)
end

function SlotManager.MonitorPlot(player: Player, plot: Model)
	for _, child in ipairs(plot:GetChildren()) do
		if child.Name:match("Floor%d+") then
			monitorFloor(player, child)
		end
	end
	plot.ChildAdded:Connect(function(child)
		if child.Name:match("Floor%d+") then
			monitorFloor(player, child)
		end
	end)
end

-- [ INITIALIZATION ]
function SlotManager:Init(controllers)
	PlayerController = controllers.PlayerController
	local Modules = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(Modules:WaitForChild("ItemManager"))
	LuckyBlockManager = require(Modules:WaitForChild("LuckyBlockManager"))

	local upgradeEvent = Events:FindFirstChild("RequestSlotUpgrade")
	if not upgradeEvent then
		upgradeEvent = Instance.new("RemoteEvent")
		upgradeEvent.Name = "RequestSlotUpgrade"
		upgradeEvent.Parent = Events
	end

	if not SlotManager._connected then
		SlotManager._connected = true
		upgradeEvent.OnServerEvent:Connect(function(player, floorName, slotName)
			SlotManager.UpgradeItem(player, floorName, slotName)
		end)
	end

	local popupEvent = Events:FindFirstChild("ShowCashPopUp")
	if not popupEvent then
		popupEvent = Instance.new("RemoteEvent")
		popupEvent.Name = "ShowCashPopUp"
		popupEvent.Parent = Events
	end
end

-- [ START ]
local function setupPlayerMonitoring(player: Player)
	local plotName = "Plot_" .. player.Name
	local existingPlot = Workspace:FindFirstChild(plotName)
	if existingPlot then
		SlotManager.MonitorPlot(player, existingPlot)
	end

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == plotName then
			SlotManager.MonitorPlot(player, child)
		end
	end)
end

function SlotManager:Start()
	Players.PlayerAdded:Connect(setupPlayerMonitoring)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayerMonitoring(player)
	end
end

return SlotManager
