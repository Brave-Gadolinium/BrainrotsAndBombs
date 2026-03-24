script.Parent.MouseButton1Click:Connect(function()
	game.ReplicatedStorage.Remotes.Helper.TeleportPlayer:FireServer(game.Players.LocalPlayer)
end)