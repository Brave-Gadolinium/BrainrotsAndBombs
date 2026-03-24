--!strict
-- LOCATION: ServerScriptService/Modules/Bootstrap.lua (CORRECTED)

local Extensions = require(script:WaitForChild("Extensions"))

local Bootstrap = {}

local isRunning: boolean = false
local controllers: {[string]: any} = {}

function Bootstrap(container: Instance)
	if isRunning then
		error("[Bootstrap] Already initialized!")
	end
	isRunning = true

	-- ## START OF FIX ##

	-- 1. Load PlayerController FIRST
	local playerControllerModule = container:WaitForChild("PlayerController")
	local success, playerController = pcall(require, playerControllerModule)
	if not success then
		error("[Bootstrap] CRITICAL: PlayerController failed to load! Error: " .. tostring(playerController))
		return
	end
	setmetatable(playerController, Extensions.Controller)
	playerController._bs_name = "PlayerController"
	controllers["PlayerController"] = playerController

	-- 2. Call SetupSharedInstances immediately
	-- This creates the "Events" and "Functions" folders *before* any other controller needs them.
	if playerController.SetupSharedInstances then
		playerController:SetupSharedInstances()
	else
		warn("[Bootstrap] Could not find PlayerController:SetupSharedInstances()!")
	end

	-- 3. Load all OTHER controllers
	for _, module: Instance in container:GetDescendants() do
		-- Skip PlayerController since we already loaded it
		if module:IsA("ModuleScript") and module.Name:match("Controller$") and module.Name ~= "PlayerController" then
			local controllerName: string = module.Name
			local success, requiredModule = pcall(require, module)
			if success then
				setmetatable(requiredModule, Extensions.Controller)
				requiredModule._bs_name = controllerName
				controllers[controllerName] = requiredModule
			else
				-- If a controller fails to load, pcall will catch it and just warn
				-- This stops the 'nil' error, but you should check the output for this warning!
				warn(`[Bootstrap] Controller '{controllerName}' failed to load. Error: {tostring(requiredModule)}`)
			end
		end
	end

	-- ## END OF FIX ##

	-- 4. Initialize ALL controllers (this loop is unchanged)
	for _, controller in controllers do
		if controller.Init then
			controller:Init(controllers)
		end
	end

	-- 5. Start ALL controllers (this loop is unchanged)
	for _, controller in controllers do
		if controller.Start then
			task.spawn(function()
				pcall(controller.Start, controller, controllers)
			end)
		end
	end
end

return Bootstrap