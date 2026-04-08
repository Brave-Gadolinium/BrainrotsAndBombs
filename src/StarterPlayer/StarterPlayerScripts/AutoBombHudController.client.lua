--!strict
-- LOCATION: StarterPlayerScripts/AutoBombHudController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfigurations = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProductConfigurations"))

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState") :: RemoteEvent
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")

local autoBombFrame: GuiObject? = nil
local toggleButton: GuiButton? = nil

local function reportStorePromptFailed(reason: string)
	reportAnalyticsIntent:FireServer("StorePromptFailed", {
		surface = "autobomb_hud",
		section = "autobomb_hud",
		entrypoint = "toggle",
		productName = "AutoBomb",
		passId = ProductConfigurations.GamePasses.AutoBomb,
		purchaseKind = "gamepass",
		paymentType = "robux",
		reason = reason,
	})
end

local function setButtonText(button: GuiButton?, text: string)
	if not button then
		return
	end

	if button:IsA("TextButton") then
		button.Text = text
		return
	end

	local label = button:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = text
	end
end

local function findAutoBombFrame(): GuiObject?
	local frame = hud:FindFirstChild("Autobomb")
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	return nil
end

local function findToggleButton(frame: GuiObject?): GuiButton?
	if not frame then
		return nil
	end

	local button = frame:FindFirstChild("Toggle", true)
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function refreshHudAutoBomb()
	if not autoBombFrame then
		return
	end

	local hasAutoBomb = player:GetAttribute("HasAutoBomb") == true
	local isEnabled = player:GetAttribute("AutoBombEnabled") == true

	autoBombFrame.Visible = true

	if toggleButton then
		toggleButton.Active = true
		if hasAutoBomb then
			setButtonText(toggleButton, if isEnabled then "On" else "Off")
		else
			setButtonText(toggleButton, "Buy")
		end
	end
end

local function bindToggleButton(button: GuiButton?)
	if not button or button:GetAttribute("AutoBombHudBound") == true then
		return
	end

	button:SetAttribute("AutoBombHudBound", true)
	button.Activated:Connect(function()
		if player:GetAttribute("HasAutoBomb") == true then
			local nextState = not (player:GetAttribute("AutoBombEnabled") == true)
			reportAnalyticsIntent:FireServer("AutoBombToggleRequested", {
				surface = "autobomb_hud",
				enabled = nextState,
			})
			requestAutoBombState:FireServer(nextState)
			return
		end

		local passId = ProductConfigurations.GamePasses.AutoBomb
		if type(passId) == "number" and passId > 0 then
			reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
				surface = "autobomb_hud",
				section = "autobomb_hud",
				entrypoint = "toggle",
				productName = "AutoBomb",
				passId = passId,
				purchaseKind = "gamepass",
				paymentType = "robux",
			})
			local success, err = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)
			if not success then
				warn("[AutoBombHudController] Failed to prompt AutoBomb pass:", err)
				reportStorePromptFailed("prompt_failed")
			end
		else
			reportStorePromptFailed("missing_pass_id")
		end
	end)
end

local function resolveHudAutoBomb()
	autoBombFrame = findAutoBombFrame()
	toggleButton = findToggleButton(autoBombFrame)
	bindToggleButton(toggleButton)
	refreshHudAutoBomb()
end

hud.ChildAdded:Connect(function(child)
	if child.Name == "Autobomb" then
		task.defer(resolveHudAutoBomb)
	end
end)

hud.ChildRemoved:Connect(function(child)
	if child == autoBombFrame then
		autoBombFrame = nil
		toggleButton = nil
	end
end)

hud.DescendantAdded:Connect(function(descendant)
	if autoBombFrame and descendant:IsDescendantOf(autoBombFrame) and descendant.Name == "Toggle" then
		task.defer(resolveHudAutoBomb)
	end
end)

player:GetAttributeChangedSignal("HasAutoBomb"):Connect(refreshHudAutoBomb)
player:GetAttributeChangedSignal("AutoBombEnabled"):Connect(refreshHudAutoBomb)

resolveHudAutoBomb()
