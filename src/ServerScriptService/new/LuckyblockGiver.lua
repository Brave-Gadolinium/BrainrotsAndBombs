function ArenaEntityManager:giveLuckyBlockFromId(player, id)
	local luckyBlockConfig = Config.lucky_blocks[id]
	if not luckyBlockConfig then 
		warn('Lucky block config not found', id)
		return 
	end

	local tool = Instance.new("Tool")
	tool.Name = luckyBlockConfig.name
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	if luckyBlockConfig.img then
		tool.TextureId = luckyBlockConfig.img
	end

	tool:SetAttribute("LuckyBlockId", luckyBlockConfig.id)
	tool:SetAttribute("Rarity", luckyBlockConfig.rarity)
	tool:SetAttribute("Kg", luckyBlockConfig.kg)
	tool:SetAttribute("Name", luckyBlockConfig.name)

	local model = ReplicatedStorage.Assets.LuckyBlocks[luckyBlockConfig.id]:Clone()
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	end

	local root = model.PrimaryPart
	if not root then
		warn("RootPart not found for lucky block:", id)
		tool:Destroy()
		model:Destroy()
		return
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = false
			part.Massless = true
		end
	end

	-- Handle обязателен
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1,1,1)
	handle.CanCollide = false
	handle.Anchored = false
	handle.Transparency = 1
	handle.Parent = tool

	local offset = CFrame.new(-0.4, 4.5, 1.4)
	model:PivotTo(handle.CFrame * offset)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = root
	weld.Parent = handle
	weld.Name = "LuckyBlockWeld"

	model.Parent = tool
	tool.Parent = player.Backpack

	--SoundManager.Play('Get_weapon', nil, false, workspace, 'Local')
end