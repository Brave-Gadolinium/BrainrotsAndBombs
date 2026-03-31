local TweenService = game:GetService("TweenService")

local container = script.Parent
local originalSizes = {}
local hoverStates = {}

for _, frame in ipairs(container:GetChildren()) do
	if frame:IsA("ImageButton") then
		originalSizes[frame] = frame.Size
		hoverStates[frame] = false

		local tweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		local function hoverSize()
			TweenService:Create(frame, tweenInfo, {Size = originalSizes[frame] - UDim2.new(0.02, 0, 0.02, 0)}):Play()
		end

		frame.MouseEnter:Connect(function()
			hoverStates[frame] = true
			hoverSize()
		end)

		frame.MouseLeave:Connect(function()
			hoverStates[frame] = false
			TweenService:Create(frame, tweenInfo, {Size = originalSizes[frame]}):Play()
		end)

		frame.MouseButton1Click:Connect(function()
			local clickTween = TweenService:Create(frame, tweenInfo, {Size = originalSizes[frame] - UDim2.new(0.05, 0, 0.05, 0)})
			clickTween:Play()
			clickTween.Completed:Connect(function()
				if hoverStates[frame] then
					hoverSize()
				else
					TweenService:Create(frame, tweenInfo, {Size = originalSizes[frame]}):Play()
				end
			end)
		end)
	end
end
