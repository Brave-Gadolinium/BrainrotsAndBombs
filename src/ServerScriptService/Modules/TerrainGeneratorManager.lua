local TerrainGeneratorManager = {}

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Terrain = Workspace.Terrain
local groundParts = Workspace:WaitForChild("Mines")

local function ensureTimerFinishEvent(): BindableEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local timerFolder = remotesFolder:FindFirstChild("Timer")
	if not timerFolder then
		timerFolder = Instance.new("Folder")
		timerFolder.Name = "Timer"
		timerFolder.Parent = remotesFolder
	end

	local finishTime = timerFolder:FindFirstChild("FinishTime")
	if not finishTime then
		finishTime = Instance.new("BindableEvent")
		finishTime.Name = "FinishTime"
		finishTime.Parent = timerFolder
	end

	return finishTime :: BindableEvent
end

local FinishTime = ensureTimerFinishEvent()

local VOXEL_RESOLUTION = 4
local TERRAIN_SLICE_HEIGHT = 48
local TERRAIN_NORMALIZE_BATCH_SIZE = 4
local TERRAIN_NORMALIZE_BATCH_YIELD = 0.03
local TERRAIN_CHUNK_SIZE = 64
local TERRAIN_WRITE_BUDGET_SECONDS = 0.004
local SNAPSHOT_READ_BATCH_SIZE = 6
local CHUNK_SIZE_VECTOR = Vector3.new(TERRAIN_CHUNK_SIZE, TERRAIN_CHUNK_SIZE, TERRAIN_CHUNK_SIZE)
local CHUNK_BOUNDARY_EPSILON = 0.001

local ZoneMaterialConfigs = {
	Zone1 = {
		Material = Enum.Material.Sand,
		MaterialVariant = "SandTerrain",
	},
	Zone2 = {
		Material = Enum.Material.Slate,
		MaterialVariant = "StoneTerrain3",
	},
	Zone3 = {
		Material = Enum.Material.Rock,
		MaterialVariant = "StoneTerrain",
	},
	Zone4 = {
		Material = Enum.Material.Basalt,
		MaterialVariant = "LavaTerrain",
	},
	Zone5 = {
		Material = Enum.Material.CrackedLava,
		MaterialVariant = "GlitchTerrain",
	},
}

local DEFAULT_ZONE_CONFIG = ZoneMaterialConfigs.Zone1
local queuedRegeneration = false
local isRegenerating = false
local fullResetRequired = false

type TerrainSlice = {
	Region: Region3,
	Material: Enum.Material,
}

type TerrainChunk = {
	Id: string,
	ChunkX: number,
	ChunkY: number,
	ChunkZ: number,
	Min: Vector3,
	Max: Vector3,
	Region: Region3,
	Materials: any,
	Occupancy: any,
}

local cachedSlices: {TerrainSlice} = {}
local cachedChunks: {TerrainChunk} = {}
local cachedChunksById: {[string]: TerrainChunk} = {}
local dirtyChunkIds: {[string]: boolean} = {}
local watchedGroundPartConnections: {[BasePart]: {RBXScriptConnection}} = {}

local requestRegeneration: () -> ()

local function configureMaterialOverrides()
	for zoneName, config in pairs(ZoneMaterialConfigs) do
		local variant = MaterialService:GetMaterialVariant(config.Material, config.MaterialVariant)
		if variant then
			MaterialService:SetBaseMaterialOverride(config.Material, config.MaterialVariant)
			continue
		end

		local variantByName = MaterialService:FindFirstChild(config.MaterialVariant, true)
		if variantByName and variantByName:IsA("MaterialVariant") then
			warn(string.format(
				"[TerrainGeneratorManager] %s uses MaterialVariant %q, but its BaseMaterial must match %s in MaterialService.",
				zoneName,
				config.MaterialVariant,
				tostring(config.Material)
			))
		else
			warn(string.format(
				"[TerrainGeneratorManager] MaterialVariant %q for %s was not found in MaterialService.",
				config.MaterialVariant,
				zoneName
			))
		end
	end
end

local function getChunkId(chunkX: number, chunkY: number, chunkZ: number): string
	return string.format("%d:%d:%d", chunkX, chunkY, chunkZ)
end

local function createChunk(chunkX: number, chunkY: number, chunkZ: number): TerrainChunk
	local minVector = Vector3.new(
		chunkX * TERRAIN_CHUNK_SIZE,
		chunkY * TERRAIN_CHUNK_SIZE,
		chunkZ * TERRAIN_CHUNK_SIZE
	)

	return {
		Id = getChunkId(chunkX, chunkY, chunkZ),
		ChunkX = chunkX,
		ChunkY = chunkY,
		ChunkZ = chunkZ,
		Min = minVector,
		Max = minVector + CHUNK_SIZE_VECTOR,
		Region = Region3.new(minVector, minVector + CHUNK_SIZE_VECTOR),
		Materials = nil,
		Occupancy = nil,
	}
end

local function chunkSortComparator(a: TerrainChunk, b: TerrainChunk): boolean
	if a.ChunkY ~= b.ChunkY then
		return a.ChunkY < b.ChunkY
	end

	if a.ChunkX ~= b.ChunkX then
		return a.ChunkX < b.ChunkX
	end

	return a.ChunkZ < b.ChunkZ
end

local function buildSlicesAndChunks(): ({TerrainSlice}, {TerrainChunk}, {[string]: TerrainChunk})
	local slices: {TerrainSlice} = {}
	local chunks: {TerrainChunk} = {}
	local chunksById: {[string]: TerrainChunk} = {}

	for _, groundPart in ipairs(groundParts:GetChildren()) do
		if not groundPart:IsA("BasePart") then
			continue
		end

		local config = ZoneMaterialConfigs[groundPart.Name] or DEFAULT_ZONE_CONFIG
		local size = groundPart.Size
		local position = groundPart.Position

		local minX = position.X - (size.X * 0.5)
		local maxX = position.X + (size.X * 0.5)
		local minZ = position.Z - (size.Z * 0.5)
		local maxZ = position.Z + (size.Z * 0.5)
		local bottomY = position.Y - (size.Y * 0.5)
		local topY = position.Y + (size.Y * 0.5)

		local currentBottomY = bottomY
		while currentBottomY < topY do
			local currentTopY = math.min(currentBottomY + TERRAIN_SLICE_HEIGHT, topY)
			local region = Region3.new(
				Vector3.new(minX, currentBottomY, minZ),
				Vector3.new(maxX, currentTopY, maxZ)
			):ExpandToGrid(VOXEL_RESOLUTION)

			table.insert(slices, {
				Region = region,
				Material = config.Material,
			})

			currentBottomY = currentTopY
		end

		local minChunkX = math.floor(minX / TERRAIN_CHUNK_SIZE)
		local maxChunkX = math.ceil(maxX / TERRAIN_CHUNK_SIZE) - 1
		local minChunkY = math.floor(bottomY / TERRAIN_CHUNK_SIZE)
		local maxChunkY = math.ceil(topY / TERRAIN_CHUNK_SIZE) - 1
		local minChunkZ = math.floor(minZ / TERRAIN_CHUNK_SIZE)
		local maxChunkZ = math.ceil(maxZ / TERRAIN_CHUNK_SIZE) - 1

		for chunkX = minChunkX, maxChunkX do
			for chunkY = minChunkY, maxChunkY do
				for chunkZ = minChunkZ, maxChunkZ do
					local chunkId = getChunkId(chunkX, chunkY, chunkZ)
					if not chunksById[chunkId] then
						local chunk = createChunk(chunkX, chunkY, chunkZ)
						chunksById[chunkId] = chunk
						table.insert(chunks, chunk)
					end
				end
			end
		end
	end

	table.sort(chunks, chunkSortComparator)

	return slices, chunks, chunksById
end

local function restoreTerrainBaselineSlices(slices: {TerrainSlice})
	for index, slice in ipairs(slices) do
		Terrain:FillRegion(slice.Region, VOXEL_RESOLUTION, slice.Material)

		if index % TERRAIN_NORMALIZE_BATCH_SIZE == 0 then
			task.wait(TERRAIN_NORMALIZE_BATCH_YIELD)
		end
	end
end

local function clearTerrainChunks(chunks: {TerrainChunk})
	for index, chunk in ipairs(chunks) do
		Terrain:FillRegion(chunk.Region, VOXEL_RESOLUTION, Enum.Material.Air)

		if index % TERRAIN_NORMALIZE_BATCH_SIZE == 0 then
			task.wait(TERRAIN_NORMALIZE_BATCH_YIELD)
		end
	end
end

local function captureChunkSnapshots(chunks: {TerrainChunk})
	for index, chunk in ipairs(chunks) do
		local materials, occupancy = Terrain:ReadVoxels(chunk.Region, VOXEL_RESOLUTION)
		chunk.Materials = materials
		chunk.Occupancy = occupancy

		if index % SNAPSHOT_READ_BATCH_SIZE == 0 then
			task.wait()
		end
	end
end

local function rebuildBaselineSnapshot()
	local slices, chunks, chunksById = buildSlicesAndChunks()
	local chunksToClear: {TerrainChunk} = {}
	local clearChunkIds: {[string]: boolean} = {}

	for _, chunk in ipairs(cachedChunks) do
		if not clearChunkIds[chunk.Id] then
			clearChunkIds[chunk.Id] = true
			table.insert(chunksToClear, chunk)
		end
	end

	for _, chunk in ipairs(chunks) do
		if not clearChunkIds[chunk.Id] then
			clearChunkIds[chunk.Id] = true
			table.insert(chunksToClear, chunk)
		end
	end

	table.sort(chunksToClear, chunkSortComparator)
	clearTerrainChunks(chunksToClear)

	cachedSlices = slices
	cachedChunks = chunks
	cachedChunksById = chunksById

	restoreTerrainBaselineSlices(cachedSlices)
	captureChunkSnapshots(cachedChunks)

	dirtyChunkIds = {}
	fullResetRequired = false
end

local function hasPendingDirtyChunks(): boolean
	return next(dirtyChunkIds) ~= nil
end

local function restoreChunksFromSnapshot(chunks: {TerrainChunk})
	local deadline = os.clock() + TERRAIN_WRITE_BUDGET_SECONDS

	for _, chunk in ipairs(chunks) do
		if chunk.Materials and chunk.Occupancy then
			Terrain:WriteVoxels(chunk.Region, VOXEL_RESOLUTION, chunk.Materials, chunk.Occupancy)
		end

		if os.clock() >= deadline then
			task.wait()
			deadline = os.clock() + TERRAIN_WRITE_BUDGET_SECONDS
		end
	end
end

local function collectChunksForRestore(): {TerrainChunk}
	if fullResetRequired then
		rebuildBaselineSnapshot()

		local allChunks: {TerrainChunk} = {}
		for index, chunk in ipairs(cachedChunks) do
			allChunks[index] = chunk
		end

		return allChunks
	end

	if not hasPendingDirtyChunks() then
		return {}
	end

	local chunksToRestore: {TerrainChunk} = {}
	for _, chunk in ipairs(cachedChunks) do
		if dirtyChunkIds[chunk.Id] then
			table.insert(chunksToRestore, chunk)
		end
	end

	dirtyChunkIds = {}

	return chunksToRestore
end

local function runRegeneration()
	if isRegenerating then
		queuedRegeneration = true
		return
	end

	isRegenerating = true

	task.spawn(function()
		local restoreActive = false

		local function setRestoreState(active: boolean)
			if restoreActive == active then
				return
			end

			restoreActive = active
			Workspace:SetAttribute("TerrainResetInProgress", active)
		end

		repeat
			queuedRegeneration = false

			local shouldRunRestore = fullResetRequired or hasPendingDirtyChunks()
			if shouldRunRestore then
				setRestoreState(true)

				local success, err = pcall(function()
					local chunksToRestore = collectChunksForRestore()
					if #chunksToRestore > 0 then
						restoreChunksFromSnapshot(chunksToRestore)
					end
				end)

				if not success then
					warn("[TerrainGeneratorManager] Terrain regeneration failed:", err)
					fullResetRequired = true
				end
			end
		until not queuedRegeneration

		isRegenerating = false
		setRestoreState(false)
	end)
end

local function disconnectGroundPartWatchers(part: BasePart)
	local connections = watchedGroundPartConnections[part]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	watchedGroundPartConnections[part] = nil
end

local function invalidateMineLayout()
	fullResetRequired = true

	if isRegenerating then
		queuedRegeneration = true
	elseif Workspace:GetAttribute("SessionEnded") == true then
		runRegeneration()
	end
end

local function watchGroundPart(part: BasePart)
	if watchedGroundPartConnections[part] then
		return
	end

	local function onPartChanged()
		invalidateMineLayout()
	end

	watchedGroundPartConnections[part] = {
		part:GetPropertyChangedSignal("CFrame"):Connect(onPartChanged),
		part:GetPropertyChangedSignal("Size"):Connect(onPartChanged),
		part:GetPropertyChangedSignal("Name"):Connect(onPartChanged),
		part:GetPropertyChangedSignal("Parent"):Connect(onPartChanged),
	}
end

local function syncGroundPartWatchers()
	local seen: {[BasePart]: boolean} = {}

	for _, child in ipairs(groundParts:GetChildren()) do
		if child:IsA("BasePart") then
			seen[child] = true
			watchGroundPart(child)
		end
	end

	for part in pairs(watchedGroundPartConnections) do
		if not seen[part] then
			disconnectGroundPartWatchers(part)
		end
	end
end

local function sphereIntersectsChunk(center: Vector3, radius: number, chunk: TerrainChunk): boolean
	local closestX = math.clamp(center.X, chunk.Min.X, chunk.Max.X)
	local closestY = math.clamp(center.Y, chunk.Min.Y, chunk.Max.Y)
	local closestZ = math.clamp(center.Z, chunk.Min.Z, chunk.Max.Z)
	local distance = center - Vector3.new(closestX, closestY, closestZ)
	return distance:Dot(distance) <= (radius * radius)
end

function TerrainGeneratorManager.MarkSphereDirty(center: Vector3, radius: number)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then
		return
	end

	if fullResetRequired then
		return
	end

	local minChunkX = math.floor((center.X - radius - CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)
	local maxChunkX = math.floor((center.X + radius + CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)
	local minChunkY = math.floor((center.Y - radius - CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)
	local maxChunkY = math.floor((center.Y + radius + CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)
	local minChunkZ = math.floor((center.Z - radius - CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)
	local maxChunkZ = math.floor((center.Z + radius + CHUNK_BOUNDARY_EPSILON) / TERRAIN_CHUNK_SIZE)

	for chunkX = minChunkX, maxChunkX do
		for chunkY = minChunkY, maxChunkY do
			for chunkZ = minChunkZ, maxChunkZ do
				local chunk = cachedChunksById[getChunkId(chunkX, chunkY, chunkZ)]
				if chunk and sphereIntersectsChunk(center, radius, chunk) then
					dirtyChunkIds[chunk.Id] = true
				end
			end
		end
	end
end

requestRegeneration = function()
	runRegeneration()
end

function TerrainGeneratorManager.RequestRegeneration()
	requestRegeneration()
end

configureMaterialOverrides()
syncGroundPartWatchers()
Workspace:SetAttribute("TerrainResetInProgress", true)

local bootstrapSuccess, bootstrapError = pcall(rebuildBaselineSnapshot)
if not bootstrapSuccess then
	fullResetRequired = true
	warn("[TerrainGeneratorManager] Failed to build terrain baseline snapshot:", bootstrapError)
end

Workspace:SetAttribute("TerrainResetInProgress", false)

groundParts.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		syncGroundPartWatchers()
		invalidateMineLayout()
	end
end)

groundParts.ChildRemoved:Connect(function(child)
	if child:IsA("BasePart") then
		disconnectGroundPartWatchers(child)
		invalidateMineLayout()
	end
end)

FinishTime.Event:Connect(function()
	TerrainGeneratorManager.RequestRegeneration()
end)

return TerrainGeneratorManager
