--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local wheelFrame = frames:WaitForChild("CandyWheel", 20) :: GuiObject?
local worldCandyWheel = Workspace:WaitForChild("CandyWheel", 20)
local candyEventRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CandyEvent")
local spinRemote = candyEventRemotes:WaitForChild("Spin") :: RemoteFunction

if not wheelFrame then
	warn("[CandySpinController] GUI.Frames.CandyWheel was not found.")
	return
end

local isSpinning = false
local isSpinRequestPending = false
local spinWheel: GuiObject? = nil
local pattern: Instance? = nil
local buttonsContainer: Instance? = nil
local redArrow: ImageLabel? = nil
local spinButton: GuiButton? = nil
local spinButtonText: TextLabel? = nil
local robuxButton1: GuiButton? = nil
local robuxButton2: GuiButton? = nil
local candyCountLabel: TextLabel? = nil

local function findDescendantByPredicate(root: Instance?, predicate: (Instance) -> boolean): Instance?
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if predicate(descendant) then
			return descendant
		end
	end

	return nil
end

local function findTextLabelByName(root: Instance?, names: {string}): TextLabel?
	local wanted = {}
	for _, name in ipairs(names) do
		wanted[string.lower(name)] = true
	end

	return findDescendantByPredicate(root, function(instance)
		return instance:IsA("TextLabel") and wanted[string.lower(instance.Name)] == true
	end) :: TextLabel?
end

local function findTextLabelByText(root: Instance?, expectedText: string): TextLabel?
	local upperExpectedText = string.upper(expectedText)
	return findDescendantByPredicate(root, function(instance)
		return instance:IsA("TextLabel") and string.find(string.upper(instance.Text), upperExpectedText, 1, true) ~= nil
	end) :: TextLabel?
end

local function findPrimaryTextLabel(root: Instance?): TextLabel?
	return findDescendantByPredicate(root, function(instance)
		if not instance:IsA("TextLabel") then
			return false
		end

		local lowerName = string.lower(instance.Name)
		return lowerName == "text" or lowerName == "label" or lowerName == "title"
	end) :: TextLabel?
end

local function resolveGui()
	spinWheel = findDescendantByPredicate(wheelFrame, function(instance)
		return instance:IsA("GuiObject") and instance.Name == "SpinWheel"
	end) :: GuiObject?
	pattern = findDescendantByPredicate(spinWheel, function(instance)
		return instance.Name == "Pattern"
	end)
	buttonsContainer = findDescendantByPredicate(wheelFrame, function(instance)
		return instance.Name == "Buttons"
	end)
	redArrow = findDescendantByPredicate(wheelFrame, function(instance)
		return instance:IsA("ImageLabel") and instance.Name == "RedArrow"
	end) :: ImageLabel?
	spinButton = findDescendantByPredicate(buttonsContainer, function(instance)
		return instance:IsA("GuiButton") and instance.Name == "SpinButton"
	end) :: GuiButton?
	spinButtonText = findTextLabelByName(spinButton, {"Text"}) or findPrimaryTextLabel(spinButton)
	robuxButton1 = findDescendantByPredicate(buttonsContainer, function(instance)
		return instance:IsA("GuiButton") and instance.Name == "RobuxButton1"
	end) :: GuiButton?
	robuxButton2 = findDescendantByPredicate(buttonsContainer, function(instance)
		return instance:IsA("GuiButton") and instance.Name == "RobuxButton2"
	end) :: GuiButton?
	candyCountLabel = findTextLabelByName(wheelFrame, {"CandyCount", "Candies"}) or findTextLabelByText(wheelFrame, "CANDIES")
end

local function getButtonLabel(root: Instance?): TextLabel?
	return findTextLabelByName(root, {"Text", "Title", "Label", "Amount"}) or findPrimaryTextLabel(root)
end

local function getButtonPriceLabel(root: Instance?): TextLabel?
	return findTextLabelByName(root, {"Price", "Robux", "Cost"})
end

local function playSound(soundName: string)
	local sounds = Workspace:FindFirstChild("Sounds")
	local sound = sounds and sounds:FindFirstChild(soundName)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function updateCandyCountText()
	if candyCountLabel then
		candyCountLabel.Text = CandyEventConfiguration.Text.CandyCountPrefix .. tostring(math.max(0, tonumber(player:GetAttribute("CandyCount")) or 0))
	end
end

local function updateSpinButtonText()
	if not spinButtonText or isSpinning or isSpinRequestPending then
		return
	end

	local candyCount = math.max(0, tonumber(player:GetAttribute("CandyCount")) or 0)
	local paidSpinCount = math.max(0, tonumber(player:GetAttribute("CandyPaidSpinCount")) or 0)

	if candyCount >= CandyEventConfiguration.SpinCost then
		spinButtonText.Text = CandyEventConfiguration.GetSpinButtonText()
	elseif paidSpinCount > 0 then
		spinButtonText.Text = CandyEventConfiguration.Text.PaidSpinButton
	else
		spinButtonText.Text = CandyEventConfiguration.Text.NotEnoughCandies
	end
end

local function setSlotText(slot: Instance, text: string)
	if slot:IsA("TextLabel") or slot:IsA("TextButton") then
		slot.Text = text
		return
	end

	local label = findPrimaryTextLabel(slot)
	if label then
		label.Text = text
	end
end

local function populateSlots()
	if not pattern then
		return
	end

	for index, reward in ipairs(CandyEventConfiguration.Rewards) do
		local slot = pattern:FindFirstChild(tostring(index))
		if slot then
			local image = findDescendantByPredicate(slot, function(instance)
				return instance:IsA("ImageLabel") and instance.Name == "Image"
			end) :: ImageLabel?
			if image then
				image.Image = reward.Image or ""
			end

			local chanceLabel = findTextLabelByName(slot, {"Chance"})
			if chanceLabel then
				chanceLabel.Text = string.format("(%.1f%%)", reward.DisplayChance)
			end

			setSlotText(slot, reward.DisplayName)
		end
	end
end

local function updateProductLabel(button: GuiButton?, labelText: string, productKey: string)
	if not button then
		return
	end

	local textLabel = getButtonLabel(button)
	local priceLabel = getButtonPriceLabel(button)
	local productId = ProductConfigurations.Products[productKey]

	if textLabel then
		textLabel.Text = labelText
	end

	if type(productId) ~= "number" or productId <= 0 then
		return
	end

	task.spawn(function()
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)

		if success and productInfo and priceLabel then
			priceLabel.Text = tostring(productInfo.PriceInRobux or "")
		end
	end)
end

local function animateSpin(targetIndex: number)
	isSpinning = true
	updateSpinButtonText()
	playSound("Spin")

	local finished = false

	if spinWheel and spinWheel:IsA("GuiObject") then
		spinWheel.Rotation = 0

		local degreesPerSlot = 360 / math.max(1, #CandyEventConfiguration.Rewards)
		local fullSpins = 5
		local finalAngle = (360 * fullSpins) + ((targetIndex - 1) * degreesPerSlot)
		local lastTickAngle = 0
		local rotationTracker = Instance.new("NumberValue")
		rotationTracker.Value = 0

		local rotationConnection = rotationTracker.Changed:Connect(function(value)
			if spinWheel and spinWheel.Parent then
				spinWheel.Rotation = value
			end

			if value - lastTickAngle >= degreesPerSlot then
				lastTickAngle = value
				playSound("Tick")
				if redArrow then
					redArrow.Rotation = -15
					TweenService:Create(redArrow, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
				end
			end
		end)

		local tween = TweenService:Create(rotationTracker, TweenInfo.new(CandyEventConfiguration.SpinAnimationSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Value = finalAngle,
		})

		tween:Play()
		tween.Completed:Once(function()
			rotationConnection:Disconnect()
			rotationTracker:Destroy()
			playSound("Reward")
			finished = true
			isSpinning = false
			updateSpinButtonText()
			updateCandyCountText()
		end)
	end

	if not finished then
		task.delay(CandyEventConfiguration.SpinAnimationSeconds + 0.1, function()
			if isSpinning then
				isSpinning = false
				updateSpinButtonText()
				updateCandyCountText()
			end
		end)
	end
end

local function promptCandySpinProduct(productKey: string)
	local productId = ProductConfigurations.Products[productKey]
	if type(productId) ~= "number" or productId <= 0 then
		NotificationManager.show("Candy spin product is not configured.", "Error")
		return
	end

	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)

	if not success then
		warn("[CandySpinController] Failed to prompt product:", productKey, errorMessage)
		NotificationManager.show("Purchase prompt is unavailable right now.", "Error")
	end
end

local function getBoundsData(instance: Instance?): (CFrame?, Vector3?)
	if not instance then
		return nil, nil
	end

	local preferredBounds = findDescendantByPredicate(instance, function(descendant)
		if not descendant:IsA("BasePart") then
			return false
		end

		local lowerName = string.lower(descendant.Name)
		return lowerName == "bounds" or lowerName == "hitbox" or lowerName == "trigger"
	end)
	if preferredBounds and preferredBounds:IsA("BasePart") then
		return preferredBounds.CFrame, preferredBounds.Size
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart then
			return primaryPart.CFrame, primaryPart.Size
		end

		local cf, size = instance:GetBoundingBox()
		return cf, size
	end

	return nil, nil
end

local function isInsideCandyWheelBounds(rootPosition: Vector3): boolean
	local boundsCFrame, boundsSize = getBoundsData(worldCandyWheel)
	if not boundsCFrame or not boundsSize then
		return false
	end

	local localPosition = boundsCFrame:PointToObjectSpace(rootPosition)
	local padding = Vector3.new(4, 6, 4)
	local halfSize = (boundsSize + padding) * 0.5

	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local wasInsideBounds = false

local function updateWorldEntryState()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local isInside = isInsideCandyWheelBounds(rootPart.Position)
	if isInside and not wasInsideBounds then
		FrameManager.open("CandyWheel")
	elseif not isInside and wasInsideBounds and wheelFrame.Visible then
		FrameManager.close("CandyWheel")
	end

	wasInsideBounds = isInside
end

resolveGui()
populateSlots()
updateCandyCountText()
updateSpinButtonText()
updateProductLabel(robuxButton1, "+3 Spins!", CandyEventConfiguration.ProductKeys.SpinsX3)
updateProductLabel(robuxButton2, "+9 Spins!", CandyEventConfiguration.ProductKeys.SpinsX9)

if spinButton then
	spinButton.Activated:Connect(function()
		if isSpinning or isSpinRequestPending then
			return
		end

		isSpinRequestPending = true

		local success, response = pcall(function()
			return spinRemote:InvokeServer()
		end)

		if not success or type(response) ~= "table" then
			isSpinRequestPending = false
			NotificationManager.show("Spin is unavailable right now.", "Error")
			updateSpinButtonText()
			return
		end

		if response.Success ~= true then
			isSpinRequestPending = false
			NotificationManager.show(tostring(response.Message or CandyEventConfiguration.Text.NotEnoughCandies), "Error")
			updateSpinButtonText()
			updateCandyCountText()
			return
		end

		isSpinRequestPending = false
		animateSpin(math.max(1, math.floor(tonumber(response.Index) or 1)))
	end)
end

if robuxButton1 then
	robuxButton1.Activated:Connect(function()
		promptCandySpinProduct(CandyEventConfiguration.ProductKeys.SpinsX3)
	end)
end

if robuxButton2 then
	robuxButton2.Activated:Connect(function()
		promptCandySpinProduct(CandyEventConfiguration.ProductKeys.SpinsX9)
	end)
end

player:GetAttributeChangedSignal("CandyCount"):Connect(function()
	updateCandyCountText()
	updateSpinButtonText()
end)

player:GetAttributeChangedSignal("CandyPaidSpinCount"):Connect(updateSpinButtonText)

wheelFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if wheelFrame.Visible then
		updateCandyCountText()
		updateSpinButtonText()
	end
end)

task.spawn(function()
	while true do
		updateWorldEntryState()
		task.wait(0.2)
	end
end)
