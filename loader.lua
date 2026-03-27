local function normalizeName(value)
    return string.lower(tostring(value or ""))
end

local function getRuntimeGameName()
    local fallbackName = game.Name
    local marketplaceService = game:GetService("MarketplaceService")

    local productInfoOk, productInfo = pcall(function()
        return marketplaceService:GetProductInfo(game.PlaceId)
    end)

    if productInfoOk and type(productInfo) == "table" and productInfo.Name then
        return productInfo.Name
    end

    return fallbackName
end

local function runChunk(label, source)
    local chunk = loadstring(source)
    if not chunk then
        error(string.format("[LuminaLoader] failed to compile %s", tostring(label)))
    end

    local ok, err = pcall(chunk)
    if not ok then
        error(string.format("[LuminaLoader] %s failed: %s", tostring(label), tostring(err)))
    end
end

local runtimeName = getRuntimeGameName()
local normalizedRuntimeName = normalizeName(runtimeName)
local normalizedGameName = normalizeName(game.Name)

local mainSource = [================[
-- Minimal bootstrap: keep startup close to second.lua because the heavier boot path crashes in Madium
local RuntimeEnv = nil
-- selene: allow(incorrect_standard_library_use)
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()
local LoggedRuntimeErrors = {}

local function AppendBootLogLine(_)
end

local function LogBoot(_)
end

-- Services
local Players = game:GetService("Players")
local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Remotes / values
local Remote = ReplicatedStorage:WaitForChild("RemoteEvent")
local CompValue = ReplicatedStorage:WaitForChild("ComputersLeft")
local IsGameActiveValue = ReplicatedStorage:WaitForChild("IsGameActive")
local CurrentPowerValue = ReplicatedStorage:FindFirstChild("CurrentPower")

-- States
local Toggles = {
    ActionBoost = false,
    PlayerESP = false,
    PlayerOutlineESP = false,
    ShowBeastESP = false,
    ShowSurvivorESP = false,
    PlayerTracers = false,
    PlayerBoxes = false,
    PlayerNameESP = false,
    PlayerSkeletonESP = false,
    PlayerDistanceText = false,
    ObjectESP = false,
    ComputerV2ESP = false,
    BestComputerESP = false,
    FreezePodESP = false,
    AutoSafeExit = false,
    AutoHammerHit = false,
    AutoHammerTieUp = false,
    BeastProximityInvisibility = false,
    FullRoundInvisibility = false,
    BeastRadar = false,
    BeastETARadar = false,
    SprintBoost = false,
    NoClip = false,
    FogRemover = false,
    RemoteRescue = false,
    AutoNotifyPower = false
}

local Colors = {
    BeastColor = Color3.fromRGB(255, 0, 50),
    SurvivorColor = Color3.fromRGB(255, 200, 0),
    ComputerColor = Color3.fromRGB(0, 255, 255),
    BestComputerColor = Color3.fromRGB(255, 215, 0),
    ExitColor = Color3.fromRGB(255, 255, 0),
    FreezePodColor = Color3.fromRGB(160, 255, 255)
}

local ActionProgress = nil
local isRunning = true
local EnableStartupWorkspaceCleanup = false
local ActionBoostThread = nil
local MainLoopThread = nil
local VisibilityLoopThread = nil
local AutoEscapeTriggered = false
local InvisibilityActive = false
local OriginalVisualStates = setmetatable({}, { __mode = "k" })
local FEInvisibilityActive = false
local FEInvisibilitySeat = nil
local FEInvisibilitySeatName = "LuminaInvisSeat"
local FESeatTeleportPosition = Vector3.new(-25.95, 400, 3537.55)
local BeastRadarDistance = 35
local BeastETARange = 120
local BeastRadarGui = nil
local BeastRadarLabel = nil
local BeastETALabel = nil
local SprintTargetSpeed = 22
local SprintOriginalWalkSpeed = nil
local SprintOriginalNormalWalkSpeed = nil
local SprintOriginalSpeedMulti = nil
local SprintTrackedCharacter = nil
local OriginalCameraSubject = nil
local OriginalCameraType = nil
local OriginalCameraMode = nil
local OriginalCameraMinZoomDistance = nil
local OriginalCameraMaxZoomDistance = nil
local OriginalBeastSoundStates = setmetatable({}, { __mode = "k" })
local OriginalBeastGlowStates = setmetatable({}, { __mode = "k" })
local WallHopHighlights = setmetatable({}, { __mode = "k" })
local WallHopViewerScanInterval = 0.75
local LastWallHopViewerScan = 0
local NoClipOriginalCollisionStates = setmetatable({}, { __mode = "k" })
local OriginalFogEnd = nil
local OriginalBrightness = nil
local RemoteRescueDistance = 20
local RemoteRescueCooldown = 0.75
local LastRemoteRescueTimes = setmetatable({}, { __mode = "k" })
local RoundStatusGui = nil
local RoundStatusLabel = nil
local PlayerESPGui = nil
local PlayerESPObjects = {}
local BeastAutoHitDistance = 7
local BeastAutoTieUpDistance = 7
local BeastHammerCooldown = 0.35
local LastBeastHammerTime = 0
local PowerNotifyConnection = nil
local RenderSteppedConnection = nil
local PlayerRemovingConnection = nil
local WindowTitleText = "vesper.lua"
local WindowFooterText = "v0.1"
local IsRoundActive
local UIBuilding = true
local StartRuntimeOnBoot = true

local function ResolveCurrentPowerValue()
    if CurrentPowerValue and CurrentPowerValue.Parent == ReplicatedStorage then
        return CurrentPowerValue
    end

    CurrentPowerValue = ReplicatedStorage:FindFirstChild("CurrentPower")
    return CurrentPowerValue
end

local function WaitForCurrentCamera()
    while not Workspace.CurrentCamera do
        Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
    end

    return Workspace.CurrentCamera
end

local function SafeCall(label, callback, ...)
    local args = table.pack(...)
    local success, result = xpcall(function()
        return callback(table.unpack(args, 1, args.n))
    end, function(err)
        return debug.traceback(string.format("Lumina runtime [%s]: %s", label, tostring(err)), 2)
    end)

    if not success then
        if not LoggedRuntimeErrors[result] then
            LoggedRuntimeErrors[result] = true
            warn(result)
            AppendBootLogLine("[Lumina] " .. tostring(result))
        end
    end

    return success, result
end

-- Find ActionProgress safely
local function FindActionProgress()
    local StatsFolder = LP:FindFirstChild("TempPlayerStatsModule")
    if not StatsFolder then
        StatsFolder = LP:WaitForChild("TempPlayerStatsModule", 5)
    end

    if StatsFolder then
        ActionProgress = StatsFolder:FindFirstChild("ActionProgress")
        if not ActionProgress then
            ActionProgress = StatsFolder:WaitForChild("ActionProgress", 5)
        end
    end

    return ActionProgress ~= nil
end

local function CleanupExistingLuminaArtifacts()
    local guiNames = {
        "LuminaPlayerESP",
        "LuminaBeastRadar",
        "LuminaRoundStatus"
    }

    for _, guiName in ipairs(guiNames) do
        local existingGui = PlayerGui:FindFirstChild(guiName)
        if existingGui then
            existingGui:Destroy()
        end
    end

    local artifactNames = {
        "LuminaCompTag",
        "LuminaCompV2",
        "LuminaBestComp",
        "LuminaExitTag",
        "LuminaFreezePodTag",
        "LuminaWallHop",
        "LuminaHighlight"
    }

    if EnableStartupWorkspaceCleanup then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            for _, artifactName in ipairs(artifactNames) do
                local artifact = obj:FindFirstChild(artifactName)
                if artifact then
                    artifact:Destroy()
                end
            end
        end
    end
end

CleanupExistingLuminaArtifacts()

-- Action booster
local function StartActionBoost()
    while isRunning do
        SafeCall("ActionBoostLoop", function()
            if not ActionProgress or not ActionProgress.Parent then
                FindActionProgress()
            end

            if Toggles.ActionBoost and ActionProgress and ActionProgress.Value > 0 then
                for _ = 1, 8 do
                    Remote:FireServer("SetPlayerMinigameResult", true)
                end
            end
        end)

        task.wait(0.1)
    end
end

local function GetCharacterRoot(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character.PrimaryPart
end

local function GetCharacterTorso(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
end

local function GetCharacterHumanoid(character)
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function GetNoClipParts(character)
    if not character then
        return {}
    end

    local parts = {}
    local partNames = {
        "HumanoidRootPart",
        "Torso",
        "UpperTorso",
        "LowerTorso"
    }

    for _, partName in ipairs(partNames) do
        local part = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            table.insert(parts, part)
        end
    end

    return parts
end

local function GetBeastCharacter()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character and player.Character:FindFirstChild("BeastPowers") then
            return player.Character
        end
    end

    return nil
end

local function GetBeastPlayer()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character and player.Character:FindFirstChild("BeastPowers") then
            return player
        end
    end

    return nil
end

IsRoundActive = function()
    return IsGameActiveValue and IsGameActiveValue.Value == true
end

local function GetCurrentBeastPower()
    local powerValue = ResolveCurrentPowerValue()
    if not powerValue then
        return nil
    end

    local powerName = tostring(powerValue.Value or "")
    if powerName == "" then
        return nil
    end

    return powerName
end

local function GetSpeedMultiValue()
    local statsFolder = LP:FindFirstChild("TempPlayerStatsModule")
    if not statsFolder then
        return nil
    end

    local speedMulti = statsFolder:FindFirstChild("SpeedMulti")
    if speedMulti and (speedMulti:IsA("NumberValue") or speedMulti:IsA("IntValue")) then
        return speedMulti
    end

    return nil
end

local function GetTempNumberStat(player, statName)
    if not player then
        return nil
    end

    local statsFolder = player:FindFirstChild("TempPlayerStatsModule")
    if not statsFolder then
        return nil
    end

    local stat = statsFolder:FindFirstChild(statName)
    if stat and (stat:IsA("NumberValue") or stat:IsA("IntValue")) then
        return stat
    end

    return nil
end

local function GetTempBoolStat(player, statName)
    if not player then
        return nil
    end

    local statsFolder = player:FindFirstChild("TempPlayerStatsModule")
    if not statsFolder then
        return nil
    end

    local stat = statsFolder:FindFirstChild(statName)
    if stat and stat:IsA("BoolValue") then
        return stat
    end

    return nil
end

local function ShouldShowPlayerTarget(isTargetBeast)
    if isTargetBeast then
        return Toggles.ShowBeastESP
    end

    return Toggles.ShowSurvivorESP
end

local function GetPlayerESPColor(isTargetBeast)
    return isTargetBeast and Colors.BeastColor or Colors.SurvivorColor
end

local function GetCharacterDistanceStuds(character)
    local localCharacter = LP.Character
    local localRoot = GetCharacterRoot(localCharacter)
    local targetRoot = GetCharacterRoot(character)
    if not localRoot or not targetRoot then
        return nil
    end

    return (localRoot.Position - targetRoot.Position).Magnitude
end

local function IsHackableComputerScreen(screen)
    if not screen or not screen:IsA("BasePart") then
        return false
    end

    local color = screen.Color
    local r = math.floor(color.R * 255)
    local g = math.floor(color.G * 255)
    local b = math.floor(color.B * 255)
    return r == 13 and g == 105 and b == 172
end

local function IsSolvedComputerScreen(screen)
    if not screen or not screen:IsA("BasePart") then
        return false
    end

    local color = screen.Color
    local r = math.floor(color.R * 255)
    local g = math.floor(color.G * 255)
    local b = math.floor(color.B * 255)
    return r == 40 and g == 127 and b == 71
end

local function GetComputerScreen(computerModel)
    if not computerModel then
        return nil
    end

    return computerModel:FindFirstChild("Screen") or computerModel:FindFirstChild("Monitor")
end

local function IsComputerModel(instance)
    if not instance or not instance:IsA("Model") then
        return false
    end

    local screen = GetComputerScreen(instance)
    if not screen or not screen:IsA("BasePart") then
        return false
    end

    return instance.Name == "ComputerTable"
        or instance:FindFirstChild("ComputerTrigger1") ~= nil
        or instance:FindFirstChild("ComputerTrigger2") ~= nil
        or instance:FindFirstChild("ComputerTrigger3") ~= nil
end

local function ComputerHasVisibleParts(computerModel)
    if not computerModel then
        return false
    end

    for _, descendant in ipairs(computerModel:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local lowerName = descendant.Name:lower()
            local isTriggerLike = lowerName:find("trigger", 1, true)
                or lowerName:find("actionsign", 1, true)
                or lowerName:find("touchtransmitter", 1, true)

            if descendant.Transparency < 0.95 and not isTriggerLike then
                return true
            end
        end
    end

    return false
end

local function CollectTrackedWorldObjects()
    local computerModels = {}
    local exitDoors = {}
    local freezePods = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if IsComputerModel(obj) then
            table.insert(computerModels, obj)
        elseif obj.Name == "ExitDoor" then
            table.insert(exitDoors, obj)
        elseif obj:IsA("Model") and obj.Name == "FreezePod" then
            table.insert(freezePods, obj)
        end
    end

    return computerModels, exitDoors, freezePods
end

local function GetNearestComputerModel(requireHackable, computerModels)
    local localRoot = GetCharacterRoot(LP.Character)
    if not localRoot then
        return nil
    end

    local models = computerModels
    if not models then
        models = select(1, CollectTrackedWorldObjects())
    end

    local bestComputerModel = nil
    local bestDistance = math.huge

    for _, obj in ipairs(models) do
        local screen = GetComputerScreen(obj)
        local isValidScreen = screen and screen:IsA("BasePart")

        if isValidScreen then
            local isEligible = true
            if requireHackable then
                isEligible = IsHackableComputerScreen(screen) and ComputerHasVisibleParts(obj)
            end

            if isEligible then
                local distance = (screen.Position - localRoot.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestComputerModel = obj
                end
            end
        end
    end

    return bestComputerModel
end

local function GetBestComputerModel(computerModels)
    return GetNearestComputerModel(true, computerModels)
end

local function GetBeastMovementSpeed()
    if not IsRoundActive() then
        return nil
    end

    local beastPlayer = GetBeastPlayer()
    local beastCharacter = beastPlayer and beastPlayer.Character
    local beastHumanoid = GetCharacterHumanoid(beastCharacter)
    local normalWalkSpeed = GetTempNumberStat(beastPlayer, "NormalWalkSpeed")
    local speedMulti = GetTempNumberStat(beastPlayer, "SpeedMulti")

    local speed = nil

    if normalWalkSpeed then
        speed = normalWalkSpeed.Value
        if speedMulti then
            speed = speed * math.max(speedMulti.Value, 0.01)
        end
    elseif beastHumanoid then
        speed = beastHumanoid.WalkSpeed
    end

    if speed and speed > 0 then
        return speed
    end

    return nil
end

local function IsLocalBeast()
    local character = LP.Character
    return character and character:FindFirstChild("BeastPowers") ~= nil
end

local function GetLocalHammer()
    local character = LP.Character
    if character then
        local hammer = character:FindFirstChild("Hammer")
        if hammer and hammer:FindFirstChild("HammerEvent") then
            return hammer
        end
    end

    local backpack = LP:FindFirstChildOfClass("Backpack")
    if backpack then
        local hammer = backpack:FindFirstChild("Hammer")
        if hammer and hammer:FindFirstChild("HammerEvent") then
            return hammer
        end
    end

    return nil
end

local function GetLocalHammerEvent()
    local hammer = GetLocalHammer()
    if not hammer then
        return nil
    end

    local hammerEvent = hammer:FindFirstChild("HammerEvent")
    if hammerEvent and hammerEvent:IsA("RemoteEvent") then
        return hammerEvent
    end

    return nil
end

local function GetClosestCharacterHitPart(character, fromPosition)
    if not character or not fromPosition then
        return nil, nil
    end

    local candidateNames = {
        "HumanoidRootPart",
        "UpperTorso",
        "Torso",
        "Head",
        "Left Arm",
        "Right Arm",
        "LeftHand",
        "RightHand"
    }

    local bestPart = nil
    local bestDistance = math.huge

    for _, partName in ipairs(candidateNames) do
        local part = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") and part.Transparency < 0.95 then
            local distance = (part.Position - fromPosition).Magnitude
            if distance < bestDistance then
                bestPart = part
                bestDistance = distance
            end
        end
    end

    if bestPart then
        return bestPart, bestDistance
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Transparency < 0.95 then
            local distance = (descendant.Position - fromPosition).Magnitude
            if distance < bestDistance then
                bestPart = descendant
                bestDistance = distance
            end
        end
    end

    return bestPart, bestDistance
end

local function GetClosestSurvivorHammerTarget(maxDistance, requireRagdoll)
    local localCharacter = LP.Character
    local localRoot = GetCharacterRoot(localCharacter)
    if not localRoot then
        return nil, nil, nil
    end

    local bestPart = nil
    local bestPlayer = nil
    local bestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP then
            local character = player.Character
            if character and not character:FindFirstChild("BeastPowers") then
                local humanoid = GetCharacterHumanoid(character)
                local healthStat = GetTempNumberStat(player, "Health")
                local ragdollStat = GetTempBoolStat(player, "Ragdoll")
                local capturedStat = GetTempBoolStat(player, "Captured")
                local escapedStat = GetTempBoolStat(player, "Escaped")

                local isAlive = (not humanoid or humanoid.Health > 0) and (not healthStat or healthStat.Value > 0)
                local isCaptured = capturedStat and capturedStat.Value == true
                local isEscaped = escapedStat and escapedStat.Value == true
                local isRagdolled = ragdollStat and ragdollStat.Value == true

                if isAlive and not isCaptured and not isEscaped then
                    if (requireRagdoll and isRagdolled) or (not requireRagdoll and not isRagdolled) then
                        local hitPart, distance = GetClosestCharacterHitPart(character, localRoot.Position)
                        if hitPart and distance and distance <= maxDistance and distance < bestDistance then
                            bestPart = hitPart
                            bestPlayer = player
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end

    return bestPart, bestPlayer, bestDistance
end

local function FireLocalHammerAction(actionName, hitPart)
    if not actionName or not hitPart then
        return false
    end

    local hammerEvent = GetLocalHammerEvent()
    if not hammerEvent then
        return false
    end

    local now = tick()
    if now - LastBeastHammerTime < BeastHammerCooldown then
        return false
    end

    hammerEvent:FireServer("HammerClick", true)

    if actionName == "HammerTieUp" then
        hammerEvent:FireServer(actionName, hitPart, hitPart.Position)
    else
        hammerEvent:FireServer(actionName, hitPart)
    end

    LastBeastHammerTime = now
    return true
end

local function FormatStatValue(valueObject)
    if not valueObject then
        return "nil"
    end

    local success, result = pcall(function()
        return tostring(valueObject.Value)
    end)

    if success then
        return result
    end

    return "<unreadable>"
end

local function DumpStatFolder(folder, folderLabel)
    if not folder then
        print(string.format("Lumina Hub: %s not found.", folderLabel))
        return
    end

    print(string.format("Lumina Hub: %s", folderLabel))

    local children = folder:GetChildren()
    table.sort(children, function(a, b)
        return a.Name < b.Name
    end)

    for _, child in ipairs(children) do
        if child:IsA("ValueBase") then
            print(string.format("  %s [%s] = %s", child.Name, child.ClassName, FormatStatValue(child)))
        end
    end
end

local function DumpBeastStats()
    local beastPlayer = GetBeastPlayer()
    if not beastPlayer then
        warn("Lumina Hub: no Beast player is currently available.")
        return false
    end

    print(string.rep("=", 48))
    print(string.format("Lumina Hub: Beast stat dump for %s", beastPlayer.Name))
    DumpStatFolder(beastPlayer:FindFirstChild("SavedPlayerStatsModule"), "SavedPlayerStatsModule")
    DumpStatFolder(beastPlayer:FindFirstChild("TempPlayerStatsModule"), "TempPlayerStatsModule")
    print(string.rep("=", 48))
    return true
end

local function GetExitAnchor(exitDoor)
    if not exitDoor then
        return nil
    end

    local trigger = exitDoor:FindFirstChild("ExitDoorTrigger")
    if trigger and trigger:IsA("BasePart") then
        return trigger
    end

    if exitDoor:IsA("Model") then
        if exitDoor.PrimaryPart then
            return exitDoor.PrimaryPart
        end

        return exitDoor:FindFirstChildWhichIsA("BasePart", true)
    end

    if exitDoor:IsA("BasePart") then
        return exitDoor
    end

    return nil
end

local function GetModelAnchor(model)
    if not model then
        return nil
    end

    if model:IsA("BasePart") then
        return model
    end

    if model:IsA("Model") then
        if model.PrimaryPart then
            return model.PrimaryPart
        end

        return model:FindFirstChildWhichIsA("BasePart", true)
    end

    return nil
end

local function GetSafestExitDoor()
    local exitDoors = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name == "ExitDoor" then
            local anchor = GetExitAnchor(obj)
            if anchor then
                table.insert(exitDoors, {
                    Door = obj,
                    Anchor = anchor
                })
            end
        end
    end

    if #exitDoors == 0 then
        return nil
    end

    local beastCharacter = GetBeastCharacter()
    local beastRoot = GetCharacterRoot(beastCharacter)

    if not beastRoot then
        return exitDoors[1]
    end

    local safestDoor = nil
    local furthestDistance = -math.huge

    for _, exitInfo in ipairs(exitDoors) do
        local distance = (exitInfo.Anchor.Position - beastRoot.Position).Magnitude
        if distance > furthestDistance then
            furthestDistance = distance
            safestDoor = exitInfo
        end
    end

    return safestDoor
end

local function TeleportToSafeExit()
    local character = LP.Character
    local root = GetCharacterRoot(character)
    if not character or not root then
        return false
    end

    local safestDoor = GetSafestExitDoor()
    if not safestDoor or not safestDoor.Anchor then
        return false
    end

    local targetCFrame = safestDoor.Anchor.CFrame * CFrame.new(0, 3, 0)
    character:PivotTo(targetCFrame)
    return true
end

local function HandleAutoSafeExit()
    if not CompValue then
        return
    end

    local localCharacter = LP.Character
    if localCharacter and localCharacter:FindFirstChild("BeastPowers") then
        AutoEscapeTriggered = false
        return
    end

    if CompValue.Value > 0 then
        AutoEscapeTriggered = false
        return
    end

    if not Toggles.AutoSafeExit or AutoEscapeTriggered then
        return
    end

    AutoEscapeTriggered = TeleportToSafeExit()
end

local function GetBeastHeartbeatSound()
    local beastCharacter = GetBeastCharacter()
    if not beastCharacter then
        return nil
    end

    local sound = beastCharacter:FindFirstChild("SoundHeartBeat", true)
    if sound and sound:IsA("Sound") then
        return sound
    end

    return nil
end

local function GetBeastDistance()
    if not IsRoundActive() then
        return nil
    end

    local character = LP.Character
    if not character or character:FindFirstChild("BeastPowers") then
        return nil
    end

    local localRoot = GetCharacterRoot(character)
    local beastCharacter = GetBeastCharacter()
    local beastRoot = GetCharacterRoot(beastCharacter)
    if not localRoot or not beastRoot then
        return nil
    end

    return (localRoot.Position - beastRoot.Position).Magnitude
end

local function EnsureRoundStatusUI()
    if RoundStatusGui and RoundStatusGui.Parent and RoundStatusLabel then
        return
    end

    if RoundStatusGui then
        pcall(function()
            RoundStatusGui:Destroy()
        end)
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LuminaRoundStatus"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    local label = Instance.new("TextLabel")
    label.Name = "RoundLabel"
    label.AnchorPoint = Vector2.new(1, 0)
    label.Position = UDim2.new(1, -18, 0, 24)
    label.Size = UDim2.fromOffset(220, 36)
    label.BackgroundColor3 = Color3.fromRGB(160, 115, 20)
    label.BackgroundTransparency = 0.15
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Text = "ROUND: WAITING"
    label.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = label

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 240, 200)
    stroke.Thickness = 2
    stroke.Parent = label

    RoundStatusGui = screenGui
    RoundStatusLabel = label
end

local function UpdateRoundStatusUI()
    EnsureRoundStatusUI()

    if not RoundStatusLabel then
        return
    end

    if IsRoundActive() then
        RoundStatusLabel.Text = "ROUND: ACTIVE"
        RoundStatusLabel.BackgroundColor3 = Color3.fromRGB(24, 120, 48)
    else
        RoundStatusLabel.Text = "ROUND: WAITING / HEAD START"
        RoundStatusLabel.BackgroundColor3 = Color3.fromRGB(160, 115, 20)
    end
end

local function EnsureBeastRadarUI()
    if BeastRadarGui and BeastRadarGui.Parent and BeastRadarLabel and BeastETALabel then
        return
    end

    if BeastRadarGui then
        pcall(function()
            BeastRadarGui:Destroy()
        end)
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LuminaBeastRadar"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    local label = Instance.new("TextLabel")
    label.Name = "WarningLabel"
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 24)
    label.Size = UDim2.fromOffset(360, 48)
    label.BackgroundColor3 = Color3.fromRGB(145, 15, 15)
    label.BackgroundTransparency = 0.15
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Text = "BEAST NEARBY"
    label.Visible = false
    label.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = label

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 220, 220)
    stroke.Thickness = 2
    stroke.Parent = label

    local etaLabel = Instance.new("TextLabel")
    etaLabel.Name = "ETALabel"
    etaLabel.AnchorPoint = Vector2.new(0.5, 0)
    etaLabel.Position = UDim2.new(0.5, 0, 0, 78)
    etaLabel.Size = UDim2.fromOffset(340, 34)
    etaLabel.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
    etaLabel.BackgroundTransparency = 0.2
    etaLabel.BorderSizePixel = 0
    etaLabel.Font = Enum.Font.GothamMedium
    etaLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    etaLabel.TextScaled = true
    etaLabel.Text = "ETA: --"
    etaLabel.Visible = false
    etaLabel.Parent = screenGui

    local etaCorner = Instance.new("UICorner")
    etaCorner.CornerRadius = UDim.new(0, 12)
    etaCorner.Parent = etaLabel

    local etaStroke = Instance.new("UIStroke")
    etaStroke.Color = Color3.fromRGB(210, 210, 210)
    etaStroke.Thickness = 1.5
    etaStroke.Parent = etaLabel

    BeastRadarGui = screenGui
    BeastRadarLabel = label
    BeastETALabel = etaLabel
end

local function SetBeastRadarVisible(visible, distance)
    if not BeastRadarLabel then
        if not visible then
            return
        end

        EnsureBeastRadarUI()
    end

    if not BeastRadarLabel then
        return
    end

    BeastRadarLabel.Visible = visible
    if visible and distance then
        BeastRadarLabel.Text = string.format("BEAST NEARBY - %d STUDS", math.floor(distance + 0.5))
    end
end

local function SetBeastETAVisible(visible, distance, etaSeconds, beastSpeed)
    if not BeastETALabel then
        if not visible then
            return
        end

        EnsureBeastRadarUI()
    end

    if not BeastETALabel then
        return
    end

    BeastETALabel.Visible = visible
    if visible and distance and etaSeconds and beastSpeed then
        BeastETALabel.Text = string.format(
            "ETA %.1fs | %d studs | speed %.1f",
            etaSeconds,
            math.floor(distance + 0.5),
            beastSpeed
        )

        if etaSeconds <= 2 then
            BeastETALabel.BackgroundColor3 = Color3.fromRGB(145, 25, 25)
        elseif etaSeconds <= 4 then
            BeastETALabel.BackgroundColor3 = Color3.fromRGB(160, 105, 24)
        else
            BeastETALabel.BackgroundColor3 = Color3.fromRGB(28, 95, 36)
        end
    end
end

local function DestroyInvisibilitySeat()
    if FEInvisibilitySeat and FEInvisibilitySeat.Parent then
        pcall(function()
            FEInvisibilitySeat:Destroy()
        end)
    end

    FEInvisibilitySeat = nil

    local leftoverSeat = Workspace:FindFirstChild(FEInvisibilitySeatName)
    if leftoverSeat then
        pcall(function()
            leftoverSeat:Destroy()
        end)
    end
end

local function CacheVisualProperty(instance, propertyName, value)
    local visualState = OriginalVisualStates[instance]
    if not visualState then
        visualState = {}
        OriginalVisualStates[instance] = visualState
    end

    if visualState[propertyName] == nil then
        visualState[propertyName] = value
    end
end

local function ApplyHiddenVisual(instance)
    if instance:IsA("BasePart") then
        CacheVisualProperty(instance, "Transparency", instance.Transparency)
        CacheVisualProperty(instance, "LocalTransparencyModifier", instance.LocalTransparencyModifier)
        instance.Transparency = 1
        instance.LocalTransparencyModifier = 1
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        CacheVisualProperty(instance, "Transparency", instance.Transparency)
        instance.Transparency = 1
    elseif instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") or instance:IsA("Highlight")
        or instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
        or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") then
        CacheVisualProperty(instance, "Enabled", instance.Enabled)
        instance.Enabled = false
    end
end

local function RestoreVisual(instance)
    local visualState = OriginalVisualStates[instance]
    if not visualState then
        return
    end

    for propertyName, propertyValue in pairs(visualState) do
        pcall(function()
            instance[propertyName] = propertyValue
        end)
    end

    OriginalVisualStates[instance] = nil
end

local function ApplyCharacterInvisibility(character)
    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        ApplyHiddenVisual(descendant)
    end
end

local function EnableFEInvisibility(character)
    if not character then
        return false
    end

    local humanoidRootPart = GetCharacterRoot(character)
    local torso = GetCharacterTorso(character)
    if not humanoidRootPart or not torso then
        return false
    end

    DestroyInvisibilitySeat()

    local savedCFrame = humanoidRootPart.CFrame
    pcall(function()
        character:MoveTo(FESeatTeleportPosition)
    end)
    task.wait(0.05)

    local currentRoot = GetCharacterRoot(character)
    if not currentRoot or currentRoot.Position.Y < -100 then
        pcall(function()
            character:PivotTo(savedCFrame)
        end)
        return false
    end

    local seat = Instance.new("Seat")
    seat.Name = FEInvisibilitySeatName
    seat.Parent = Workspace
    seat.Anchored = false
    seat.CanCollide = false
    seat.Transparency = 1
    seat.Position = FESeatTeleportPosition

    local weld = Instance.new("Weld")
    weld.Part0 = seat
    weld.Part1 = torso
    weld.Parent = seat

    task.wait()
    pcall(function()
        seat.CFrame = savedCFrame
    end)

    FEInvisibilitySeat = seat
    FEInvisibilityActive = true
    ApplyCharacterInvisibility(character)
    return true
end

local function RestoreCharacterVisibility(character)
    if not character then
        InvisibilityActive = false
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        RestoreVisual(descendant)
    end
end

local function DisableFEInvisibility(character)
    FEInvisibilityActive = false
    DestroyInvisibilitySeat()
    RestoreCharacterVisibility(character)
end

local function ShouldCharacterBeInvisible()
    local character = LP.Character
    if not character then
        return false
    end

    if Toggles.FullRoundInvisibility then
        return true
    end

    if not Toggles.BeastProximityInvisibility then
        return false
    end

    if character:FindFirstChild("BeastPowers") then
        return false
    end

    local beastDistance = GetBeastDistance()
    if not beastDistance then
        return false
    end

    local heartbeatSound = GetBeastHeartbeatSound()
    local maxDistance = heartbeatSound and heartbeatSound.RollOffMaxDistance or 60
    return beastDistance <= maxDistance
end

local function UpdateBeastRadar()
    if not Toggles.BeastRadar then
        SetBeastRadarVisible(false)
        return
    end

    local beastDistance = GetBeastDistance()
    if beastDistance and beastDistance <= BeastRadarDistance then
        SetBeastRadarVisible(true, beastDistance)
    else
        SetBeastRadarVisible(false)
    end
end

local function UpdateBeastETARadar()
    if not Toggles.BeastETARadar then
        SetBeastETAVisible(false)
        return
    end

    local beastDistance = GetBeastDistance()
    local beastSpeed = GetBeastMovementSpeed()

    if beastDistance and beastSpeed and beastSpeed > 0 and beastDistance <= BeastETARange then
        local etaSeconds = beastDistance / beastSpeed
        SetBeastETAVisible(true, beastDistance, etaSeconds, beastSpeed)
    else
        SetBeastETAVisible(false)
    end
end

local function UpdateSprintState()
    local character = LP.Character
    local humanoid = GetCharacterHumanoid(character)
    local normalWalkSpeed = GetTempNumberStat(LP, "NormalWalkSpeed")
    local speedMulti = GetSpeedMultiValue()

    if character ~= SprintTrackedCharacter then
        SprintTrackedCharacter = character
        SprintOriginalNormalWalkSpeed = nil
        SprintOriginalSpeedMulti = nil
        SprintOriginalWalkSpeed = nil
    end

    if not Toggles.SprintBoost then
        if normalWalkSpeed and SprintOriginalNormalWalkSpeed ~= nil then
            normalWalkSpeed.Value = SprintOriginalNormalWalkSpeed
        end

        if speedMulti and SprintOriginalSpeedMulti ~= nil then
            speedMulti.Value = SprintOriginalSpeedMulti
        end

        if humanoid and SprintOriginalWalkSpeed ~= nil then
            humanoid.WalkSpeed = SprintOriginalWalkSpeed
        end

        SprintOriginalNormalWalkSpeed = nil
        SprintOriginalSpeedMulti = nil
        SprintOriginalWalkSpeed = nil
        SprintTrackedCharacter = character
        return
    end

    if not character or character:FindFirstChild("BeastPowers") then
        return
    end

    if humanoid and SprintOriginalWalkSpeed == nil then
        SprintOriginalWalkSpeed = humanoid.WalkSpeed
    end

    if normalWalkSpeed and SprintOriginalNormalWalkSpeed == nil then
        SprintOriginalNormalWalkSpeed = normalWalkSpeed.Value
    end

    if speedMulti and SprintOriginalSpeedMulti == nil then
        SprintOriginalSpeedMulti = speedMulti.Value
    end

    if speedMulti then
        local baseSpeed = SprintOriginalNormalWalkSpeed
            or SprintOriginalWalkSpeed
            or (humanoid and humanoid.WalkSpeed)
            or 16
        speedMulti.Value = SprintTargetSpeed / math.max(baseSpeed, 1)
    elseif normalWalkSpeed then
        normalWalkSpeed.Value = SprintTargetSpeed
    end

    if humanoid then
        humanoid.WalkSpeed = SprintTargetSpeed
    end
end

-- selene: allow(unused_variable)
local function UpdateNoSlowState()
    if not Toggles.NoSlow then
        return
    end

    local character = LP.Character
    if not character or not character:FindFirstChild("BeastPowers") then
        return
    end

    local speedMulti = GetSpeedMultiValue()
    if speedMulti and speedMulti.Value < 1 then
        speedMulti.Value = 1
    end
end

local function RestoreUnlockCameraState()
    local camera = Workspace.CurrentCamera

    if OriginalCameraMode ~= nil then
        pcall(function()
            LP.CameraMode = OriginalCameraMode
        end)
        OriginalCameraMode = nil
    end

    if OriginalCameraMinZoomDistance ~= nil then
        pcall(function()
            LP.CameraMinZoomDistance = OriginalCameraMinZoomDistance
        end)
        OriginalCameraMinZoomDistance = nil
    end

    if OriginalCameraMaxZoomDistance ~= nil then
        pcall(function()
            LP.CameraMaxZoomDistance = OriginalCameraMaxZoomDistance
        end)
        OriginalCameraMaxZoomDistance = nil
    end

    if camera and OriginalCameraSubject ~= nil then
        pcall(function()
            camera.CameraSubject = OriginalCameraSubject
        end)
        OriginalCameraSubject = nil
    end

    if camera and OriginalCameraType ~= nil then
        pcall(function()
            camera.CameraType = OriginalCameraType
        end)
        OriginalCameraType = nil
    end
end

-- selene: allow(unused_variable)
local function UpdateUnlockCameraState()
    local character = LP.Character
    local camera = Workspace.CurrentCamera
    local humanoid = GetCharacterHumanoid(character)

    if not Toggles.UnlockCamera or not character or not character:FindFirstChild("BeastPowers") or not camera or not humanoid then
        RestoreUnlockCameraState()
        return
    end

    if OriginalCameraMode == nil then
        OriginalCameraMode = LP.CameraMode
    end

    if OriginalCameraMinZoomDistance == nil then
        OriginalCameraMinZoomDistance = LP.CameraMinZoomDistance
    end

    if OriginalCameraMaxZoomDistance == nil then
        OriginalCameraMaxZoomDistance = LP.CameraMaxZoomDistance
    end

    if OriginalCameraSubject == nil then
        OriginalCameraSubject = camera.CameraSubject
    end

    if OriginalCameraType == nil then
        OriginalCameraType = camera.CameraType
    end

    pcall(function()
        LP.CameraMode = Enum.CameraMode.Classic
        LP.CameraMinZoomDistance = 0.5
        LP.CameraMaxZoomDistance = math.max(OriginalCameraMaxZoomDistance or 12, 12)
    end)

    camera.CameraSubject = humanoid
    camera.CameraType = Enum.CameraType.Custom
end

local function RestoreBeastSoundGlowState()
    for instance, state in pairs(OriginalBeastSoundStates) do
        if instance and instance.Parent and state then
            if state.Volume ~= nil then
                pcall(function()
                    instance.Volume = state.Volume
                end)
            end

            if state.RollOffMaxDistance ~= nil then
                pcall(function()
                    instance.RollOffMaxDistance = state.RollOffMaxDistance
                end)
            end
        end

        OriginalBeastSoundStates[instance] = nil
    end

    for instance, state in pairs(OriginalBeastGlowStates) do
        if instance and instance.Parent and state then
            for propertyName, propertyValue in pairs(state) do
                pcall(function()
                    instance[propertyName] = propertyValue
                end)
            end
        end

        OriginalBeastGlowStates[instance] = nil
    end
end

local function CacheBeastGlowState(instance)
    if OriginalBeastGlowStates[instance] then
        return
    end

    local state = {}

    if instance:IsA("Highlight") then
        state.FillTransparency = instance.FillTransparency
        state.OutlineTransparency = instance.OutlineTransparency
    elseif instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("BillboardGui")
        or instance:IsA("SurfaceGui")
    then
        state.Enabled = instance.Enabled
    elseif instance:IsA("BasePart") then
        state.Transparency = instance.Transparency
    end

    if next(state) then
        OriginalBeastGlowStates[instance] = state
    end
end

local function HideBeastGlow(instance)
    if instance:IsA("Highlight") then
        instance.FillTransparency = 1
        instance.OutlineTransparency = 1
    elseif instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight")
        or instance:IsA("BillboardGui")
        or instance:IsA("SurfaceGui")
    then
        instance.Enabled = false
    elseif instance:IsA("BasePart") then
        instance.Transparency = 1
    end
end

-- selene: allow(unused_variable)
local function UpdateRemoveSoundGlowState()
    local character = LP.Character
    if not Toggles.RemoveSoundGlow or not character or not character:FindFirstChild("BeastPowers") then
        RestoreBeastSoundGlowState()
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Sound") then
            if not OriginalBeastSoundStates[descendant] then
                OriginalBeastSoundStates[descendant] = {
                    Volume = descendant.Volume,
                    RollOffMaxDistance = descendant.RollOffMaxDistance
                }
            end

            descendant.Volume = 0
            descendant.RollOffMaxDistance = 0
        else
            local lowerName = descendant.Name:lower()
            if lowerName:find("glow", 1, true) or lowerName:find("aura", 1, true) then
                CacheBeastGlowState(descendant)
                HideBeastGlow(descendant)
            end
        end
    end
end

local function ClearWallHopViewerState()
    for part, highlight in pairs(WallHopHighlights) do
        if highlight and highlight.Parent then
            highlight:Destroy()
        end

        WallHopHighlights[part] = nil
    end
end

-- selene: allow(unused_variable)
local function UpdateWallHopViewer()
    if not Toggles.WallHopViewer then
        ClearWallHopViewerState()
        return
    end

    local character = LP.Character
    local root = GetCharacterRoot(character)
    if not root then
        ClearWallHopViewerState()
        return
    end

    local now = tick()
    if now - LastWallHopViewerScan < WallHopViewerScanInterval then
        return
    end
    LastWallHopViewerScan = now

    local activeParts = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") then
            local lowerName = obj.Name:lower()
            local looksLikeWallHop = lowerName:find("wall", 1, true) or lowerName:find("hop", 1, true)
            if looksLikeWallHop and (obj.Position - root.Position).Magnitude <= 15 then
                activeParts[obj] = true

                local highlight = WallHopHighlights[obj]
                if not highlight or not highlight.Parent then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "LuminaWallHop"
                    highlight.FillColor = Color3.fromRGB(255, 200, 0)
                    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                    highlight.FillTransparency = 0.55
                    highlight.OutlineTransparency = 0.1
                    highlight.Adornee = obj
                    highlight.Parent = obj
                    WallHopHighlights[obj] = highlight
                else
                    highlight.Adornee = obj
                end
            end
        end
    end

    for part, highlight in pairs(WallHopHighlights) do
        if not activeParts[part] then
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
            WallHopHighlights[part] = nil
        end
    end
end

local function UpdateNoClipState()
    local character = LP.Character
    local parts = GetNoClipParts(character)

    if not Toggles.NoClip then
        for _, part in ipairs(parts) do
            local originalState = NoClipOriginalCollisionStates[part]
            if originalState ~= nil then
                part.CanCollide = originalState
                NoClipOriginalCollisionStates[part] = nil
            end
        end
        return
    end

    for _, part in ipairs(parts) do
        if NoClipOriginalCollisionStates[part] == nil then
            NoClipOriginalCollisionStates[part] = part.CanCollide
        end

        part.CanCollide = false
    end
end

local function UpdateFogRemoverState()
    if not Toggles.FogRemover then
        if OriginalFogEnd ~= nil then
            Lighting.FogEnd = OriginalFogEnd
        end

        if OriginalBrightness ~= nil then
            Lighting.Brightness = OriginalBrightness
        end

        OriginalFogEnd = nil
        OriginalBrightness = nil
        return
    end

    if OriginalFogEnd == nil then
        OriginalFogEnd = Lighting.FogEnd
    end

    if OriginalBrightness == nil then
        OriginalBrightness = Lighting.Brightness
    end

    Lighting.FogEnd = 999999
    Lighting.Brightness = 2
end

local function FreezePodLooksActive(pod)
    if not pod then
        return false
    end

    local activeAttributes = {
        "Active",
        "Occupied",
        "Captured",
        "Frozen",
        "InUse"
    }

    for _, attributeName in ipairs(activeAttributes) do
        if pod:GetAttribute(attributeName) == true then
            return true
        end
    end

    for _, descendant in ipairs(pod:GetDescendants()) do
        local lowerName = descendant.Name:lower()
        local looksRelevant = lowerName:find("active", 1, true)
            or lowerName:find("occup", 1, true)
            or lowerName:find("captur", 1, true)
            or lowerName:find("froz", 1, true)
            or lowerName:find("inuse", 1, true)

        if looksRelevant then
            if descendant:IsA("BoolValue") and descendant.Value then
                return true
            end

            if (descendant:IsA("IntValue") or descendant:IsA("NumberValue")) and descendant.Value > 0 then
                return true
            end

            if descendant:IsA("ObjectValue") and descendant.Value ~= nil then
                return true
            end

            if descendant:IsA("StringValue") then
                local value = descendant.Value:lower()
                if value ~= "" and value ~= "false" and value ~= "0" and value ~= "inactive" and value ~= "empty" then
                    return true
                end
            end
        end
    end

    return false
end

local function UpdateRemoteRescueState()
    if not Toggles.RemoteRescue or not IsRoundActive() then
        return
    end

    local character = LP.Character
    if not character or character:FindFirstChild("BeastPowers") then
        return
    end

    local root = GetCharacterRoot(character)
    if not root then
        return
    end

    local now = tick()

    for _, pod in ipairs(Workspace:GetDescendants()) do
        if pod:IsA("Model") and pod.Name == "FreezePod" then
            local anchor = GetModelAnchor(pod)
            if anchor and (anchor.Position - root.Position).Magnitude <= RemoteRescueDistance and FreezePodLooksActive(pod) then
                local lastTriggerTime = LastRemoteRescueTimes[pod]
                if not lastTriggerTime or now - lastTriggerTime >= RemoteRescueCooldown then
                    Remote:FireServer("SaveSurvivor", pod)
                    LastRemoteRescueTimes[pod] = now
                end
            end
        end
    end
end

local function UpdateBeastHammerAutomation()
    if not IsRoundActive() or (not Toggles.AutoHammerHit and not Toggles.AutoHammerTieUp) then
        return
    end

    if not IsLocalBeast() then
        return
    end

    local character = LP.Character
    local humanoid = GetCharacterHumanoid(character)
    if not character or not humanoid or humanoid.Health <= 0 then
        return
    end

    local carriedTorso = character:FindFirstChild("CarriedTorso")
    if carriedTorso and carriedTorso:IsA("ObjectValue") and carriedTorso.Value then
        return
    end

    if Toggles.AutoHammerTieUp then
        local targetPart = GetClosestSurvivorHammerTarget(BeastAutoTieUpDistance, true)
        if targetPart and FireLocalHammerAction("HammerTieUp", targetPart) then
            return
        end
    end

    if Toggles.AutoHammerHit then
        local targetPart = GetClosestSurvivorHammerTarget(BeastAutoHitDistance, false)
        if targetPart then
            FireLocalHammerAction("HammerHit", targetPart)
        end
    end
end

local function UpdateInvisibilityState()
    local character = LP.Character
    local shouldBeInvisible = ShouldCharacterBeInvisible()

    if FEInvisibilityActive and (not FEInvisibilitySeat or not FEInvisibilitySeat.Parent) then
        FEInvisibilityActive = false
        FEInvisibilitySeat = nil
    end

    if shouldBeInvisible then
        if not FEInvisibilityActive then
            local enabled = EnableFEInvisibility(character)
            if not enabled then
                RestoreCharacterVisibility(character)
                InvisibilityActive = false
                return
            end
        else
            ApplyCharacterInvisibility(character)
        end
    elseif InvisibilityActive or FEInvisibilityActive then
        DisableFEInvisibility(character)
    end

    InvisibilityActive = shouldBeInvisible
end

local function StartVisibilityLoop()
    while isRunning do
        SafeCall("UpdateInvisibilityState", UpdateInvisibilityState)
        SafeCall("UpdateBeastRadar", UpdateBeastRadar)
        SafeCall("UpdateBeastETARadar", UpdateBeastETARadar)
        SafeCall("UpdateSprintState", UpdateSprintState)
        SafeCall("UpdateNoClipState", UpdateNoClipState)
        SafeCall("UpdateFogRemoverState", UpdateFogRemoverState)
        SafeCall("UpdateRemoteRescueState", UpdateRemoteRescueState)
        SafeCall("UpdateBeastHammerAutomation", UpdateBeastHammerAutomation)
        SafeCall("UpdateRoundStatusUI", UpdateRoundStatusUI)
        task.wait(0.15)
    end
end

-- Player ESP
local function HidePlayerESPEntry(entry)
    if not entry then
        return
    end

    if entry.Box then
        entry.Box.Visible = false
    end

    if entry.Tracer then
        entry.Tracer.Visible = false
    end

    if entry.Label then
        entry.Label.Visible = false
    end

    if entry.SkeletonLines then
        for _, line in ipairs(entry.SkeletonLines) do
            line.Visible = false
        end
    end
end

local function DestroyPlayerESPEntry(player)
    local entry = PlayerESPObjects[player]
    if not entry then
        return
    end

    if entry.Box and entry.Box.Parent then
        entry.Box:Destroy()
    end

    if entry.Tracer and entry.Tracer.Parent then
        entry.Tracer:Destroy()
    end

    if entry.Label and entry.Label.Parent then
        entry.Label:Destroy()
    end

    if entry.SkeletonLines then
        for _, line in ipairs(entry.SkeletonLines) do
            if line.Parent then
                line:Destroy()
            end
        end
    end

    PlayerESPObjects[player] = nil
end

local function ClearPlayerESPOverlay()
    for player, entry in pairs(PlayerESPObjects) do
        if player.Parent ~= Players then
            DestroyPlayerESPEntry(player)
        else
            HidePlayerESPEntry(entry)
        end
    end
end

local function EnsurePlayerESPOverlay()
    if PlayerESPGui and PlayerESPGui.Parent then
        return
    end

    if PlayerESPGui then
        pcall(function()
            PlayerESPGui:Destroy()
        end)
    end

    PlayerESPObjects = {}

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "LuminaPlayerESP"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = PlayerGui

    PlayerESPGui = screenGui
end

local function GetOrCreatePlayerESPEntry(player)
    local entry = PlayerESPObjects[player]
    if entry and entry.Box and entry.Box.Parent and entry.Tracer and entry.Tracer.Parent and entry.Label and entry.Label.Parent then
        return entry
    end

    EnsurePlayerESPOverlay()

    local box = Instance.new("Frame")
    box.Name = "ESPBox_" .. player.UserId
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false
    box.ZIndex = 10
    box.Parent = PlayerESPGui

    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 2
    boxStroke.Color = Color3.fromRGB(255, 255, 255)
    boxStroke.Parent = box

    local tracer = Instance.new("Frame")
    tracer.Name = "ESPTracer_" .. player.UserId
    tracer.AnchorPoint = Vector2.new(0, 0.5)
    tracer.BackgroundTransparency = 0.1
    tracer.BorderSizePixel = 0
    tracer.Visible = false
    tracer.ZIndex = 9
    tracer.Parent = PlayerESPGui

    local tracerCorner = Instance.new("UICorner")
    tracerCorner.CornerRadius = UDim.new(1, 0)
    tracerCorner.Parent = tracer

    local label = Instance.new("TextLabel")
    label.Name = "ESPLabel_" .. player.UserId
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
    label.BackgroundTransparency = 0.2
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = false
    label.TextSize = 14
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Visible = false
    label.ZIndex = 11
    label.Parent = PlayerESPGui

    local labelCorner = Instance.new("UICorner")
    labelCorner.CornerRadius = UDim.new(0, 8)
    labelCorner.Parent = label

    local labelStroke = Instance.new("UIStroke")
    labelStroke.Thickness = 1.5
    labelStroke.Color = Color3.fromRGB(255, 255, 255)
    labelStroke.Parent = label

    local skeletonLines = {}
    for index = 1, 20 do
        local line = Instance.new("Frame")
        line.Name = "ESPSkeleton_" .. player.UserId .. "_" .. index
        line.AnchorPoint = Vector2.new(0, 0.5)
        line.BackgroundTransparency = 0.05
        line.BorderSizePixel = 0
        line.Visible = false
        line.ZIndex = 8
        line.Parent = PlayerESPGui

        local lineCorner = Instance.new("UICorner")
        lineCorner.CornerRadius = UDim.new(1, 0)
        lineCorner.Parent = line

        skeletonLines[index] = line
    end

    entry = {
        Box = box,
        BoxStroke = boxStroke,
        Tracer = tracer,
        Label = label,
        LabelStroke = labelStroke,
        SkeletonLines = skeletonLines
    }

    PlayerESPObjects[player] = entry
    return entry
end

local function GetCharacterScreenBounds(character, camera)
    if not character or not camera then
        return nil
    end

    local root = GetCharacterRoot(character)
    if not root then
        return nil
    end

    local centerPoint, centerOnScreen = camera:WorldToViewportPoint(root.Position)
    if centerPoint.Z <= 0 or not centerOnScreen then
        return nil
    end

    local boxCFrame, boxSize = character:GetBoundingBox()
    local halfSize = boxSize * 0.5
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for x = -1, 1, 2 do
        for y = -1, 1, 2 do
            for z = -1, 1, 2 do
                local worldPoint = boxCFrame:PointToWorldSpace(Vector3.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z))
                local screenPoint = camera:WorldToViewportPoint(worldPoint)
                if screenPoint.Z > 0 then
                    minX = math.min(minX, screenPoint.X)
                    minY = math.min(minY, screenPoint.Y)
                    maxX = math.max(maxX, screenPoint.X)
                    maxY = math.max(maxY, screenPoint.Y)
                end
            end
        end
    end

    if minX == math.huge or minY == math.huge then
        return nil
    end

    local viewport = camera.ViewportSize
    minX = math.clamp(minX, 0, viewport.X)
    minY = math.clamp(minY, 0, viewport.Y)
    maxX = math.clamp(maxX, 0, viewport.X)
    maxY = math.clamp(maxY, 0, viewport.Y)

    if maxX - minX < 2 or maxY - minY < 2 then
        return nil
    end

    return minX, minY, maxX, maxY
end

local function SetESPLine(line, startPos, endPos, color, thickness)
    if not line or not startPos or not endPos then
        return
    end

    local delta = endPos - startPos
    local length = delta.Magnitude
    if length <= 1 then
        line.Visible = false
        return
    end

    line.Visible = true
    line.Position = UDim2.fromOffset(startPos.X, startPos.Y)
    line.Size = UDim2.fromOffset(length, thickness or 2)
    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
    line.BackgroundColor3 = color
end

local function ProjectWorldPoint(camera, worldPoint)
    if not camera or not worldPoint then
        return nil
    end

    local screenPoint, onScreen = camera:WorldToViewportPoint(worldPoint)
    if onScreen and screenPoint.Z > 0 then
        return Vector2.new(screenPoint.X, screenPoint.Y)
    end

    return nil
end

local function GetTracerScreenPoint(character, camera, minX, minY, maxX, maxY)
    local root = GetCharacterRoot(character)
    if root then
        local worldPoint = root.Position + Vector3.new(0, math.max(root.Size.Y * 0.5, 1.5), 0)
        local screenPoint = ProjectWorldPoint(camera, worldPoint)
        if screenPoint then
            return screenPoint
        end
    end

    return Vector2.new((minX + maxX) * 0.5, (minY + maxY) * 0.5)
end

local function FindCharacterMotor(character, motorName)
    if not character then
        return nil
    end

    local descendant = character:FindFirstChild(motorName, true)
    if descendant and descendant:IsA("Motor6D") then
        return descendant
    end

    return nil
end

local function GetMotorJointWorldPosition(character, motorName)
    local motor = FindCharacterMotor(character, motorName)
    if not motor then
        return nil
    end

    local part0Position = motor.Part0 and (motor.Part0.CFrame * motor.C0).Position or nil
    local part1Position = motor.Part1 and (motor.Part1.CFrame * motor.C1).Position or nil

    if part0Position and part1Position then
        return (part0Position + part1Position) * 0.5
    end

    if part0Position then
        return part0Position
    end

    if part1Position then
        return part1Position
    end

    return nil
end

local function AddSkeletonWorldSegment(segments, camera, startWorld, endWorld)
    local startPoint = ProjectWorldPoint(camera, startWorld)
    local endPoint = ProjectWorldPoint(camera, endWorld)
    if startPoint and endPoint then
        table.insert(segments, {
            Start = startPoint,
            End = endPoint
        })
    end
end

local function BuildPlayerLabelText(player, character)
    local lines = {}

    if Toggles.PlayerNameESP then
        table.insert(lines, player.DisplayName or player.Name)
    end

    if Toggles.PlayerDistanceText then
        local distance = GetCharacterDistanceStuds(character)
        if distance then
            table.insert(lines, string.format("%d studs", math.floor(distance + 0.5)))
        end
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

local function GetSkeletonSegments(character, camera)
    if not character or not camera then
        return {}
    end

    local segments = {}

    if character:FindFirstChild("UpperTorso") then
        local head = character:FindFirstChild("Head")
        local upperTorso = character:FindFirstChild("UpperTorso")
        local lowerTorso = character:FindFirstChild("LowerTorso")
        local leftHand = character:FindFirstChild("LeftHand")
        local rightHand = character:FindFirstChild("RightHand")
        local leftFoot = character:FindFirstChild("LeftFoot")
        local rightFoot = character:FindFirstChild("RightFoot")

        local headTop = head and (head.Position + Vector3.new(0, head.Size.Y * 0.4, 0)) or nil
        local neck = GetMotorJointWorldPosition(character, "Neck")
            or (upperTorso and (upperTorso.Position + Vector3.new(0, upperTorso.Size.Y * 0.45, 0)) or nil)
        local waist = GetMotorJointWorldPosition(character, "Waist")
            or (lowerTorso and upperTorso and ((lowerTorso.Position + upperTorso.Position) * 0.5) or nil)
        local leftShoulder = GetMotorJointWorldPosition(character, "LeftShoulder")
        local rightShoulder = GetMotorJointWorldPosition(character, "RightShoulder")
        local leftElbow = GetMotorJointWorldPosition(character, "LeftElbow")
        local rightElbow = GetMotorJointWorldPosition(character, "RightElbow")
        local leftWrist = GetMotorJointWorldPosition(character, "LeftWrist")
        local rightWrist = GetMotorJointWorldPosition(character, "RightWrist")
        local leftHip = GetMotorJointWorldPosition(character, "LeftHip")
        local rightHip = GetMotorJointWorldPosition(character, "RightHip")
        local leftKnee = GetMotorJointWorldPosition(character, "LeftKnee")
        local rightKnee = GetMotorJointWorldPosition(character, "RightKnee")
        local leftAnkle = GetMotorJointWorldPosition(character, "LeftAnkle")
        local rightAnkle = GetMotorJointWorldPosition(character, "RightAnkle")

        AddSkeletonWorldSegment(segments, camera, headTop, neck)
        AddSkeletonWorldSegment(segments, camera, neck, waist)
        AddSkeletonWorldSegment(segments, camera, neck, leftShoulder)
        AddSkeletonWorldSegment(segments, camera, leftShoulder, leftElbow)
        AddSkeletonWorldSegment(segments, camera, leftElbow, leftWrist)
        AddSkeletonWorldSegment(segments, camera, leftWrist, leftHand and leftHand.Position or nil)
        AddSkeletonWorldSegment(segments, camera, neck, rightShoulder)
        AddSkeletonWorldSegment(segments, camera, rightShoulder, rightElbow)
        AddSkeletonWorldSegment(segments, camera, rightElbow, rightWrist)
        AddSkeletonWorldSegment(segments, camera, rightWrist, rightHand and rightHand.Position or nil)
        AddSkeletonWorldSegment(segments, camera, waist, leftHip)
        AddSkeletonWorldSegment(segments, camera, leftHip, leftKnee)
        AddSkeletonWorldSegment(segments, camera, leftKnee, leftAnkle)
        AddSkeletonWorldSegment(segments, camera, leftAnkle, leftFoot and leftFoot.Position or nil)
        AddSkeletonWorldSegment(segments, camera, waist, rightHip)
        AddSkeletonWorldSegment(segments, camera, rightHip, rightKnee)
        AddSkeletonWorldSegment(segments, camera, rightKnee, rightAnkle)
        AddSkeletonWorldSegment(segments, camera, rightAnkle, rightFoot and rightFoot.Position or nil)
    else
        local head = character:FindFirstChild("Head")
        local torso = character:FindFirstChild("Torso")
        local leftArm = character:FindFirstChild("Left Arm")
        local rightArm = character:FindFirstChild("Right Arm")
        local leftLeg = character:FindFirstChild("Left Leg")
        local rightLeg = character:FindFirstChild("Right Leg")

        local headTop = head and (head.Position + Vector3.new(0, head.Size.Y * 0.4, 0)) or nil
        local neck = GetMotorJointWorldPosition(character, "Neck")
            or (torso and (torso.Position + Vector3.new(0, torso.Size.Y * 0.45, 0)) or nil)
        local leftShoulder = GetMotorJointWorldPosition(character, "Left Shoulder")
            or (torso and leftArm and ((torso.Position + leftArm.Position) * 0.5) or nil)
        local rightShoulder = GetMotorJointWorldPosition(character, "Right Shoulder")
            or (torso and rightArm and ((torso.Position + rightArm.Position) * 0.5) or nil)
        local leftHip = GetMotorJointWorldPosition(character, "Left Hip")
            or (torso and leftLeg and ((torso.Position + leftLeg.Position) * 0.5) or nil)
        local rightHip = GetMotorJointWorldPosition(character, "Right Hip")
            or (torso and rightLeg and ((torso.Position + rightLeg.Position) * 0.5) or nil)

        AddSkeletonWorldSegment(segments, camera, headTop, neck)
        AddSkeletonWorldSegment(segments, camera, neck, torso and torso.Position or nil)
        AddSkeletonWorldSegment(segments, camera, neck, leftShoulder)
        AddSkeletonWorldSegment(segments, camera, leftShoulder, leftArm and leftArm.Position or nil)
        AddSkeletonWorldSegment(segments, camera, neck, rightShoulder)
        AddSkeletonWorldSegment(segments, camera, rightShoulder, rightArm and rightArm.Position or nil)
        AddSkeletonWorldSegment(segments, camera, torso and torso.Position or nil, leftHip)
        AddSkeletonWorldSegment(segments, camera, leftHip, leftLeg and leftLeg.Position or nil)
        AddSkeletonWorldSegment(segments, camera, torso and torso.Position or nil, rightHip)
        AddSkeletonWorldSegment(segments, camera, rightHip, rightLeg and rightLeg.Position or nil)
    end

    return segments
end

-- selene: allow(unused_variable)
local function UpdatePlayerESPOverlay()
    local overlayEnabled = Toggles.PlayerTracers
        or Toggles.PlayerBoxes
        or Toggles.PlayerNameESP
        or Toggles.PlayerDistanceText
        or Toggles.PlayerSkeletonESP

    if not overlayEnabled then
        ClearPlayerESPOverlay()
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        ClearPlayerESPOverlay()
        return
    end

    EnsurePlayerESPOverlay()

    local viewport = camera.ViewportSize
    local tracerStart = Vector2.new(viewport.X * 0.5, viewport.Y - 2)
    local activePlayers = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character then
            local targetChar = player.Character
            local isTargetBeast = targetChar:FindFirstChild("BeastPowers") ~= nil

            if ShouldShowPlayerTarget(isTargetBeast) then
                local minX, minY, maxX, maxY = GetCharacterScreenBounds(targetChar, camera)
                if minX and minY and maxX and maxY then
                    local entry = GetOrCreatePlayerESPEntry(player)
                    local color = GetPlayerESPColor(isTargetBeast)
                    local labelText = BuildPlayerLabelText(player, targetChar)
                    local skeletonSegments = Toggles.PlayerSkeletonESP and GetSkeletonSegments(targetChar, camera) or nil
                    activePlayers[player] = true

                    if Toggles.PlayerBoxes then
                        entry.Box.Visible = true
                        entry.Box.Position = UDim2.fromOffset(minX, minY)
                        entry.Box.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
                        entry.BoxStroke.Color = color
                    else
                        entry.Box.Visible = false
                    end

                    if Toggles.PlayerTracers then
                        local tracerEnd = GetTracerScreenPoint(targetChar, camera, minX, minY, maxX, maxY)
                        SetESPLine(entry.Tracer, tracerStart, tracerEnd, color, 2)
                    else
                        entry.Tracer.Visible = false
                    end

                    if labelText then
                        local labelLines = select(2, string.gsub(labelText, "\n", "\n")) + 1
                        entry.Label.Visible = true
                        entry.Label.Text = labelText
                        entry.Label.Position = UDim2.fromOffset((minX + maxX) * 0.5, minY - 6)
                        entry.Label.Size = UDim2.fromOffset(170, labelLines > 1 and 40 or 22)
                        entry.LabelStroke.Color = color
                    else
                        entry.Label.Visible = false
                    end

                    local lineIndex = 1
                    if skeletonSegments then
                        for _, segment in ipairs(skeletonSegments) do
                            local line = entry.SkeletonLines[lineIndex]
                            if not line then
                                break
                            end

                            SetESPLine(line, segment.Start, segment.End, color, 2)
                            lineIndex = lineIndex + 1
                        end
                    end

                    for index = lineIndex, #entry.SkeletonLines do
                        entry.SkeletonLines[index].Visible = false
                    end
                end
            end
        end
    end

    for player, entry in pairs(PlayerESPObjects) do
        if not activePlayers[player] then
            if player.Parent ~= Players then
                DestroyPlayerESPEntry(player)
            else
                HidePlayerESPEntry(entry)
            end
        end
    end
end

local function UpdatePlayerESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LP and player.Character then
            local targetChar = player.Character
            local isTargetBeast = targetChar:FindFirstChild("BeastPowers") ~= nil
            local existing = targetChar:FindFirstChild("LuminaHighlight")
            local shouldShowHighlight = ShouldShowPlayerTarget(isTargetBeast)
                and (Toggles.PlayerESP or Toggles.PlayerOutlineESP)

            if existing and not existing:IsA("Highlight") then
                existing:Destroy()
                existing = nil
            end

            if shouldShowHighlight then
                local espColor = GetPlayerESPColor(isTargetBeast)

                if not existing then
                    local hl = Instance.new("Highlight")
                    hl.Name = "LuminaHighlight"
                    hl.FillColor = espColor
                    hl.OutlineColor = espColor
                    hl.Parent = targetChar
                end

                existing = targetChar:FindFirstChild("LuminaHighlight")
                if existing then
                    existing.FillColor = espColor
                    existing.OutlineColor = espColor
                    existing.FillTransparency = Toggles.PlayerESP and 0.4 or 1
                    existing.OutlineTransparency = Toggles.PlayerOutlineESP and 0 or 1
                end
            elseif existing then
                existing:Destroy()
            end
        end
    end
end

-- Object ESP
local function StyleObjectHighlight(highlight, color, fillTransparency)
    if not highlight then
        return
    end

    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = math.clamp(fillTransparency or 0.82, 0.55, 0.95)
    highlight.OutlineTransparency = 0.22
end

local function ClearObjectESPArtifacts(computerModels, exitDoors, freezePods)
    local computers = computerModels
    local doors = exitDoors
    local pods = freezePods

    if not computers or not doors or not pods then
        computers, doors, pods = CollectTrackedWorldObjects()
    end

    for _, obj in ipairs(computers) do
        local screen = GetComputerScreen(obj)
        local tag = obj:FindFirstChild("LuminaCompTag") or (screen and screen:FindFirstChild("LuminaCompTag"))
        local v2Tag = obj:FindFirstChild("LuminaCompV2")
        local bestTag = obj:FindFirstChild("LuminaBestComp")

        if tag then
            tag:Destroy()
        end

        if v2Tag then
            v2Tag:Destroy()
        end

        if bestTag then
            bestTag:Destroy()
        end
    end

    for _, obj in ipairs(doors) do
        local doorTag = obj:FindFirstChild("LuminaExitTag")
        if doorTag then
            doorTag:Destroy()
        end
    end

    for _, obj in ipairs(pods) do
        local freezePodTag = obj:FindFirstChild("LuminaFreezePodTag")
        if freezePodTag then
            freezePodTag:Destroy()
        end
    end

end

local function UpdateComputerV2ESP(computerModels)
    local models = computerModels
    if not models then
        models = select(1, CollectTrackedWorldObjects())
    end

    for _, obj in ipairs(models) do
        local screen = GetComputerScreen(obj)
        local tag = obj:FindFirstChild("LuminaCompV2")
        local shouldHighlight = Toggles.ComputerV2ESP
            and IsRoundActive()
            and IsHackableComputerScreen(screen)
            and ComputerHasVisibleParts(obj)

        if shouldHighlight then
            if not tag then
                local hl = Instance.new("Highlight")
                hl.Name = "LuminaCompV2"
                hl.Adornee = obj
                hl.Parent = obj
                tag = hl
            end

            tag.Adornee = obj
            StyleObjectHighlight(tag, Colors.ComputerColor, 0.82)
        elseif tag then
            tag:Destroy()
        end
    end
end

local function UpdateBestComputerESP(computerModels, bestComputerModel)
    local models = computerModels
    local resolvedBestComputer = bestComputerModel

    if not models then
        models = select(1, CollectTrackedWorldObjects())
    end

    if Toggles.BestComputerESP and IsRoundActive() and not resolvedBestComputer then
        resolvedBestComputer = GetBestComputerModel(models)
    end

    for _, obj in ipairs(models) do
        local tag = obj:FindFirstChild("LuminaBestComp")
        if tag then
            if obj ~= resolvedBestComputer then
                tag:Destroy()
            else
                tag.Adornee = obj
                StyleObjectHighlight(tag, Colors.BestComputerColor, 0.68)
            end
        end
    end

    if resolvedBestComputer and not resolvedBestComputer:FindFirstChild("LuminaBestComp") then
        local hl = Instance.new("Highlight")
        hl.Name = "LuminaBestComp"
        hl.Adornee = resolvedBestComputer
        hl.Parent = resolvedBestComputer
        StyleObjectHighlight(hl, Colors.BestComputerColor, 0.68)
    end
end

local function UpdateObjectESP(computerModels, exitDoors, freezePods, bestComputerModel)
    local models = computerModels
    local doors = exitDoors
    local pods = freezePods

    if not models or not doors or not pods then
        models, doors, pods = CollectTrackedWorldObjects()
    end

    if not IsRoundActive() then
        ClearObjectESPArtifacts(models, doors, pods)
        return
    end

    local canEscape = CompValue and CompValue.Value == 0
    local resolvedBestComputer = bestComputerModel

    if Toggles.BestComputerESP and not resolvedBestComputer then
        resolvedBestComputer = GetBestComputerModel(models)
    end

    for _, obj in ipairs(models) do
        if IsComputerModel(obj) then
            local screen = GetComputerScreen(obj)
            if screen and screen:IsA("BasePart") then
                local tag = obj:FindFirstChild("LuminaCompTag") or screen:FindFirstChild("LuminaCompTag")

                if IsSolvedComputerScreen(screen) then
                    if tag then
                        tag:Destroy()
                    end
                elseif IsHackableComputerScreen(screen) then
                    if Toggles.ObjectESP and not tag then
                        local hl = Instance.new("Highlight")
                        hl.Name = "LuminaCompTag"
                        hl.Adornee = obj
                        hl.Parent = obj
                        tag = hl
                    elseif tag and Toggles.ObjectESP then
                        tag.Adornee = obj
                    elseif not Toggles.ObjectESP and tag then
                        tag:Destroy()
                    end

                    if tag and Toggles.ObjectESP then
                        StyleObjectHighlight(tag, Colors.ComputerColor, 0.88)
                    end
                end
            end
        end
    end

    for _, obj in ipairs(doors) do
        local doorTag = obj:FindFirstChild("LuminaExitTag")

        if Toggles.ObjectESP and canEscape then
            local trigger = obj:FindFirstChild("ExitDoorTrigger")
            if trigger then
                if not doorTag then
                    local hl = Instance.new("Highlight")
                    hl.Name = "LuminaExitTag"
                    hl.FillColor = Colors.ExitColor
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
                    hl.Parent = obj
                else
                    doorTag.FillColor = Colors.ExitColor
                end
            else
                if doorTag then
                    doorTag:Destroy()
                end
            end
        else
            if doorTag then
                doorTag:Destroy()
            end
        end
    end

    for _, obj in ipairs(pods) do
        local freezePodTag = obj:FindFirstChild("LuminaFreezePodTag")

        if Toggles.FreezePodESP then
            if not freezePodTag then
                local hl = Instance.new("Highlight")
                hl.Name = "LuminaFreezePodTag"
                hl.FillColor = Colors.FreezePodColor
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                hl.FillTransparency = 0.5
                hl.Parent = obj
            else
                freezePodTag.FillColor = Colors.FreezePodColor
            end
        elseif freezePodTag then
            freezePodTag:Destroy()
        end
    end
end

local function RefreshObjectFeatures()
    local computerModels, exitDoors, freezePods = CollectTrackedWorldObjects()

    if not IsRoundActive() then
        ClearObjectESPArtifacts(computerModels, exitDoors, freezePods)
        return
    end

    local bestComputerModel = nil
    if Toggles.BestComputerESP then
        bestComputerModel = GetBestComputerModel(computerModels)
    end

    UpdateObjectESP(computerModels, exitDoors, freezePods, bestComputerModel)
    UpdateComputerV2ESP(computerModels)
    UpdateBestComputerESP(computerModels, bestComputerModel)
end

local function UpdateAutoNotifyPower()
    local powerValue = ResolveCurrentPowerValue()

    if Toggles.AutoNotifyPower and powerValue and not PowerNotifyConnection then
        local currentPowerName = GetCurrentBeastPower()
        if currentPowerName then
            print("[Lumina Hub] Beast Power: " .. currentPowerName)
        end

        PowerNotifyConnection = powerValue:GetPropertyChangedSignal("Value"):Connect(function()
            local powerName = GetCurrentBeastPower() or "Unknown"
            print("[Lumina Hub] Beast Power: " .. powerName)
        end)
        return
    end

    if not Toggles.AutoNotifyPower and PowerNotifyConnection then
        PowerNotifyConnection:Disconnect()
        PowerNotifyConnection = nil
    end
end

-- Main loop
local function StartMainLoop()
    while isRunning do
        if Toggles.PlayerESP or Toggles.PlayerOutlineESP then
            SafeCall("UpdatePlayerESP", UpdatePlayerESP)
        end

        if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
            SafeCall("RefreshObjectFeatures", RefreshObjectFeatures)
        end

        SafeCall("HandleAutoSafeExit", HandleAutoSafeExit)

        task.wait(1.5)
    end
end

-- API
local Lumina = {}

function Lumina:ToggleActionBoost(state)
    if UIBuilding then
        return
    end

    Toggles.ActionBoost = state

    if state and not ActionProgress then
        FindActionProgress()
    end
end

function Lumina:TogglePlayerESP(state)
    if UIBuilding then
        return
    end

    Toggles.PlayerESP = state
    UpdatePlayerESP()
end

function Lumina:TogglePlayerOutlineESP(state)
    if UIBuilding then
        return
    end

    Toggles.PlayerOutlineESP = state
    UpdatePlayerESP()
end

function Lumina:ToggleShowBeastESP(state)
    if UIBuilding then
        return
    end

    Toggles.ShowBeastESP = state
    UpdatePlayerESP()
end

function Lumina:ToggleShowSurvivorESP(state)
    if UIBuilding then
        return
    end

    Toggles.ShowSurvivorESP = state
    UpdatePlayerESP()
end

function Lumina:TogglePlayerTracers(_)
    return
end

function Lumina:TogglePlayerBoxes(_)
    return
end

function Lumina:TogglePlayerNameESP(_)
    return
end

function Lumina:TogglePlayerSkeletonESP(_)
    return
end

function Lumina:TogglePlayerDistanceText(_)
    return
end

function Lumina:ToggleObjectESP(state)
    if UIBuilding then
        return
    end

    Toggles.ObjectESP = state

    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    else
        ClearObjectESPArtifacts()
    end
end

function Lumina:ToggleComputerV2ESP(state)
    if UIBuilding then
        return
    end

    Toggles.ComputerV2ESP = state

    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    else
        ClearObjectESPArtifacts()
    end
end

function Lumina:ToggleBestComputerESP(state)
    if UIBuilding then
        return
    end

    Toggles.BestComputerESP = state

    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    else
        ClearObjectESPArtifacts()
    end
end

function Lumina:ToggleFreezePodESP(state)
    if UIBuilding then
        return
    end

    Toggles.FreezePodESP = state

    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    else
        ClearObjectESPArtifacts()
    end
end

function Lumina:ToggleAutoSafeExit(state)
    if UIBuilding then
        return
    end

    Toggles.AutoSafeExit = state

    if not state then
        AutoEscapeTriggered = false
        return
    end

    HandleAutoSafeExit()
end

function Lumina:ToggleAutoHammerHit(state)
    if UIBuilding then
        return
    end

    Toggles.AutoHammerHit = state
end

function Lumina:ToggleAutoHammerTieUp(state)
    if UIBuilding then
        return
    end

    Toggles.AutoHammerTieUp = state
end

function Lumina:ToggleBeastProximityInvisibility(state)
    if UIBuilding then
        return
    end

    Toggles.BeastProximityInvisibility = state
    UpdateInvisibilityState()
end

function Lumina:ToggleFullRoundInvisibility(state)
    if UIBuilding then
        return
    end

    Toggles.FullRoundInvisibility = state
    UpdateInvisibilityState()
end

function Lumina:ToggleBeastRadar(state)
    if UIBuilding then
        return
    end

    Toggles.BeastRadar = state
    UpdateBeastRadar()
end

function Lumina:ToggleBeastETARadar(state)
    if UIBuilding then
        return
    end

    Toggles.BeastETARadar = state
    UpdateBeastETARadar()
end

function Lumina:ToggleSprintBoost(state)
    if UIBuilding then
        return
    end

    Toggles.SprintBoost = state
    UpdateSprintState()
end

function Lumina:ToggleNoSlow(_)
    return
end

function Lumina:ToggleUnlockCamera(_)
    return
end

function Lumina:ToggleRemoveSoundGlow(_)
    return
end

function Lumina:ToggleNoClip(state)
    if UIBuilding then
        return
    end

    Toggles.NoClip = state
    UpdateNoClipState()
end

function Lumina:ToggleFogRemover(state)
    if UIBuilding then
        return
    end

    Toggles.FogRemover = state
    UpdateFogRemoverState()
end

function Lumina:ToggleRemoteRescue(state)
    if UIBuilding then
        return
    end

    Toggles.RemoteRescue = state
    UpdateRemoteRescueState()
end

function Lumina:ToggleAutoNotifyPower(state)
    if UIBuilding then
        return
    end

    Toggles.AutoNotifyPower = state
    UpdateAutoNotifyPower()
end

function Lumina:ToggleWallHopViewer(_)
    return
end

function Lumina:DumpBeastStats()
    return DumpBeastStats()
end

function Lumina:SetBeastColor(color)
    if UIBuilding then
        return
    end

    Colors.BeastColor = color
    UpdatePlayerESP()
end

function Lumina:SetSurvivorColor(color)
    if UIBuilding then
        return
    end

    Colors.SurvivorColor = color
    UpdatePlayerESP()
end

function Lumina:SetComputerColor(color)
    if UIBuilding then
        return
    end

    Colors.ComputerColor = color
    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    end
end

function Lumina:SetBestComputerColor(color)
    if UIBuilding then
        return
    end

    Colors.BestComputerColor = color
    if Toggles.ObjectESP or Toggles.ComputerV2ESP or Toggles.BestComputerESP or Toggles.FreezePodESP then
        RefreshObjectFeatures()
    end
end

function Lumina:SetExitColor(color)
    if UIBuilding then
        return
    end

    Colors.ExitColor = color
    if Toggles.ObjectESP then
        RefreshObjectFeatures()
    end
end

function Lumina:SetFreezePodColor(color)
    if UIBuilding then
        return
    end

    Colors.FreezePodColor = color
    if Toggles.FreezePodESP then
        RefreshObjectFeatures()
    end
end

function Lumina:EnableAll()
    self:ToggleActionBoost(true)
    self:TogglePlayerESP(true)
    self:ToggleObjectESP(true)
    self:ToggleAutoSafeExit(true)
    self:ToggleBeastProximityInvisibility(true)
    self:ToggleSprintBoost(true)
    self:ToggleNoClip(true)
    self:ToggleRemoteRescue(true)
end

function Lumina:DisableAll()
    self:ToggleActionBoost(false)
    self:TogglePlayerESP(false)
    self:TogglePlayerOutlineESP(false)
    self:TogglePlayerTracers(false)
    self:TogglePlayerBoxes(false)
    self:TogglePlayerNameESP(false)
    self:TogglePlayerSkeletonESP(false)
    self:TogglePlayerDistanceText(false)
    self:ToggleObjectESP(false)
    self:ToggleComputerV2ESP(false)
    self:ToggleBestComputerESP(false)
    self:ToggleFreezePodESP(false)
    self:ToggleAutoSafeExit(false)
    self:ToggleAutoHammerHit(false)
    self:ToggleAutoHammerTieUp(false)
    self:ToggleBeastProximityInvisibility(false)
    self:ToggleFullRoundInvisibility(false)
    self:ToggleBeastRadar(false)
    self:ToggleBeastETARadar(false)
    self:ToggleSprintBoost(false)
    self:ToggleNoClip(false)
    self:ToggleFogRemover(false)
    self:ToggleRemoteRescue(false)
    self:ToggleAutoNotifyPower(false)
end

-- UI
LogBoot("waiting for current camera")
WaitForCurrentCamera()
LogBoot("current camera ready")

LogBoot("creating window")
local Window = Library:CreateWindow({
    Title = WindowTitleText,
    Footer = WindowFooterText,
    Center = true,
    Resizable = true,
    AutoShow = true,
    ToggleKeybind = Enum.KeyCode.Insert
})
print("Lumina startup: window created")
LogBoot("window created")

local SurvivorTab = Window:AddTab("Survivor", "user")
local BeastTab = Window:AddTab("Beast", "shield")
local ExploitTab = Window:AddTab("Exploits", "wrench")
local SettingsTab = Window:AddTab("Settings", "settings")
local InfoTab = Window:AddTab("Info", "info")
LogBoot("tabs created")

local SurvivorGroup = SurvivorTab:AddLeftGroupbox("Objective ESP")
local BeastGroup = BeastTab:AddLeftGroupbox("Player ESP")
local BeastActionGroup = BeastTab:AddRightGroupbox("Hammer Automation")
local ExploitGroup = ExploitTab:AddLeftGroupbox("Automation")
local ControlGroup = ExploitTab:AddRightGroupbox("Controls")
local SettingsGroup = SettingsTab:AddLeftGroupbox("Stealth, Radar & Visuals")
local InfoGroup = InfoTab:AddLeftGroupbox("About")
LogBoot("groupboxes created")

local ActionToggle = ExploitGroup:AddToggle("Lumina_ActionBoost", {
    Text = "Auto Complete Minigames",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleActionBoost(Value)
    end
})

local AutoSafeExitToggle = ExploitGroup:AddToggle("Lumina_AutoSafeExit", {
    Text = "Auto Safe Exit",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleAutoSafeExit(Value)
    end
})

local SprintToggle = ExploitGroup:AddToggle("Lumina_SprintBoost", {
    Text = "Sprint Toggle (22 Speed)",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleSprintBoost(Value)
    end
})

local NoClipToggle = ExploitGroup:AddToggle("Lumina_NoClip", {
    Text = "No-Clip (Door Squeeze)",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleNoClip(Value)
    end
})

local RemoteRescueToggle = ExploitGroup:AddToggle("Lumina_RemoteRescue", {
    Text = "Remote Rescue (FreezePod)",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleRemoteRescue(Value)
    end
})

local BeastHideToggle = SettingsGroup:AddToggle("Lumina_BeastProximityInvisibility", {
    Text = "Hide Near Beast",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleBeastProximityInvisibility(Value)
    end
})

local FullRoundHideToggle = SettingsGroup:AddToggle("Lumina_FullRoundInvisibility", {
    Text = "Invisible Whole Round",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleFullRoundInvisibility(Value)
    end
})

local BeastRadarToggle = SettingsGroup:AddToggle("Lumina_BeastRadar", {
    Text = "Beast Radar Warning",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleBeastRadar(Value)
    end
})

local BeastETARadarToggle = SettingsGroup:AddToggle("Lumina_BeastETARadar", {
    Text = "Beast ETA Radar",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleBeastETARadar(Value)
    end
})

local FogRemoverToggle = SettingsGroup:AddToggle("Lumina_FogRemover", {
    Text = "Fog Remover (Full Bright)",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleFogRemover(Value)
    end
})

local AutoNotifyPowerToggle = SettingsGroup:AddToggle("Lumina_AutoNotifyPower", {
    Text = "Auto Notify Beast Power",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleAutoNotifyPower(Value)
    end
})

local PlayerToggle = BeastGroup:AddToggle("Lumina_PlayerESP", {
    Text = "Fill ESP",
    Default = false,
    Callback = function(Value)
        Lumina:TogglePlayerESP(Value)
    end
})

local PlayerOutlineToggle = BeastGroup:AddToggle("Lumina_PlayerOutlineESP", {
    Text = "Outline ESP",
    Default = false,
    Callback = function(Value)
        Lumina:TogglePlayerOutlineESP(Value)
    end
})

BeastGroup:AddToggle("Lumina_ShowBeastESP", {
    Text = "Show Beast",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleShowBeastESP(Value)
    end
})

BeastGroup:AddToggle("Lumina_ShowSurvivorESP", {
    Text = "Show Survivors",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleShowSurvivorESP(Value)
    end
})

BeastGroup:AddButton({
    Text = "Dump Beast Stats",
    Func = function()
        local dumped = Lumina:DumpBeastStats()
        if not dumped then
            warn("Lumina Hub: no Beast stats could be dumped right now.")
        end
    end,
})

local AutoHammerHitToggle = BeastActionGroup:AddToggle("Lumina_AutoHammerHit", {
    Text = "Auto Hammer Hit",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleAutoHammerHit(Value)
    end
})

local AutoHammerTieUpToggle = BeastActionGroup:AddToggle("Lumina_AutoHammerTieUp", {
    Text = "Auto Tie Up",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleAutoHammerTieUp(Value)
    end
})

PlayerToggle:AddColorPicker("Lumina_BeastColor", {
    Default = Colors.BeastColor,
    Title = "Beast Color",
    Callback = function(Color)
        Lumina:SetBeastColor(Color)
    end
})

PlayerToggle:AddColorPicker("Lumina_SurvivorColor", {
    Default = Colors.SurvivorColor,
    Title = "Survivor Color",
    Callback = function(Color)
        Lumina:SetSurvivorColor(Color)
    end
})

local ObjectToggle = SurvivorGroup:AddToggle("Lumina_ObjectESP", {
    Text = "Enable Object ESP",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleObjectESP(Value)
    end
})

local ComputerV2Toggle = SurvivorGroup:AddToggle("Lumina_ComputerV2ESP", {
    Text = "Computer ESP V2",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleComputerV2ESP(Value)
    end
})

local BestComputerToggle = SurvivorGroup:AddToggle("Lumina_BestComputerESP", {
    Text = "Best Computer ESP",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleBestComputerESP(Value)
    end
})

local FreezePodToggle = SurvivorGroup:AddToggle("Lumina_FreezePodESP", {
    Text = "FreezePod ESP",
    Default = false,
    Callback = function(Value)
        Lumina:ToggleFreezePodESP(Value)
    end
})

ObjectToggle:AddColorPicker("Lumina_ComputerColor", {
    Default = Colors.ComputerColor,
    Title = "Computer Color",
    Callback = function(Color)
        Lumina:SetComputerColor(Color)
    end
})

ObjectToggle:AddColorPicker("Lumina_ExitColor", {
    Default = Colors.ExitColor,
    Title = "Exit Door Color",
    Callback = function(Color)
        Lumina:SetExitColor(Color)
    end
})

BestComputerToggle:AddColorPicker("Lumina_BestComputerColor", {
    Default = Colors.BestComputerColor,
    Title = "Best PC Color",
    Callback = function(Color)
        Lumina:SetBestComputerColor(Color)
    end
})

FreezePodToggle:AddColorPicker("Lumina_FreezePodColor", {
    Default = Colors.FreezePodColor,
    Title = "FreezePod Color",
    Callback = function(Color)
        Lumina:SetFreezePodColor(Color)
    end
})

ControlGroup:AddButton({
    Text = "Enable All",
    Func = function()
        ActionToggle:SetValue(true)
        AutoSafeExitToggle:SetValue(true)
        SprintToggle:SetValue(true)
        NoClipToggle:SetValue(true)
        RemoteRescueToggle:SetValue(true)
        BeastHideToggle:SetValue(true)
        PlayerToggle:SetValue(true)
        ObjectToggle:SetValue(true)
        Lumina:EnableAll()
    end,
})

ControlGroup:AddButton({
    Text = "Disable All",
    Func = function()
        ActionToggle:SetValue(false)
        AutoSafeExitToggle:SetValue(false)
        SprintToggle:SetValue(false)
        NoClipToggle:SetValue(false)
        RemoteRescueToggle:SetValue(false)
        PlayerOutlineToggle:SetValue(false)
        AutoHammerHitToggle:SetValue(false)
        AutoHammerTieUpToggle:SetValue(false)
        BeastHideToggle:SetValue(false)
        FullRoundHideToggle:SetValue(false)
        BeastRadarToggle:SetValue(false)
        BeastETARadarToggle:SetValue(false)
        FogRemoverToggle:SetValue(false)
        AutoNotifyPowerToggle:SetValue(false)
        PlayerToggle:SetValue(false)
        ObjectToggle:SetValue(false)
        ComputerV2Toggle:SetValue(false)
        BestComputerToggle:SetValue(false)
        FreezePodToggle:SetValue(false)
        Lumina:DisableAll()
    end,
})

InfoGroup:AddLabel("vesper.lua v0.1")
InfoGroup:AddLabel("")
InfoGroup:AddLabel("Features:")
InfoGroup:AddLabel("  - Auto Hammer Hit / Tie Up")
InfoGroup:AddLabel("  - Player Tracers / 2D Boxes")
InfoGroup:AddLabel("  - Name / Distance / Skeleton ESP")
InfoGroup:AddLabel("  - Computer ESP V2 / Best Computer ESP")
InfoGroup:AddLabel("  - Auto Minigame Complete")
InfoGroup:AddLabel("  - Sprint Toggle (22 Speed)")
InfoGroup:AddLabel("  - No-Clip (Door Squeeze)")
InfoGroup:AddLabel("  - Fog Remover (Full Bright)")
InfoGroup:AddLabel("  - Remote Rescue (FreezePod)")
InfoGroup:AddLabel("  - Round Status Indicator")
InfoGroup:AddLabel("  - Beast Power Tracker")
InfoGroup:AddLabel("  - Auto Notify Beast Power")
InfoGroup:AddLabel("  - Beast ETA Radar")
InfoGroup:AddLabel("  - No Slow / Unlock Camera")
InfoGroup:AddLabel("  - WallHop Viewer")
InfoGroup:AddLabel("  - Player ESP (Beast / Survivor / Outline)")
InfoGroup:AddLabel("  - FreezePod ESP")
InfoGroup:AddLabel("  - Computer & Door Highlight")
InfoGroup:AddLabel("  - Beast Radar Warning")
InfoGroup:AddLabel("  - Customizable Colors")
InfoGroup:AddLabel("")
InfoGroup:AddLabel("Controls:")
InfoGroup:AddLabel("  - INSERT - Show / Hide UI")

LogBoot("ui controls created")
UIBuilding = false

if StartRuntimeOnBoot then
    SafeCall("StartupFindActionProgress", FindActionProgress)
    SafeCall("StartupUpdatePlayerESP", UpdatePlayerESP)
    SafeCall("StartupUpdateRoundStatusUI", UpdateRoundStatusUI)
end

local function StopRuntime()
    if not isRunning then
        return
    end

    isRunning = false

    if PlayerRemovingConnection then
        PlayerRemovingConnection:Disconnect()
        PlayerRemovingConnection = nil
    end

    if RenderSteppedConnection then
        RenderSteppedConnection:Disconnect()
        RenderSteppedConnection = nil
    end

    if PowerNotifyConnection then
        PowerNotifyConnection:Disconnect()
        PowerNotifyConnection = nil
    end

    RestoreUnlockCameraState()
    RestoreBeastSoundGlowState()
    ClearWallHopViewerState()

    if PlayerESPGui then
        PlayerESPGui:Destroy()
        PlayerESPGui = nil
    end

    if BeastRadarGui then
        BeastRadarGui:Destroy()
        BeastRadarGui = nil
        BeastRadarLabel = nil
        BeastETALabel = nil
    end

    if RoundStatusGui then
        RoundStatusGui:Destroy()
        RoundStatusGui = nil
        RoundStatusLabel = nil
    end

    CleanupExistingLuminaArtifacts()

    if Library and Library.Unload and not Library.Unloaded then
        pcall(function()
            Library:Unload()
        end)
    end
end

if RuntimeEnv then
    RuntimeEnv.LuminaHubRuntime = {
        Stop = StopRuntime
    }
end

-- Init
if StartRuntimeOnBoot then
    FindActionProgress()
    print("Lumina startup: beginning thread startup")
    LogBoot("starting runtime threads")

    MainLoopThread = coroutine.create(StartMainLoop)
    local mainLoopStarted, mainLoopError = coroutine.resume(MainLoopThread)
    print("Lumina startup: main loop resumed", mainLoopStarted, mainLoopError or "")
    LogBoot("main loop resumed: " .. tostring(mainLoopStarted) .. " " .. tostring(mainLoopError or ""))

    ActionBoostThread = coroutine.create(StartActionBoost)
    local actionBoostStarted, actionBoostError = coroutine.resume(ActionBoostThread)
    print("Lumina startup: action boost resumed", actionBoostStarted, actionBoostError or "")
    LogBoot("action boost resumed: " .. tostring(actionBoostStarted) .. " " .. tostring(actionBoostError or ""))

    VisibilityLoopThread = coroutine.create(StartVisibilityLoop)
    local visibilityLoopStarted, visibilityLoopError = coroutine.resume(VisibilityLoopThread)
    print("Lumina startup: visibility loop resumed", visibilityLoopStarted, visibilityLoopError or "")
    LogBoot("visibility loop resumed: " .. tostring(visibilityLoopStarted) .. " " .. tostring(visibilityLoopError or ""))

else
    print("Lumina startup: runtime auto-start disabled for bisect")
end

print("vesper.lua loaded successfully!")
print("Press INSERT to open the UI")
LogBoot("startup complete")

]================]

local helperSource = [================[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- selene: allow(undefined_variable, global_usage)
local runtimeEnv = (getgenv and getgenv()) or shared
local existingRuntime = runtimeEnv and runtimeEnv.ComputerTPHelperRuntime
if existingRuntime and existingRuntime.Stop then
    pcall(existingRuntime.Stop)
end

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")
local IsGameActiveValue = ReplicatedStorage:FindFirstChild("IsGameActive")

local overlayGui = nil
local renderConnection = nil
local overlayButtons = {}
local trackedHackableScreens = {}
local screenLastHackableAt = {}
local lastRefreshAt = 0
local refreshInterval = 0.2
local hackableGracePeriod = 1.5

local function isRoundActive()
    return IsGameActiveValue and IsGameActiveValue.Value == true
end

local function getCharacterRoot(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character.PrimaryPart
end

local function getComputerScreen(computerModel)
    if not computerModel then
        return nil
    end

    return computerModel:FindFirstChild("Screen") or computerModel:FindFirstChild("Monitor")
end

local function isComputerModel(instance)
    if not instance or not instance:IsA("Model") then
        return false
    end

    local screen = getComputerScreen(instance)
    if not screen or not screen:IsA("BasePart") then
        return false
    end

    return instance.Name == "ComputerTable"
        or instance:FindFirstChild("ComputerTrigger1") ~= nil
        or instance:FindFirstChild("ComputerTrigger2") ~= nil
        or instance:FindFirstChild("ComputerTrigger3") ~= nil
end

local function collectComputerScreens()
    local screens = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if isComputerModel(obj) then
            local screen = getComputerScreen(obj)
            if screen and screen:IsA("BasePart") then
                table.insert(screens, screen)
            end
        end
    end

    return screens
end

local function isHackableComputerScreen(screen)
    if not screen or not screen:IsA("BasePart") then
        return false
    end

    local color = screen.Color
    local r = math.floor(color.R * 255)
    local g = math.floor(color.G * 255)
    local b = math.floor(color.B * 255)
    return r == 13 and g == 105 and b == 172
end

local function getNearestHackableScreen(screens)
    local localRoot = getCharacterRoot(LP.Character)
    if not localRoot then
        return nil
    end

    local bestScreen = nil
    local bestDistance = math.huge

    for _, screen in ipairs(screens) do
        if screen and screen.Parent and isHackableComputerScreen(screen) then
            local distance = (screen.Position - localRoot.Position).Magnitude
            if distance < bestDistance then
                bestDistance = distance
                bestScreen = screen
            end
        end
    end

    return bestScreen
end

local function getTeleportCFrame(screen)
    if not screen or not screen:IsA("BasePart") then
        return nil
    end

    local targetPosition = screen.Position + (screen.CFrame.LookVector * 5) + Vector3.new(0, 2.5, 0)
    local lookAtPosition = screen.Position + Vector3.new(0, 1, 0)
    return CFrame.lookAt(targetPosition, lookAtPosition)
end

local function teleportToScreen(screen)
    local character = LP.Character
    local root = getCharacterRoot(character)
    if not character or not root or not screen then
        return false, "missing character, root, or screen"
    end

    local desiredCFrame = getTeleportCFrame(screen) or (screen.CFrame * CFrame.new(0, 3, 0))
    local pivotOk = pcall(function()
        character:PivotTo(desiredCFrame)
    end)
    if pivotOk then
        return true, "PivotTo"
    end

    local rootCFrameOk = pcall(function()
        root.CFrame = desiredCFrame
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if rootCFrameOk then
        return true, "HumanoidRootPart.CFrame"
    end

    return false, "PivotTo and root CFrame both failed"
end

local function updateTrackedHackableScreens()
    table.clear(trackedHackableScreens)

    if not isRoundActive() then
        return
    end

    local now = tick()
    for _, screen in ipairs(collectComputerScreens()) do
        if screen and screen.Parent then
            if isHackableComputerScreen(screen) then
                trackedHackableScreens[screen] = true
                screenLastHackableAt[screen] = now
            else
                local lastHackableAt = screenLastHackableAt[screen]
                if lastHackableAt and now - lastHackableAt <= hackableGracePeriod then
                    trackedHackableScreens[screen] = true
                end
            end
        end
    end

    for screen in pairs(screenLastHackableAt) do
        if not screen or not screen.Parent then
            screenLastHackableAt[screen] = nil
        end
    end
end

local function removeButton(screen)
    local button = overlayButtons[screen]
    if button then
        button:Destroy()
        overlayButtons[screen] = nil
    end
end

local function clearButtons()
    for screen in pairs(overlayButtons) do
        removeButton(screen)
    end
end

local function ensureOverlayGui()
    if overlayGui and overlayGui.Parent then
        return
    end

    if overlayGui then
        pcall(function()
            overlayGui:Destroy()
        end)
    end

    overlayGui = Instance.new("ScreenGui")
    overlayGui.Name = "ComputerTPHelper"
    overlayGui.ResetOnSpawn = false
    overlayGui.IgnoreGuiInset = true
    overlayGui.DisplayOrder = 120
    overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    overlayGui.Parent = PlayerGui
end

local function ensureButton(screen, isBest)
    ensureOverlayGui()

    local button = overlayButtons[screen]
    if not button or not button.Parent then
        button = Instance.new("TextButton")
        button.Name = "ComputerTPButton"
        button.AnchorPoint = Vector2.new(0.5, 0.5)
        button.Size = UDim2.fromOffset(120, 34)
        button.Visible = false
        button.BorderSizePixel = 0
        button.TextColor3 = Color3.fromRGB(15, 15, 15)
        button.Font = Enum.Font.GothamBold
        button.TextScaled = true
        button.Active = true
        button.Selectable = true
        button.AutoButtonColor = true
        button.ZIndex = 120
        button.Parent = overlayGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = button

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1.5
        stroke.Color = Color3.fromRGB(255, 255, 255)
        stroke.Parent = button

        button.Activated:Connect(function()
            local success, reason = teleportToScreen(screen)
            if not success then
                warn(string.format("[ComputerTP] failed to teleport (%s)", reason))
            end
        end)

        overlayButtons[screen] = button
    end

    button.Text = isBest and "BEST TP" or "TELEPORT"
    button.BackgroundColor3 = isBest and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(0, 255, 255)
    return button
end

local function reconcileButtons()
    if not isRoundActive() then
        clearButtons()
        return
    end

    updateTrackedHackableScreens()

    local screens = {}
    for screen in pairs(trackedHackableScreens) do
        table.insert(screens, screen)
    end

    local bestScreen = getNearestHackableScreen(screens)

    for _, screen in ipairs(screens) do
        if screen and screen.Parent then
            ensureButton(screen, screen == bestScreen)
        end
    end

    for screen in pairs(overlayButtons) do
        if not trackedHackableScreens[screen] then
            removeButton(screen)
        end
    end
end

local function cleanup()
    if renderConnection then
        renderConnection:Disconnect()
        renderConnection = nil
    end

    clearButtons()
    table.clear(trackedHackableScreens)
    table.clear(screenLastHackableAt)

    if overlayGui then
        overlayGui:Destroy()
        overlayGui = nil
    end

    local existingOverlay = PlayerGui:FindFirstChild("ComputerTPHelper")
    if existingOverlay then
        existingOverlay:Destroy()
    end
end

cleanup()
ensureOverlayGui()

renderConnection = RunService.RenderStepped:Connect(function()
    local now = tick()
    if now - lastRefreshAt >= refreshInterval then
        lastRefreshAt = now
        reconcileButtons()
    end

    local camera = Workspace.CurrentCamera
    if not camera or not isRoundActive() then
        for _, button in pairs(overlayButtons) do
            if button then
                button.Visible = false
            end
        end
        return
    end

    for screen, button in pairs(overlayButtons) do
        if not screen or not screen.Parent or not button or not button.Parent then
            removeButton(screen)
        else
            local point, onScreen = camera:WorldToViewportPoint(screen.Position)
            if onScreen and point.Z > 0 then
                button.Visible = true
                button.Position = UDim2.fromOffset(point.X, point.Y - 38)
            else
                button.Visible = false
            end
        end
    end
end)

if runtimeEnv then
    runtimeEnv.ComputerTPHelperRuntime = {
        Stop = cleanup
    }
end

print("[ComputerTP] helper loaded")

]================]

local bladeBallSource = [================[
-- Minimal Blade Ball scaffold using the same Obsidian UI shell as the FTF script.
-- Feature logic can be dropped into the toggle callbacks later.

-- selene: allow(incorrect_standard_library_use)
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()

local State = {
    AutoParry = false,
    BallESP = false,
    PlayerESP = false,
    AutoSpam = false
}

local function setState(stateKey, featureName, value)
    State[stateKey] = value
    print(string.format("[Blade Ball] %s = %s", featureName, tostring(State[stateKey])))
end

local Window = Library:CreateWindow({
    Title = "vesper.lua",
    Footer = "Blade Ball scaffold",
    Center = true,
    Resizable = true,
    AutoShow = true,
    ToggleKeybind = Enum.KeyCode.Insert
})

local MainTab = Window:AddTab("Main", "shield")
local VisualTab = Window:AddTab("Visuals", "user")
local SettingsTab = Window:AddTab("Settings", "settings")
local InfoTab = Window:AddTab("Info", "info")

local MainGroup = MainTab:AddLeftGroupbox("Combat")
local VisualGroup = VisualTab:AddLeftGroupbox("ESP")
local SettingsGroup = SettingsTab:AddLeftGroupbox("Controls")
local InfoGroup = InfoTab:AddLeftGroupbox("About")

MainGroup:AddToggle("BladeBall_AutoParry", {
    Text = "Auto Parry",
    Default = false,
    Callback = function(value)
        setState("AutoParry", "Auto Parry", value)
    end
})

MainGroup:AddToggle("BladeBall_AutoSpam", {
    Text = "Auto Spam",
    Default = false,
    Callback = function(value)
        setState("AutoSpam", "Auto Spam", value)
    end
})

VisualGroup:AddToggle("BladeBall_BallESP", {
    Text = "Ball ESP",
    Default = false,
    Callback = function(value)
        setState("BallESP", "Ball ESP", value)
    end
})

VisualGroup:AddToggle("BladeBall_PlayerESP", {
    Text = "Player ESP",
    Default = false,
    Callback = function(value)
        setState("PlayerESP", "Player ESP", value)
    end
})

SettingsGroup:AddButton({
    Text = "Unload",
    Func = function()
        if Library and Library.Unload and not Library.Unloaded then
            pcall(function()
                Library:Unload()
            end)
        end
    end
})

InfoGroup:AddLabel("vesper.lua - Blade Ball")
InfoGroup:AddLabel("")
InfoGroup:AddLabel("Scaffold ready.")
InfoGroup:AddLabel("Drop Blade Ball feature logic into the toggle callbacks.")
InfoGroup:AddLabel("")
InfoGroup:AddLabel("Controls:")
InfoGroup:AddLabel("  - INSERT - Show / Hide UI")

print("Blade Ball scaffold loaded successfully!")
print("Press INSERT to open the UI")

]================]

if normalizedRuntimeName:find("flee the facility", 1, true)
    or normalizedGameName:find("flee the facility", 1, true)
then
    runChunk("main.lua", mainSource)
    runChunk("computer_tp_helper.lua", helperSource)
elseif normalizedRuntimeName:find("blade ball", 1, true)
    or normalizedGameName:find("blade ball", 1, true)
then
    runChunk("blade_ball.lua", bladeBallSource)
else
    error(string.format(
        "[LuminaLoader] unsupported game | name=%s | placeId=%s | universeId=%s",
        tostring(runtimeName),
        tostring(game.PlaceId),
        tostring(game.GameId)
    ))
end

