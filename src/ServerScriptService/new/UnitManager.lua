local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService('CollectionService')
local AnalyticsService = game:GetService('AnalyticsService')
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(game.ReplicatedStorage.Configs.Config)
local Formulas = require(game.ReplicatedStorage.Configs.Formulas)
local Constants = require(game.ReplicatedStorage.Configs.Constants)
local Functions = require(ReplicatedStorage.Modules.Helpers.Functions)

local Profiles = require(ServerStorage.Modules.General.Data)
local SoundManager = require(ReplicatedStorage.Modules.Helpers.SoundManager)
local Tutorial = require(game.ServerStorage.Modules.General.TutorialManager)


local Remotes = ReplicatedStorage.Remotes
local EquipPickaxeForPlayer = Remotes.EquipPickaxeForPlayer

local RNG = Random.new()
local IndexUpdated = Remotes.IndexUpdated

local UnitManager = {}
UnitManager.__index = UnitManager

local rarityMapping = {
	common = 'Common',
	rare = 'Rare',
	epic = 'Epic',
	legendary = 'Legendary',
}

local function formatNumber(value)
	if value > 999 * 10^33 then
		return "inf"
	end
	if value < 1000 then
		return tostring(math.floor(value))
	end
	local suffixes = {"", "K", "M", "B", "T", "Q", "QT", "S", "SP", "O", "N", "D"}
	local index = 1
	while value >= 1000 and index < #suffixes do
		value = value / 1000
		index += 1
	end
	if value >= 100 then
		return string.format("%.0f%s", math.floor(value + 0.001), suffixes[index])
	else
		local truncated = math.floor(value * 10) / 10
		return string.format("%.1f%s", truncated, suffixes[index])
	end
end

-- Получение атрибута с умолчанием
local function getAttr(model, name, default)
	local v = model:GetAttribute(name)
	if v == nil then return default end
	return v
end

-- Конструктор класса
function UnitManager.new(player)
	local self = setmetatable({}, UnitManager)
	
	return self
end

-- Метод для добавления юнита игроку
function UnitManager:AddUnitToPlayer(player: Player, unitData, toHands: BoolValue, slot, toolData, lvlAfretMerge, withoutSlot, auraData)
	local PlayerStats = player:WaitForChild("PlayerStats")

	if withoutSlot == true then
		local NewUnit = Instance.new("StringValue")
		NewUnit.Value = unitData.id
		NewUnit.Name = Config.bosses[unitData.id].id
		NewUnit:SetAttribute('Type', 'Unit')

		local unitTool = Instance.new("Tool")
		unitTool.Name = unitData.id
		unitTool.CanBeDropped = false
		unitTool.RequiresHandle = true
		unitTool.TextureId = Config.bosses[unitData.id].img

		local Units = player:WaitForChild("Pets")
		NewUnit:SetAttribute('PetID', Config.bosses[unitData.id].id)
		NewUnit.Parent = Units

		unitTool:SetAttribute("Reward", 1)
		unitTool:SetAttribute("BossId", unitData.id)
		unitTool:SetAttribute("Name", unitData.name)
		unitTool:SetAttribute("Rarity", unitData.rarity)
		unitTool:SetAttribute("MoneyRate", unitData.money_rate)

		self:_setAuraData(unitTool, auraData or unitData)
		self:_applyUnitStatsWithAura(unitTool, unitData.id, unitData.money_rate)

		CollectionService:AddTag(unitTool,"Unit")
		
		local template = nil

		template = game.ReplicatedStorage.Assets.Mobs[unitData.id]

		if not template then
			warn("Template не найден:", unitData.id)
			return
		end

		local unitClone = template:Clone()

		local root = unitClone.PrimaryPart or unitClone:FindFirstChild("HumanoidRootPart") or unitClone:FindFirstChildWhichIsA("BasePart")
		if not root then
			warn("RootPart не найден у модели:", unitData.unit_id)
			return
		end

		for _, descendant in ipairs(unitClone:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") then
				descendant:Destroy()
			end
		end

		for _, part in ipairs(unitClone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = false
				part.Massless = true
			end
		end

		-- Создаём Handle
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(1, 1, 1)
		handle.CanCollide = false
		handle.Anchored = false
		handle.Transparency = 1
		handle.Parent = unitTool

		local offset = CFrame.new(-0.4, 4.5, 1.4)
		unitClone:PivotTo(handle.CFrame * offset)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = root
		weld.Parent = handle

		unitClone.Parent = unitTool
		
		self:_refreshAuraVisual(unitClone, unitTool)

		CollectionService:AddTag(unitTool, "Unit")
		unitTool.Parent = player.Backpack

		player:SetAttribute('TotalBrainrots', player:GetAttribute('TotalBrainrots') + 1)

		return true
	end
	
	local SlotUnit = slot:FindFirstChild('Unit') and slot:FindFirstChild('Unit'):FindFirstChildOfClass('Model')

	-- Добавляем запись о юните
	local NewUnit = Instance.new("StringValue")
	NewUnit.Value = SlotUnit.Name
	NewUnit.Name = Config.bosses[SlotUnit.Name].id
	NewUnit:SetAttribute('Type', 'Unit')

	self:GiveReward(slot, player)

	-- Создаём Tool
	local unitTool = Instance.new("Tool")
	unitTool.Name = SlotUnit.Name
	unitTool.CanBeDropped = false
	unitTool.RequiresHandle = true
	unitTool.TextureId = Config.bosses[SlotUnit.Name].img

	local Units = player:WaitForChild("Pets")
	NewUnit:SetAttribute('PetID', Config.bosses[SlotUnit.Name].id)
	NewUnit.Parent = Units

	unitTool:SetAttribute("Reward", SlotUnit:GetAttribute("Reward") or SlotUnit:GetAttribute("MoneyRate"))

	if SlotUnit:GetAttribute('BossId') then
		unitTool:SetAttribute("BossId", SlotUnit:GetAttribute('BossId'))
	elseif SlotUnit:GetAttribute('BaddieId') then
		unitTool:SetAttribute("BaddieId", SlotUnit:GetAttribute('BaddieId'))
	end

	unitTool:SetAttribute("Name", SlotUnit:GetAttribute('Name'))
	unitTool:SetAttribute("Rarity", SlotUnit:GetAttribute('Rarity'))
	unitTool:SetAttribute("MoneyRate", SlotUnit:GetAttribute("MoneyRate"))
	unitTool:SetAttribute("BaseMoneyRate", SlotUnit:GetAttribute("BaseMoneyRate"))
	unitTool:SetAttribute("Kg", SlotUnit:GetAttribute('Kg'))
	unitTool:SetAttribute('Perk', SlotUnit:GetAttribute('Perk') or '')

	self:_copyAuraAttributes(SlotUnit, unitTool)
	self:_applyUnitStatsWithAura(
		unitTool,
		SlotUnit:GetAttribute("BossId"),
		SlotUnit:GetAttribute("BaseMoneyRate") or SlotUnit:GetAttribute("MoneyRate")
	)

	CollectionService:AddTag(unitTool,"Unit")

	local template = nil

	if SlotUnit:GetAttribute('BossId') then
		template = game.ReplicatedStorage.Assets.Mobs[SlotUnit.Name]
	elseif SlotUnit:GetAttribute('BaddieId') then
		template = game.ReplicatedStorage.Assets.Baddies[SlotUnit.Name]
	else
		template = game.ReplicatedStorage.Assets.LuckyBlocks[SlotUnit.Name]
	end

	if not template then
		warn("Template не найден:", SlotUnit.Name)
		return
	end

	local unitClone = template:Clone()

	local root = unitClone.PrimaryPart or unitClone:FindFirstChild("HumanoidRootPart") or unitClone:FindFirstChildWhichIsA("BasePart")
	if not root then
		warn("RootPart не найден у модели:", unitData.unit_id)
		return
	end

	for _, descendant in ipairs(unitClone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	for _, part in ipairs(unitClone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			part.Massless = true
		end
	end

	-- Создаём Handle
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Anchored = false
	handle.Transparency = 1
	handle.Parent = unitTool

	local offset = CFrame.new(-0.4, 4.5, 1.4)
	unitClone:PivotTo(handle.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = root
	weld.Parent = handle

	unitClone.Parent = unitTool
	
	self:_refreshAuraVisual(unitClone, unitTool)

	CollectionService:AddTag(unitTool, "Unit")

	if toHands then
		local activeTool = player.Character:FindFirstChildOfClass("Tool")
		if activeTool then
			activeTool.Parent = player.Backpack
		end
		unitTool.Parent = player.Character
	else
		local activeTool = player.Character:FindFirstChildOfClass("Tool")
		if activeTool then
			activeTool.Parent = player.Backpack
		end
		unitTool.Parent = player.Character
	end
end	

-- Метод для взятия юнита со слота
function UnitManager:GetUnitFromSlot(player, slot, unitName, toHands)

	print('Запуск взятия юнита со слота')

	if slot:WaitForChild('Available').Value == true or slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model") and slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model"):GetAttribute('LuckyBlockId') then
		return false
	end	
	
	if slot:GetAttribute('OwnerId') ~= player.UserId then
		return
	end

	slot:WaitForChild('Available').Value = true

	SoundManager.Play('Drop_Item', nil, false, slot.PrimaryPart, "Server")
	self:AddUnitToPlayer(player, nil, toHands, slot)

	if slot:FindFirstChild('Unit') then
		slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model"):Destroy()

	elseif slot:FindFirstChild('Chest') then
		slot:FindFirstChild('Chest'):FindFirstChildWhichIsA("Model"):Destroy()
	end
end

function UnitManager:DestroyUnit(slot)
	if slot:WaitForChild('Available').Value == true or slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model") and slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model"):GetAttribute('LuckyBlockId') then
		return false
	end	
	
	if slot:FindFirstChild('Unit') then
		slot:FindFirstChild('Unit'):FindFirstChildWhichIsA("Model"):Destroy()
	end
	
	slot:WaitForChild('Available').Value = true
end

local function calculateIdleIncome(userData, idle_income)
	local now = os.time()
	local time_diff = now - userData.daily_streak.last_login
	if time_diff < 0 then
		warn("[IdleIncome] Некорректное время last_login!")
		return 0
	end

	if time_diff > 14400 then
		local timeModificator = 0
		if userData.conveyor_unit_level > 1 then
			timeModificator = userData.conveyor_unit_level
		end
		time_diff = 14400 + (300 * timeModificator)
	end

	local income = time_diff * idle_income

	return math.ceil(income * 10) / 10
end

local function AnimateLuckyBlock(model)
	if not model or not model.PrimaryPart then
		warn("AnimateLuckyBlock: No PrimaryPart")
		return
	end

	local part = model.PrimaryPart
	local spinning = true

	local sound = game.ReplicatedStorage.Assets.Sounds.Roll:Clone()

	task.spawn(function()
		while spinning do
			sound.Parent = model.PrimaryPart
			sound:Play()
			sound.Ended:Wait()
		end
	end)

	------------------------------------------------
	-- НАСТРОЙКИ (можешь менять)
	------------------------------------------------

	local ACCEL_TIME = 0.5      -- разгон
	local SPIN_TIME = 1.3       -- основное вращение
	local DECEL_TIME = 0.7      -- торможение
	local FADE_TIME = 0.5       -- исчезновение

	local MAX_SPEED = 3000      -- град/сек (макс скорость)


	------------------------------------------------
	-- 1️⃣ ПЛАВНЫЙ РАЗГОН (Tween)
	------------------------------------------------

	local speedValue = Instance.new("NumberValue")
	speedValue.Value = 0
	speedValue.Parent = model


	local accelTween = TweenService:Create(
		speedValue,
		TweenInfo.new(
			ACCEL_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{ Value = MAX_SPEED }
	)

	accelTween:Play()
	accelTween.Completed:Wait()


	------------------------------------------------
	-- 2️⃣ ОСНОВНОЕ ВРАЩЕНИЕ (Heartbeat)
	------------------------------------------------

	local elapsed = 0
	local currentSpeed = MAX_SPEED

	local spinConnection

	spinConnection = RunService.Heartbeat:Connect(function(dt)

		if not part or not part.Parent then
			spinConnection:Disconnect()
			return
		end

		elapsed += dt

		------------------------------------------------
		-- Вращаем каждый кадр
		------------------------------------------------
		local angle = math.rad(currentSpeed * dt)

		part.CFrame = part.CFrame * CFrame.Angles(0, angle, 0)


		------------------------------------------------
		-- Запускаем торможение
		------------------------------------------------
		if elapsed >= SPIN_TIME then

			spinConnection:Disconnect()


			----------------------------------------
			-- 3️⃣ ЗАМЕДЛЕНИЕ (Tween)
			----------------------------------------

			local decelTween = TweenService:Create(
				speedValue,
				TweenInfo.new(
					DECEL_TIME,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.In
				),
				{ Value = 0 }
			)

			decelTween:Play()


			----------------------------------------
			-- Крутимся пока тормозит
			----------------------------------------

			local decelConn

			decelConn = RunService.Heartbeat:Connect(function(dt2)

				if not part or not part.Parent then
					decelConn:Disconnect()
					return
				end

				currentSpeed = speedValue.Value

				if currentSpeed <= 5 then
					decelConn:Disconnect()
					speedValue:Destroy()
					return
				end

				local ang = math.rad(currentSpeed * dt2)

				part.CFrame = part.CFrame * CFrame.Angles(0, ang, 0)

			end)
		end
	end)


	------------------------------------------------
	-- Ждём пока всё докрутится
	------------------------------------------------

	task.wait(ACCEL_TIME + SPIN_TIME + DECEL_TIME - 1)


	------------------------------------------------
	-- 4️⃣ ИСЧЕЗНОВЕНИЕ (Fade)
	------------------------------------------------

	local fadeTween = TweenService:Create(
		part,
		TweenInfo.new(
			FADE_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{
			--Transparency = 1,
			Size = part.Size * 0.25
		}
	)

	fadeTween:Play()
	spinning = false
	fadeTween.Completed:Wait()

	SoundManager.Play('Open_block', nil, false, workspace, "Local")
	--game.ReplicatedStorage.Assets.Sounds.Open_block:Play()
end

local function getAuraById(id)
	for _, aura in ipairs(Config.auras) do
		if aura.id == id then
			return aura
		end
	end
end

local function setupAuraLabel(billboard, source)
	if not billboard or not billboard.Frame then
		return
	end

	local auraLabel = billboard.Frame:FindFirstChild("Aura")
	if not auraLabel then
		return
	end

	auraLabel.Visible = false
	auraLabel.Text = ""

	local oldGradient = auraLabel:FindFirstChild("RainbowGradient")
	if oldGradient then
		oldGradient:Destroy()
	end

	local hasAura = source:GetAttribute("HasAura")
	local auraId = source:GetAttribute("AuraId")

	if not hasAura or not auraId then
		return
	end

	local aura = getAuraById(auraId)
	if not aura then
		return
	end

	auraLabel.Visible = true
	auraLabel.Text = aura.name

	if aura.id == "rainbow" then
		auraLabel.TextColor3 = Color3.new(1, 1, 1)

		local gradient = Instance.new("UIGradient")
		gradient.Name = "RainbowGradient"
		gradient.Parent = auraLabel
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(170, 0, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 170, 255)),
		})
	else
		auraLabel.TextColor3 = Constants.AURA_COLORS[aura.id] or Color3.new(1, 1, 1)
	end
end

function UnitManager:PlaceUnitInSlot(player, slot, unitData, autoPlacing, unit, tool)
	if not slot then
		warn("Slot folder is missing!")
		return false
	end

	if slot:GetAttribute("access") == false then
		return false
	end

	if not unitData then
		if slot:WaitForChild("Available", 20).Value == false then
			print("Slot is busy or debounce active")
			return false
		end
	end

	if slot:GetAttribute("OwnerId") ~= player.UserId then
		return
	end

	local unitName
	local perkID
	local storageMoney
	local mergeLevel
	local Rarity
	local Kg
	local typeItem
	local ModelUnit

	local function getCharacterTool()
		if tool then
			return tool
		end

		if not player.Character then
			return nil
		end

		return player.Character:FindFirstChildOfClass("Tool")
	end

	local function getPrimaryTool()
		local currentTool = getCharacterTool()
		if not currentTool then
			return nil
		end
		return currentTool
	end

	local function cleanupPlayerUnit(unitNameToRemove, toolInstanceToDestroy)
		local PlayerStats = player:WaitForChild("PlayerStats", 10)
		
		if Config.bosses[unitNameToRemove] then
			local petsFolder = player:WaitForChild("Pets")
			local UnitString = petsFolder:FindFirstChild(Config.bosses[unitNameToRemove].id)
			if UnitString then
				UnitString:Destroy()
			end
		end

		if toolInstanceToDestroy then
			toolInstanceToDestroy:Destroy()
		end
	end

	local function setModelPartsCollision(model)
		for _, v in pairs(model:GetChildren()) do
			if v:IsA("BasePart") or v:IsA("MeshPart") then
				v.CanQuery = false
				v.CanCollide = false
			end
		end
	end

	local function placeModelOnSlot(model, slotRef, itemType)
		model.PrimaryPart = model.PrimaryPart

		local slotPart = slotRef.PrimaryPart
		local slotCFrame = slotPart.CFrame
		local targetPos = slotPart.Position

		if itemType == "block" then
			local initialCFrame = CFrame.new(targetPos, targetPos + slotCFrame.LookVector)
			model:PivotTo(initialCFrame)

			local _, modelSize = model:GetBoundingBox()
			local bottomOffset = modelSize.Y / 2
			local elevatedPos = slotPart.Position + Vector3.new(0, slotPart.Size.Y / 2 + bottomOffset, 0)
			local finalCFrame = CFrame.lookAt(elevatedPos, elevatedPos + slotPart.CFrame.LookVector)

			model:PivotTo(finalCFrame)
		else
			local initialCFrame = CFrame.new(targetPos, targetPos + slotCFrame.LookVector)
			model:PivotTo(initialCFrame)

			local finalCFrame = CFrame.lookAt(targetPos, targetPos + slotPart.CFrame.LookVector)
			model:PivotTo(finalCFrame)
		end
	end

	local function getBillboardParent(model, itemType)
		if itemType == "block" then
			return model.PrimaryPart
		end

		return model.PrimaryPart or model:WaitForChild("HumanoidRootPart")
	end

	local function setupIdleAnimation(model)
		local animationController = model:FindFirstChildWhichIsA("AnimationController")
		local animator = animationController and animationController:FindFirstChildWhichIsA("Animator")

		if animator and animationController then
			local animation =
				animationController:FindFirstChild("idle")
				or animationController:FindFirstChild("Idle")
				or animationController:FindFirstChild("walk")
				or animationController:FindFirstChild("Walk")

			if animation and animation:IsA("Animation") then
				local track = animator:LoadAnimation(animation)
				track.Looped = true
				track:Play()
			end
		end

		if not animationController then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local animation = model:FindFirstChildWhichIsA("Animation")
				if animation then
					local track = humanoid:LoadAnimation(animation)
					track.Looped = true
					track:Play()
				end
			end
		end
	end

	local currentTool = getPrimaryTool()

	if not unitData then
		if not currentTool then
			return false
		end

		if currentTool:GetAttribute("BossId") then
			ModelUnit = game.ReplicatedStorage.Assets.Mobs[currentTool:GetAttribute("BossId")]
			typeItem = "boss"

			Tutorial:HandleEvent(player, "BrainrotPlaced")
			Tutorial:ShowIfNeeded(player)
		elseif currentTool:GetAttribute("LuckyBlockId") then
			ModelUnit = game.ReplicatedStorage.Assets.LuckyBlocks[currentTool:GetAttribute("LuckyBlockId")]
			typeItem = "block"
			
			Tutorial:HandleEvent(player, "LuckyblockPlaced")
			Tutorial:ShowIfNeeded(player)
		else
			return
		end
	else
		typeItem = "boss"
		ModelUnit = game.ReplicatedStorage.Assets.Mobs[unitData.id]
	end

	if not ModelUnit then
		warn("Unit model not found:", unitName)
		return false
	end

	SoundManager.Play("Drop_Item", nil, false, slot.PrimaryPart, "Server")

	if unitData then
		unitName = unitData.id or unitData.unit_id

		local profile = Profiles:GetProfile(player)
		if not profile then
			warn("Профиль игрока не найден для продажи юнита:", player)
			return false
		end
		
		

		storageMoney = (unitData.soft_collected or 0) + calculateIdleIncome(profile.Data, Config.bosses[unitName].money_rate)

		if not profile.Data.stats.cash_collected_offline then
			profile.Data.stats.cash_collected_offline = 0
		end

		profile.Data.stats.cash_collected_offline += storageMoney

		storageMoney = 0
		
	elseif autoPlacing and unit then
		if not unit then
			warn("Player does not have a Unit tool!")
			return false
		end

		perkID = 0
		storageMoney = 0
		unitName = unit.unit.Name

		cleanupPlayerUnit(unitName, unit.unit)
	else
		local equippedTool = getPrimaryTool()

		if not equippedTool then
			warn("Player does not have a Unit tool!")
			return false
		end

		unitName =
			equippedTool:GetAttribute("BossId")
			or equippedTool:GetAttribute("LuckyBlockId")
			or equippedTool:GetAttribute("BaddieId")
			or equippedTool.Name

		storageMoney = equippedTool:GetAttribute("StorageMoney") or 0
		cleanupPlayerUnit(unitName, equippedTool)
	end

	local ModelUnitClone = ModelUnit:Clone()
	setModelPartsCollision(ModelUnitClone)
	placeModelOnSlot(ModelUnitClone, slot, typeItem)

	local Weld = Instance.new("Weld")
	Weld.Part0 = ModelUnitClone.PrimaryPart
	Weld.Part1 = slot.PrimaryPart
	Weld.Parent = ModelUnitClone.PrimaryPart

	local BilboardInfo = game.ReplicatedStorage.Assets.UI.InfoUnit:Clone()
	BilboardInfo.Parent = getBillboardParent(ModelUnitClone, typeItem)

	local BilboardInfo2 = game.ReplicatedStorage.Assets.UI.InfoUnit2:Clone()
	BilboardInfo2.Parent = getBillboardParent(ModelUnitClone, typeItem)

	ModelUnitClone:SetAttribute("StorageMoney", storageMoney)
	ModelUnitClone:AddTag("Unit")

	local BillboardInfo

	if typeItem == "block" then
		BillboardInfo = ModelUnitClone.PrimaryPart
		if currentTool then
			ModelUnitClone:SetAttribute("LuckyBlockId", currentTool:GetAttribute("LuckyBlockId"))
			self:_copyAuraAttributes(currentTool, ModelUnitClone)
		end
	elseif typeItem == "baddie" then
		if currentTool then
			ModelUnitClone:SetAttribute("BaddieId", currentTool:GetAttribute("BaddieId"))
		end
		BillboardInfo =
			ModelUnitClone:FindFirstChild("MainPart")
			or ModelUnitClone.PrimaryPart.InfoUnit
			or ModelUnitClone:FindFirstChild("HumanoidRootPart").InfoUnit
	else
		BillboardInfo =
			ModelUnitClone:FindFirstChild("MainPart")
			or ModelUnitClone.PrimaryPart.InfoUnit
			or ModelUnitClone:FindFirstChild("HumanoidRootPart").InfoUnit
	end

	unitName =
		(unitData and unitData.id)
		or (currentTool and currentTool:GetAttribute("BossId"))
		or (currentTool and currentTool:GetAttribute("LuckyBlockId"))
		or (currentTool and currentTool:GetAttribute("BaddieId"))

	BilboardInfo.Frame.UnitName.Visible = true

	if typeItem == "block" then
		BilboardInfo.Frame.UnitName.UnitName.Text = Config.lucky_blocks[unitName].name
		BilboardInfo.Enabled = false
	elseif typeItem == "boss" then
		BilboardInfo.Frame.UnitName.UnitName.Text = Config.bosses[unitName].name or "Что это за фигня?"
		--if unitData and unitData.has_aura then
		--	BilboardInfo.Frame.Aura.Visible = true
		--	local aura = getAuraById(unitData.aura_id)
		--	BilboardInfo.Frame.Aura.Text = aura and aura.name or "No Aura"
			
		--	if aura.id == 'rainbow' then
		--		BilboardInfo.Frame.Aura.TextColor3 = Color3.new(1,1,1)

		--		local gradient = BilboardInfo.Frame.Aura:FindFirstChild("RainbowGradient")
		--		if not gradient then
		--			gradient = Instance.new("UIGradient")
		--			gradient.Name = "RainbowGradient"
		--			gradient.Parent = BilboardInfo.Frame.Aura

		--			gradient.Color = ColorSequence.new({
		--				ColorSequenceKeypoint.new(0.00, Color3.fromRGB(170, 0, 255)),
		--				ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 170, 255)),
		--			})
		--		end				
		--	else
		--		BilboardInfo.Frame.Aura.TextColor3 = Constants.AURA_COLORS[aura.id]
		--	end
		--end
	else
		BilboardInfo.Frame.UnitName.UnitName.Text = Config.baddies[unitName].name
	end

	if typeItem == "boss" then
		ModelUnitClone:SetAttribute("BossId", unitData and unitData.id or (currentTool and currentTool:GetAttribute("BossId")))
		ModelUnitClone:SetAttribute("Name", unitData and Config.bosses[unitName].name or (currentTool and currentTool:GetAttribute("Name")))
		ModelUnitClone:SetAttribute("Rarity", unitData and Config.bosses[unitName].rarity or (currentTool and currentTool:GetAttribute("Rarity")))
		ModelUnitClone:SetAttribute("BaseMoneyRate", Config.bosses[unitName].money_rate or 0)

		if unitData then
			self:_setAuraData(ModelUnitClone, unitData)
		elseif currentTool then
			self:_copyAuraAttributes(currentTool, ModelUnitClone)
		end

		self:_applyUnitStatsWithAura(ModelUnitClone, unitName)
		setupAuraLabel(BilboardInfo, ModelUnitClone)
	end

	BilboardInfo.Frame.UnitName.Class.Visible = false

	local idleIncome = nil

	if typeItem == "block" then
		-- nothing
	else
		self:idleIncome(player, ModelUnitClone, BilboardInfo, slot:WaitForChild("Button"), slot:WaitForChild("Available", 20))

		BillboardInfo.Frame.UnitName.UnitName.Text = Config.bosses[unitName].name
		BillboardInfo.Frame.UnitName.Visible = true

		BillboardInfo.Frame.Rarity.Text = Config.bosses[unitName].rarity
		BillboardInfo.Frame.Rarity.Visible = true
		BillboardInfo.Frame.Rarity.TextColor3 = Constants.RARITY_COLORS[string.lower(Config.bosses[unitName].rarity)] or  Constants.RARITY_COLORS.secret

		local UnitString = player:WaitForChild("Pets", 10):FindFirstChild(Config.bosses[unitName].id)
		if UnitString then
			UnitString:Destroy()
		end

		idleIncome = math.floor(ModelUnitClone:GetAttribute("MoneyRate") or 0)
		BillboardInfo.Frame.TimeIncome.Visible = true
		BillboardInfo.Frame.TimeIncome.Text = "$" .. idleIncome .. "/s"
	end

	task.delay(2, function()
		for _, v in pairs(ModelUnitClone:GetChildren()) do
			if v:IsA("Part") or v:IsA("MeshPart") then
				v.CanCollide = false
				v.CanQuery = false
				v.CanTouch = false
			end
		end
	end)

	ModelUnitClone.Parent = slot:FindFirstChild("Unit")
	
	self:_refreshAuraVisual(ModelUnitClone, ModelUnitClone)

	if typeItem == "block" then
		ModelUnitClone.PrimaryPart.Anchored = true
	else
		ModelUnitClone.PrimaryPart.Anchored = true
	end

	slot:WaitForChild("Available", 20).Value = false

	if typeItem == "block" then
		if not ModelUnitClone.PrimaryPart then
			ModelUnitClone.PrimaryPart = ModelUnitClone:FindFirstChildWhichIsA("BasePart")
		end

		ModelUnitClone.PrimaryPart.Anchored = true
		self:DropUnit(player, ModelUnitClone, slot)
		return
	end

	setupIdleAnimation(ModelUnitClone)

	local TriggerPart = slot:WaitForChild("Button")
	local Debounce = false

	TriggerPart.Touched:Connect(function(hit)
		if
			hit.Parent:FindFirstChild("Humanoid")
			and Debounce == false
			and slot:WaitForChild("Unit")
			and slot:WaitForChild("Unit"):FindFirstChildOfClass("Model")
		then
			if not game.Players:FindFirstChild(hit.Parent.Name) then
				return
			end

			local Player = game.Players:GetPlayerFromCharacter(hit.Parent)
			if not Player then
				return
			end

			if slot:GetAttribute("OwnerId") ~= Player.UserId then
				return
			end

			local placedUnitName = slot.Unit:FindFirstChildWhichIsA("Model").Name

			Debounce = true
			self:GiveReward(slot, game.Players:WaitForChild(hit.Parent.Name))

			task.wait(2)
			Debounce = false
		end
	end)

	return true
end

local function playMoneyEffect(Slot, player, amount, allCash, profile)
	local character = player.Character
	if not character then
		warn("Character not found for player:", player.Name)
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		warn("HumanoidRootPart not found for player:", player.Name)
		return
	end

	if amount > 100 then
		amount = 100
	end

	SoundManager.Play('Collect_sound', nil, false, Slot.PrimaryPart, "Server")
	--game.ReplicatedStorage.Assets.Sounds.Collect_sound:Play()

	local dropsCount = math.clamp(math.floor(amount / 10), 3, 15)
	local remainingCash = dropsCount

	for i = 1, dropsCount do
		local cashTemplate = ReplicatedStorage.Assets.Effects.Cash
		if not cashTemplate then
			warn("Cash template not found in ReplicatedStorage!")
			return
		end

		local cash = cashTemplate:Clone()

		local offset = Vector3.new(
			RNG:NextNumber(-5, 5),
			RNG:NextNumber(5, 10),
			RNG:NextNumber(-5, 5)
		)

		cash:PivotTo(CFrame.new(Slot.PrimaryPart.CFrame.Position + offset))
		cash.Cash.CollisionGroup = 'Cash'
		cash.Parent = workspace

		task.delay(0.5, function()
			if not cash or not cash.Parent then
				warn("Cash object was destroyed or removed before moving.")
				return
			end

			if not cash or not cash.Parent then
				warn("Cash object was destroyed or removed before moving.")
				remainingCash -= 1
				return
			end

			local speed = math.random(60, 75)

			local connection
			connection = RunService.Heartbeat:Connect(function(deltaTime)
				if not cash or not cash.Parent then
					connection:Disconnect()
					return
				end

				if not cash or not cash.Parent then
					connection:Disconnect()
					remainingCash -= 1
					return
				end

				local cashPosition = cash.PrimaryPart.Position
				cash.PrimaryPart.Anchored = true
				local targetPosition = hrp.Position

				local distance = (targetPosition - cashPosition).Magnitude

				if distance < 0.5 then
					cash:Destroy()
					connection:Disconnect()
					remainingCash -= 1
					SoundManager.Play('Coin', nil, false, Slot.PrimaryPart, "Server")
					--game.ReplicatedStorage.Assets.Sounds.Coin:Play()

					if remainingCash == 0 then
						Profiles:AddStat(player, "gems", allCash)
						game.ReplicatedStorage.Remotes.UpdateSoft:FireClient(player, profile.Data.stats)
						
						if profile.Data.stats.gems >= Constants.CASH_TUTORIAL_TO_COLLECT then
							Tutorial:HandleEvent(player, "MoneyCollected")
							Tutorial:ShowIfNeeded(player)
						end
					end
					return
				end

				local direction = (targetPosition - cashPosition).Unit
				local movement = direction * speed * deltaTime
				cash:PivotTo(CFrame.new(cashPosition + movement))
			end)
		end)
	end
end

function UnitManager:DropUnit(player, item, slot)
	if not item then
		warn("[DropUnit] item is nil")
		return
	end

	local luckyId = item:GetAttribute("LuckyBlockId")
	if not luckyId then
		warn("[DropUnit] No LuckyBlockId")
		return
	end
	
	local auraData = self:_getAuraData(item)

	local luckyConfig = Config.lucky_blocks[luckyId]
	if not luckyConfig or not luckyConfig.bosses then
		warn("[DropUnit] Lucky block config not found:", luckyId)
		return
	end

	-- =========================
	-- Weighted random
	-- =========================
	
	local totalWeight = 0
	local weightedBosses = {}
	
	for _, bossId in ipairs(luckyConfig.bosses) do
		local bossConfig = Config.bosses[bossId.bosses_id]
		if bossConfig then
			local rarity = bossConfig.rarity
			local weight = Constants.RarityWeights[rarity]

			if weight and weight > 0 then
				totalWeight += weight
				table.insert(weightedBosses, {
					bosses_id = bossId,
					weight = weight,
				})
			else
				warn("[DropUnit] No rarity weight for:", bossId, "rarity:", rarity)
			end
		else
			warn("[DropUnit] bosses config not found:", bossId)
		end
	end
	
	-- Логика у каждого юнита свой вес
	local totalWeight = 0
	for _, data in ipairs(luckyConfig.bosses) do
		totalWeight += data.weight
	end
		
	local roll = math.random(1, totalWeight)
	local current = 0
	local BossId = nil

	for _, data in ipairs(luckyConfig.bosses) do
		current += data.weight
		if roll <= current then
			BossId = data.bosses_id
			break
		end
	end

	if not BossId then
		warn("[DropUnit] Failed to select boss")
		return
	end

	local bossConfig = Config.bosses[BossId]
	if not bossConfig then
		warn("[DropUnit] bosses config not found:", BossId)
		return
	end

	-- =========================
	-- Cleanup lucky block
	-- =========================
	
	AnimateLuckyBlock(item)
	
	local unitFolder = slot:FindFirstChild("Unit")
	if unitFolder then
		for _, model in ipairs(unitFolder:GetChildren()) do
			model:Destroy()
		end
	end

	local effectDrop = game.ReplicatedStorage.Assets.Effects.Drop_effect:Clone()
	effectDrop.Parent = slot

	task.delay(0.5, function()
		for i, v in pairs(effectDrop:GetChildren()) do
			if v:IsA('ParticleEmitter') then
				v.Enabled = false
			end
		end
		task.delay(1, function()
			effectDrop:Destroy()
		end)
	end)

	if slot and slot:FindFirstChild('Available') then
		slot.Available.Value = true
	else 
		return
	end
	
	local profile = Profiles:GetProfile(player)
	if not profile then
		warn("Профиль игрока не найден для продажи юнита:", player)
		return false
	end


	local selectedItem = nil

	selectedItem = {
		nameItem = BossId,
		type = 'bosses',
		level =  1
	}

	table.insert(profile.Data.items, {
		name = selectedItem.nameItem or 'undefined',
		type = 'bosses',
		level = selectedItem.level or 1,
	})

	if not profile.Data.index then
		profile.Data.index = {}
	end

	local indexKeys = {}
	for key in pairs(profile.Data.index) do
		indexKeys[key] = true
	end

	for _, item in pairs(profile.Data.items) do
		
		if not item or not item.level or not item.name then
			break
		end
		
		local key = item.name  --.. "_" .. item.level or 1

		if not indexKeys[key] and item.name then
			profile.Data.index[key] = {
				name = item.name,
				type = 'bosses',
				--level = item.level or 1,
			}
			game.ReplicatedStorage.Remotes.NotifsEvent2:FireClient(player, "You have received an item in the collection!", "green")
			IndexUpdated:FireClient(player, key)
		end
	end
	
	local UnitData = {
		id = BossId,
		has_aura = auraData.has_aura,
		aura_id = auraData.aura_id,
		aura_multiplier = auraData.aura_multiplier,
	}

	-- =========================
	-- Place brainrot in same slot
	-- =========================
	player:SetAttribute('TotalBrainrots', player:GetAttribute('TotalBrainrots') + 1)
	
	self:PlaceUnitInSlot(player, slot, UnitData)
end

-- Метод для idle дохода
function UnitManager:idleIncome(player : Player, unit, BilboardInfo, button, available)
	local unitData = unit
	if not unitData then
		warn("Не удалось получить юнита ", unitData)
		return
	end

	local timeReward = 1 
	local reward = unitData:GetAttribute("Reward") or 1
	local storageMoney = unitData:GetAttribute('StorageMoney') or 0
	local unitInfo = BilboardInfo.Frame
	
	local profile = Profiles:GetProfile(player)
	if not profile then
		repeat
			profile = Profiles:GetProfile(player)
			wait(1)
		until profile
	end

	task.delay(1, function()
		available.Changed:Connect(function()
			return
		end)
		
		while player and unitData and available and available.Value == false do
			if not game.Players:FindFirstChild(player.Name) then break end
			
			local moneyRateMod = profile.Data.stats.money_rate_mod or 1

			local idleIncome =
				(reward or 1)
				* (player:GetAttribute("permanentIncomeBonus") or 1)
				* (player:GetAttribute("MoneyBonus") or 1)
				* moneyRateMod

			if unitData:GetAttribute("giveReward") == true then
				unitData:SetAttribute("giveReward", false)
				storageMoney = 0
			else
				storageMoney = storageMoney + idleIncome
			end
			
			button.SurfaceGui.Frame.TextLabel.Text = "$" .. formatNumber(math.ceil(storageMoney * 10) / 10)
			
			if unitInfo and unitInfo:FindFirstChild('TimeIncome') then
				unitInfo.TimeIncome.Text = '$'..formatNumber(idleIncome).."/s"
			end
			
			button.SurfaceGui.Enabled = true
			unitData:SetAttribute("StorageMoney", storageMoney)
			
			task.wait(timeReward)
		end
		button.SurfaceGui.Enabled = false
		
		return
	end)
end

function UnitManager:DropUnitFromWheel(player, rarity)
	print(player, rarity)
	if not rarity then
		warn("[DropUnit] rarity is nil")
		return
	end

	local bossesConfig = Config.bosses
	if not bossesConfig then
		warn("[DropUnit] bossesConfig config not found")
		return
	end

	-- =========================
	-- Weighted random
	-- =========================

	local pool = {}

	for _, data in pairs(bossesConfig) do
		if data.rarity == rarity then
			table.insert(pool, data)
		end
	end

	if #pool == 0 then
		error("No bosses with rarity:", rarity)
		return
	end

	local selected = pool[math.random(1, #pool)]
	local BossId = selected.id

	if not BossId then
		error("[DropUnit] Failed to select BossId")
		return
	end

	local bossesConfigUnit = Config.bosses[BossId]
	if not bossesConfigUnit then
		warn("[DropUnit] bossesConfigUnit config not found:", BossId)
		return
	end


	local Tool = Instance.new("Tool")
	Tool.Name = BossId

	Tool:SetAttribute("Name", bossesConfigUnit.name)
	Tool:SetAttribute("Rarity", bossesConfigUnit.rarity)
	Tool:SetAttribute("MoneyRate", bossesConfigUnit.money_rate)
	Tool:SetAttribute("BossId", BossId)

	Tool.Parent = player.Backpack

	local profile = Profiles:GetProfile(player)
	if not profile then
		warn("Профиль игрока не найден для продажи юнита:", player)
		return false
	end

	local selectedItem = nil

	selectedItem = {
		nameItem = BossId,
		type = 'bosses',
		level =  1
	}

	table.insert(profile.Data.items, {
		name = selectedItem.nameItem or 'undefined',
		type = 'bosses',
		level = selectedItem.level or 1,
	})

	if not profile.Data.index then
		profile.Data.index = {}
	end

	local indexKeys = {}
	for key in pairs(profile.Data.index) do
		indexKeys[key] = true
	end

	for _, item in pairs(profile.Data.items) do

		if not item or not item.level or not item.name then
			break
		end

		local key = item.name  --.. "_" .. item.level or 1

		if not indexKeys[key] and item.name then
			profile.Data.index[key] = {
				name = item.name,
				type = 'bosses',
			}
			game.ReplicatedStorage.Remotes.NotifsEvent2:FireClient(player, "You have received an item in the collection!", "green")
			IndexUpdated:FireClient(player, key)
		end
	end

	local UnitData = {
		id = BossId
	}

	player:SetAttribute('TotalBrainrots', player:GetAttribute('TotalBrainrots') + 1)
end

function UnitManager:GiveReward(slot, player, action)
	local unit = slot:WaitForChild('Unit'):FindFirstChildOfClass('Model')
	if not unit then
		warn('Юнит не найден')
		return false
	end

	local storageMoney = unit:GetAttribute('StorageMoney') or 0

	if storageMoney < 1 then
		return
	end

	local profile = Profiles:GetProfile(player)
	if not profile then
		--warn('Profile is not find')
		repeat
			profile = Profiles:GetProfile(player)
			wait(2)
			warn('Try catch user Profile p')
			--print(Profiles:GetProfile(player))
		until profile
	end

	--profile.Data.stats.gems += storageMoney
	Profiles:AddStat(player, "gems", storageMoney)
	if profile.Data.stats.gems >= Constants.CASH_TUTORIAL_TO_COLLECT then
		Tutorial:HandleEvent(player, "MoneyCollected")
		Tutorial:ShowIfNeeded(player)
	end
	
	game.ReplicatedStorage.Remotes.UpdateSoft:FireClient(
		player,
		profile.Data.stats
	)
	game.ReplicatedStorage.Remotes.PlayMoneyEffect:FireClient(
		player,
		slot.PrimaryPart.Position,
		storageMoney
	)
	SoundManager.Play('Collect_sound', nil, false, slot.PrimaryPart, "Server")

	local unit = slot:WaitForChild('Unit'):FindFirstChildOfClass('Model')

	if unit then
		unit:SetAttribute('StorageMoney', 0)
		unit:SetAttribute('giveReward', true)
		local BillboardInfo = unit:FindFirstChild('MainPart') or unit.PrimaryPart.InfoUnit or unit:FindFirstChild('HumanoidRootPart').InfoUnit
		BillboardInfo.Frame.Income.Text = '$0'
	else
		warn('Юнит не найден')
	end
	
	local billboard =
		unit:FindFirstChild("MainPart")
		or (unit.PrimaryPart and unit.PrimaryPart:FindFirstChild("InfoUnit"))
		or unit:FindFirstChild("HumanoidRootPart")

	if billboard and billboard:FindFirstChild("Frame") then
		billboard.Frame.Income.Text = "$0"
	end
	
	return true
end

function UnitManager:_getAuraData(source)
	if not source then
		return {
			has_aura = false,
			aura_id = nil,
			aura_multiplier = 1,
		}
	end

	local hasAura = source:GetAttribute("HasAura") == true
	local auraId = source:GetAttribute("AuraId")
	local auraMultiplier = source:GetAttribute("AuraMultiplier") or 1

	if not hasAura or not auraId then
		return {
			has_aura = false,
			aura_id = nil,
			aura_multiplier = 1,
		}
	end

	return {
		has_aura = true,
		aura_id = auraId,
		aura_multiplier = auraMultiplier,
	}
end

function UnitManager:_setAuraData(target, auraData)
	if not target then
		return
	end

	auraData = auraData or {}

	local hasAura = auraData.has_aura == true and auraData.aura_id ~= nil
	target:SetAttribute("HasAura", hasAura)

	if hasAura then
		target:SetAttribute("AuraId", auraData.aura_id)
		target:SetAttribute("AuraMultiplier", auraData.aura_multiplier or 1)
	else
		target:SetAttribute("AuraId", nil)
		target:SetAttribute("AuraMultiplier", nil)
	end
end

function UnitManager:_copyAuraAttributes(fromInstance, toInstance)
	if not fromInstance or not toInstance then
		return
	end

	self:_setAuraData(toInstance, self:_getAuraData(fromInstance))
end

function UnitManager:_applyUnitStatsWithAura(target, bossId, fallbackMoneyRate)
	if not target then
		return
	end

	local baseRate = fallbackMoneyRate
	if bossId and Config.bosses[bossId] then
		baseRate = Config.bosses[bossId].money_rate
	end

	baseRate = baseRate or 0

	local auraData = self:_getAuraData(target)
	local finalRate = baseRate

	if auraData.has_aura then
		finalRate = baseRate * (auraData.aura_multiplier or 1)
	end

	target:SetAttribute("Reward", finalRate)
	target:SetAttribute("MoneyRate", finalRate)
	target:SetAttribute("BaseMoneyRate", baseRate)
end

function UnitManager:_clearAuraFromUnitModel(unitModel)
	if not unitModel then
		return
	end

	local primary = unitModel.PrimaryPart or unitModel:FindFirstChild("HumanoidRootPart")
	if not primary then
		return
	end

	for _, child in ipairs(primary:GetChildren()) do
		if child:GetAttribute("IsAuraEffect") then
			child:Destroy()
		end
	end
end

function UnitManager:_applyAuraToUnitModel(unitModel, auraId)
	if not unitModel or not unitModel.Parent then
		return
	end

	self:_clearAuraFromUnitModel(unitModel)

	if not auraId then
		return
	end

	local primary = unitModel.PrimaryPart or unitModel:FindFirstChild("HumanoidRootPart")
	if not primary then
		return
	end

	local auraFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Auras"):FindFirstChild(auraId)
	if not auraFolder then
		warn("[UnitManager] Aura folder not found:", auraId)
		return
	end

	for _, child in ipairs(auraFolder:GetChildren()) do
		local clone = child:Clone()
		clone:SetAttribute("IsAuraEffect", true)
		clone.Parent = primary
	end
	
	Functions.ScaleParticles(unitModel, unitModel:GetScale() * 2)
end

function UnitManager:_refreshAuraVisual(unitModel, source)
	if not unitModel or not source then
		return
	end

	local auraData = self:_getAuraData(source)
	if auraData.has_aura then
		self:_applyAuraToUnitModel(unitModel, auraData.aura_id)
	else
		self:_clearAuraFromUnitModel(unitModel)
	end
end

return UnitManager