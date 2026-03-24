-- LOCATION: Inside the NPC Model (Script)

local npc = script.Parent
local humanoid = npc:WaitForChild("Humanoid")
-- The Animator object handles loading animations smoothly
local animator = humanoid:WaitForChild("Animator") 

-- 1. Create the Animation Instance
local idleAnim = Instance.new("Animation")
idleAnim.Name = "IdleAnimation"
-- REPLACE THE NUMBER BELOW WITH YOUR ANIMATION ID
idleAnim.AnimationId = "rbxassetid://117364235771341" 

-- 2. Function to Play
local function playIdle()
	local track = animator:LoadAnimation(idleAnim)
	track.Looped = true -- Ensures it repeats forever
	track.Priority = Enum.AnimationPriority.Idle
	track:Play()
end

-- 3. Run it
playIdle()