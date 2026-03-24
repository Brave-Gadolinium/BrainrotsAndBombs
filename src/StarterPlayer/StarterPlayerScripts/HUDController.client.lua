--!strict
-- LOCATION: StarterPlayerScripts/HUDController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local SocialService = game:GetService("SocialService") 
local Workspace = game:GetService("Workspace")

-- [ MODULES ]
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local ItemConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemConfigurations"))
local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))
local NotificationManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NotificationManager")) 

local player = Players.LocalPlayer

-- Animation Config
local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Income Calculation Constants
local INCOME_SCALING = 1.125
local MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}

print("[HUDController] Loaded (Only Money in Leaderstats, Active Offline Income Calc)")

local function setupButtonAnimation(button: GuiButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale"); uiScale.Name = "AnimationScale"; uiScale.Parent = button
	end
	button.MouseEnter:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
	button.MouseLeave:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = 1}):Play() end)
	button.MouseButton1Down:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = CLICK_SCALE}):Play() end)
	button.MouseButton1Up:Connect(function() TweenService:Create(uiScale, TWEEN_INFO, {Scale = HOVER_SCALE}):Play() end)
end

local function setupHUD()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI")
	local hud = gui:WaitForChild("HUD")

	-- 1. TRACK MONEY AND OFFLINE INCOME
	local labels = hud:WaitForChild("Labels")
	local moneyLabel = labels:WaitForChild("Money") :: TextLabel
	local offlineLabel = labels:WaitForChild("Offline") :: TextLabel

	local leaderstats = player:WaitForChild("leaderstats")
	local moneyStat = leaderstats:WaitForChild("Money") :: NumberValue

	local function updateMoney()
		moneyLabel.Text = NumberFormatter.Format(moneyStat.Value)
	end
	moneyStat.Changed:Connect(updateMoney)
	updateMoney()

	-- Start loop to calculate Offline/Hour dynamically
	task.spawn(function()
		while true do
			local totalIncomePerSec = 0
			local plotName = "Plot_" .. player.Name
			local plot = Workspace:FindFirstChild(plotName)

			if plot then
				-- Read all spawned physical items to calculate true income
				for _, desc in ipairs(plot:GetDescendants()) do
					if desc:IsA("Model") and desc.Name == "VisualItem" then
						local name = desc:GetAttribute("OriginalName")
						local mut = desc:GetAttribute("Mutation") or "Normal"
						local lvl = desc:GetAttribute("Level") or 1

						local itemData = ItemConfigurations.GetItemData(name)
						if itemData then
							local base = itemData.Income or 0
							local mutMult = MUTATION_MULTIPLIERS[mut] or 1
							local lvlMult = INCOME_SCALING ^ (lvl - 1)
							totalIncomePerSec += (base * mutMult * lvlMult)
						end
					end
				end
			end

			-- Apply Global Multipliers
			local reb = player:GetAttribute("Rebirths") or 0
			local rebMult = 1 + (reb * 0.5)
			local isVip = player:GetAttribute("IsVIP") == true
			local vipMult = isVip and 1.5 or 1

			totalIncomePerSec = totalIncomePerSec * rebMult * vipMult
			local offlinePerHour = totalIncomePerSec * 3600

			if offlineLabel then
				offlineLabel.Text = "Offline/Hour: $" .. NumberFormatter.Format(offlinePerHour)
			end

			task.wait(2) -- Recalculate every 2 seconds to be highly efficient
		end
	end)

	-- 2. SETUP RANDOM ITEM BUTTON (GACHA)
	local rightPanel = hud:WaitForChild("Right")
	local randomBtn = rightPanel:WaitForChild("Random") :: TextButton
	local itemImage = randomBtn:WaitForChild("Image") :: ImageLabel
	local randomPriceLabel = randomBtn:WaitForChild("Price") :: TextLabel
	local randomTextLabel = randomBtn:FindFirstChild("Text") :: TextLabel 

	setupButtonAnimation(randomBtn)

	local validItems = {}
	for name, data in pairs(ItemConfigurations.Items) do
		if data.Rarity ~= "Common" and data.Rarity ~= "Uncommon" then table.insert(validItems, data) end
	end

	if #validItems > 0 then
		local totalValidItems = #validItems
		if not randomBtn:GetAttribute("CyclerRunning") then
			randomBtn:SetAttribute("CyclerRunning", true)
			task.spawn(function()
				while randomBtn.Parent do
					local selectedData = validItems[math.random(1, totalValidItems)]
					itemImage.Image = selectedData.ImageId
					if randomTextLabel then randomTextLabel.Text = string.format("Random (%.1f%%)", (1 / totalValidItems) * 100) end
					task.wait(1.5)
				end
			end)
		end
	end

	local randomProductId = ProductConfigurations.Products["RandomItem"]
	if randomProductId then
		task.spawn(function()
			local success, info = pcall(function() return MarketplaceService:GetProductInfo(randomProductId, Enum.InfoType.Product) end)
			if success and info and randomPriceLabel then randomPriceLabel.Text = "" .. tostring(info.PriceInRobux) else if randomPriceLabel then randomPriceLabel.Text = "N/A" end end
		end)
		randomBtn.MouseButton1Click:Connect(function() MarketplaceService:PromptProductPurchase(player, randomProductId) end)
	end

	-- 3. SETUP INVITE FRIENDS BUTTON
	local leftButtons2 = hud:WaitForChild("Left"):WaitForChild("Buttons2")
	local inviteBtn = leftButtons2:FindFirstChild("Invite") :: TextButton
	if inviteBtn then
		setupButtonAnimation(inviteBtn)
		inviteBtn.MouseButton1Click:Connect(function()
			local success, canInvite = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
			if success and canInvite then SocialService:PromptGameInvite(player) else NotificationManager.show("You cannot send invites right now.", "Error") end
		end)
	end
end

player.CharacterAdded:Connect(function(char) task.wait(0.5); setupHUD() end)
if player.Character then setupHUD() end