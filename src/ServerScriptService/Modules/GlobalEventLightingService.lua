--!strict

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GlobalEventLightingService = {}

type LightingEffect = {
	Priority: number,
	SkyboxName: string?,
}

local SKYBOX_FOLDER_NAME = "Skybox"
local DEFAULT_SKYBOX_NAME = "Sky"
local COLOR_CORRECTION_NAME = "GlobalEventColorCorrection"
local MANAGED_SKYBOX_ATTRIBUTE = "GlobalEventManagedSkybox"

local effectsByOwner: {[string]: LightingEffect} = {}
local warnedSkyboxes: {[string]: boolean} = {}

local function warnMissingSkybox(skyboxName: string)
	if warnedSkyboxes[skyboxName] then
		return
	end

	warnedSkyboxes[skyboxName] = true
	warn(`[GlobalEventLightingService] ReplicatedStorage.{SKYBOX_FOLDER_NAME}.{skyboxName} Sky was not found.`)
end

local function getSkyboxTemplate(skyboxName: string): Sky?
	local skyboxContainer = ReplicatedStorage:FindFirstChild(SKYBOX_FOLDER_NAME)
	local skyboxTemplate = skyboxContainer and skyboxContainer:FindFirstChild(skyboxName)
	if skyboxTemplate and skyboxTemplate:IsA("Sky") then
		return skyboxTemplate
	end

	warnMissingSkybox(skyboxName)
	return nil
end

local function applySkybox(skyboxName: string)
	local skyboxTemplate = getSkyboxTemplate(skyboxName)
	if not skyboxTemplate then
		return
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end

	local skybox = skyboxTemplate:Clone()
	skybox.Name = skyboxName
	skybox:SetAttribute(MANAGED_SKYBOX_ATTRIBUTE, true)
	skybox.Parent = Lighting
end

local function clearEventTint()
	local existing = Lighting:FindFirstChild(COLOR_CORRECTION_NAME)
	if existing then
		existing:Destroy()
	end
end

local function getHighestPriorityEffect(): LightingEffect?
	local selectedEffect: LightingEffect? = nil

	for _, effect in pairs(effectsByOwner) do
		if not selectedEffect or effect.Priority > selectedEffect.Priority then
			selectedEffect = effect
		end
	end

	return selectedEffect
end

local function reapply()
	clearEventTint()

	local effect = getHighestPriorityEffect()
	if effect then
		applySkybox(effect.SkyboxName or DEFAULT_SKYBOX_NAME)
		return
	end

	applySkybox(DEFAULT_SKYBOX_NAME)
end

function GlobalEventLightingService:SetEffect(ownerKey: string, effect: LightingEffect)
	if type(ownerKey) ~= "string" or ownerKey == "" then
		return
	end

	effectsByOwner[ownerKey] = {
		Priority = math.floor(tonumber(effect.Priority) or 0),
		SkyboxName = effect.SkyboxName,
	}
	reapply()
end

function GlobalEventLightingService:ClearEffect(ownerKey: string)
	if type(ownerKey) ~= "string" or ownerKey == "" then
		return
	end

	effectsByOwner[ownerKey] = nil
	reapply()
end

return GlobalEventLightingService
