--[[====================================================================
  BLOX FRUITS // DELTA PRO — HUB DE FARM & DINHEIRO
  --------------------------------------------------------------------
  COMO USAR
  1) Entra num servidor com inimigos (Jungle, Desert, Village...)
  2) Abre o executor do Delta Pro, cola o script e Execute
  3) Abre o painel "BF // DELTA" e liga o que quiser
  --------------------------------------------------------------------
  O SCRIPT FAZ
  • Luta sozinho no inimigo mais próximo (aim + golpes + TP/grapple)
  • Compra e come a fruta-alvo automaticamente (troca a antiga)
  • Abre baús (com TP opcional até eles)
  • Coleta bounty e sobe nível sozinho
  • Revive, speed, pulo infinito, noclip, ESP, visão noturna
  • Salva/carrega sua config (se o executor tiver writefile)
  OBS: quando atualizam o jogo, alguns nomes internos mudam.
  O script testa vários nomes e avisa no painel/remota o que achou.
=====================================================================]]

if getgenv().BF_DELTA_LOADED then warn("[BF] Já está carregado.") return end
getgenv().BF_DELTA_LOADED = true

-- ============ SERVIÇOS ============
local Players  = game:GetService("Players")
local LP       = Players.LocalPlayer
local WS       = game:GetService("Workspace")
local UIS      = game:GetService("UserInputService")
local RS       = game:GetService("ReplicatedStorage")
local LIGHTING = game:GetService("Lighting")
local HTTP     = game:GetService("HttpService")

-- ============ CONFIG ============
local DEFAULTS = {
  AutoFarm    = false,
  Range       = 25,
  TP          = true,
  Grappling   = false,
  Clicks      = 1,
  AutoFruit   = false,
  FruitTarget = "Dragon",
  FruitPrice  = "",
  AutoChest   = false,
  ChestTP     = true,
  Bounty      = true,
  AutoLevel   = true,
  AutoRevive  = true,
  WalkSpeed   = 16,
  InfJump     = false,
  NoClip      = false,
  ESP         = true,
  FullBright  = false,
  Coords      = "",
}
local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
getgenv().BFCFG = cfg

-- ============ AVISOS ============
local NOTIF = {}
local function notify(text, dur)
  dur = dur or 3
  local ok, dt = pcall(function()
    local d = DrawText.new(tostring(text))
    d.TextSize = 16
    d.Color = Color3.new(1, 1, 1)
    d.TextStrokeTransparency = 0
    d.BackgroundTransparency = 1
    d.ZIndex = 100
    return d
  end)
  print("[BF] " .. tostring(text))
  if not ok or not dt then return end
  local n = 0
  for _ in pairs(NOTIF) do n = n + 1 end
  dt.Position = -24 * (n + 1)
  NOTIF[dt] = true
  task.spawn(function()
    task.wait(dur)
    pcall(dt.Remove, dt)
    NOTIF[dt] = nil
  end)
end

-- ============ HELPERS BÁSICOS ============
local function getChar()
  local c = LP.Character
  if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid") then
    return c
  end
  return nil
end

local lastTP = 0
local function teleport(pos, cd)
  cd = cd or 1
  if tick() - lastTP < cd then return false end
  lastTP = tick()
  local ch = LP.Character
  local root = ch and ch:FindFirstChild("HumanoidRootPart")
  if not root then return false end
  local ok = pcall(function()
    root.CFrame = CFrame.new(pos + Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1))
  end)
  return ok
end

local function pivotOf(o)
  if o:IsA("BasePart") then return o.CFrame end
  local ok, cf = pcall(function() return o:GetPivot() end)
  if ok and cf then return cf end
  local part = o:FindFirstChildOfClass("BasePart")
  return part and part.CFrame or CFrame.new(0, 0, 0)
end

local function ancestorMatches(inst, sub)
  local p = inst.Parent
  while p do
    if p:IsA("GuiObject") and p.Name:lower():find(sub) then return true end
    p = p.Parent
  end
  return false
end

-- ============ REMOTES ============
local remotes = {}
local function initRemotes()
  local root = RS:FindFirstChild("Remotes")
  local containers = {}
  if root then
    table.insert(containers, root:FindFirstChild("Events"))
    table.insert(containers, root)
  end
  local names = { "Combat", "FruitHandler", "Teleport", "Revive", "Bounty",
                  "UpdateHealth", "PlayerStatus", "Chests", "Fruit" }
  for _, nm in ipairs(names) do
    for _, c in ipairs(containers) do
      if c and c:FindFirstChild(nm) then
        remotes[nm] = c:FindFirstChild(nm)
        break
      end
    end
  end
  local found = {}
  for k in pairs(remotes) do table.insert(found, k) end
  table.sort(found)
  local summary = next(found) and table.concat(found, ", ") or "nenhum detectado"
  print("[BF] Remotes: " .. summary)
  notify("Remotes: " .. summary, 5)
end

-- ============ INIMIGOS ============
local function enemyModels()
  local list = {}
  local folder = WS:FindFirstChild("Enemies")
  if folder then
    for _, m in pairs(folder:GetChildren()) do
      if m:IsA("Model") then table.insert(list, m) end
    end
  else
    for _, m in pairs(WS:GetChildren()) do
      if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") and m ~= LP.Character then
        table.insert(list, m)
      end
    end
  end
  return list
end

local function pickEnemy(maxDist)
  local ch = getChar()
  if not ch then return nil end
  local root = ch:FindFirstChild("HumanoidRootPart")
  local best, bd = nil, maxDist
  for _, m in ipairs(enemyModels()) do
    if m ~= ch then
      local hum = m:FindFirstChildOfClass("Humanoid")
      local rp = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildOfClass("BasePart")
      if hum and hum.Health > 0 and rp then
        local d = (rp.Position - root.Position).Magnitude
        if d < bd then best, bd = m, d end
      end
    end
  end
  return best, bd
end

-- ============ ATAQUE ============
local function meleeClickAt(worldPos)
  local p = UIS:WorldToViewportPoint(worldPos)
  p.Z = 0
  pcall(function()
    UIS:InsertMouseObject(p)
    UIS:FireMouseButton1()
    UIS:ReleaseMouseButton1()
    UIS:ReleaseMouse()
  end)
end

local grappleCD = 0
local function tryGrapple(dir)
  if tick() - grappleCD < 3 then return end
  grappleCD = tick()
  if remotes.Combat then
    pcall(function() remotes.Combat:FireServer("GrapplingHook", dir) end)
  end
end

-- ============ GUl GENÉRICO ============
local function fireGuiButton(match)
  local pg = LP:FindFirstChild("PlayerGui")
  if not pg then return false end
  for _, b in ipairs(pg:Descendants()) do
    if b:IsA("TextButton") and b.Visible and b.Active and match(b) then
      local ok = pcall(function() b.MouseButton1Click:Fire() end)
      if ok then return true end
    end
  end
  return false
end

-- ============ DINHEIRO / NÍVEL ============
local function getMoney()
  local ls = LP:FindFirstChild("leaderstats")
  if ls then
    for _, st in pairs(ls:GetChildren()) do
      local v = tonumber(st.Value)
      if v and (st.Name:lower():find("money") or st.Name:lower():find("cash") or st.Name:lower():find("coin")) then
        return v
      end
    end
  end
  local a = LP:GetAttribute("Money")
  if type(a) == "number" then return a end
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, lbl in pairs(pg:Descendants()) do
      if lbl:IsA("TextLabel") then
        local txt = tostring(lbl.Text):gsub("%s", "")
        if txt:match("^$%d+$") then
          return tonumber(txt:gsub("%$", ""))
        end
      end
    end
  end
  return 0
end

local function getLevel()
  local ls = LP:FindFirstChild("leaderstats")
  if ls then
    local l = ls:FindFirstChild("Level")
    if l then return tostring(l.Value) end
  end
  local a = LP:GetAttribute("Level")
  if a then return tostring(a) end
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, lbl in pairs(pg:Descendants()) do
      if lbl:IsA("TextLabel") then
        local lv = tostring(lbl.Text):match("^(?:Lv|Level)[.%s]*(%d+)")
        if lv then return lv end
      end
    end
  end
  return "?"
end

-- ============ FRUTAS ============
local FRUIT_NAMES = {
  "Dragon", "Dough", "Leopard", "Kitsune", "T-Rex", "Mammoth", "Obsidian",
  "Portal", "Control", "Shadow", "Rumble", "Gravity", "Phoenix", "Buddha",
  "Blade", "Spring", "Spider", "Quartz", "Love", "Yeti", "Rabbit", "Venom",
  "Falcon", "Sand", "Ice", "Magma", "Dark", "Light", "Ghost", "Diamond",
  "Rope", "Smoke", "String", "Sound", "Spin", "Luffy", "Gura", "Kuma",
  "Ray", "Spike", "Flame", "Blizzard", "Quake", "Portga", "Leech", "Blast",
  "Rubber",
}
table.sort(FRUIT_NAMES, function(a, b) return #a > #b end)

local function getCurrentFruit()
  local sources = { LP }
  local ch = LP.Character
  if ch then
    table.insert(sources, ch)
    for _, p in ipairs(ch:GetChildren()) do
      if p:IsA("BasePart") then table.insert(sources, p) end
    end
  end
  for _, s in ipairs(sources) do
    for _, at in ipairs(s:GetAttributes()) do
      if at:lower():find("fruit") then
        local v = s:GetAttribute(at)
        if type(v) == "string" and #v > 0 and v:lower() ~= "none" then return v end
      end
    end
  end
  local pm = LP:FindFirstChild("PlayerModules")
  if pm then
    local inv = pm:FindFirstChild("Inventory")
    if inv and inv:IsA("ModuleScript") then
      local mod = require(inv)
      for _, fn in ipairs({ "GetFruit", "GetEquippedFruit", "GetCurrentFruit" }) do
        local f = rawget(mod, fn)
        if type(f) == "function" then
          local ok, r = pcall(f, mod)
          if ok and type(r) == "string" and r ~= "" and r:lower() ~= "none" then return r end
          if ok and r and r.Name then return r.Name end
        end
      end
      if type(rawget(mod, "GetItem")) == "function" then
        local ok, r = pcall(rawget(mod, "GetItem"), mod, "Fruit")
        if ok and r and r.Name then return r.Name end
      end
    end
    for _, at in ipairs(pm:GetAttributes()) do
      if at:lower():find("fruit") then
        local v = pm:GetAttribute(at)
        if type(v) == "string" and v ~= "" then return v end
      end
    end
  end
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, lbl in pairs(pg:Descendants()) do
      if lbl:IsA("TextLabel") then
        local txt = lbl.Text:lower()
        for _, fn in ipairs(FRUIT_NAMES) do
          if txt:find(fn:lower(), 1, true) and #fn > 3 then return fn end
        end
      end
    end
  end
  return nil
end

local function getFruitInstance(name)
  if not name then return nil end
  for _, root in ipairs({ RS, WS }) do
    local folders = {}
    for _, c in pairs(root:GetChildren()) do
      local n = c.Name:lower()
      if (n:find("fruit") or n:find("devil")) and (c:IsA("Folder") or c:IsA("Model")) then
        table.insert(folders, c)
      end
    end
    for _, f in ipairs(folders) do
      for _, it in pairs(f:GetChildren()) do
        if it.Name:lower() == name:lower() then return it end
      end
      for _, it in pairs(f:GetChildren()) do
        if it.Name:lower():find(name:lower(), 1, true) then return it end
      end
    end
  end
  return nil
end

local function sellFruitNow()
  local cur = getCurrentFruit()
  if not cur then notify("Você não tem fruta para vender.") return end
  if remotes.FruitHandler then
    local inst = getFruitInstance(cur)
    pcall(function() remotes.FruitHandler:FireServer("Sell", inst or cur) end)
    notify("Venda de " .. cur .. " enviada.")
  else
    fireGuiButton(function(b)
      return b.Name:lower():find("sell") and ancestorMatches(b, "fruit")
    end)
    notify("Tentativa de venda via loja (" .. cur .. ")")
  end
end

local function dropFruitNow()
  if remotes.FruitHandler then
    pcall(function() remotes.FruitHandler:FireServer("DevilFruitDrop") end)
    notify("Queda de fruta enviada.")
  else
    notify("Remote FruitHandler não encontrado.")
  end
end

-- ============ SPAWN / REVIVER ============
local function teleportToSpawn()
  if remotes.Teleport then
    local ok = pcall(function() remotes.Teleport:FireServer("TeleportToSpawn") end)
    if ok then
      task.wait(1.5)
      local ch = getChar()
      local hum = ch and ch:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 then return true end
    end
  end
  local pos = nil
  for _, c in ipairs(WS:GetChildren()) do
    if c:IsA("BasePart") and c.Name:lower():find("spawn") then pos = c.Position break end
  end
  if not pos then
    local sl = WS:FindFirstChild("SpawnLocation")
    if sl then
      local pp = sl.PrimaryPart or sl:FindFirstChildOfClass("BasePart")
      if pp then pos = pp.Position end
    end
  end
  if pos then
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if root then pcall(function() root.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0)) end) end
    notify("Voltando ao spawn.")
    return true
  end
  notify("Spawn não encontrado.")
  return false
end

local lastRevive = 0
local function tryRevive()
  if tick() - lastRevive < 5 then return end
  lastRevive = tick()
  if remotes.Revive then
    pcall(function() remotes.Revive:FireServer() end)
  end
  fireGuiButton(function(b)
    local n = b.Name:lower()
    return n:find("revive") or b.Text:lower():find("reviver")
  end)
  task.spawn(function()
    task.wait(2)
    local ch = LP.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then teleportToSpawn() end
  end)
end

-- ============ BOUNTY / NÍVEL ============
local function tryCollectBounty()
  if not cfg.Bounty then return end
  task.spawn(function()
    task.wait(1)
    local ok = fireGuiButton(function(b)
      local n, t = b.Name:lower(), b.Text:lower()
      if n:find("collect") or n:find("claim") or t:find("collect") then
        return ancestorMatches(b, "bounty")
      end
      return false
    end)
    if not ok and remotes.Bounty then
      pcall(function() remotes.Bounty:FireServer("CollectBounty") end)
    end
  end)
end

local function tryLevelUp()
  fireGuiButton(function(b)
    local n, t = b.Name:lower(), b.Text:lower()
    return n:find("level") or t:find("level up") or t:find("max level") or t:find("subir")
  end)
end

-- ============ BAÚS ============
local function findChests()
  local out = {}
  for _, c in pairs(WS:GetChildren()) do
    if c:IsA("Model") or c:IsA("BasePart") then
      local n = c.Name:lower()
      if n:find("chest") or n:find("mystery") then
        table.insert(out, c)
      end
    end
  end
  return out
end

local function chestStep()
  local ch = getChar()
  if not ch then return end
  local root = ch:FindFirstChild("HumanoidRootPart")
  local chests = findChests()
  if #chests == 0 then return end
  local best, bd
  for _, c in ipairs(chests) do
    local d = (pivotOf(c).Position - root.Position).Magnitude
    if not bd or d < bd then best, bd = c, d end
  end
  local pos = pivotOf(best).Position
  if bd > 10 and cfg.ChestTP then
    teleport(pos + (root.Position - pos).Unit * 3, 0.8)
  elseif bd > 10 and cfg.Grappling then
    tryGrapple(pos - root.Position)
  end
  local opened = false
  for _, pp in ipairs(best:GetDescendants()) do
    if pp:IsA("ProximityPrompt") then
      if pcall(pp.FirePrompt, pp) then opened = true end
    end
  end
  if opened then notify("Baú aberto: " .. best.Name, 2) end
end

-- ============ FARM PRINCIPAL ============
local function farmStep()
  local ch = getChar()
  if not ch then return end
  local hum = ch:FindFirstChildOfClass("Humanoid")
  local root = ch:FindFirstChild("HumanoidRootPart")
  if hum.Health <= 0 then
    if cfg.AutoRevive then tryRevive() end
    return
  end
  local enemy, d = pickEnemy(cfg.Range + 250)
  if not enemy then return end
  local erp = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChildOfClass("BasePart")
  local epos, mpos = erp.Position, root.Position
  local dist = (epos - mpos).Magnitude
  if dist > cfg.Range then
    if cfg.TP then
      local spot = epos - (epos - mpos).Unit * math.max(10, cfg.Range * 0.5)
      teleport(spot, 0.8)
    elseif cfg.Grappling then
      tryGrapple(epos - mpos)
    end
  else
    local cam = WS.CurrentCamera
    pcall(function()
      cam.CFrame = CFrame.new(cam.CFrame.Position, epos + Vector3.new(0, 1.5, 0))
    end)
    pcall(function()
      root.CFrame = CFrame.lookAt(root.Position, epos + Vector3.new(0, 1, 0))
    end)
    for _ = 1, math.max(1, cfg.Clicks) do
      meleeClickAt(epos + Vector3.new(0, 1, 0))
    end
    if remotes.Combat then
      pcall(function() remotes.Combat:FireServer("Attack", true) end)
    end
  end
end

-- ============ FRUTA AUTOMÁTICA ============
local function fruitStep()
  local target = cfg.FruitTarget
  if target == "" then return end
  local cur = getCurrentFruit()
  if cur and cur:lower() == target:lower() then return end
  local money = getMoney()
  local price = tonumber(cfg.FruitPrice) or 0
  if price > 0 and money < price then
    notify("Sem dinheiro para " .. target .. " ainda.", 2)
    return
  end
  if cur then
    if remotes.FruitHandler then
      pcall(function() remotes.FruitHandler:FireServer("DevilFruitDrop") end)
    end
    task.wait(2)
    if getCurrentFruit() then return end
  end
  local bought = fireGuiButton(function(b)
    return b.Name:lower() == target:lower() and ancestorMatches(b, "fruit")
  end)
  if not bought then
    local inst = getFruitInstance(target)
    if inst and remotes.FruitHandler then
      if price > 0 then
        pcall(function() remotes.FruitHandler:FireServer("Buy", price, inst) end)
      else
        pcall(function() remotes.FruitHandler:FireServer("Buy", inst) end)
      end
      bought = true
    end
  end
  if not bought then return end
  task.wait(2.5)
  local inst = getFruitInstance(target)
  if inst and remotes.FruitHandler then
    pcall(function() remotes.FruitHandler:FireServer("Eat", inst) end)
  end
  task.wait(1)
  local nowF = getCurrentFruit()
  if nowF and nowF:lower() == target:lower() then
    notify("Fruta equipada: " .. target, 3)
  else
    notify("Compra de " .. target .. " sem confirmação — cheque a loja.", 3)
  end
end

-- ============ MOVIMENTO / ESP / STATUS ============
local function movementStep()
  local ch = LP.Character
  if not ch then return end
  local hum = ch:FindFirstChildOfClass("Humanoid")
  if hum then
    pcall(function()
      if hum.WalkSpeed ~= cfg.WalkSpeed then hum.WalkSpeed = cfg.WalkSpeed end
    end)
  end
  if cfg.NoClip then
    local root = ch:FindFirstChild("HumanoidRootPart")
    for _, p in ipairs(ch:GetDescendants()) do
      if p:IsA("BasePart") then
        if p.CanCollide then p.CanCollide = false end
        if p.Anchored and p ~= root then p.Anchored = false end
      end
    end
  end
end

local espHL = {}
local function espStep()
  if not cfg.ESP then
    for _, hl in pairs(espHL) do pcall(hl.Destroy, hl) end
    for k in pairs(espHL) do espHL[k] = nil end
    return
  end
  for m, hl in pairs(espHL) do
    if (not m or m.Parent == nil) or (not hl or hl.Parent == nil) then espHL[m] = nil end
  end
  for _, m in ipairs(enemyModels()) do
    if not espHL[m] then
      local ok, hl = pcall(function()
        local h = Instance.new("Highlight")
        h.FillColor = Color3.fromRGB(255, 70, 70)
        h.FillTransparency = 1
        h.OutlineColor = Color3.fromRGB(255, 90, 90)
        h.OutlineTransparency = 0.35
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = m
        return h
      end)
      if ok then espHL[m] = hl end
    end
  end
end

local function statusStep()
  if not UI_status then return end
  local cur = getCurrentFruit() or "Nenhuma"
  UI_status.Text = ("Fruta: %s   $%d   Nv: %s   Meta: %s"):format(cur, getMoney(), getLevel(), cfg.FruitTarget)
end

-- ============ META LOOP (kills, bounty, nível) ============
local tracked = {}
local nextBounty, nextLevel = 0, 0
local function metaStep()
  local t = tick()
  for m in pairs(tracked) do
    if not m or m.Parent == nil then tracked[m] = nil end
  end
  for _, m in ipairs(enemyModels()) do
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum and not tracked[m] then
      tracked[m] = true
      pcall(function()
        hum.Died:Connect(function()
          notify("Deu conta: " .. m.Name, 2)
          if cfg.Bounty then tryCollectBounty() end
        end)
      end)
    end
  end
  if cfg.Bounty and t >= nextBounty then nextBounty = t + 6 tryCollectBounty() end
  if cfg.AutoLevel and t >= nextLevel then nextLevel = t + 4 tryLevelUp() end
end

-- ============ PERSONAGEM / PULO INFINITO ============
local function setupCharacter(ch)
  if not ch then return end
  task.spawn(function()
    local hum = ch:WaitForChild("Humanoid", 15)
    if not hum then return end
    pcall(function()
      hum.Jumped:Connect(function()
        if cfg.InfJump then
          task.spawn(function()
            task.wait(0.45)
            local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
              pcall(function()
                h:ChangeState(Enum.HumanoidStateType.Jumping)
                h.Jump = true
              end)
            end
          end)
        end
      end)
    end)
  end)
end

-- ============ UI ============
local COLORS = {
  bg     = Color3.fromRGB(16, 17, 20),
  bg2    = Color3.fromRGB(30, 33, 40),
  accent = Color3.fromRGB(0, 200, 120),
  red    = Color3.fromRGB(220, 70, 70),
  text   = Color3.fromRGB(235, 235, 235),
  sub    = Color3.fromRGB(150, 152, 158),
}
local UI = {}
local UI_status

local function newC(cls, props)
  local o = Instance.new(cls)
  if props then
    for k, v in pairs(props) do
      pcall(function() o[k] = v end)
    end
  end
  return o
end

local function buildUI()
  if UI.root then pcall(UI.root.Destroy, UI.root) end
  local pg = LP:WaitForChild("PlayerGui", 15)
  if not pg then error("PlayerGui não encontrado") end
  local gui = newC("ScreenGui", { Name = "BF_DELTA_GUI", ResetOnSpawn = false, DisplayOrder = 999 })
  gui.Parent = pg
  UI.root = gui

  local W = 252
  local main = newC("Frame", {
    Name = "Main", Size = UDim2.fromOffset(W, 560), Position = UDim2.new(0, 12, 0, 12),
    BackgroundColor3 = COLORS.bg, BorderSizePixel = 0,
  })
  main.Parent = gui

  local title = newC("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0 })
  title.Parent = main
  newC("TextLabel", {
    Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    Text = "BF // DELTA PRO  (arraste o topo | clique p/ recolher)",
    TextColor3 = COLORS.bg, Font = Enum.Font.GothamBold, TextSize = 14,
  }).Parent = title

  local body = newC("ScrollingFrame", {
    Size = UDim2.new(1, -4, 1, -26), Position = UDim2.new(0, 2, 0, 26),
    BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 4, CanvasSize = UDim2.fromScale(1, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, UIScale = 1,
  })
  body.Parent = main
  UI.body = body

  local y = 4
  local function section(t)
    newC("TextLabel", {
      Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 16),
      BackgroundTransparency = 1, Text = t, TextColor3 = COLORS.accent,
      Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }).Parent = body
    y = y + 22
  end

  local function toggle(key, label)
    local row = newC("Frame", { Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 20), BackgroundTransparency = 1 })
    row.Parent = body
    newC("TextLabel", {
      Size = UDim2.new(0.7, 0, 1, 0), BackgroundTransparency = 1, Text = label,
      TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 13,
      TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    }).Parent = row
    local btn = newC("TextButton", {
      Position = UDim2.new(0.7, 0, 0, 1), Size = UDim2.new(0.3, 0, 1, -2),
      BackgroundColor3 = cfg[key] and COLORS.accent or COLORS.red, BorderSizePixel = 0,
      Text = cfg[key] and "[ ON ]" or "[ OFF ]", TextColor3 = COLORS.bg,
      Font = Enum.Font.GothamBold, TextSize = 13,
    })
    btn.Parent = row
    btn.MouseButton1Click:Connect(function()
      cfg[key] = not cfg[key]
      btn.BackgroundColor3 = cfg[key] and COLORS.accent or COLORS.red
      btn.Text = cfg[key] and "[ ON ]" or "[ OFF ]"
    end)
    y = y + 24
  end

  local function num(key, label, minV, maxV)
    local row = newC("Frame", { Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 22), BackgroundTransparency = 1 })
    row.Parent = body
    newC("TextLabel", {
      Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1, Text = label,
      TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 13,
      TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    }).Parent = row
    local tb = newC("TextBox", {
      Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(0.5, 0, 1, 0),
      BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0, NumberBox = true,
      Text = tostring(cfg[key]), TextColor3 = COLORS.text,
      Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
    })
    tb.Parent = row
    tb.FocusLost:Connect(function()
      local v = tonumber(tb.Text) or cfg[key]
      v = math.clamp(v, minV, maxV)
      cfg[key] = v
      notify(label .. " = " .. v, 1.5)
    end)
    y = y + 26
  end

  local function text(key, label, ph)
    local row = newC("Frame", { Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 22), BackgroundTransparency = 1 })
    row.Parent = body
    newC("TextLabel", {
      Size = UDim2.new(0.48, 0, 1, 0), BackgroundTransparency = 1, Text = label,
      TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 13,
      TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    }).Parent = row
    local tb = newC("TextBox", {
      Position = UDim2.new(0.48, 0, 0, 1), Size = UDim2.new(0.52, 0, 1, 0),
      BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0,
      PlaceholderText = ph or "", PlaceholderColor3 = COLORS.sub,
      Text = tostring(cfg[key] or ""), TextColor3 = COLORS.text,
      Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
    })
    tb.Parent = row
    tb.FocusLost:Connect(function() cfg[key] = tb.Text end)
    y = y + 26
  end

  local function button(label, fn)
    local b = newC("TextButton", {
      Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 22),
      BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0, Text = label,
      TextColor3 = COLORS.text, Font = Enum.Font.GothamBold, TextSize = 13,
    })
    b.Parent = body
    b.MouseButton1Click:Connect(fn)
    y = y + 26
  end

  section("FARM")
  toggle("AutoFarm", "Lutar sozinho")
  num("Range", "Alcance de combate", 10, 100)
  toggle("TP", "TP até inimigo")
  toggle("Grappling", "Grappling Hook (sem TP)")
  num("Clicks", "Golpes por tick", 1, 5)

  section("FRUTA & DINHEIRO")
  toggle("AutoFruit", "Fruta automática")
  text("FruitTarget", "Fruta alvo", "Dragon")
  text("FruitPrice", "Preço (opcional)", "")
  button("Vender fruta agora", sellFruitNow)
  button("Jogar fruta (drop)", dropFruitNow)

  section("EXTRAS DE FARM")
  toggle("AutoChest", "Abrir baús")
  toggle("ChestTP", "TP até baú")
  toggle("Bounty", "Pegar bounty")
  toggle("AutoLevel", "Subir nível")
  toggle("AutoRevive", "Reviver")

  section("MOVIMENTO")
  num("WalkSpeed", "Speed", 10, 200)
  toggle("InfJump", "Pulo infinito")
  toggle("NoClip", "NoClip")

  section("VISUAL")
  toggle("ESP", "ESP (inimigos)")
  toggle("FullBright", "Visão noturna")

  section("TELEPORTE")
  text("Coords", "Coordenadas (x, y, z)", "")
  button("Ir para coordenadas", function()
    local x, y2, z = cfg.Coords:match("^[%s]*(%-?%d+%.?%d*)[%s,]+(%-?%d+%.?%d*)[%s,]+(%-?%d+%.?%d*)")
    if not x then notify("Formato esperado: x, y, z") return end
    if teleport(Vector3.new(tonumber(x), tonumber(y2), tonumber(z)), 0) then
      notify("Teleportado!")
    else
      notify("Falhou — personagem não pronto.")
    end
  end)
  button("Ir para spawn", teleportToSpawn)

  section("CONFIG")
  button("Salvar config", function()
    local ok, err = pcall(function()
      if type(writefile) ~= "function" then error("writefile indisponível") end
      writefile("BF_DELTA_CFG.json", HTTP:JSONEncode(cfg))
    end)
    notify(ok and "Config salva!" or "Falha: " .. tostring(err))
  end)
  button("Carregar config", function()
    local ok, err = pcall(function()
      if type(readfile) ~= "function" then error("readfile indisponível") end
      local data = readfile("BF_DELTA_CFG.json")
      if not data or data == "" then error("arquivo vazio") end
      local d = HTTP:JSONDecode(data)
      for k, v in pairs(d) do
        if DEFAULTS[k] ~= nil then cfg[k] = v end
      end
    end)
    if ok then notify("Config carregada!"); buildUI() else notify("Falha: " .. tostring(err)) end
  end)
  button("Resetar tudo", function()
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    buildUI()
    notify("Config resetada.")
  end)

  UI_status = newC("TextLabel", {
    Position = UDim2.fromOffset(6, y), Size = UDim2.new(1, -12, 0, 18),
    BackgroundColor3 = COLORS.bg2, Text = "…", TextColor3 = COLORS.sub,
    Font = Enum.Font.Gotham, TextSize = 12,
  })
  UI_status.Parent = body
  y = y + 24

  -- recolher
  title.MouseButton1Click:Connect(function() UI.body.Visible = not UI.body.Visible end)

  -- arrastar
  local dragging, dragStart, startPos = false, nil, nil
  title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true
      dragStart = input.Position
      startPos = main.Position
    end
  end)
  title.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end)
  UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
       or input.UserInputType == Enum.UserInputType.Touch) then
      local d = input.Position - dragStart
      main.Position = UDim2.new(
        startPos.X.Scale, startPos.X.Offset + d.X,
        startPos.Y.Scale, startPos.Y.Offset + d.Y
      )
    end
  end)
end

-- ============ LOOPS ============
initRemotes()

local okGui, errGui = pcall(buildUI)
if not okGui then notify("GUI falhou: " .. tostring(errGui)) end

LP.CharacterAdded:Connect(setupCharacter)
setupCharacter(LP.Character)
getgenv().BFHUB = { cfg = cfg, sell = sellFruitNow, drop = dropFruitNow }

task.spawn(function()
  local nextMeta, nextFruit, nextChest, nextEsp, nextStatus = 0, 0, 0, 0, 0
  while true do
    local t = tick()
    movementStep()
    if cfg.AutoFarm then farmStep() end
    if t >= nextEsp then nextEsp = t + 1 espStep() end
    if t >= nextMeta then nextMeta = t + 0.6 metaStep() end
    if cfg.AutoChest and t >= nextChest then nextChest = t + 2 chestStep() end
    if cfg.AutoFruit and t >= nextFruit then nextFruit = t + 8 fruitStep() end
    if t >= nextStatus then nextStatus = t + 3 statusStep() end
    if cfg.FullBright then
      LIGHTING.Brightness = 2
      LIGHTING.ClockTime = 14
      LIGHTING.Ambient = Color3.new(1, 1, 1)
    end
    task.wait(0.1)
  end
end)

notify("BF DELTA pronto — configure o menu e liga o farm!", 5)
