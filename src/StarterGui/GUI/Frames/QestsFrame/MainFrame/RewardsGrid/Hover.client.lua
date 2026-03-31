local TweenService = game:GetService("TweenService")
local container = script.Parent
local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function createTweens(button)
	local frame = button:WaitForChild("Frame")
	local originalSize = frame.Size
	local hoverSize = originalSize + UDim2.new(-0.05, 0, -0.05, 0)
	local clickSize = originalSize + UDim2.new(-0.15, 0, -0.15, 0)
	local isHovered = false
	button.MouseEnter:Connect(function()
		isHovered = true
		TweenService:Create(frame, tweenInfo, {Size = hoverSize}):Play()
	end)
	button.MouseLeave:Connect(function()
		isHovered = false
		TweenService:Create(frame, tweenInfo, {Size = originalSize}):Play()
	end)
	button.MouseButton1Click:Connect(function()
		local clickTween = TweenService:Create(frame, tweenInfo, {Size = clickSize})
		clickTween:Play()
		clickTween.Completed:Connect(function()
			if isHovered then
				TweenService:Create(frame, tweenInfo, {Size = hoverSize}):Play()
			else
				TweenService:Create(frame, tweenInfo, {Size = originalSize}):Play()
			end
		end)
	end)
end

local function setupContainer(container)
	for _, button in ipairs(container:GetChildren()) do
		if button:IsA("ImageButton") then
			createTweens(button)
		end
	end
end

container.ChildAdded:Connect(function(button)
	if button:IsA("ImageButton") then
		createTweens(button)
	end
end)

setupContainer(container)