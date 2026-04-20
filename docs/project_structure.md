# Project Structure

Top-level source:
- `src/ReplicatedStorage` shared modules, templates, runtime config, and replicated assets
- `src/ServerScriptService` server controllers and gameplay modules
- `src/StarterPlayer/StarterPlayerScripts` client gameplay and UI controllers
- `src/StarterGui` Rojo-managed GUI snapshots; some runtime UI still exists only in Studio and is tolerated via `$ignoreUnknownInstances`

Important server folders:
- `src/ServerScriptService/Controllers` stateful gameplay systems loaded by `ServerMain.server.lua`
- `src/ServerScriptService/Modules` reusable server-side helpers, runtime bridges, managers, and analytics services
- `src/ServerScriptService/Modules/CandyEventService.lua` runs the hourly candy event and wheel reward flow
- `src/ServerScriptService/Modules/MineSpawnUtils.lua` centralizes mine spawn positioning shared by event and baseline item spawning

Important shared folders:
- `src/ReplicatedStorage/Modules` shared config and utility modules used by both server and client
- `src/ReplicatedStorage/Modules/CandyEventConfiguration.lua` stores candy event schedule, copy, rewards, and per-zone counts

Important client folders:
- `src/StarterPlayer/StarterPlayerScripts` HUD, shop, rewards, tutorial, and other client controllers
- `src/StarterPlayer/StarterPlayerScripts/CandyEventController.client.lua` and `CandySpinController.client.lua` own the world timer and candy wheel UI entry flow
- `src/StarterPlayer/StarterPlayerScripts/LoadingScreenController.client.lua` owns the startup loading-screen gating and fade-out timing

Documentation:
- `docs/` is the project memory source for architecture, configs, networking, mechanics, and change facts
