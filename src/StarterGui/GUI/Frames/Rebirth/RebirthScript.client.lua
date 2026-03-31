--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

--// Remotes / Modules
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PrestigeRequest = Remotes:WaitForChild("PrestigeRequest")
local GetPrestigeData = Remotes:WaitForChild("GetPrestigeData")

local PrestigeService = require(ReplicatedStorage.Modules.General.PrestigeService)
local Config = require(ReplicatedStorage.Configs.Config)
local Constants = require(ReplicatedStorage.Configs.Constants)
local MonetizationConfig = require(ReplicatedStorage.Configs.MonetizationConfig)

--// Player
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

--------------------------------------------------
-- UI
--------------------------------------------------

local rootUI = player.PlayerGui:WaitForChild("GUI").Frames.Rebirth
local mainFrame = rootUI:WaitForChild("MainFrame")

local button = mainFrame.Button.Soft
local robuxRebirth = mainFrame.Button.Robux
local statusLabel = button.TextLabel

-- Requirements UI
local YouNeedContent = mainFrame.Content.YouNeed.Content
local TemplateNeed = YouNeedContent.Template

-- Rewards UI
local YouRewardContent = mainFrame.Content.Rewards.Content
local TemplateFloor = YouRewardContent.Floor
local TemplateMoney = YouRewardContent.Money
local TemplateSlots = YouRewardContent.Slots
local currentPrestige = 0


--------------------------------------------------
-- CONFIG
--------------------------------------------------

-- Requirements
local NeedConfig = {

	soft_required = {
		name = "Gems",
		image = "rbxassetid://102121104989061",
	},
	
	--ufo_height_level_required = {
	--	name = "UFO Level",
	--	image = "",
	--},

	island_name = {
		name = "Reach Island",
		image = "",
	},

	carry_capacity_required = {
		name = "Carry Capacity",
		image = "rbxassetid://98936947495356",
	},

	total_dmg_required = {
		name = "Total Damage",
		image = "rbxassetid://128814675536689",
	},

	item_required = {
		name = "Required Item",
		image = "rbxassetid://114633371829343",
	},
}

-- Rewards
local RewardUIConfig = {

	floors = {
		template = TemplateFloor,
		name = "Floors",
		img = "rbxassetid://108565344366236",
	},

	slots = {
		template = TemplateSlots,
		name = "Slots",
		img = "rbxassetid://114718845135038",
	},

	money = {
		template = TemplateMoney,
		name = "Money",
		img = "rbxassetid://102121104989061",
	},
	
	island_unlock = {
		template = TemplateFloor,
		name = "Unlock",
		img = "",
	},
}



local function formatNumber2(value)
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


--------------------------------------------------
-- UTILS
--------------------------------------------------

local debounce = false

local hoverSound = ReplicatedStorage:WaitForChild('Assets'):WaitForChild('Sounds'):WaitForChild('UIHoverSound')
local clickSound = ReplicatedStorage:WaitForChild('Assets'):WaitForChild('Sounds'):WaitForChild('UIClickSound')
local function setupButtonEffects(button)
	local defaultSize = button.Size
	local hoverSize = defaultSize + UDim2.fromScale(0.03, 0.03)
	local clickSize = defaultSize - UDim2.fromScale(0.02, 0.02)

	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function tweenTo(size)
		TweenService:Create(button, tweenInfo, {Size = size}):Play()
	end

	button.MouseEnter:Connect(function()
		tweenTo(hoverSize)
		hoverSound:Play()
	end)

	button.MouseLeave:Connect(function()
		tweenTo(defaultSize)
	end)

	button.MouseButton1Down:Connect(function()
		tweenTo(clickSize)
	end)

	button.MouseButton1Up:Connect(function()
		tweenTo(hoverSize)
		clickSound:Play()
	end)
end

local function formatNumber(num)

	if num >= 1_000_000 then
		return string.format("%.1fM", num / 1_000_000)

	elseif num >= 1000 then
		return math.floor(num / 1000) .. "K"

	else
		return tostring(num)
	end
end

--------------------------------------------------
-- CLEAR
--------------------------------------------------

local function clearRequirements()

	for _, child in ipairs(YouNeedContent:GetChildren()) do

		if child:IsA("Frame") and child ~= TemplateNeed then
			child:Destroy()
		end
	end
end


local function clearRewards()

	for _, child in ipairs(YouRewardContent:GetChildren()) do

		if child:IsA("Frame")
			and child ~= TemplateFloor
			and child ~= TemplateMoney
			and child ~= TemplateSlots then

			child:Destroy()
		end
	end
end

--------------------------------------------------
-- REQUIREMENTS UI
--------------------------------------------------

local function updateRequirementsDisplay(currentPrestige)
	local req = PrestigeService:GetRequirementForLevel(currentPrestige + 1)
	if not req then return end

	clearRequirements()

	for key, uiConfig in pairs(NeedConfig) do
		local value = req[key]
		if not value then continue end

		local clone = TemplateNeed:Clone()
		clone.Visible = true
		clone.Parent = YouNeedContent

		local icon = clone:FindFirstChild("ImageLabel")
		local nameLabel = clone:FindFirstChild("NameLabel")
		local valueLabel = clone:FindFirstChild("NeedLabel")

		if nameLabel then
			nameLabel.Text = uiConfig.name
			nameLabel.TextColor3 = Color3.new(1, 1, 1)
		end

		local isRequirementMet = true
		if valueLabel then
			valueLabel.TextColor3 = Color3.new(1, 1, 1)
		end

		if key == "item_required" and type(value) == "table" then
			local itemName = tostring(value[1] or "Item")

			if Config.bosses[itemName] then
				if icon then
					icon.Image = Config.bosses[itemName].img
				end

				if valueLabel then
					valueLabel.Text = Config.bosses[itemName].name
				end

				if nameLabel then
					nameLabel.Text = Config.bosses[itemName].rarity
					nameLabel.TextColor3 = Constants.RARITY_COLORS[string.lower(Config.bosses[itemName].rarity)]
				end
			end

			local requiredItemName = value[1]
			local hasItem = false

			local plot
			for _, p in pairs(workspace.Base.Main.Plots:GetChildren()) do
				if p:GetAttribute("OwnerId") == player.UserId then
					plot = p
					break
				end
			end

			if not plot then
				warn("No plot for player")
				return
			end

			local slots = plot:FindFirstChild("PlayerBase") and plot.PlayerBase:FindFirstChild("Slots")
			if slots then
				for _, slot in ipairs(slots:GetChildren()) do
					local unitFolder = slot:FindFirstChild("Unit")
					local model = unitFolder and unitFolder:FindFirstChildOfClass("Model")

					if model and model.Name == requiredItemName then
						hasItem = true
						break
					end
				end
			end

			isRequirementMet = hasItem

		elseif key == "soft_required" then
			local playerMoney = player:GetAttribute("gems") or 0
			isRequirementMet = playerMoney >= value

			if icon then
				icon.Image = uiConfig.image
			end

			if nameLabel then
				nameLabel.Text = "Money"
			end

			if valueLabel then
				valueLabel.Text = formatNumber2(value)
			end

		--elseif key == "ufo_height_level_required" then
		--	local currentUFOLevel = player:GetAttribute("UFOHeightLevel") or 0
		--	isRequirementMet = currentUFOLevel >= value

		--	if icon then
		--		icon.Image = uiConfig.image
		--	end

		--	if valueLabel then
		--		valueLabel.Text = tostring(value)
		--	end

		elseif key == "island_name" then
			local currentUFOLevel = player:GetAttribute("UFOHeightLevel") or 0
			local neededUFOLevel = req.ufo_height_level_required or 0
			isRequirementMet = currentUFOLevel >= neededUFOLevel

			if icon then
				icon.Image = req.island_image or uiConfig.image or ""
			end

			if valueLabel then
				valueLabel.Text = tostring(value)
			end

		else
			if icon then
				icon.Image = uiConfig.image
			end

			if valueLabel then
				valueLabel.Text = tostring(value)
			end
		end

		if valueLabel then
			if isRequirementMet then
				valueLabel.TextColor3 = Color3.new(0, 1, 0)
			else
				valueLabel.TextColor3 = Color3.new(1, 0, 0)
			end
		end
	end
end

--------------------------------------------------
-- REWARDS UI
--------------------------------------------------

local function updateRewardsDisplay(nextPrestigeLevel)

	local rewards = PrestigeService:GetPrestigeRewards(nextPrestigeLevel)
	if not rewards then return end

	clearRewards()


	for key, value in pairs(rewards) do

		local uiConfig = RewardUIConfig[key]
		if not uiConfig then
			warn("No reward UI config for:", key)
			continue
		end

		local clone = uiConfig.template:Clone()
		clone.Visible = true
		clone.Parent = YouRewardContent

		local icon = clone:FindFirstChild("ImageLabel")
		local nameLabel = clone:FindFirstChild("NameLabel")
		local valueLabel = clone:FindFirstChild("ValueLabel")

		if key == "island_unlock" then
			-- value = {name = "", image = ""}

			if icon then
				icon.Image = value.image
			end

			if nameLabel then
				nameLabel.Text = "Unlock"
			end

			if valueLabel then
				valueLabel.Text = value.name
			end

		else
			if icon then
				icon.Image = uiConfig.img
			end

			if nameLabel then
				nameLabel.Text = uiConfig.name
			end

			if valueLabel then
				valueLabel.Text = "+" .. formatNumber(value)
			end

			if key == "money" then
				valueLabel.Text = "+ " .. formatNumber(value) .. "%"
			end
		end

	end
end

local function loadPrestigeFromServer()
	
	--local result
	--local success = pcall(function()
	--	result = PrestigeRequest:InvokeServer()
	--end)

	--local success, result = pcall(function()
	--	return GetPrestigeData:InvokeServer()
	--end)
	
	--print('Тест престижа ', success, result, result.prestige)

	--if not success or not result then
	--	warn("Failed to get prestige data")
	--	return 0
	--end 

	return player:GetAttribute('PrestigeModifier') or 0
end

local function prestigeData()
	
	local success2, result2 = pcall(function()
		return GetPrestigeData:InvokeServer()
	end)

	
	return player:GetAttribute('PrestigeModifier') or 0

end

local function getProductPrice(productId)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
	end)

	if not ok or not info then
		warn("[getProductPrice] Failed to get info for product:", productId, info)
		return nil
	end

	local price = info.PriceInRobux
	return price
end

local function setRobuxPrice(button, productId)
	local price = getProductPrice(productId)
	if price then
		button.Text = "\u{E002}" .. tostring(price)
	else
		button.Text = "\u{E002}?"
	end
end

--------------------------------------------------
-- SETUP
--------------------------------------------------

local function setupPrestigeUI()

	currentPrestige = loadPrestigeFromServer()

	updateRewardsDisplay(currentPrestige + 1)
	updateRequirementsDisplay(currentPrestige)
	
	
	setRobuxPrice(robuxRebirth.Price, MonetizationConfig.products.rebirth.product_id)
end

--------------------------------------------------
-- BUTTON
--------------------------------------------------

button.MouseButton1Click:Connect(function()

	if debounce then return end
	debounce = true


	local result
	local success = pcall(function()
		result = PrestigeRequest:InvokeServer()
	end)


	if not success or not result then

		statusLabel.Text = "❌ Server error"
		debounce = false
		return
	end


	if not result.success then



		--if result.reason == "NOT_ENOUGH_SOFT" then
		--	statusLabel.Text = "❌ Not enough money"

		--elseif result.reason == "NOT_ENOUGH_CAPACITY" then
		--	statusLabel.Text = "❌ Increase capacity"

		--elseif result.reason == "NOT_ENOUGH_DAMAGE" then
		--	statusLabel.Text = "❌ Upgrade weapons"

		--elseif result.reason == "MAX_PRESTIGE" then
		--	statusLabel.Text = "🏆 Max prestige"

		--else
		--	statusLabel.Text = "❌ Requirements not met"
		--end

	else

		-- Sound
		ReplicatedStorage.Assets.Sounds.Rebirth1:Play()


		statusLabel.Text =
			"🔥 Prestige UP! Level: " .. result.new_prestige


		-- Effect
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root then

			local effect = ReplicatedStorage.Assets.Effects.Rebirth:Clone()
			effect.Parent = root


			if effect.PrimaryPart then

				effect:PivotTo(root.CFrame)

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = effect.PrimaryPart
				weld.Part1 = root
				weld.Parent = effect
			end


			task.delay(3, function()
				effect:Destroy()
			end)
		end
	end


	if result.success then

		updateRewardsDisplay(result.new_prestige + 1)
		updateRequirementsDisplay(result.new_prestige)
	end
	
	setupPrestigeUI()
	setupButtonEffects(button)
	setupButtonEffects(robuxRebirth)
	prestigeData()

	task.wait(1)
	
	setupPrestigeUI()
	setupButtonEffects(button)
	setupButtonEffects(robuxRebirth)
	prestigeData()
	
	debounce = false
	statusLabel.Text = "Rebirth!"
end)


robuxRebirth.Activated:Connect(function()
	Remotes.Purchase:FireServer('rebirth')
end)

local debounce = false

script.Parent:GetPropertyChangedSignal("Visible"):Connect(function()
	if script.Parent.Visible and debounce == false then
		debounce = true
		ReplicatedStorage.Remotes.TutorialStepProceed:FireServer('PrestigeOpened')
		
		setupPrestigeUI()
		setupButtonEffects(button)
		setupButtonEffects(robuxRebirth)
		prestigeData()
		task.delay(1, function()
			debounce = false
		end)

	end
end)

--------------------------------------------------
-- START
--------------------------------------------------

setupPrestigeUI()
setupButtonEffects(button)
setupButtonEffects(robuxRebirth)

task.delay(15, function()
	prestigeData()
end)

game.ReplicatedStorage.Remotes.RebirthRobuxSuccess.OnClientEvent:Connect(function()
	
	local result
	local success = pcall(function()
		result = PrestigeRequest:InvokeServer(true)
	end)


	if not success or not result then

		statusLabel.Text = "❌ Server error"
		debounce = false
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if root then

		local effect = ReplicatedStorage.Assets.Effects.Rebirth:Clone()
		effect.Parent = root


		if effect.PrimaryPart then

			effect:PivotTo(root.CFrame)

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = effect.PrimaryPart
			weld.Part1 = root
			weld.Parent = effect
		end


		task.delay(3, function()
			effect:Destroy()
		end)
	end
	
	prestigeData()
	
	setupPrestigeUI()
	setupButtonEffects(button)
	setupButtonEffects(robuxRebirth)

	task.wait(1)

	debounce = false
	statusLabel.Text = "Rebirth!"

end)