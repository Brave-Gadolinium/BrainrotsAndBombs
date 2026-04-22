--!strict
-- LOCATION: ServerScriptService/Modules/CarrySystem

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local CarrySystem = {}

-- [ MODULES ]
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local ProfileReadyUtils = require(ReplicatedStorage.Modules.ProfileReadyUtils)
local PlayerController = require(ServerScriptService.Controllers.PlayerController) 
local BadgeManager = require(ServerScriptService.Modules.BadgeManager)
local TutorialService = require(ServerScriptService.Modules.TutorialService)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)
local ItemManager -- Lazy Loaded
local PickaxeController -- ## ADDED ##
local RoundBrainrotEventManager -- Lazy Loaded
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- [ ASSETS ]
local CollectionZones = Workspace:WaitForChild("Zones")
local Templates = ReplicatedStorage:WaitForChild("Templates")
local ConfettiTemplate = Templates:WaitForChild("Confetti") 
local Events = ReplicatedStorage:WaitForChild("Events")
local GlobalSounds = Workspace:WaitForChild("Sounds")

-- [ DATA ]
local carryingData: {[Player]: {any}} = {}
local playersInZone: {[Player]: boolean} = {}
local pendingInitialZoneEnter: {[Player]: boolean} = {}
local lastLimitNotif: {[Player]: number} = {}
local lastBombRepairAttempt: {[Player]: number} = {}
local ALLOW_MANUAL_CARRY_DROP = false
local DEBUG_BRAINROT_TRACE = false

-- [ CONFIG ]
local CHECK_INTERVAL = 0.2 
local PROFILE_READY_EXIT_TIMEOUT_SECONDS = 3
local STACK_GAP = 0.5 
local STACK_HEAD_CLEARANCE = 0.05

local function summarizeTool(tool: Tool): string
	local originalName = tool:GetAttribute("OriginalName")
	local mutation = tool:GetAttribute("Mutation")
	local rarity = tool:GetAttribute("Rarity")
	local level = tool:GetAttribute("Level")
	local isLuckyBlock = tool:GetAttribute("IsLuckyBlock") == true
	local isBomb = BombsConfigurations.Bombs[tool.Name] ~= nil
		or (type(originalName) == "string" and BombsConfigurations.Bombs[originalName] ~= nil)
	local toolKind = if isLuckyBlock then "LuckyBlock" elseif isBomb then "Bomb" elseif mutation ~= nil then "Brainrot" else "Tool"
	return ("%s{name=%s,orig=%s,mut=%s,rar=%s,lvl=%s,parent=%s}"):format(
		toolKind,
		tostring(tool.Name),
		tostring(originalName),
		tostring(mutation),
		tostring(rarity),
		tostring(level),
		tostring(tool.Parent and tool.Parent.Name or "nil")
	)
end

local function summarizeToolContainer(container: Instance?): string
	if not container then
		return "[]"
	end

	local entries = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			table.insert(entries, summarizeTool(child))
		end
	end

	table.sort(entries)
	return "[" .. table.concat(entries, ", ") .. "]"
end

local function summarizeCarryEntries(items): string
	if type(items) ~= "table" or #items == 0 then
		return "[]"
	end

	local entries = {}
	for index, itemData in ipairs(items) do
		table.insert(entries, ("#%d{name=%s,mut=%s,rar=%s,lvl=%s,visual=%s,event=%s}"):format(
			index,
			tostring(itemData.Name),
			tostring(itemData.Mutation),
			tostring(itemData.Rarity),
			tostring(itemData.Level or 1),
			tostring(itemData.VisualModel ~= nil and itemData.VisualModel.Parent ~= nil),
			tostring(type(itemData.EventAttributes) == "table")
		))
	end

	return "[" .. table.concat(entries, ", ") .. "]"
end

local function formatVector3(value: Vector3?): string
	if not value then
		return "nil"
	end

	return ("(%.2f, %.2f, %.2f)"):format(value.X, value.Y, value.Z)
end

local function logCarryTrace(player: Player?, message: string)
	if not DEBUG_BRAINROT_TRACE then
		return
	end

	local playerName = player and player.Name or "nil"
	local step = player and player:GetAttribute("OnboardingStep") or nil
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local rootPosition = if root and root:IsA("BasePart") then root.Position else nil
	local backpack = if player then player:FindFirstChild("Backpack") else nil
	local carry = if player then carryingData[player] else nil

	print(("[BrainrotTrace][CarrySystem][%s][step=%s][inZone=%s][server=%.3f] %s | root=%s | carry=%s | char=%s | backpack=%s"):format(
		playerName,
		tostring(step),
		tostring(player and playersInZone[player] == true or false),
		Workspace:GetServerTimeNow(),
		message,
		formatVector3(rootPosition),
		summarizeCarryEntries(carry),
		summarizeToolContainer(player and player.Character or nil),
		summarizeToolContainer(backpack)
	))
end

local function shouldTraceCriticalTutorialWindow(player: Player?): boolean
	if not player then
		return false
	end

	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep == 4 or onboardingStep == 5
end

local function logCriticalCarryTrace(player: Player?, message: string)
	if not DEBUG_BRAINROT_TRACE or not shouldTraceCriticalTutorialWindow(player) then
		return
	end

	print(("[BrainrotTrace][CarrySystem][%s][step=%s][server=%.3f] %s"):format(
		tostring(player and player.Name or "nil"),
		tostring(player and player:GetAttribute("OnboardingStep") or nil),
		Workspace:GetServerTimeNow(),
		message
	))
end

local function summarizeTraceInstance(instance: Instance?): string
	if not instance then
		return "nil"
	end

	if instance:IsA("Tool") then
		return summarizeTool(instance)
	end

	if instance:IsA("Model") then
		return ("Model{name=%s,parent=%s}"):format(
			tostring(instance.Name),
			tostring(instance.Parent and instance.Parent.Name or "nil")
		)
	end

	return ("%s{name=%s,parent=%s}"):format(
		instance.ClassName,
		tostring(instance.Name),
		tostring(instance.Parent and instance.Parent.Name or "nil")
	)
end

local function traceDestroyCall(label: string, instance: Instance?)
	if not DEBUG_BRAINROT_TRACE or not instance then
		return
	end

	print(("[DESTROY CALL][CarrySystem][%s] %s"):format(label, summarizeTraceInstance(instance)))
	warn(debug.traceback())
end

local function getFallbackDropPosition(): (Vector3, Vector3)
	local mines = Workspace:FindFirstChild("Mines")
	local zonePart = mines and mines:FindFirstChild("Zone5")
	if zonePart and zonePart:IsA("BasePart") then
		local elevatedPosition = zonePart.Position + Vector3.new(0, (zonePart.Size.Y * 0.5) + 8, 0)
		return elevatedPosition, elevatedPosition
	end

	return Vector3.new(0, 12, 0), Vector3.new(0, 12, 0)
end

local function getDropPositionsNearPlayer(player: Player, distance: number?): (Vector3, Vector3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")

	if root and root:IsA("BasePart") then
		local originPosition = if head and head:IsA("BasePart") then head.Position else root.Position
		return root.Position + (root.CFrame.LookVector * (distance or 4)), originPosition
	end

	return getFallbackDropPosition()
end

-- [ HELPERS ]
local function isInsideAnyZone(position: Vector3): boolean
	for _, zonePart in ipairs(CollectionZones:GetChildren()) do
		if zonePart:IsA("BasePart") and zonePart.Name == "ZonePart" then
			local relativePos = zonePart.CFrame:PointToObjectSpace(position)
			local size = zonePart.Size

			local inside = math.abs(relativePos.X) <= size.X / 2 and
				math.abs(relativePos.Y) <= size.Y / 2 and
				math.abs(relativePos.Z) <= size.Z / 2

			if inside then return true end
		end
	end
	return false
end

local function isBrainrotTool(tool: Tool): boolean
	if tool:GetAttribute("IsTemporary") == true then
		return false
	end

	local mutation = tool:GetAttribute("Mutation")
	local originalName = tool:GetAttribute("OriginalName")
	return type(mutation) == "string"
		and mutation ~= ""
		and type(originalName) == "string"
		and originalName ~= ""
		and BombsConfigurations.Bombs[tool.Name] == nil
		and BombsConfigurations.Bombs[originalName] == nil
end

local function hasBrainrotTool(container: Instance?): boolean
	if not container then
		return false
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isBrainrotTool(child) then
			return true
		end
	end

	return false
end

local function shouldPreserveFtuePlacementToolOnZoneEnter(player: Player): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	if onboardingStep ~= 4 and onboardingStep ~= 5 then
		return false
	end

	return hasBrainrotTool(player.Character) or hasBrainrotTool(player:FindFirstChild("Backpack"))
end

local function shouldSkipMineToolMutation(player: Player, _isInitialZoneEnter: boolean?): boolean
	return not ProfileReadyUtils.IsReady(player)
end

local function createStackItem(player: Player, itemName: string, mutation: string, rarity: string, eventAttributes: {[string]: any}?)
	local character = player.Character
	if not character then return nil end

	local headPart = character:FindFirstChild("Head") :: BasePart
	if not headPart then return nil end

	if not ItemManager then
		ItemManager = require(ServerScriptService.Modules.ItemManager)
	end

	local model = ItemManager.CreateItemModel and ItemManager.CreateItemModel(itemName, mutation, rarity)
	if not model then return nil end

	model.Name = "StackItem"
	if type(eventAttributes) == "table" then
		for attributeName, attributeValue in pairs(eventAttributes) do
			model:SetAttribute(attributeName, attributeValue)
		end
	end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then return nil end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.Massless = true
			desc.Anchored = false
		elseif desc:IsA("Script") or desc:IsA("LocalScript") then
			desc:Destroy()
		end
	end

	local currentItems = carryingData[player] or {}
	local itemSize = model:GetExtentsSize()

	model.Parent = character

	local totalHeight = (headPart.Size.Y / 2) + STACK_HEAD_CLEARANCE

	for _, data in ipairs(currentItems) do
		if data.VisualModel and data.VisualModel:IsA("Model") then
			totalHeight = totalHeight + data.VisualModel:GetExtentsSize().Y + STACK_GAP
		end
	end
	totalHeight = totalHeight + (itemSize.Y / 2)

	model:PivotTo(headPart.CFrame * CFrame.new(0, totalHeight, 0))

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = headPart
	weld.Part1 = primary
	weld.Parent = primary

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= primary then
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = part
			w.Parent = part
		end
	end

	return model
end

local function getRoundBrainrotEventManager()
	if not RoundBrainrotEventManager then
		local roundBrainrotEventModule = ServerScriptService.Modules:FindFirstChild("RoundBrainrotEventManager")
		if roundBrainrotEventModule and roundBrainrotEventModule:IsA("ModuleScript") then
			RoundBrainrotEventManager = require(roundBrainrotEventModule)
		end
	end

	return RoundBrainrotEventManager
end

local function dropCarriedItemData(itemData, targetPos: Vector3, originPos: Vector3?)
	local roundBrainrotEventManager = getRoundBrainrotEventManager()
	local handledByEventManager = roundBrainrotEventManager
		and roundBrainrotEventManager.HandleEventItemDropped
		and roundBrainrotEventManager:HandleEventItemDropped(itemData, targetPos, originPos)

	if handledByEventManager then
		return
	end

	ItemManager.SpawnDroppedItem(
		itemData.Name,
		itemData.Mutation,
		itemData.Rarity,
		targetPos,
		originPos,
		{
			Level = itemData.Level or 1,
			ExtraAttributes = itemData.EventAttributes,
		}
	)
end

local function restoreActiveEventItemsFromCarry(player: Player)
	local items = carryingData[player]
	if not items or #items == 0 then
		return
	end

	logCarryTrace(player, ("restoreActiveEventItemsFromCarry begin items=%s"):format(summarizeCarryEntries(items)))

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local baseDropPosition = if root then root.Position else if head then head.Position else nil
	local dropPosition: Vector3
	local originPosition: Vector3

	if baseDropPosition then
		local forwardVector = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
		dropPosition = baseDropPosition + (forwardVector * 3)
		originPosition = if head then head.Position else baseDropPosition
	else
		dropPosition, originPosition = getFallbackDropPosition()
	end

	for _, itemData in ipairs(items) do
		if type(itemData.EventAttributes) == "table" then
			dropCarriedItemData(itemData, dropPosition, originPosition)
		end
	end

	logCarryTrace(player, ("restoreActiveEventItemsFromCarry end dropPosition=%s origin=%s"):format(
		formatVector3(dropPosition),
		formatVector3(originPosition)
	))
end

local function clearVisualStack(player: Player)
	local items = carryingData[player]
	if items then
		for _, data in ipairs(items) do
			if data.VisualModel and data.VisualModel.Parent then
				traceDestroyCall("clearVisualStack.visualModel", data.VisualModel)
				data.VisualModel:Destroy()
			end
		end
	end
end

-- [ PUBLIC API ]
function CarrySystem.IsPlayerInZone(player: Player): boolean
	return playersInZone[player] == true
end

function CarrySystem.CanCarryMore(player: Player): boolean
	local current = carryingData[player] or {}
	local profile = PlayerController:GetProfile(player)
	local limit = profile and profile.Data.CarryCapacity or 1
	return #current < limit
end

function CarrySystem.AddItemToCarry(player: Player, name: string, mutation: string, rarity: string, _source: BasePart?, metadata)
	if not carryingData[player] then carryingData[player] = {} end

	local level = type(metadata) == "table" and (metadata.Level or 1) or 1
	local eventAttributes = type(metadata) == "table" and metadata.EventAttributes or nil
	logCarryTrace(player, ("AddItemToCarry requested name=%s mut=%s rar=%s lvl=%s source=%s event=%s"):format(
		tostring(name),
		tostring(mutation),
		tostring(rarity),
		tostring(level),
		tostring(_source and _source:GetFullName() or "nil"),
		tostring(type(eventAttributes) == "table")
	))

	if CarrySystem.CanCarryMore(player) then
		local visualModel = createStackItem(player, name, mutation, rarity, eventAttributes)

		table.insert(carryingData[player], {
			Name = name,
			Mutation = mutation,
			Rarity = rarity,
			Level = level,
			EventAttributes = eventAttributes,
			VisualModel = visualModel
		})

		local token = type(eventAttributes) == "table" and eventAttributes.EventBrainrotToken or nil
		local roundBrainrotEventManager = getRoundBrainrotEventManager()
		if roundBrainrotEventManager and roundBrainrotEventManager.HandleEventItemPickedUp and type(token) == "string" then
			roundBrainrotEventManager:HandleEventItemPickedUp(player, token)
		end
		logCarryTrace(player, ("AddItemToCarry success visualCreated=%s token=%s"):format(
			tostring(visualModel ~= nil and visualModel.Parent ~= nil),
			tostring(token)
		))
		return true
	end

	local currentTime = tick()
	if not lastLimitNotif[player] or (currentTime - lastLimitNotif[player] > 2) then
		lastLimitNotif[player] = currentTime
		local notif = Events:FindFirstChild("ShowNotification")
		if notif then notif:FireClient(player, "Carry limit reached!", "Error") end
		AnalyticsFunnelsService:LogFailure(player, "carry_limit_reached", {
			zone = "mine",
		})
	end

	logCarryTrace(player, ("AddItemToCarry rejected carryLimit=%s"):format(tostring(PlayerController:GetProfile(player) and PlayerController:GetProfile(player).Data.CarryCapacity or "nil")))

	return false
end

function CarrySystem.ClearAllItems(player: Player)
	local previousItems = carryingData[player]
	logCarryTrace(player, ("ClearAllItems begin items=%s"):format(summarizeCarryEntries(previousItems)))
	clearVisualStack(player)
	carryingData[player] = {}
	logCarryTrace(player, "ClearAllItems end")
end

function CarrySystem.DropItemsAtFeet(player: Player)
	local items = carryingData[player]
	if not items or #items == 0 then return end

	logCarryTrace(player, ("DropItemsAtFeet begin items=%s"):format(summarizeCarryEntries(items)))

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart

	if root then
		local dropPos = root.Position + (root.CFrame.LookVector * 4)
		local head = char:FindFirstChild("Head") :: BasePart
		local originPos = head and head.Position or root.Position

		for _, itemData in ipairs(items) do
			dropCarriedItemData(itemData, dropPos, originPos)
		end
	end

	CarrySystem.ClearAllItems(player)
	logCarryTrace(player, "DropItemsAtFeet end")
end

function CarrySystem.HasCarriedItems(player: Player): boolean
	local items = carryingData[player]
	return items ~= nil and #items > 0
end

function CarrySystem.DropOneItemAtFeet(player: Player): boolean
	local items = carryingData[player]
	if not items or #items == 0 then
		logCarryTrace(player, "DropOneItemAtFeet skipped emptyCarry")
		return false
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then
		logCarryTrace(player, "DropOneItemAtFeet aborted missingRoot")
		return false
	end

	local itemData = table.remove(items, #items)
	if not itemData then
		logCarryTrace(player, "DropOneItemAtFeet aborted noItemAfterRemove")
		return false
	end

	if itemData.VisualModel and itemData.VisualModel.Parent then
		traceDestroyCall("DropOneItemAtFeet.visualModel", itemData.VisualModel)
		itemData.VisualModel:Destroy()
	end

	local head = char:FindFirstChild("Head") :: BasePart
	local originPos = head and head.Position or root.Position
	local dropPos = root.Position + (root.CFrame.LookVector * 3)

	dropCarriedItemData(itemData, dropPos, originPos)
	logCarryTrace(player, ("DropOneItemAtFeet success dropped=%s/%s/%s"):format(
		tostring(itemData.Name),
		tostring(itemData.Mutation),
		tostring(itemData.Rarity)
	))

	return true
end

-- [ ZONE LOGIC ]
local function processZoneExit(player: Player)
	local items = carryingData[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hadItems = items and #items > 0 or false

	local isDead = not humanoid or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead
	local isAlive = not isDead
	logCarryTrace(player, ("processZoneExit begin hadItems=%s isAlive=%s items=%s"):format(
		tostring(hadItems),
		tostring(isAlive),
		summarizeCarryEntries(items)
	))

	AnalyticsEconomyService:FlushBombIncome(player)

	if hadItems then
		if isAlive then
			local profileReady = ProfileReadyUtils.WaitForReady(player, PROFILE_READY_EXIT_TIMEOUT_SECONDS)
			if not profileReady then
				logCriticalCarryTrace(player, "processZoneExit profile not ready before carry conversion; continuing after timeout")
			end

			local lastGivenTool = nil
			local deliveredItems = {}
			local failedDeliveryCount = 0
			local profile = PlayerController:GetProfile(player)
			local totalCollected = profile and (profile.Data.TotalBrainrotsCollected or 0) or 0

			for _, itemData in ipairs(items) do
				-- Capture the returned tool
				logCarryTrace(player, ("processZoneExit givingTool name=%s mut=%s rar=%s lvl=%s"):format(
					tostring(itemData.Name),
					tostring(itemData.Mutation),
					tostring(itemData.Rarity),
					tostring(itemData.Level or 1)
				))
				local newTool = ItemManager.GiveItemToPlayer(
					player,
					itemData.Name,
					itemData.Mutation,
					itemData.Rarity,
					itemData.Level or 1,
					false,
					itemData.EventAttributes
				)
				if newTool then lastGivenTool = newTool end
				logCarryTrace(player, ("processZoneExit giveResult success=%s tool=%s"):format(
					tostring(newTool ~= nil),
					tostring(newTool and summarizeTool(newTool) or "nil")
				))
				if newTool then
					table.insert(deliveredItems, {
						Name = itemData.Name,
						Mutation = itemData.Mutation,
						Rarity = itemData.Rarity,
						Level = itemData.Level or 1,
					})

					AnalyticsEconomyService:LogItemValueSourceForItem(
						player,
						itemData.Name,
						itemData.Mutation,
						1,
						TRANSACTION_TYPES.Gameplay,
						`Item:{itemData.Name}`,
						{
							feature = "mine_exit",
							content_id = itemData.Name,
							context = "mine",
							rarity = itemData.Rarity,
							mutation = itemData.Mutation,
						}
					)
				end
				if newTool then
					local roundBrainrotEventManager = getRoundBrainrotEventManager()
					if roundBrainrotEventManager and roundBrainrotEventManager.HandleEventItemDelivered then
						roundBrainrotEventManager:HandleEventItemDelivered(newTool)
					end

					totalCollected += 1
					BadgeManager:EvaluateBrainrotMilestones(player, itemData.Rarity, totalCollected)
				else
					failedDeliveryCount += 1
					local dropPosition, originPosition = getDropPositionsNearPlayer(player, 4)
					dropCarriedItemData(itemData, dropPosition, originPosition)
					logCriticalCarryTrace(player, ("processZoneExit fallbackDrop name=%s mut=%s rar=%s pos=%s"):format(
						tostring(itemData.Name),
						tostring(itemData.Mutation),
						tostring(itemData.Rarity),
						formatVector3(dropPosition)
					))
				end
			end

			if #deliveredItems > 0 and PlayerController.EnsureInventoryContainsItems then
				PlayerController:EnsureInventoryContainsItems(player, deliveredItems, "mine_exit")
			end

			if profile then
				profile.Data.TotalBrainrotsCollected = totalCollected
				player:SetAttribute("TotalBrainrotsCollected", totalCollected)
			end

			-- Auto-Equip the newly received item
			if lastGivenTool and ItemManager.ProtectFtuePlacementTool and shouldTraceCriticalTutorialWindow(player) then
				ItemManager.ProtectFtuePlacementTool(player, lastGivenTool, true)
			end

			if lastGivenTool and humanoid then
				logCarryTrace(player, ("processZoneExit equipping lastTool=%s"):format(summarizeTool(lastGivenTool)))
				humanoid:EquipTool(lastGivenTool)
				logCriticalCarryTrace(player, ("processZoneExit equipped tool=%s"):format(summarizeTool(lastGivenTool)))
				logCarryTrace(player, "processZoneExit equip complete")
			end
			if #deliveredItems > 0 and PlayerController.EnsureInventoryContainsItems then
				PlayerController:EnsureInventoryContainsItems(player, deliveredItems, "mine_exit:post_equip")
			end
			if lastGivenTool then
				AnalyticsFunnelsService:HandleMineExitToolGranted(player)
			else
				logCriticalCarryTrace(player, ("processZoneExit failed noToolGranted carryCount=%d"):format(#items))
				logCarryTrace(player, "processZoneExit noToolWasGranted")
			end

			local successSound = GlobalSounds:FindFirstChild("Success")
			if successSound then
				local s = successSound:Clone(); s.Parent = player:WaitForChild("PlayerGui"); s:Play(); Debris:AddItem(s, 3)
			end

			if character:FindFirstChild("HumanoidRootPart") then
				local confetti = ConfettiTemplate:Clone(); confetti.Parent = character.HumanoidRootPart
				for _, child in ipairs(confetti:GetChildren()) do
					if child:IsA("ParticleEmitter") then child:Emit(child:GetAttribute("EmitCount") or 20) end
				end
				Debris:AddItem(confetti, 3)
			end

			local notif = Events:FindFirstChild("ShowNotification")
			if notif then
				if #deliveredItems > 0 then
					notif:FireClient(player, "Items Unlocked!", "Success")
				elseif failedDeliveryCount > 0 then
					notif:FireClient(player, "Items dropped nearby.", "Success")
				end
			end

			local effectEvent = Events:FindFirstChild("TriggerUIEffect")
			if effectEvent then 
				effectEvent:FireClient(player, "FOVPop") 
			end
		end

		CarrySystem.ClearAllItems(player)
	end

	if isAlive then
		-- Advance FTUE only after the carry stack has been converted/cleared so step 5
		-- observes the real equipped/backpack state instead of the transient mine stack.
		logCarryTrace(player, "processZoneExit before TutorialService:HandleMineZoneExited")
		TutorialService:HandleMineZoneExited(player)
		AnalyticsFunnelsService:HandleMineZoneExited(player, hadItems)
	end

	logCarryTrace(player, "processZoneExit end")
end

local function processZoneEnter(player: Player, isInitialZoneEnter: boolean?)
	if not carryingData[player] then carryingData[player] = {} end
	logCarryTrace(player, "processZoneEnter begin")
	TutorialService:HandleMineZoneEntered(player)
	AnalyticsFunnelsService:HandleMineZoneEntered(player)

	if shouldPreserveFtuePlacementToolOnZoneEnter(player) then
		logCarryTrace(player, "processZoneEnter preserving FTUE placement tool")
		return
	end

	if shouldSkipMineToolMutation(player, isInitialZoneEnter) then
		logCarryTrace(player, ("processZoneEnter skipping tool mutation profileReady=%s initial=%s"):format(
			tostring(ProfileReadyUtils.IsReady(player)),
			tostring(isInitialZoneEnter == true)
		))
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Hide any equipped carryable/tool item when the player goes back into the mine.
		-- FTUE step 5 is excluded so the placement brainrot survives zone-edge re-entry.
		logCarryTrace(player, "processZoneEnter calling UnequipTools")
		humanoid:UnequipTools()
		logCarryTrace(player, "processZoneEnter UnequipTools complete")
	end

	-- Restore the preferred bomb without destroying/recreating it on every zone enter.
	if PickaxeController and PickaxeController.EnsureBombEquipped then
		PickaxeController.EnsureBombEquipped(player)
		logCarryTrace(player, "processZoneEnter EnsureBombEquipped complete")
	end
end

local function hasEquippedBomb(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and BombsConfigurations.Bombs[child.Name] then
			return true
		end
	end

	return false
end

local function repairMissingBombInZone(player: Player)
	if not PickaxeController or not PickaxeController.EnsureBombEquipped then
		return
	end

	if shouldPreserveFtuePlacementToolOnZoneEnter(player) or shouldSkipMineToolMutation(player, nil) then
		return
	end

	local now = tick()
	local lastAttempt = lastBombRepairAttempt[player] or 0
	if now - lastAttempt < 0.75 then
		return
	end

	lastBombRepairAttempt[player] = now
	PickaxeController.EnsureBombEquipped(player)
end

function CarrySystem:Init()
	local Modules = ServerScriptService:WaitForChild("Modules")
	ItemManager = require(Modules:WaitForChild("ItemManager"))

	-- ## ADDED: Pull the PickaxeController so we can use it to auto-equip ##
	local Controllers = ServerScriptService:WaitForChild("Controllers")
	PickaxeController = require(Controllers:WaitForChild("PickaxeController"))

	local dropEvent = Events:FindFirstChild("RequestDropItem")
	if not dropEvent then
		dropEvent = Instance.new("RemoteEvent")
		dropEvent.Name = "RequestDropItem"
		dropEvent.Parent = Events
	end

	dropEvent.OnServerEvent:Connect(function(player)
		if ALLOW_MANUAL_CARRY_DROP and playersInZone[player] then
			logCarryTrace(player, "RequestDropItem accepted")
			CarrySystem.DropItemsAtFeet(player)
		else
			logCarryTrace(player, ("RequestDropItem ignored allow=%s inZone=%s"):format(
				tostring(ALLOW_MANUAL_CARRY_DROP),
				tostring(playersInZone[player] == true)
			))
		end
	end)

	local clearEvent = Events:FindFirstChild("RequestClearCarry")
	if not clearEvent then
		clearEvent = Instance.new("RemoteEvent")
		clearEvent.Name = "RequestClearCarry"
		clearEvent.Parent = Events
	end

	clearEvent.OnServerEvent:Connect(function(player)
		logCarryTrace(player, "RequestClearCarry received")
		restoreActiveEventItemsFromCarry(player)
		CarrySystem.ClearAllItems(player)
	end)
end

function CarrySystem:Start()
	local function bindCharacter(player: Player, character: Model)
		logCarryTrace(player, ("bindCharacter character=%s"):format(character:GetFullName()))
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				logCarryTrace(player, "Humanoid.Died detected")
				restoreActiveEventItemsFromCarry(player)
				CarrySystem.ClearAllItems(player)
			end)
		end
	end

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(function(character)
			logCarryTrace(player, ("CharacterAdded resettingCarry character=%s"):format(character:GetFullName()))
			carryingData[player] = {}
			pendingInitialZoneEnter[player] = true
			bindCharacter(player, character)
		end)

		if player.Character then
			pendingInitialZoneEnter[player] = true
			bindCharacter(player, player.Character)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
	Players.PlayerAdded:Connect(onPlayerAdded)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)
			local foundPlayers = {}
			local initialZoneEnterByPlayer = {}
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character then
					local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
					if rootPart and isInsideAnyZone(rootPart.Position) then
						local isInitialZoneEnter = pendingInitialZoneEnter[player] == true and playersInZone[player] ~= true
						foundPlayers[player] = true
						initialZoneEnterByPlayer[player] = isInitialZoneEnter
						if not hasEquippedBomb(player)
							and not shouldPreserveFtuePlacementToolOnZoneEnter(player)
							and not shouldSkipMineToolMutation(player, isInitialZoneEnter)
						then
							repairMissingBombInZone(player)
						end
					elseif pendingInitialZoneEnter[player] then
						pendingInitialZoneEnter[player] = nil
					end
				end
			end
			for player, _ in pairs(playersInZone) do
				if not foundPlayers[player] then
					playersInZone[player] = nil
					processZoneExit(player)
				end
			end
			for player, _ in pairs(foundPlayers) do
				if not playersInZone[player] then
					playersInZone[player] = true
					local isInitialZoneEnter = initialZoneEnterByPlayer[player] == true
					pendingInitialZoneEnter[player] = nil
					processZoneEnter(player, isInitialZoneEnter)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		logCarryTrace(player, "PlayerRemoving begin")
		restoreActiveEventItemsFromCarry(player)
		CarrySystem.ClearAllItems(player)
		carryingData[player] = nil
		playersInZone[player] = nil
		pendingInitialZoneEnter[player] = nil
		lastLimitNotif[player] = nil
		lastBombRepairAttempt[player] = nil
	end)
end

return CarrySystem
