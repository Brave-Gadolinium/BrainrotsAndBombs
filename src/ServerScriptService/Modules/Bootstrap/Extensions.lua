--[[
    SCRIPT: Extensions (MODULE SCRIPT) - OPTIMIZED
    
    Location: ServerScriptService/Modules/Bootstrap/Extensions
    
    Description: Base metatable for controllers with shared methods.
    Clean code: Strict typing, simplified.
--]]
--!strict

local Extensions = {}

local Controller = {}
Controller.__index = Controller

function Controller:IsInitialized(): boolean
	return self._bs_initialized or false
end

Extensions.Controller = Controller

return Extensions