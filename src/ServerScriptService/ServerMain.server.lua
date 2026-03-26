--!strict
-- LOCATION: ServerScriptService/ServerMain
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ServerScriptService.Modules
local Controllers = ServerScriptService.Controllers

-- 1. LOAD PLAYER CONTROLLER FIRST
local PlayerController = require(Controllers.PlayerController)

-- PRE-LOAD SHARED INSTANCES
print("[ServerMain] Pre-loading Shared Instances...")
if PlayerController.SetupSharedInstances then
	PlayerController:SetupSharedInstances()
else
	if not ReplicatedStorage:FindFirstChild("Events") then
		local e = Instance.new("Folder")
		e.Name = "Events"
		e.Parent = ReplicatedStorage
	end
end

local SharedControllers = {
	PlayerController = PlayerController
}

local SystemModules = {}

print("[ServerMain] Loading Controllers...")

-- [FIX START] LOAD OTHER CONTROLLERS ----------------------------------
-- This ensures IncomeController and LeaderboardController are actually loaded!
for _, controllerScript in ipairs(Controllers:GetChildren()) do
	if controllerScript:IsA("ModuleScript") and controllerScript.Name ~= "PlayerController" then
		local success, loadedModule = pcall(require, controllerScript)
		if success then
			SystemModules[controllerScript.Name] = loadedModule
			-- Add to SharedControllers for dependency injection
			SharedControllers[controllerScript.Name] = loadedModule
			print("   > Loaded Controller:", controllerScript.Name)
		else
			warn("   X FAILED to load Controller:", controllerScript.Name, loadedModule)
		end
	end
end
-- [FIX END] -----------------------------------------------------------

print("[ServerMain] Loading Modules...")

for _, moduleScript in ipairs(Modules:GetChildren()) do
	if moduleScript:IsA("ModuleScript") then
		local success, loadedModule = pcall(require, moduleScript)
		if success then
			SystemModules[moduleScript.Name] = loadedModule
			print("   > Loaded Module:", moduleScript.Name)
		else
			warn("   X FAILED to load Module:", moduleScript.Name, loadedModule)
		end
	end
end

-- 2. INITIALIZE (Init)
print("[ServerMain] Initializing Systems...")

if PlayerController.Init then PlayerController:Init(SharedControllers) end

for name, system in pairs(SystemModules) do
	if type(system) == "table" and system.Init then
		task.spawn(function()
			system:Init(SharedControllers)
		end)
	end
end

task.wait(0.5)

-- 3. START (Start)
print("[ServerMain] Starting Systems...")

if PlayerController.Start then PlayerController:Start() end

for name, system in pairs(SystemModules) do
	if type(system) == "table" and system.Start then
		task.spawn(function()
			system:Start()
		end)
	end
end

-- 4. HANDLE SHUTDOWN
game:BindToClose(function()
	if PlayerController.OnClose then
		PlayerController:OnClose()
	end
end)

print("[ServerMain] --- Server Ready ---")