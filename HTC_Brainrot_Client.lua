--[[
HTC AUTONOMOUS CLIENT - BRAINROT EDITION
Client-side discovery, safe NPC targeting, normal movement, carry diagnostics and FPS monitoring.

Compatibility:
- Uses standard Roblox client APIs only.
- No executor-only APIs, hidden properties, remote spying/replay, or invented remote names.
- Does not force pickup/steal actions. The server/game must implement and authorize those actions.
- Aim mode only tracks non-player NPC models; it does not target other players.
- Object discovery is heuristic and may need tags/attributes added in your own Studio game for accuracy.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

local APP_NAME = "HTC_Brainrot_Client"
local old = PlayerGui:FindFirstChild(APP_NAME)
if old then old:Destroy() end

local State = {
    running = true,
    autoMove = false,
    aimAssist = false,
    carryAssist = false,
    perfMonitor = true,
    discovery = {},
    counts = {},
    target = nil,
    carryCandidate = nil,
    fps = 0,
    pingText = "Ping: unavailable",
    lastScan = 0,
    scanInterval = 1.25,
    moveInterval = 0.65,
    lastMove = 0,
    status = "Ready. Press SCAN to inspect client-visible objects.",
    errors = 0,
}

local function safeName(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or (inst and inst.Name or "?")
end

local function isPlayerCharacter(model)
    return model:IsA("Model") and Players:GetPlayerFromCharacter(model) ~= nil
end

local function getHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end

local function getRoot(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function isAliveNpc(model)
    if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then
        return false
    end
    if isPlayerCharacter(model) then return false end
    local humanoid = getHumanoid(model)
    local root = getRoot(model)
    return humanoid ~= nil and humanoid.Health > 0 and root ~= nil
end

local function hasTagOrAttribute(inst, tag, attribute)
    local tagged = false
    pcall(function() tagged = CollectionService:HasTag(inst, tag) end)
    if tagged then return true end
    local ok, value = pcall(function() return inst:GetAttribute(attribute) end)
    return ok and value == true
end

local function classify(inst)
    local labels = {}
    local lower = string.lower(inst.Name)

    if inst:IsA("Model") then
        if isPlayerCharacter(inst) then
            table.insert(labels, "PlayerCharacter")
        elseif getHumanoid(inst) and getRoot(inst) then
            table.insert(labels, "CharacterLike")
            if getHumanoid(inst).Health > 0 then table.insert(labels, "Alive") end
        end
    end

    if inst:IsA("BasePart") then
        table.insert(labels, "Part")
    end
    if inst:IsA("Tool") then table.insert(labels, "Tool") end
    if inst:IsA("ProximityPrompt") then table.insert(labels, "ProximityPrompt") end
    if inst:IsA("ClickDetector") then table.insert(labels, "ClickDetector") end
    if inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
        table.insert(labels, "WorldGui")
    end

    if hasTagOrAttribute(inst, "HTC_Target", "HTC_Target") then
        table.insert(labels, "HTC_Target")
    end
    if hasTagOrAttribute(inst, "HTC_Carryable", "HTC_Carryable") then
        table.insert(labels, "HTC_Carryable")
    end

    -- Name hints are only clues, not proof that an object can be picked up or stolen.
    if string.find(lower, "brainrot", 1, true)
        or string.find(lower, "brain", 1, true)
        or string.find(lower, "carry", 1, true)
        or string.find(lower, "pickup", 1, true)
        or string.find(lower, "pick_up", 1, true)
        or string.find(lower, "item", 1, true) then
        table.insert(labels, "PossibleCarryName")
    end

    if string.find(lower, "base", 1, true)
        or string.find(lower, "plot", 1, true)
        or string.find(lower, "conveyor", 1, true)
        or string.find(lower, "belt", 1, true)
        or string.find(lower, "spawn", 1, true) then
        table.insert(labels, "PossibleGameplayObject")
    end

    return labels
end

local function scanWorkspace()
    local index = {}
    local counts = {
        total = 0, models = 0, humanoids = 0, parts = 0, prompts = 0,
        tools = 0, playerCharacters = 0, npcLike = 0, taggedTargets = 0,
        taggedCarryables = 0, carryHints = 0, gameplayHints = 0,
    }

    local ok, descendants = pcall(function() return Workspace:GetDescendants() end)
    if not ok then
        State.errors += 1
        State.status = "Scan failed: " .. tostring(descendants)
        return
    end

    -- Yield periodically to avoid freezing the client on large maps.
    for i, inst in ipairs(descendants) do
        if not State.running then return end
        local labels = classify(inst)
        index[inst] = {name = inst.Name, path = safeName(inst), className = inst.ClassName, labels = labels}
        counts.total += 1

        if inst:IsA("Model") then
            counts.models += 1
            if isPlayerCharacter(inst) then
                counts.playerCharacters += 1
            elseif getHumanoid(inst) and getRoot(inst) then
                counts.npcLike += 1
            end
        end
        if inst:IsA("Humanoid") then counts.humanoids += 1 end
        if inst:IsA("BasePart") then counts.parts += 1 end
        if inst:IsA("ProximityPrompt") then counts.prompts += 1 end
        if inst:IsA("Tool") then counts.tools += 1 end
        if hasTagOrAttribute(inst, "HTC_Target", "HTC_Target") then counts.taggedTargets += 1 end
        if hasTagOrAttribute(inst, "HTC_Carryable", "HTC_Carryable") then counts.taggedCarryables += 1 end

        for _, label in ipairs(labels) do
            if label == "PossibleCarryName" then counts.carryHints += 1 end
            if label == "PossibleGameplayObject" then counts.gameplayHints += 1 end
        end

        if i % 650 == 0 then task.wait() end
    end

    State.discovery = index
    State.counts = counts
    State.lastScan = os.clock()
    State.status = ("Scan complete: %d client-visible descendants."):format(counts.total)
end

local function getCharacter()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if character and humanoid and humanoid.Health > 0 and root then
        return character, humanoid, root
    end
    return nil
end

local function findNpcCandidates()
    local list, seen = {}, {}
    for inst in pairs(State.discovery) do
        if inst:IsA("Model") and not seen[inst] and isAliveNpc(inst) then
            seen[inst] = true
            table.insert(list, inst)
        end
    end
    -- Include tagged targets even if a scan is still in progress.
    local ok, tagged = pcall(function() return CollectionService:GetTagged("HTC_Target") end)
    if ok then
        for _, inst in ipairs(tagged) do
            if inst:IsA("Model") and not seen[inst] and isAliveNpc(inst) then
                seen[inst] = true
                table.insert(list, inst)
            end
        end
    end
    return list
end

local function nearestNpc(maxDistance)
    local _, _, root = getCharacter()
    if not root then return nil end
    local best, bestDistance
    for _, model in ipairs(findNpcCandidates()) do
        local targetRoot = getRoot(model)
        if targetRoot then
            local distance = (targetRoot.Position - root.Position).Magnitude
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = model, distance
            end
        end
    end
    return best, bestDistance
end

local function isLikelyCarryable(inst)
    if not inst or not inst.Parent then return false end
    if hasTagOrAttribute(inst, "HTC_Carryable", "HTC_Carryable") then return true end
    local lower = string.lower(inst.Name)
    return string.find(lower, "brainrot", 1, true) ~= nil
        or string.find(lower, "brain", 1, true) ~= nil
        or string.find(lower, "carry", 1, true) ~= nil
        or string.find(lower, "pickup", 1, true) ~= nil
        or string.find(lower, "pick_up", 1, true) ~= nil
end

local function nearestCarryCandidate(maxDistance)
    local _, _, root = getCharacter()
    if not root then return nil end
    local best, bestDistance
    local seen = {}

    for inst in pairs(State.discovery) do
        local candidate
        if inst:IsA("BasePart") and isLikelyCarryable(inst) then
            candidate = inst
        elseif inst:IsA("Model") and isLikelyCarryable(inst) then
            candidate = getRoot(inst)
        end

        if candidate and candidate:IsDescendantOf(Workspace) and not seen[candidate] then
            seen[candidate] = true
            local distance = (candidate.Position - root.Position).Magnitude
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                best, bestDistance = candidate, distance
            end
        end
    end

    -- A prompt is useful evidence of an interaction, but does not prove pickup semantics.
    return best, bestDistance
end

local function targetForAim()
    local _, _, root = getCharacter()
    if not root then return nil end
    local best, bestScore
    local viewport = Camera and Camera.ViewportSize or Vector2.new(800, 600)
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)

    for _, model in ipairs(findNpcCandidates()) do
        local targetRoot = getRoot(model)
        if targetRoot then
            local screenPoint, onScreen = Camera:WorldToViewportPoint(targetRoot.Position)
            if onScreen and screenPoint.Z > 0 then
                local screenDistance = (Vector2.new(screenPoint.X, screenPoint.Y) - center).Magnitude
                local worldDistance = (targetRoot.Position - root.Position).Magnitude
                if worldDistance <= 250 then
                    local score = screenDistance + worldDistance * 0.15
                    if not bestScore or score < bestScore then
                        best, bestScore = model, score
                    end
                end
            end
        end
    end
    return best
end

-- UI
local gui = Instance.new("ScreenGui")
gui.Name = APP_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 999
gui.Parent = PlayerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 320, 0, 455)
panel.Position = UDim2.new(0, 14, 0.2, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(105, 70, 190)
stroke.Thickness = 1.5
stroke.Parent = panel

local header = Instance.new("TextButton")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(96, 55, 170)
header.Text = "HTC BRAINROT CLIENT  •  drag / hide"
header.TextColor3 = Color3.new(1, 1, 1)
header.Font = Enum.Font.GothamBold
header.TextSize = 12
header.Parent = panel
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

local status = Instance.new("TextLabel")
status.Position = UDim2.fromOffset(9, 47)
status.Size = UDim2.new(1, -18, 0, 74)
status.BackgroundColor3 = Color3.fromRGB(31, 34, 45)
status.TextColor3 = Color3.fromRGB(235, 235, 245)
status.Font = Enum.Font.Code
status.TextSize = 11
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Text = State.status
status.Parent = panel
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 7)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(9, 128)
scroll.Size = UDim2.new(1, -18, 1, -137)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 5)
layout.Parent = scroll

local function addButton(label, callback)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -3, 0, 34)
    b.BackgroundColor3 = Color3.fromRGB(44, 47, 62)
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.Text = label
    b.AutoButtonColor = true
    b.Parent = scroll
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    b.Activated:Connect(callback)
    return b
end

local function toggleButton(label, stateKey)
    local b
    local function refresh()
        b.Text = label .. (State[stateKey] and "  [ON]" or "  [OFF]")
        b.BackgroundColor3 = State[stateKey] and Color3.fromRGB(34, 115, 83) or Color3.fromRGB(44, 47, 62)
    end
    b = addButton(label, function()
        State[stateKey] = not State[stateKey]
        refresh()
        if stateKey == "autoMove" and not State.autoMove then
            local _, humanoid = getCharacter()
            if humanoid then humanoid:Move(Vector3.zero, false) end
        end
        if stateKey == "aimAssist" and not State.aimAssist then State.target = nil end
        State.status = label .. (State[stateKey] and " enabled." or " disabled.")
    end)
    refresh()
    return b
end

addButton("SCAN WORKSPACE", function()
    State.status = "Scanning client-visible objects..."
    task.spawn(scanWorkspace)
end)

toggleButton("AUTO MOVE TO NEAREST NPC", "autoMove")
toggleButton("AIM ASSIST (NPC ONLY)", "aimAssist")
toggleButton("CARRY ASSIST (NAVIGATE ONLY)", "carryAssist")
toggleButton("FPS MONITOR", "perfMonitor")

addButton("FIND NEAREST CARRY CANDIDATE", function()
    local item, distance = nearestCarryCandidate(250)
    State.carryCandidate = item
    if item then
        State.status = ("Candidate: %s\nDistance: %.1f studs\nPickup must be approved by your game's server."):format(safeName(item), distance or 0)
    else
        State.status = "No likely carryable object found nearby. Add HTC_Carryable tag/attribute in your own game for reliable discovery."
    end
end)

addButton("MOVE TO CARRY CANDIDATE", function()
    local item, distance = nearestCarryCandidate(250)
    if not item then
        State.status = "No carry candidate found."
        return
    end
    local _, humanoid = getCharacter()
    if not humanoid then
        State.status = "Character unavailable."
        return
    end
    humanoid:MoveTo(item.Position)
    State.carryCandidate = item
    State.status = ("Walking to %s (%.1f studs).\nUse the game's normal interaction prompt to pick it up."):format(safeName(item), distance or 0)
end)

addButton("REPORT DISCOVERY COUNTS", function()
    local c = State.counts
    State.status = ("Objects %d | Models %d | Parts %d\nNPC-like %d | Prompts %d | Tools %d\nTagged target %d | tagged carryable %d\nName hints: carry %d, gameplay %d"):format(
        c.total or 0, c.models or 0, c.parts or 0, c.npcLike or 0, c.prompts or 0,
        c.tools or 0, c.taggedTargets or 0, c.taggedCarryables or 0, c.carryHints or 0, c.gameplayHints or 0)
end)

local compact = false
header.Activated:Connect(function()
    compact = not compact
    status.Visible = not compact
    scroll.Visible = not compact
    panel.Size = compact and UDim2.new(0, 320, 0, 40) or UDim2.new(0, 320, 0, 455)
    header.Text = compact and "HTC BRAINROT CLIENT  •  tap to expand" or "HTC BRAINROT CLIENT  •  drag / hide"
end)

addButton("CLOSE HTC", function()
    State.running = false
    State.autoMove = false
    State.aimAssist = false
    if gui then gui:Destroy() end
end)

-- Drag panel for mouse and touch.
do
    local dragging, dragInput, dragStart, startPosition
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and panel.Parent then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
end

-- Incremental updates make the discovery index respond to spawned/despawned objects.
Workspace.DescendantAdded:Connect(function(inst)
    if State.running then
        task.defer(function()
            if inst.Parent and not State.discovery[inst] then
                local labels = classify(inst)
                State.discovery[inst] = {name = inst.Name, path = safeName(inst), className = inst.ClassName, labels = labels}
            end
        end)
    end
end)

Workspace.DescendantRemoving:Connect(function(inst)
    State.discovery[inst] = nil
    if State.target == inst then State.target = nil end
    if State.carryCandidate == inst then State.carryCandidate = nil end
end)

-- Main loop: ordinary Humanoid movement, NPC-only camera tracking and lightweight FPS sample.
local elapsed, frames, lastHud, lastAction = 0, 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
    if not State.running then return end

    elapsed += dt
    frames += 1
    if elapsed >= 1 then
        State.fps = math.floor(frames / elapsed + 0.5)
        elapsed, frames = 0, 0
    end

    if os.clock() - State.lastScan > State.scanInterval and next(State.discovery) == nil then
        -- First pass only; don't rescan automatically on every interval.
        State.lastScan = os.clock()
        task.spawn(scanWorkspace)
    end

    if os.clock() - lastAction >= State.moveInterval then
        lastAction = os.clock()
        local _, humanoid, root = getCharacter()

        if State.autoMove and humanoid and root then
            local target, distance = nearestNpc(250)
            State.target = target
            local targetRoot = target and getRoot(target)
            if targetRoot then
                humanoid:MoveTo(targetRoot.Position)
                State.status = ("Auto Move: %s\nDistance %.1f studs"):format(target.Name, distance or 0)
            else
                State.status = "Auto Move: no eligible NPC found."
            end
        end

        if State.carryAssist and humanoid and root then
            local item, distance = nearestCarryCandidate(250)
            State.carryCandidate = item
            if item then
                humanoid:MoveTo(item.Position)
                if not State.autoMove then
                    State.status = ("Carry assist navigating to %s\nDistance %.1f. Pickup is server-controlled."):format(item.Name, distance or 0)
                end
            end
        end
    end

    if State.aimAssist and Camera then
        local target = targetForAim()
        State.target = target
        local targetRoot = target and getRoot(target)
        if targetRoot then
            -- Gentle camera tracking of non-player NPCs only. No attack or remote invocation.
            local current = Camera.CFrame
            local desired = CFrame.lookAt(current.Position, targetRoot.Position)
            Camera.CFrame = current:Lerp(desired, math.clamp(dt * 3.5, 0, 0.12))
        end
    end

    if os.clock() - lastHud >= 0.5 then
        lastHud = os.clock()
        if State.perfMonitor then
            local c = State.counts
            status.Text = ("HTC running | FPS ~%d | errors %d\nIndexed %d | NPC-like %d | prompts %d\nAutoMove %s | Aim %s | CarryAssist %s\n%s"):format(
                State.fps, State.errors, c.total or 0, c.npcLike or 0, c.prompts or 0,
                tostring(State.autoMove), tostring(State.aimAssist), tostring(State.carryAssist), State.status)
        else
            status.Text = State.status
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    State.target = nil
    State.autoMove = false
    State.aimAssist = false
    State.carryAssist = false
    task.wait(0.4)
    if gui.Parent then
        State.status = "Respawn detected. Movement/aim/carry assist reset."
    end
end)

task.spawn(scanWorkspace)
print("[HTC] Brainrot client loaded. Client-visible discovery only; server-authorized actions are required for carry/steal.")
