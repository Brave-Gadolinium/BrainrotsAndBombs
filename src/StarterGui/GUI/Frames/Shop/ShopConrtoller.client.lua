local Players = game:GetService('Players')
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local MarketplaceService = game:GetService('MarketplaceService')

local Config = require(ReplicatedStorage.Configs.Config)
local MonetizationConfig = require(ReplicatedStorage.Configs.MonetizationConfig)

local Remotes = ReplicatedStorage:WaitForChild('Remotes')
local player = Players.LocalPlayer

local ShopFrame = script.Parent
local MainFrame = ShopFrame:WaitForChild('MainFrame')
local Content = MainFrame:WaitForChild("Content")

local HL_HackerLuckyblockFrame = Content:WaitForChild('HackerLuckyBlock')
local HL_HackerButtons = HL_HackerLuckyblockFrame:WaitForChild('Content'):WaitForChild('Buttons')
local HL_HackerButton1 = HL_HackerButtons:WaitForChild('Buy_1')
local HL_HackerButton2 = HL_HackerButtons:WaitForChild('Buy_2')
local HL_HackerButton10 = HL_HackerButtons:WaitForChild('Buy_10')
local HL_ChancesFrame = HL_HackerLuckyblockFrame:WaitForChild('Content'):WaitForChild('Chances')


local SP_StarterPackFrame = Content:WaitForChild('StarterPack')
local SP_Buttons = SP_StarterPackFrame:WaitForChild('Content'):WaitForChild('Buttons')
local SP_BuyButton = SP_Buttons:WaitForChild('Buy')

local MP_Content = Content:WaitForChild('Moneys'):WaitForChild('Content')
local MP_TinyPackFrame = MP_Content:WaitForChild('Tiny Pack')
local MP_MegaPackFrame = MP_Content:WaitForChild('Mega  Pack')
local MP_UltimatePackFrame = MP_Content:WaitForChild('Ultimate Pack')

local MP_TinyPackButton = MP_TinyPackFrame:WaitForChild('Button'):WaitForChild('Buy')
local MP_MegaPackButton = MP_MegaPackFrame:WaitForChild('Button'):WaitForChild('Buy')
local MP_UltimatePackButton = MP_UltimatePackFrame:WaitForChild('Button'):WaitForChild('Buy')

local Offer2 = Content:WaitForChild('Offer2')
local CS_BuyButton = Offer2:WaitForChild('Content'):WaitForChild('CastleSkin'):WaitForChild('Button'):WaitForChild('Buy')
local MC_BuyButton = Offer2:WaitForChild('Content'):WaitForChild('Carpet'):WaitForChild('Button'):WaitForChild('Buy')

local Offer1 = Content:WaitForChild('Offer1')
local Skins_Chest1 = Offer1:WaitForChild("Content"):WaitForChild('Chest1')
local Skins_Chest2 = Offer1:WaitForChild("Content"):WaitForChild('Chest2')


local ChestOfferMap = {
	{
		container = Skins_Chest1,
		chestId = "chest_1",
		productKey = "ufo_chest_1",
	},
	{
		container = Skins_Chest2,
		chestId = "chest_2",
		productKey = "ufo_chest_2",
	},
}

local productPriceCache = {}

local activeChestOffers = {}
local chestSkinConnections = {}

local initialized = false

local hoverSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("UIHoverSound")
local clickSound = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("UIClickSound")

local function setupButtonEffects(button, isParent)
	if isParent then
		local defaultSize = button.Parent.Size
		local hoverSize = defaultSize + UDim2.fromScale(0.03, 0.03)
		local clickSize = defaultSize - UDim2.fromScale(0.02, 0.02)

		local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		local function tweenTo(size)
			TweenService:Create(button.Parent, tweenInfo, {Size = size}):Play()
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
	else
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
end

local function getProductPrice(productId)
	if productPriceCache[productId] ~= nil then
		return productPriceCache[productId]
	end

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
	end)

	if not ok or not info then
		warn("[getProductPrice] Failed to get info for product:", productId, info)
		return nil
	end

	local price = info.PriceInRobux
	productPriceCache[productId] = price
	return price
end

local function setRobuxPrice(label, productId)
	local price = getProductPrice(productId)
	if price then
		label.Text = "\u{E002}" .. tostring(price)
	else
		label.Text = "\u{E002}?"
	end
end

local function hasUFOSkin(skinId)
	local folder = player:FindFirstChild("UFOSkins")
	if not folder then
		return false
	end

	local skinValue = folder:FindFirstChild(skinId)
	if not skinValue or not skinValue:IsA("BoolValue") then
		return false
	end

	return skinValue.Value == true
end

local function refreshChestOffer(container, chestId)
	local chestConfig = Config.ufo_skins.chests[chestId]
	if not chestConfig then
		warn("[refreshChestOffer] chest config not found:", chestId)
		return
	end

	local listFrame = container:FindFirstChild("List")
	if not listFrame then
		return
	end

	local skinImages = listFrame:GetChildren()

	for _, image in ipairs(skinImages) do
		if image:IsA("ImageLabel") then
			image.Visible = false
			image.Image = ""
		end
	end

	local visibleIndex = 1

	for _, skinEntry in ipairs(chestConfig.skins) do
		local skinId = skinEntry.id
		local skinConfig = Config.ufo_skins.skins[skinId]

		if not skinConfig then
			warn("[refreshChestOffer] skin config not found:", skinId)
			continue
		end

		if not hasUFOSkin(skinId) then
			local skinImage = listFrame:FindFirstChild("Image" .. visibleIndex)
				or listFrame:FindFirstChild(tostring(visibleIndex))
				or skinImages[visibleIndex]

			if skinImage and skinImage:IsA("ImageLabel") then
				skinImage.Visible = true
				skinImage.Image = skinConfig.img or ""
			end

			visibleIndex += 1
		end
	end

	container.Visible = visibleIndex > 1
end

local function initStarterButtons()
	setRobuxPrice(SP_BuyButton.Price, MonetizationConfig.products.starter_pack.product_id)
	
	setupButtonEffects(SP_BuyButton, false)
	
	SP_BuyButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('starter_pack')
	end)
end

local function initChestOffer(container, chestId, productKey)
	local chestConfig = Config.ufo_skins.chests[chestId]
	if not chestConfig then
		warn("[initChestOffer] chest config not found:", chestId)
		return
	end

	local productConfig = MonetizationConfig.products[productKey]
	if not productConfig then
		warn("[initChestOffer] product config not found:", productKey)
		return
	end

	local nameFrame = container:FindFirstChild("Name")
	local iconFrame = container:FindFirstChild("Icon")
	local buttonHolder = container:FindFirstChild("Button")
	local buyButton = buttonHolder and buttonHolder:FindFirstChild("Buy")

	if nameFrame and nameFrame:FindFirstChild("TextLabel") then
		nameFrame.TextLabel.Text = chestConfig.name or chestId
	end

	if iconFrame and iconFrame:FindFirstChild("ImageLabel") then
		iconFrame.ImageLabel.Image = chestConfig.img or ""
	end

	activeChestOffers[chestId] = {
		container = container,
		chestId = chestId,
		productKey = productKey,
	}

	refreshChestOffer(container, chestId)

	if buyButton then
		setRobuxPrice(buyButton.Price, productConfig.product_id)
		setupButtonEffects(buyButton, true)

		buyButton.Activated:Connect(function()
			Remotes.Purchase:FireServer(productKey)
		end)
	end
end

local function refreshAllChestOffers()
	for chestId, offerData in pairs(activeChestOffers) do
		refreshChestOffer(offerData.container, chestId)
	end
end

local function clearChestSkinConnections()
	for _, connection in ipairs(chestSkinConnections) do
		connection:Disconnect()
	end
	table.clear(chestSkinConnections)
end

local function bindUFOSkinsFolder()
	local folder = player:FindFirstChild("UFOSkins")
	if not folder then
		return
	end

	clearChestSkinConnections()

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BoolValue") then
			table.insert(chestSkinConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
				refreshAllChestOffers()

				if child.Name == "castle_ufo" and child.Value == true then
					Offer2.Content.CastleSkin.Visible = false
				end
			end))
		end
	end

	table.insert(chestSkinConnections, folder.ChildAdded:Connect(function(child)
		if child:IsA("BoolValue") then
			table.insert(chestSkinConnections, child:GetPropertyChangedSignal("Value"):Connect(function()
				refreshAllChestOffers()

				if child.Name == "castle_ufo" and child.Value == true then
					Offer2.Content.CastleSkin.Visible = false
				end
			end))
		end

		refreshAllChestOffers()

		if child.Name == "castle_ufo" and child:IsA("BoolValue") and child.Value == true then
			Offer2.Content.CastleSkin.Visible = false
		end
	end))

	table.insert(chestSkinConnections, folder.ChildRemoved:Connect(function()
		refreshAllChestOffers()
	end))
end

local function initHackerButtons()
	setRobuxPrice(HL_HackerButton1.Price, MonetizationConfig.products.hacker_luckyblock_1.product_id)
	setRobuxPrice(HL_HackerButton2.Price, MonetizationConfig.products.hacker_luckyblock_2.product_id)
	setRobuxPrice(HL_HackerButton10.Price, MonetizationConfig.products.hacker_luckyblock_10.product_id)

	HL_HackerButton2.Discount.Text = "\u{E002}" .. tostring(productPriceCache[MonetizationConfig.products.hacker_luckyblock_1.product_id] * 2)
	HL_HackerButton10.Discount.Text = "\u{E002}" .. tostring(productPriceCache[MonetizationConfig.products.hacker_luckyblock_1.product_id] * 10)

	setupButtonEffects(HL_HackerButton1, false)
	setupButtonEffects(HL_HackerButton2, false)
	setupButtonEffects(HL_HackerButton10, false)
	
	-- TODO Серверно выдавать
	HL_HackerButton1.Activated:Connect(function()
		Remotes.Purchase:FireServer('hacker_luckyblock_1')
	end)
	
	HL_HackerButton2.Activated:Connect(function()
		Remotes.Purchase:FireServer('hacker_luckyblock_2')
	end)
	
	HL_HackerButton10.Activated:Connect(function()
		Remotes.Purchase:FireServer('hacker_luckyblock_10')
	end)
end

local function initHackerChances()
	local luckyBlockConfig = Config.lucky_blocks.luckyblock_hacker
	if not luckyBlockConfig then
		warn("[initHackerChances] luckyblock_hacker config not found")
		return
	end
	
	local bossesList = luckyBlockConfig.bosses
	if not bossesList or #bossesList == 0 then
		warn("[initHackerChances] brainrots list is empty")
		return
	end

	local totalWeight = 0
	for _, bossData in ipairs(bossesList) do
		totalWeight += bossData.weight or 0
	end
	
	if totalWeight <= 0 then
		warn("[initHackerChances] totalWeight <= 0")
		return
	end
	
	for index, bossData in ipairs(bossesList) do
		local chanceFrame = HL_ChancesFrame:FindFirstChild("Chance" .. index)
		if not chanceFrame then
			warn("[initHackerChances] Frame not found:", "Chance" .. index)
			continue
		end
		
		local chanceLabel = chanceFrame:FindFirstChild("Chance")
		local iconLabel = chanceFrame:FindFirstChild("Icon")

		if not chanceLabel or not iconLabel then
			warn("[initHackerChances] Chance or Icon missing in", chanceFrame.Name)
			continue
		end
		
		local bossId = bossData.bosses_id
		local bossConfig = Config.bosses[bossId]

		if not bossConfig then
			warn("[initHackerChances] boss config not found:", bossId)
			continue
		end

		local weight = bossData.weight or 0
		local chancePercent = (weight / totalWeight) * 100

		if bossConfig.img then
			iconLabel.Image = bossConfig.img
		else
			warn("[initHackerChances] boss img missing:", bossId)
			iconLabel.Image = ""
		end

		chanceLabel.Text = string.format("%.1f%%", chancePercent)
	end
end

local function initChestsOffers()
	for _, offerData in ipairs(ChestOfferMap) do
		initChestOffer(offerData.container, offerData.chestId, offerData.productKey)
	end
end

local function initMoneyPackButtons()
	setRobuxPrice(MP_TinyPackButton.Price, MonetizationConfig.products.tiny_money_pack.product_id)
	setRobuxPrice(MP_MegaPackButton.Price, MonetizationConfig.products.mega_money_pack.product_id)
	setRobuxPrice(MP_UltimatePackButton.Price, MonetizationConfig.products.ultimate_money_pack.product_id)
	
	setupButtonEffects(MP_TinyPackButton, true)
	setupButtonEffects(MP_MegaPackButton, true)
	setupButtonEffects(MP_UltimatePackButton, true)
	
	MP_TinyPackButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('tiny_money_pack')
	end)
	
	MP_MegaPackButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('mega_money_pack')
	end)
	
	MP_UltimatePackButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('ultimate_money_pack')
	end)
end

local function initMagicCarpetButton()
	setRobuxPrice(MC_BuyButton.Price, MonetizationConfig.products.magic_carpet.product_id)

	setupButtonEffects(MC_BuyButton, true)

	MC_BuyButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('magic_carpet')
	end)
end

local function initCastleSkinButton()
	setRobuxPrice(CS_BuyButton.Price, MonetizationConfig.products.castle_ufo_skin.product_id)

	setupButtonEffects(CS_BuyButton, true)

	CS_BuyButton.Activated:Connect(function()
		Remotes.Purchase:FireServer('castle_ufo_skin')
	end)
end

local function init()
	if initialized then
		refreshAllChestOffers()
		return
	end
	initialized = true

	initHackerButtons()
	initHackerChances()
	initStarterButtons()
	initMoneyPackButtons()
	initMagicCarpetButton()
	initCastleSkinButton()
	initChestsOffers()

	bindUFOSkinsFolder()
	refreshAllChestOffers()

	if player:GetAttribute('StarterPack') then
		SP_StarterPackFrame.Visible = false
	end

	player:GetAttributeChangedSignal('StarterPack'):Connect(function()
		if player:GetAttribute('StarterPack') then
			SP_StarterPackFrame.Visible = false
		end
	end)

	if player:GetAttribute('MagicCarpet') then
		Offer2.Content.Carpet.Visible = false
	end

	player:GetAttributeChangedSignal('MagicCarpet'):Connect(function()
		if player:GetAttribute('MagicCarpet') then
			Offer2.Content.Carpet.Visible = false
		end
	end)

	local folder = player:FindFirstChild("UFOSkins")
	if folder and folder:FindFirstChild("castle_ufo") and folder.castle_ufo.Value == true then
		Offer2.Content.CastleSkin.Visible = false
	end
end

Remotes.InitUpgradesUI.OnClientEvent:Connect(function()
	init()
end)
