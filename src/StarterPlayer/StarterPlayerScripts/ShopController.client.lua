--!strict
-- LOCATION: StarterPlayerScripts/ShopController

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [ MODULES ]
local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))
local ItemConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemConfigurations"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local Constants = require(ReplicatedStorage.Modules.Constants)

-- [ UI REFERENCES ]
local gui = playerGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local shopFrame = frames:WaitForChild("Shop")
local scrolling = shopFrame:WaitForChild("Scrolling")

-- [ CONFIGURATION ]
local INCOME_SCALING = Constants.INCOME_SCALING
local MUTATION_MULTIPLIERS = Constants.MUTATION_MULTIPLIERS

-- [ HELPER ]
local function findTextLabel(parent: Instance): TextLabel?
	local label = parent:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then return label end
	return parent:FindFirstChildWhichIsA("TextLabel", true)
end

-- [[ ADDED: CALCULATE INCOME ]] --
local function getIncomeText(itemName: string, mutation: string, level: number): string
	local itemData = ItemConfigurations.GetItemData(itemName)
	if not itemData then return "+$0/s" end

	local baseIncome = itemData.Income
	local mutMult = MUTATION_MULTIPLIERS[mutation] or 1

	-- Calculate total income (Base * Mutation * LevelScaling)
	-- Note: Shop items are usually Level 1, but we calculate just in case.
	local totalIncome = baseIncome * mutMult * (INCOME_SCALING ^ (level - 1))

	return "+$" .. NumberFormatter.Format(totalIncome) .. "/s"
end

-- [ LOGIC: PACKS (GamePasses) ]
local function setupPackUI(packName: string, containerName: string)
	local packFrame = scrolling:WaitForChild(containerName, 5)
	if not packFrame then return end

	local passId = ProductConfigurations.GamePasses[packName]
	local rewards = ProductConfigurations.PackRewards[packName]
	if not passId or not rewards then return end

	local buyButton = packFrame:WaitForChild("Buy", 5) :: GuiButton
	if buyButton then
		buyButton.MouseButton1Click:Connect(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		task.spawn(function()
			local priceText = findTextLabel(buyButton)
			if priceText then
				local success, info = pcall(function() return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass) end)
				priceText.Text = if success and info then "" .. tostring(info.PriceInRobux) else "N/A"
			end
		end)
	end

	local reciveFrame = packFrame:WaitForChild("Recive", 5)
	if reciveFrame then
		for i, itemData in ipairs(rewards.Items) do
			local itemFrame = reciveFrame:FindFirstChild("Item" .. i)
			if itemFrame then
				local imgLabel = itemFrame:FindFirstChild("Image") :: ImageLabel
				local nameLabel = findTextLabel(itemFrame)

				-- [[ ADDED: INCOME LABEL ]] --
				local incomeLabel = itemFrame:FindFirstChild("Income") :: TextLabel
				if incomeLabel then
					incomeLabel.Text = getIncomeText(itemData.Name, itemData.Mutation, itemData.Level or 1)
				end

				if imgLabel then
					local gItem = ItemConfigurations.GetItemData(itemData.Name)
					if gItem then imgLabel.Image = gItem.ImageId end
				end
				if nameLabel then nameLabel.Text = itemData.Name end
			end
		end
		local cashFrame = reciveFrame:FindFirstChild("Cash1")
		if cashFrame then
			local cashLabel = findTextLabel(cashFrame)
			if cashLabel then cashLabel.Text = "$" .. NumberFormatter.Format(rewards.Money) end
		end
	end
end

-- [ LOGIC: ITEMS ONLY (Dev Products) ]
local function setupItemsOnlyUI()
	local container = scrolling:WaitForChild("ItemsOnly", 5)
	if not container then warn("ItemsOnly frame missing") return end

	local recive = container:WaitForChild("Recive", 5)
	if not recive then warn("ItemsOnly.Recive missing") return end

	for i = 1, 3 do
		local productKey = "ItemProduct" .. i
		local productId = ProductConfigurations.Products[productKey]
		local rewardData = ProductConfigurations.ItemProductRewards[productKey]

		local itemFrame = recive:WaitForChild("Item" .. i, 5)

		if itemFrame and productId and rewardData then
			-- Name & Image
			local imgLabel = itemFrame:FindFirstChild("Image") :: ImageLabel
			local nameLabel = itemFrame:FindFirstChild("Name") :: TextLabel

			-- [[ ADDED: INCOME LABEL ]] --
			local incomeLabel = itemFrame:FindFirstChild("Income") :: TextLabel
			if incomeLabel then
				incomeLabel.Text = getIncomeText(rewardData.Name, rewardData.Mutation, rewardData.Level or 1)
			end

			if nameLabel then nameLabel.Text = rewardData.Name end
			if imgLabel then
				local gItem = ItemConfigurations.GetItemData(rewardData.Name)
				if gItem then imgLabel.Image = gItem.ImageId end
			end

			-- Buy Button
			local buyButton = itemFrame:WaitForChild("Buy") :: GuiButton
			if buyButton then
				buyButton.MouseButton1Click:Connect(function()
					MarketplaceService:PromptProductPurchase(player, productId)
				end)
				task.spawn(function()
					local priceText = findTextLabel(buyButton)
					if priceText then
						local success, info = pcall(function()
							return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
						end)
						priceText.Text = if success and info then "" .. tostring(info.PriceInRobux) else "N/A"
					end
				end)
			end
		end
	end
end

-- [ LOGIC: CASH ONLY (Dev Products) ]
local function setupCashOnlyUI()
	local container = scrolling:WaitForChild("CashOnly", 5)
	if not container then warn("CashOnly frame missing") return end

	local recive = container:WaitForChild("Recive", 5)
	if not recive then warn("CashOnly.Recive missing") return end

	for i = 1, 3 do
		local productKey = "CashProduct" .. i
		local productId = ProductConfigurations.Products[productKey]
		local cashAmount = ProductConfigurations.CashProductRewards[productKey]

		local cashFrame = recive:WaitForChild("Cash" .. i, 5)

		if cashFrame and productId and cashAmount then
			local amountLabel = findTextLabel(cashFrame)
			if amountLabel then
				amountLabel.Text = "$" .. NumberFormatter.Format(cashAmount)
			end

			local buyButton = cashFrame:WaitForChild("Buy") :: GuiButton
			if buyButton then
				buyButton.MouseButton1Click:Connect(function()
					MarketplaceService:PromptProductPurchase(player, productId)
				end)

				task.spawn(function()
					local priceText = findTextLabel(buyButton)
					if priceText then
						local success, info = pcall(function()
							return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
						end)
						priceText.Text = if success and info then "" .. tostring(info.PriceInRobux) else "N/A"
					end
				end)
			end
		end
	end
end

-- [ INIT ]
task.spawn(function() setupPackUI("StarterPack", "StarterPack") end)
task.spawn(function() setupPackUI("ProPack", "ProPack") end)
task.spawn(setupItemsOnlyUI)
task.spawn(setupCashOnlyUI)

print("[ShopController] Loaded")