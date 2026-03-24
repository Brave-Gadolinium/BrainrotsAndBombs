--!strict
local Utils = {}

function Utils.ToggleRagdoll(character: Model, enabled: boolean)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if enabled then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

return Utils