--!strict

local TerrainGeneratorManager = {}

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Modules.Constants)

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
local TERRAIN_NORMALIZE_BATCH_SIZE = 4
local TERRAIN_NORMALIZE_BATCH_YIELD = 0.03
local TERRAIN_CHUNK_SIZE = 64
local TERRAIN_WRITE_BUDGET_SECONDS = 0.004
local SNAPSHOT_READ_BATCH_SIZE = 6
local STARTUP_BLOCKER_THICKNESS = 6
local STARTUP_PLAYABLE_TERRAIN_PROGRESS = 0.85
local MINE_ZONE_GENERATION_ENABLED = true -- Temporary test switch.
local ENABLED_MINE_ZONES = {
	Zone1 = true,
}
local STARTUP_ZONE_ORDER = if type(Constants.MINE_STARTUP_ZONE_ORDER) == "table"
	then Constants.MINE_STARTUP_ZONE_ORDER
	else { "Zone1", "Zone2", "Zone3", "Zone4", "Zone5" }
local TERRAIN_STARTUP_SLICE_HEIGHT = math.max(4, tonumber(Constants.TERRAIN_STARTUP_SLICE_HEIGHT) or 24)
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

type ZonePlan = {
	Name: string,
	Part: BasePart,
	Material: Enum.Material,
	Slices: { TerrainSlice },
	Chunks: { TerrainChunk },
	TopY: number,
	BottomY: number,
}

local zoneReadyChangedBindable = Instance.new("BindableEvent")
TerrainGeneratorManager.ZoneReadyChanged = zoneReadyChangedBindable.Event

local started = false
local queuedRegeneration = false
local isRegenerating = false
local fullResetRequired = false
local watchedGroundPartConnections: { [BasePart]: { RBXScriptConnection } } = {}
local zonePlansByName: { [string]: ZonePlan } = {}
local orderedZonePlans: { ZonePlan } = {}
local zoneReadyByName: { [string]: boolean } = {}
local zoneBlockersByName: { [string]: BasePart } = {}
local cachedChunks: { TerrainChunk } = {}
local cachedChunksById: { [string]: TerrainChunk } = {}
local dirtyChunkIds: { [string]: boolean } = {}

local function clampStartupProgress(progress: number): number
	return math.clamp(progress, 0, 1)
end

local function setStartupProgress(progress: number)
	Workspace:SetAttribute("MineStartupProgress", clampStartupProgress(progress))
end

local function getStartupPlayableZoneName(): string?
	local firstConfigured = STARTUP_ZONE_ORDER[1]
	if type(firstConfigured) == "string" and firstConfigured ~= "" then
		return firstConfigured
	end

	local firstZone = orderedZonePlans[1]
	return firstZone and firstZone.Name or nil
end

local function getZoneSortRank(zoneName: string): number
	for index, orderedZoneName in ipairs(STARTUP_ZONE_ORDER) do
		if orderedZoneName == zoneName then
			return index
		end
	end

	return math.huge
end

local function zoneSortComparator(left: ZonePlan, right: ZonePlan): boolean
	local leftRank = getZoneSortRank(left.Name)
	local rightRank = getZoneSortRank(right.Name)

	if leftRank ~= rightRank then
		return leftRank < rightRank
	end

	return left.Name < right.Name
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

local function buildZoneSlices(groundPart: BasePart, material: Enum.Material): { TerrainSlice }
	local size = groundPart.Size
	local position = groundPart.Position
	local minX = position.X - (size.X * 0.5)
	local maxX = position.X + (size.X * 0.5)
	local minZ = position.Z - (size.Z * 0.5)
	local maxZ = position.Z + (size.Z * 0.5)
	local bottomY = position.Y - (size.Y * 0.5)
	local topY = position.Y + (size.Y * 0.5)
	local slices: { TerrainSlice } = {}

	local currentTopY = topY
	while currentTopY > bottomY do
		local currentBottomY = math.max(bottomY, currentTopY - TERRAIN_STARTUP_SLICE_HEIGHT)
		local region = Region3.new(
			Vector3.new(minX, currentBottomY, minZ),
			Vector3.new(maxX, currentTopY, maxZ)
		):ExpandToGrid(VOXEL_RESOLUTION)

		table.insert(slices, {
			Region = region,
			Material = material,
		})

		currentTopY = currentBottomY
	end

	return slices
end

local function buildMineLayoutPlan(): ({ ZonePlan }, { TerrainChunk }, { [string]: TerrainChunk })
	local plans: { ZonePlan } = {}
	local chunks: { TerrainChunk } = {}
	local chunksById: { [string]: TerrainChunk } = {}

	for _, child in ipairs(groundParts:GetChildren()) do
		if not child:IsA("BasePart") then
			continue
		end

		if not ENABLED_MINE_ZONES[child.Name] then
			continue
		end

		local config = ZoneMaterialConfigs[child.Name] or DEFAULT_ZONE_CONFIG
		local zoneChunks: { TerrainChunk } = {}
		local size = child.Size
		local position = child.Position
		local minX = position.X - (size.X * 0.5)
		local maxX = position.X + (size.X * 0.5)
		local bottomY = position.Y - (size.Y * 0.5)
		local topY = position.Y + (size.Y * 0.5)
		local minZ = position.Z - (size.Z * 0.5)
		local maxZ = position.Z + (size.Z * 0.5)

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
					local chunk = chunksById[chunkId]
					if not chunk then
						chunk = createChunk(chunkX, chunkY, chunkZ)
						chunksById[chunkId] = chunk
						table.insert(chunks, chunk)
					end

					table.insert(zoneChunks, chunk)
				end
			end
		end

		table.insert(plans, {
			Name = child.Name,
			Part = child,
			Material = config.Material,
			Slices = buildZoneSlices(child, config.Material),
			Chunks = zoneChunks,
			TopY = topY,
			BottomY = bottomY,
		})
	end

	table.sort(plans, zoneSortComparator)
	table.sort(chunks, chunkSortComparator)

	return plans, chunks, chunksById
end

local function clearTerrainChunks(chunks: { TerrainChunk })
	for index, chunk in ipairs(chunks) do
		Terrain:FillRegion(chunk.Region, VOXEL_RESOLUTION, Enum.Material.Air)

		if index % TERRAIN_NORMALIZE_BATCH_SIZE == 0 then
			task.wait(TERRAIN_NORMALIZE_BATCH_YIELD)
		end
	end
end

local function fillSlices(slices: { TerrainSlice }, materialOverride: Enum.Material?, onStep: (() -> ())?)
	for index, slice in ipairs(slices) do
		Terrain:FillRegion(slice.Region, VOXEL_RESOLUTION, materialOverride or slice.Material)
		if onStep then
			onStep()
		end

		if index % TERRAIN_NORMALIZE_BATCH_SIZE == 0 then
			task.wait(TERRAIN_NORMALIZE_BATCH_YIELD)
		end
	end
end

local function captureChunkSnapshots(chunks: { TerrainChunk }, onStep: (() -> ())?)
	for index, chunk in ipairs(chunks) do
		local materials, occupancy = Terrain:ReadVoxels(chunk.Region, VOXEL_RESOLUTION)
		chunk.Materials = materials
		chunk.Occupancy = occupancy

		if onStep then
			onStep()
		end

		if index % SNAPSHOT_READ_BATCH_SIZE == 0 then
			task.wait()
		end
	end
end

local function getStartupBlockerFolder(): Folder
	local existingFolder = Workspace:FindFirstChild("MineStartupBlockers")
	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	if existingFolder then
		existingFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "MineStartupBlockers"
	folder.Parent = Workspace
	return folder
end

local function destroyZoneBlocker(zoneName: string)
	local blocker = zoneBlockersByName[zoneName]
	if blocker then
		zoneBlockersByName[zoneName] = nil
		blocker:Destroy()
	end
end

local function createZoneBlocker(zonePlan: ZonePlan)
	destroyZoneBlocker(zonePlan.Name)

	local blocker = Instance.new("Part")
	blocker.Name = zonePlan.Name .. "_StartupBlocker"
	blocker.Size = Vector3.new(zonePlan.Part.Size.X, STARTUP_BLOCKER_THICKNESS, zonePlan.Part.Size.Z)
	blocker.CFrame = zonePlan.Part.CFrame
		* CFrame.new(0, (zonePlan.Part.Size.Y * 0.5) - (STARTUP_BLOCKER_THICKNESS * 0.5), 0)
	blocker.Anchored = true
	blocker.CanCollide = true
	blocker.CanTouch = false
	blocker.CanQuery = false
	blocker.Transparency = 1
	blocker.CastShadow = false
	blocker.Locked = true
	blocker.Parent = getStartupBlockerFolder()

	zoneBlockersByName[zonePlan.Name] = blocker
end

local function syncStartupBlockers()
	for zoneName in pairs(zoneBlockersByName) do
		if not zonePlansByName[zoneName] or zoneReadyByName[zoneName] == true then
			destroyZoneBlocker(zoneName)
		end
	end

	for _, zonePlan in ipairs(orderedZonePlans) do
		if zoneReadyByName[zonePlan.Name] ~= true and not zoneBlockersByName[zonePlan.Name] then
			createZoneBlocker(zonePlan)
		end
	end
end

local function applyZonePlanRegistry(plans: { ZonePlan }, markReady: boolean)
	for zoneName in pairs(zoneReadyByName) do
		zoneReadyByName[zoneName] = nil
	end

	table.clear(zonePlansByName)
	orderedZonePlans = plans

	for _, zonePlan in ipairs(plans) do
		zonePlansByName[zonePlan.Name] = zonePlan
		zoneReadyByName[zonePlan.Name] = markReady
	end

	syncStartupBlockers()
end

local function disableMineZoneGenerationForTests()
	fullResetRequired = false
	cachedChunks = {}
	cachedChunksById = {}
	dirtyChunkIds = {}
	applyZonePlanRegistry({}, false)
	Workspace:SetAttribute("TerrainResetInProgress", false)
	setStartupProgress(1)
	Workspace:SetAttribute("MineStartupPlayable", true)
end

local function hasPendingDirtyChunks(): boolean
	return next(dirtyChunkIds) ~= nil
end

local function restoreChunksFromSnapshot(chunks: { TerrainChunk })
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

local function markZoneReady(zoneName: string)
	if zoneReadyByName[zoneName] == true then
		return
	end

	zoneReadyByName[zoneName] = true
	destroyZoneBlocker(zoneName)
	zoneReadyChangedBindable:Fire(zoneName)
end

local function rebuildBaselineSnapshot()
	local plans, chunks, chunksById = buildMineLayoutPlan()
	local chunksToClear: { TerrainChunk } = {}
	local clearChunkIds: { [string]: boolean } = {}

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

	cachedChunks = chunks
	cachedChunksById = chunksById
	applyZonePlanRegistry(plans, true)

	for _, zonePlan in ipairs(orderedZonePlans) do
		fillSlices(zonePlan.Slices, nil, nil)
	end

	captureChunkSnapshots(cachedChunks, nil)
	dirtyChunkIds = {}
	fullResetRequired = false
end

local function collectChunksForRestore(): { TerrainChunk }
	if fullResetRequired then
		rebuildBaselineSnapshot()
		return {}
	end

	if not hasPendingDirtyChunks() then
		return {}
	end

	local chunksToRestore: { TerrainChunk } = {}
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
	local seen: { [BasePart]: boolean } = {}

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

local function createStartupProgressReporter(totalSteps: number): (() -> ())?
	local playableZoneName = getStartupPlayableZoneName()
	if not playableZoneName or totalSteps <= 0 then
		return nil
	end

	local completedSteps = 0
	return function()
		completedSteps += 1
		local alpha = math.clamp(completedSteps / totalSteps, 0, 1)
		setStartupProgress(alpha * STARTUP_PLAYABLE_TERRAIN_PROGRESS)
	end
end

local function runInitialBootstrap()
	task.spawn(function()
		local success, err = pcall(function()
			local plans, chunks, chunksById = buildMineLayoutPlan()
			cachedChunks = chunks
			cachedChunksById = chunksById
			dirtyChunkIds = {}
			fullResetRequired = false
			applyZonePlanRegistry(plans, false)

			if #orderedZonePlans == 0 then
				setStartupProgress(1)
				Workspace:SetAttribute("MineStartupPlayable", true)
				return
			end

			local playableZoneName = getStartupPlayableZoneName()

			for _, zonePlan in ipairs(orderedZonePlans) do
				local reporter = if zonePlan.Name == playableZoneName
					then createStartupProgressReporter((#zonePlan.Slices * 2) + #zonePlan.Chunks)
					else nil

				fillSlices(zonePlan.Slices, Enum.Material.Air, reporter)
				fillSlices(zonePlan.Slices, nil, reporter)
				captureChunkSnapshots(zonePlan.Chunks, reporter)
				markZoneReady(zonePlan.Name)

				if zonePlan.Name == playableZoneName then
					setStartupProgress(STARTUP_PLAYABLE_TERRAIN_PROGRESS)
				end

				task.wait()
			end
		end)

		if success then
			return
		end

		warn("[TerrainGeneratorManager] Staged startup bootstrap failed:", err)

		local rebuildSuccess, rebuildErr = pcall(rebuildBaselineSnapshot)
		if not rebuildSuccess then
			warn("[TerrainGeneratorManager] Fallback baseline rebuild failed:", rebuildErr)
		end

		for _, zonePlan in ipairs(orderedZonePlans) do
			if zoneReadyByName[zonePlan.Name] ~= true then
				markZoneReady(zonePlan.Name)
			else
				destroyZoneBlocker(zonePlan.Name)
				zoneReadyChangedBindable:Fire(zonePlan.Name)
			end
		end

		setStartupProgress(STARTUP_PLAYABLE_TERRAIN_PROGRESS)
	end)
end

local function getZonePlanForPosition(position: Vector3): ZonePlan?
	for _, zonePlan in ipairs(orderedZonePlans) do
		local relativePosition = zonePlan.Part.CFrame:PointToObjectSpace(position)
		local halfSize = zonePlan.Part.Size * 0.5
		local inside = math.abs(relativePosition.X) <= halfSize.X
			and math.abs(relativePosition.Y) <= halfSize.Y
			and math.abs(relativePosition.Z) <= halfSize.Z

		if inside then
			return zonePlan
		end
	end

	return nil
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

function TerrainGeneratorManager.RequestRegeneration()
	if not MINE_ZONE_GENERATION_ENABLED then
		return
	end

	runRegeneration()
end

function TerrainGeneratorManager.IsZoneReady(zoneName: string): boolean
	return zoneReadyByName[zoneName] == true
end

function TerrainGeneratorManager.IsPositionReady(position: Vector3): boolean
	if typeof(position) ~= "Vector3" then
		return false
	end

	local zonePlan = getZonePlanForPosition(position)
	if not zonePlan then
		return true
	end

	return zoneReadyByName[zonePlan.Name] == true
end

function TerrainGeneratorManager:Start()
	if started then
		return
	end

	started = true
	Workspace:SetAttribute("MineStartupProgress", 0)
	Workspace:SetAttribute("MineStartupPlayable", false)

	if not MINE_ZONE_GENERATION_ENABLED then
		disableMineZoneGenerationForTests()
		return
	end

	configureMaterialOverrides()
	syncGroundPartWatchers()

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

	runInitialBootstrap()
end

return TerrainGeneratorManager
