local Cache = {}

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")
local CollectionService = game:GetService("CollectionService")

local Player = game.Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local checkCount = 10
local checkLoading = false
local debounce = false

while not checkLoading do
	for i, v in pairs(CollectionService:GetTagged("Rotate")) do
		if i == checkCount then
			checkLoading = true
		end
	end
	task.wait(1)
end

for i, v in pairs(CollectionService:GetTagged("Rotate")) do
	
	local ProductId = v:GetAttribute("Product")
	--if not ProductId then continue end

	local BikeModel = v
	local StartingCFrame = BikeModel:GetPivot()

	v.PrimaryPart.Touched:Connect(function(HitPart)

		if HitPart.Parent:FindFirstChild("Humanoid") == nil then return end

		local Player = game.Players:GetPlayerFromCharacter(HitPart.Parent)
		if not Cache[Player] then 
			Cache[Player] = 0
		end
		
		if debounce == false then
			debounce = true
		else
			return
		end


		if Player == game.Players.LocalPlayer then
			debounce = true
			MarketplaceService:PromptProductPurchase(Player, ProductId)
		end
		
		task.delay(1, function()
			debounce = false
		end)
	end)

	local Rotation = 0
	local Time = 0

	game:GetService("RunService").RenderStepped:Connect(function(deltaTime)
		if (game.Workspace.Camera.CFrame.Position - StartingCFrame.Position).Magnitude <= 200 then
			Rotation = Rotation + 0.03
			Time += deltaTime
			local FloatHeight = math.sin(Time * 2) * 0.5

			local NewCFrame =
				CFrame.new(
					StartingCFrame.Position + Vector3.new(0, FloatHeight, 0)
				)
				* CFrame.Angles(0, Rotation, 0)

			BikeModel:PivotTo(NewCFrame)
		end
	end)
end