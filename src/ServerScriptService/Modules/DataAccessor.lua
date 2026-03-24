--[[
    SCRIPT: DataAccessor (MODULE SCRIPT) - SIMPLIFIED
    
    Location: ServerScriptService/Modules/DataAccessor
    
    Description: Optional wrapper for profile data access.
    Optimized: Strict typing, added key get/set for convenience.
--]]
--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlayerController = require(ServerScriptService.Controllers.PlayerController)

local DataAccessor = {}

function DataAccessor:GetData(player: Player): table?
	local profile = PlayerController:GetProfile(player)
	return profile and profile.Data
end

function DataAccessor:SaveData(player: Player)
	local profile = PlayerController:GetProfile(player)
	if profile then
		profile:Save()
	end
end

function DataAccessor:GetKey(player: Player, key: string): any?
	local data = self:GetData(player)
	return data and data[key]
end

function DataAccessor:SetKey(player: Player, key: string, value: any)
	local data = self:GetData(player)
	if data then
		data[key] = value
	end
end

return DataAccessor