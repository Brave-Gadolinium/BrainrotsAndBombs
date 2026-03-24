--!strict
-- LOCATION: StarterPlayerScripts/NotificationController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local NotificationManager = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NotificationManager"))

-- Assets
local Events = ReplicatedStorage:WaitForChild("Events")
local ShowNotificationEvent = Events:WaitForChild("ShowNotification")

print("[NotificationController] Listening for events...")

-- Connect the Server Event to the Module
ShowNotificationEvent.OnClientEvent:Connect(function(message: string, messageType: string)
	-- Pass the data to the UI Manager
	NotificationManager.show(message, messageType)
end)