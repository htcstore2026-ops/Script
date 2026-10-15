--[[
HTC AUTONOMOUS CLIENT - BRAINROT EDITION  (v2, rewritten for robustness)

Client-side discovery, NPC targeting, pathfinding movement, carry navigation, FPS/ping monitor.

Rules kept from the original:
- Standard Roblox client APIs only. No remote spying/replay, no executor-only APIs.
- Does NOT force pickup/steal. Pickup must go through the game's own prompt/server.
- Aim assist only tracks non-player NPC models, never other players.

What changed vs v1 (summary):
- Incremental registries (NPCs / carryables / prompts) instead of indexing every descendant.
- Scan lock (no overlapping scans), chunked scan, safe against errors.
- Pathfinding with stuck detection + jump handling, direct-MoveTo fallback.
- Aim: BindToRenderStep after the camera, line-of-sight check, cached retargeting.
- Carry candidates ignore items that belong to any player's character.
- UI: drag no longer collapses panel, clamped to screen, toggles stay in sync, STOP button.
- Full cleanup (all connections, render bind, GUI) on CLOSE or on re-run.
- Every step wrapped in pcall with an error counter shown in the HUD.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[HTC] This script must run on the client.")
    return
end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local APP_NAME = "HTC_Brainrot_Client"
local RENDER_BIND = "HTC_AimAssist"

----------------------------------------------------------------------
-- Single instance: clean up any previous run (GUI + connections)
----------------------------------------------------------------------
if shared.HTC_Cleanup then
    pcall(shared.HTC_Cleanup)
    shared.HTC_Cleanup = nil
end
do
    local oldGui = PlayerGui:FindFirstChild(APP_NAME)
    if oldGui then oldGui:Destroy() end
end

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local CONFIG = {
    maxDistance = 250,          -- max studs for targets/candidates
    stopDistance = 5,           -- stop this close to the goal
    selectInterval = 0.4,       -- how often the goal is re-selected
    navInterval = 0.12,         -- how often movement is stepped
    repathMinInterval = 0.6,    -- minimum time between path computations
    waypointReach = 3.5,        -- horizontal studs to consider a waypoint reached
    stuckSeconds = 1.5,         -- time without moving before unstick
    aimSmoothing = 3.5,
    aimMaxStep = 0.12,
    aimRetargetInterval = 0.1,
    scanBatch = 500,            -- descendants per frame during scan
    hudInterval = 0.5,
    tagTarget = "HTC_Target",
    tagCarry = "HTC_Carryable",
    carryKeywords = { "brainrot", "brain", "carry", "pickup", "pick_up" },
    promptHintDistance = 15,
}

----------------------------------------------------------------------
-- Maid (cleanup helper)
----------------------------------------------------------------------
local Maid = { tasks = {} }
function Maid.give(task_)
    table.insert(Maid.tasks, task_)
    return task_
end
function Maid.clean()
    for _, t in ipairs(Maid.tasks) do
        local kind = typeof(t)
        pcall(function()
            if kind == "RBXScriptConnection" then
                t:Disconnect()
            elseif kind == "Instance" then
                t:Destroy()
            elseif kind == "function" then
                t()
            end
        end)
    end
    table.clear(Maid.tasks)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local State = {
    running = true,
    autoMove = false,
    aimAssist = false,
    carryAssist = false,
    perfMonitor = true,
    usePathfinding = true,
    aimLineOfSight = true,

    target = nil,          -- current NPC target for auto move
    aimTarget = nil,       -- current NPC aim target
    carryCandidate = nil,  -- registered carry instance (Part or Model)
    manualGoal = nil,      -- one-shot "move to candidate" goal (instance)
    goalPart = nil,        -- BasePart currently being navigated to
    goalKind = nil,        -- "manual" | "carry" | "npc"

    fps = 0,
    ping = nil,
    errors = 0,
    lastError = nil,
    status = "Ready. Press SCAN to inspect client-visible objects.",
}

local function setStatus(text)
    State.status = text
end

local function reportError(where, err)
    State.errors += 1
    State.lastError = where .. ": " .. tostring(err)
end

----------------------------------------------------------------------
-- Basic helpers
----------------------------------------------------------------------
local function safeName(inst)
    local ok, value = pcall(function() return inst:GetFullName() end)
    if ok then return value end
    return inst and inst.Name or "?"
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

-- Anchor part used to get a position out of a registered Part or Model.
local function getAnchor(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return getRoot(inst) end
    return nil
end

local function isPlayerCharacter(model)
    return model:IsA("Model") and Players:GetPlayerFromCharacter(model) ~= nil
end

-- True if inst is (inside) any player's character.
local function belongsToPlayer(inst)
    local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
    while model do
        if Players:GetPlayerFromCharacter(model) then return true end
        model = model:FindFirstAncestorOfClass("Model")
    end
    return false
end

local function isAliveNpc(model)
    if not model or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then
        return false
    end
    if isPlayerCharacter(model) then return false end
    local humanoid = getHumanoid(model)
    return humanoid ~= nil and humanoid.Health > 0 and getRoot(model) ~= nil
end

local function isTagged(inst, tag)
    if CollectionService:HasTag(inst, tag) then return true end
    local ok, value = pcall(function() return inst:GetAttribute(tag) end)
    return ok and value == true
end

local function nameLooksCarryable(name)
    local lower = string.lower(name)
    for _, keyword in ipairs(CONFIG.carryKeywords) do
        if string.find(lower, keyword, 1, true) then return true end
    end
    return false
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

----------------------------------------------------------------------
-- Registry (incrementally maintained discovery index)
----------------------------------------------------------------------
local Registry = {
    npcs = {},        -- [Model] = true
    carryables = {},  -- [Part or Model] = true
    prompts = {},     -- [ProximityPrompt] = true
    n = { npcs = 0, carryables = 0, prompts = 0 },
    scanTotal = 0,
    lastScan = 0,
    scanning = false,
}

local function regAdd(set, inst)
    if not Registry[set][inst] then
        Registry[set][inst] = true
        Registry.n[set] += 1
    end
end

local function regRemove(set, inst)
    if Registry[set][inst] then
        Registry[set][inst] = nil
        Registry.n[set] -= 1
    end
end

local function carryMatch(inst)
    return isTagged(inst, CONFIG.tagCarry) or nameLooksCarryable(inst.Name)
end

local function track(inst)
    if inst:IsA("Humanoid") then
        local model = inst.Parent
        if model and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
            regAdd("npcs", model)
        end
    elseif inst:IsA("ProximityPrompt") then
        regAdd("prompts", inst)
    end

    local isPart = inst:IsA("BasePart")
    local isModel = inst:IsA("Model")
    if isPart or isModel then
        if isModel and isTagged(inst, CONFIG.tagTarget) then
            regAdd("npcs", inst) -- validated later by isAliveNpc
        end
        if carryMatch(inst) then
            -- Avoid double entries: skip a part whose parent model is already a candidate.
            local parent = inst.Parent
            local nested = isPart and parent and parent:IsA("Model") and carryMatch(parent)
            if not nested then
                regAdd("carryables", inst)
            end
        end
    end
end

local function untrack(inst)
    regRemove("npcs", inst)
    regRemove("carryables", inst)
    regRemove("prompts", inst)
    if inst:IsA("Humanoid") and inst.Parent then
        regRemove("npcs", inst.Parent)
    end
    if State.target == inst then State.target = nil end
    if State.aimTarget == inst then State.aimTarget = nil end
    if State.carryCandidate == inst then State.carryCandidate = nil end
    if State.manualGoal == inst then State.manualGoal = nil end
    if State.goalPart == inst then State.goalPart = nil end
end

local function scanWorkspace()
    if Registry.scanning or not State.running then return end
    Registry.scanning = true
    setStatus("Scanning client-visible objects...")

    local ok, err = pcall(function()
        local descendants = Workspace:GetDescendants()
        for i, inst in ipairs(descendants) do
            if not State.running then return end
            local trackOk, trackErr = pcall(track, inst)
            if not trackOk then reportError("track", trackErr) end
            if i % CONFIG.scanBatch == 0 then task.wait() end
        end
        Registry.scanTotal = #descendants
        Registry.lastScan = os.clock()
        setStatus(("Scan complete: %d descendants.\nNPC-like %d | carry hints %d | prompts %d"):format(
            #descendants, Registry.n.npcs, Registry.n.carryables, Registry.n.prompts))
    end)

    Registry.scanning = false
    if not ok then
        reportError("scan", err)
        setStatus("Scan failed: " .. tostring(err))
    end
end

----------------------------------------------------------------------
-- Queries
----------------------------------------------------------------------
local function nearestNpc(maxDistance)
    local _, _, root = getCharacter()
    if not root then return nil end
    local best, bestDistance
    for model in pairs(Registry.npcs) do
        if isAliveNpc(model) then
            local targetRoot = getRoot(model)
            if targetRoot then
                local distance = (targetRoot.Position - root.Position).Magnitude
                if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                    best, bestDistance = model, distance
                end
            end
        elseif not model:IsDescendantOf(Workspace) then
            regRemove("npcs", model)
        end
    end
    return best, bestDistance
end

-- Returns: registered instance, anchor part, distance
local function nearestCarry(maxDistance)
    local _, _, root = getCharacter()
    if not root then return nil end
    local best, bestAnchor, bestDistance
    for inst in pairs(Registry.carryables) do
        if not inst:IsDescendantOf(Workspace) then
            regRemove("carryables", inst)
        elseif not belongsToPlayer(inst) then
            local anchor = getAnchor(inst)
            if anchor then
                local distance = (anchor.Position - root.Position).Magnitude
                if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                    best, bestAnchor, bestDistance = inst, anchor, distance
                end
            end
        end
    end
    return best, bestAnchor, bestDistance
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasLineOfSight(fromPos, targetPart, targetModel)
    local character = LocalPlayer.Character
    rayParams.FilterDescendantsInstances = character and { character } or {}
    local result = Workspace:Raycast(fromPos, targetPart.Position - fromPos, rayParams)
    return result == nil or result.Instance:IsDescendantOf(targetModel)
end

local function pickAimTarget(cam, root)
    local viewport = cam.ViewportSize
    local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
    local scored = {}

    for model in pairs(Registry.npcs) do
        if isAliveNpc(model) then
            local targetRoot = getRoot(model)
            if targetRoot then
                local screenPoint, onScreen = cam:WorldToViewportPoint(targetRoot.Position)
                if onScreen and screenPoint.Z > 0 then
                    local worldDistance = (targetRoot.Position - root.Position).Magnitude
                    if worldDistance <= CONFIG.maxDistance then
                        local screenDistance = (Vector2.new(screenPoint.X, screenPoint.Y) - center).Magnitude
                        table.insert(scored, {
                            model = model,
                            root = targetRoot,
                            score = screenDistance + worldDistance * 0.15,
                        })
                    end
                end
            end
        end
    end

    table.sort(scored, function(a, b) return a.score < b.score end)
    for i = 1, math.min(#scored, 3) do
        local c = scored[i]
        if not State.aimLineOfSight or hasLineOfSight(cam.CFrame.Position, c.root, c.model) then
            return c.model
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Navigation (pathfinding + stuck detection + fallback)
----------------------------------------------------------------------
local Nav = {
    waypoints = nil,
    index = 1,
    goal = nil,
    computing = false,
    lastCompute = 0,
    lastPos = nil,
    lastMoveTime = 0,
}

local function navReset()
    Nav.waypoints = nil
    Nav.index = 1
    Nav.goal = nil
    Nav.lastPos = nil
end

local function stopMoving()
    navReset()
    local _, humanoid, root = getCharacter()
    if humanoid and root then
        humanoid:Move(Vector3.zero, false)
        humanoid:MoveTo(root.Position)
    end
end

local function computePath(startPos, goalPos)
    if Nav.computing then return end
    Nav.computing = true
    Nav.goal = goalPos
    Nav.lastCompute = os.clock()

    task.spawn(function()
        local ok, waypoints = pcall(function()
            local path = PathfindingService:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = true,
            })
            path:ComputeAsync(startPos, goalPos)
            if path.Status == Enum.PathStatus.Success then
                return path:GetWaypoints()
            end
            return nil
        end)
        Nav.computing = false
        if not State.running then return end
        if ok and waypoints and #waypoints > 0 then
            Nav.waypoints = waypoints
            Nav.index = math.min(2, #waypoints)
        else
            Nav.waypoints = nil
            if not ok then reportError("pathfinding", waypoints) end
        end
    end)
end

-- Returns true when arrived.
local function navStep(goalPos)
    local _, humanoid, root = getCharacter()
    if not humanoid or not root then return false end

    if (goalPos - root.Position).Magnitude <= CONFIG.stopDistance then
        humanoid:MoveTo(root.Position)
        navReset()
        return true
    end

    local now = os.clock()

    -- Stuck detection
    if not Nav.lastPos or (root.Position - Nav.lastPos).Magnitude > 1 then
        Nav.lastPos = root.Position
        Nav.lastMoveTime = now
    elseif now - Nav.lastMoveTime > CONFIG.stuckSeconds then
        humanoid.Jump = true
        Nav.waypoints = nil
        Nav.lastMoveTime = now
    end

    if not State.usePathfinding then
        humanoid:MoveTo(goalPos)
        return false
    end

    local goalMoved = Nav.goal and (goalPos - Nav.goal).Magnitude > 8
    local finished = Nav.waypoints and Nav.index > #Nav.waypoints
    if (not Nav.waypoints or goalMoved or finished)
        and not Nav.computing
        and now - Nav.lastCompute >= CONFIG.repathMinInterval then
        computePath(root.Position, goalPos)
    end

    local waypoints = Nav.waypoints
    local waypoint = waypoints and waypoints[Nav.index]
    if waypoint then
        local dx = waypoint.Position.X - root.Position.X
        local dz = waypoint.Position.Z - root.Position.Z
        if math.sqrt(dx * dx + dz * dz) < CONFIG.waypointReach then
            Nav.index += 1
            waypoint = waypoints[Nav.index]
        end
    end

    if waypoint then
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        humanoid:MoveTo(waypoint.Position)
    else
        -- No path yet (computing / failed): head straight for the goal.
        humanoid:MoveTo(goalPos)
    end
    return false
end

----------------------------------------------------------------------
-- Goal selection (priority: manual > carry assist > auto move)
----------------------------------------------------------------------
local function selectGoal()
    local _, _, root = getCharacter()
    if not root then
        State.goalPart, State.goalKind = nil, nil
        return
    end

    if State.manualGoal then
        local anchor = getAnchor(State.manualGoal)
        if anchor and anchor:IsDescendantOf(Workspace) then
            State.goalPart, State.goalKind = anchor, "manual"
            setStatus(("Walking to %s\n%.1f studs. Use the game's normal prompt to pick up."):format(
                State.manualGoal.Name, (anchor.Position - root.Position).Magnitude))
            return
        end
        State.manualGoal = nil
    end

    if State.carryAssist then
        local inst, anchor, distance = nearestCarry(CONFIG.maxDistance)
        State.carryCandidate = inst
        if anchor then
            State.goalPart, State.goalKind = anchor, "carry"
            setStatus(("Carry assist -> %s\nDistance %.1f. Pickup is server-controlled."):format(inst.Name, distance or 0))
            return
        end
    end

    if State.autoMove then
        local npc, distance = nearestNpc(CONFIG.maxDistance)
        State.target = npc
        local npcRoot = npc and getRoot(npc)
        if npcRoot then
            State.goalPart, State.goalKind = npcRoot, "npc"
            setStatus(("Auto Move: %s\nDistance %.1f studs"):format(npc.Name, distance or 0))
            return
        end
        setStatus("Auto Move: no eligible NPC found.")
    end

    State.goalPart, State.goalKind = nil, nil
end

local function navigate()
    local part = State.goalPart
    if not part or not part:IsDescendantOf(Workspace) then
        return
    end
    local arrived = navStep(part.Position)
    if arrived and State.goalKind == "manual" then
        State.manualGoal = nil
        State.goalPart, State.goalKind = nil, nil
        setStatus("Arrived. Use the game's normal interaction prompt.")
    end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local function make(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props) do inst[key] = value end
    inst.Parent = parent
    return inst
end

local function corner(inst, radius)
    make("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local gui = make("ScreenGui", {
    Name = APP_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    DisplayOrder = 999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)
Maid.give(gui)

local PANEL_W, PANEL_H = 320, 480

local panel = make("Frame", {
    Name = "Panel",
    Size = UDim2.fromOffset(PANEL_W, PANEL_H),
    Position = UDim2.new(0, 14, 0.2, 0),
    BackgroundColor3 = Color3.fromRGB(20, 22, 30),
    BorderSizePixel = 0,
}, gui)
corner(panel, 12)
make("UIStroke", { Color = Color3.fromRGB(105, 70, 190), Thickness = 1.5 }, panel)

local header = make("TextButton", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = Color3.fromRGB(96, 55, 170),
    Text = "HTC BRAINROT CLIENT  •  drag / tap to hide",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    AutoButtonColor = false,
}, panel)
corner(header, 10)

local statusLabel = make("TextLabel", {
    Name = "Status",
    Position = UDim2.fromOffset(9, 47),
    Size = UDim2.new(1, -18, 0, 112),
    BackgroundColor3 = Color3.fromRGB(31, 34, 45),
    TextColor3 = Color3.fromRGB(235, 235, 245),
    Font = Enum.Font.Code,
    TextSize = 11,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Text = State.status,
}, panel)
corner(statusLabel, 7)

local scroll = make("ScrollingFrame", {
    Name = "Buttons",
    Position = UDim2.fromOffset(9, 166),
    Size = UDim2.new(1, -18, 1, -175),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(),
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 5) }, scroll)

local function addButton(label, callback)
    local button = make("TextButton", {
        Size = UDim2.new(1, -8, 0, 34),
        BackgroundColor3 = Color3.fromRGB(44, 47, 62),
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        Text = label,
        AutoButtonColor = true,
    }, scroll)
    corner(button, 7)
    button.Activated:Connect(function()
        local ok, err = pcall(callback)
        if not ok then reportError(label, err) end
    end)
    return button
end

local refreshers = {}
local function refreshToggles()
    for _, refresh in ipairs(refreshers) do refresh() end
end

local function toggleButton(label, key, onChange)
    local button
    local function refresh()
        button.Text = label .. (State[key] and "  [ON]" or "  [OFF]")
        button.BackgroundColor3 = State[key] and Color3.fromRGB(34, 115, 83) or Color3.fromRGB(44, 47, 62)
    end
    button = addButton(label, function()
        State[key] = not State[key]
        refresh()
        if onChange then onChange(State[key]) end
        setStatus(label .. (State[key] and " enabled." or " disabled."))
    end)
    table.insert(refreshers, refresh)
    refresh()
    return button
end

local function releaseIfIdle()
    if not State.autoMove and not State.carryAssist and not State.manualGoal then
        State.goalPart, State.goalKind = nil, nil
        stopMoving()
    end
end

addButton("SCAN WORKSPACE", function()
    task.spawn(scanWorkspace)
end)

toggleButton("AUTO MOVE TO NEAREST NPC", "autoMove", function(on)
    if not on then State.target = nil; releaseIfIdle() end
end)
toggleButton("AIM ASSIST (NPC ONLY)", "aimAssist", function(on)
    if not on then State.aimTarget = nil end
end)
toggleButton("CARRY ASSIST (NAVIGATE ONLY)", "carryAssist", function(on)
    if not on then State.carryCandidate = nil; releaseIfIdle() end
end)
toggleButton("PATHFINDING", "usePathfinding", function() navReset() end)
toggleButton("AIM LINE-OF-SIGHT CHECK", "aimLineOfSight")
toggleButton("FPS MONITOR", "perfMonitor")

addButton("FIND NEAREST CARRY CANDIDATE", function()
    local inst, _, distance = nearestCarry(CONFIG.maxDistance)
    State.carryCandidate = inst
    if inst then
        setStatus(("Candidate: %s\nDistance: %.1f studs\nPickup must be approved by your game's server."):format(
            safeName(inst), distance or 0))
    else
        setStatus("No likely carryable object found nearby. Add the HTC_Carryable tag/attribute in your own game for reliable discovery.")
    end
end)

addButton("MOVE TO CARRY CANDIDATE", function()
    local inst, _, distance = nearestCarry(CONFIG.maxDistance)
    if not inst then
        setStatus("No carry candidate found.")
        return
    end
    if not getCharacter() then
        setStatus("Character unavailable.")
        return
    end
    State.carryCandidate = inst
    State.manualGoal = inst
    setStatus(("Walking to %s (%.1f studs).\nUse the game's normal interaction prompt to pick it up."):format(
        safeName(inst), distance or 0))
end)

addButton("STOP MOVING", function()
    State.manualGoal = nil
    State.goalPart, State.goalKind = nil, nil
    stopMoving()
    setStatus("Movement stopped.")
end)

addButton("REPORT DISCOVERY COUNTS", function()
    local taggedCarry, taggedTargets = 0, 0
    for inst in pairs(Registry.carryables) do
        if isTagged(inst, CONFIG.tagCarry) then taggedCarry += 1 end
    end
    for model in pairs(Registry.npcs) do
        if isTagged(model, CONFIG.tagTarget) then taggedTargets += 1 end
    end
    setStatus(("Scanned %d | NPC-like %d | Prompts %d\nCarry hints %d (tagged %d)\nTagged targets %d"):format(
        Registry.scanTotal, Registry.n.npcs, Registry.n.prompts,
        Registry.n.carryables, taggedCarry, taggedTargets))
end)

local function closeHTC()
    State.running = false
    State.autoMove, State.aimAssist, State.carryAssist = false, false, false
    State.manualGoal = nil
    pcall(stopMoving)
    Maid.clean()
    if shared.HTC_Cleanup == closeHTC then shared.HTC_Cleanup = nil end
end
shared.HTC_Cleanup = closeHTC

addButton("CLOSE HTC", closeHTC)

-- Drag (mouse + touch). A short tap on the header collapses/expands the panel.
do
    local dragging, dragInput, dragStart, startPos, moved = false, nil, nil, nil, 0
    local compact = false

    local function clampPosition(x, y)
        local maxX = math.max(0, gui.AbsoluteSize.X - panel.AbsoluteSize.X)
        local maxY = math.max(0, gui.AbsoluteSize.Y - panel.AbsoluteSize.Y)
        return math.clamp(x, 0, maxX), math.clamp(y, 0, maxY)
    end

    local function toggleCompact()
        compact = not compact
        statusLabel.Visible = not compact
        scroll.Visible = not compact
        panel.Size = UDim2.fromOffset(PANEL_W, compact and 40 or PANEL_H)
        header.Text = compact and "HTC BRAINROT CLIENT  •  tap to expand"
            or "HTC BRAINROT CLIENT  •  drag / tap to hide"
    end

    Maid.give(header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, 0
            dragStart = input.Position
            startPos = panel.AbsolutePosition - gui.AbsolutePosition
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if moved < 6 then toggleCompact() end
                end
            end)
        end
    end))

    Maid.give(header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    Maid.give(UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and panel.Parent then
            local delta = input.Position - dragStart
            moved = math.max(moved, delta.Magnitude)
            local x, y = clampPosition(startPos.X + delta.X, startPos.Y + delta.Y)
            panel.Position = UDim2.fromOffset(x, y)
        end
    end))
end

----------------------------------------------------------------------
-- Workspace events (incremental registry updates)
----------------------------------------------------------------------
Maid.give(Workspace.DescendantAdded:Connect(function(inst)
    if not State.running then return end
    task.defer(function()
        if State.running and inst.Parent then
            local ok, err = pcall(track, inst)
            if not ok then reportError("track", err) end
        end
    end)
end))

Maid.give(Workspace.DescendantRemoving:Connect(function(inst)
    pcall(untrack, inst)
end))

for _, tag in ipairs({ CONFIG.tagTarget, CONFIG.tagCarry }) do
    Maid.give(CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
        if State.running and inst:IsDescendantOf(Workspace) then
            pcall(track, inst)
        end
    end))
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
local function readPing()
    local ok, value = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and value then return math.floor(value + 0.5) end
    return nil
end

local function promptHint()
    local candidate = State.carryCandidate
    local _, _, root = getCharacter()
    if not candidate or not root or not candidate:IsDescendantOf(Workspace) then return nil end
    local anchor = getAnchor(candidate)
    if not anchor or (anchor.Position - root.Position).Magnitude > CONFIG.promptHintDistance then
        return nil
    end
    local prompt = candidate:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local action = prompt.ActionText ~= "" and prompt.ActionText or "interact"
        return ("Nearby prompt: [%s]. Use it normally."):format(action)
    end
    return nil
end

local function updateHud()
    if State.perfMonitor then
        local ping = State.ping and (State.ping .. "ms") or "n/a"
        local lines = {
            ("HTC running | FPS ~%d | ping %s | errors %d"):format(State.fps, ping, State.errors),
            ("Indexed NPC %d | carry %d | prompts %d"):format(
                Registry.n.npcs, Registry.n.carryables, Registry.n.prompts),
            ("Move %s | Aim %s | Carry %s"):format(
                State.autoMove and "ON" or "off",
                State.aimAssist and "ON" or "off",
                State.carryAssist and "ON" or "off"),
            State.status,
        }
        local hint = promptHint()
        if hint then table.insert(lines, hint) end
        if State.lastError then table.insert(lines, "Last error: " .. State.lastError) end
        statusLabel.Text = table.concat(lines, "\n")
    else
        statusLabel.Text = State.status
    end
end

----------------------------------------------------------------------
-- Main loops
----------------------------------------------------------------------
-- Heartbeat: goal selection, navigation, HUD (all guarded).
do
    local selectAcc, navAcc, hudAcc = 0, 0, 0
    Maid.give(RunService.Heartbeat:Connect(function(dt)
        if not State.running then return end
        selectAcc += dt
        navAcc += dt
        hudAcc += dt

        if selectAcc >= CONFIG.selectInterval then
            selectAcc = 0
            local ok, err = pcall(selectGoal)
            if not ok then reportError("selectGoal", err) end
        end

        if navAcc >= CONFIG.navInterval then
            navAcc = 0
            local ok, err = pcall(navigate)
            if not ok then reportError("navigate", err) end
        end

        if hudAcc >= CONFIG.hudInterval then
            hudAcc = 0
            State.ping = readPing()
            local ok, err = pcall(updateHud)
            if not ok then reportError("hud", err) end
        end
    end))
end

-- Render step (after the default camera): FPS sample + NPC-only aim tracking.
do
    local fpsElapsed, fpsFrames = 0, 0
    local retargetAt = 0

    RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Camera.Value + 1, function(dt)
        if not State.running then return end

        fpsElapsed += dt
        fpsFrames += 1
        if fpsElapsed >= 1 then
            State.fps = math.floor(fpsFrames / fpsElapsed + 0.5)
            fpsElapsed, fpsFrames = 0, 0
        end

        if not State.aimAssist then return end
        local ok, err = pcall(function()
            local cam = Workspace.CurrentCamera
            local _, _, root = getCharacter()
            if not cam or not root then return end

            local now = os.clock()
            if now - retargetAt >= CONFIG.aimRetargetInterval then
                retargetAt = now
                State.aimTarget = pickAimTarget(cam, root)
            end

            local aimTarget = State.aimTarget
            if aimTarget and isAliveNpc(aimTarget) then
                local targetRoot = getRoot(aimTarget)
                if targetRoot then
                    -- Gentle camera tracking of non-player NPCs only. No attack or remote calls.
                    local current = cam.CFrame
                    local desired = CFrame.lookAt(current.Position, targetRoot.Position)
                    cam.CFrame = current:Lerp(desired, math.clamp(dt * CONFIG.aimSmoothing, 0, CONFIG.aimMaxStep))
                end
            end
        end)
        if not ok then reportError("aim", err) end
    end)
    Maid.give(function() RunService:UnbindFromRenderStep(RENDER_BIND) end)
end

-- Respawn: reset assists, keep the UI in sync.
Maid.give(LocalPlayer.CharacterAdded:Connect(function()
    State.target, State.aimTarget, State.carryCandidate = nil, nil, nil
    State.manualGoal, State.goalPart, State.goalKind = nil, nil, nil
    State.autoMove, State.aimAssist, State.carryAssist = false, false, false
    navReset()
    refreshToggles()
    setStatus("Respawn detected. Movement/aim/carry assist reset.")
end))

task.spawn(scanWorkspace)
print("[HTC] Brainrot client v2 loaded. Client-visible discovery only; carry/steal must be server-authorized.")
