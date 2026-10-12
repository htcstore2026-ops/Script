--[[ BLOX FRUITS // DELTA — versão corrigida
  Não assume nome nenhum do jogo: descobre inimigos, missões, baús e botões sozinho.
  Voa em cima do inimigo (Altura), mira, clica no centro da tela (nunca nos botões de habilidade)
  e só ataca inimigos do seu nível. ]]

if getgenv().BF_DELTA_LOADED then warn("[BF] Já carregado") return end
getgenv().BF_DELTA_LOADED = true

local Players  = game:GetService("Players")
local WS       = game:GetService("Workspace")
local UIS      = game:GetService("UserInputService")
local RS       = game:GetService("ReplicatedStorage")
local LIGHTING = game:GetService("Lighting")
local HTTP     = game:GetService("HttpService")
local RUN      = game:GetService("RunService")
local VIM      = game:GetService("VirtualInputManager")
local GuiService = game:GetService("GuiService")
local LP = Players.LocalPlayer

local DEFAULTS = {
  AutoFarm = false, Height = 12, LevelMargin = 2, LevelOverride = 0, Roam = true,
  AutoQuest = true, AutoChest = false, Bounty = true, AutoRevive = true,
  AutoFruit = false, FruitTarget = "Dragon", FruitPrice = "",
  WalkSpeed = 16, InfJump = false, NoClip = false, ESP = true, FullBright = false,
  Coords = "",
}
local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
getgenv().BFCFG = cfg

local S = { target = nil, black = {}, state = "parado", hAdj = 0, myHp = 0, tT = 0, tHp = 0, aT = 0,
  busy = false, hov = false, folder = nil, folderT = 0, givers = {}, giversT = 0, questT = 0, questLv = -1,
  chests = {}, chestScanT = 0, reviveT = 0, equipT = 0, esp = {}, lvObj = nil, moneyObj = nil, lastErr = "", gT = 0, gList = {}, spawns = {}, spawnT = 0, roamT = 0, visited = {}, dTotal = 0, dElig = 0, dMin = nil }
local gui, statusLbl, toastLbl

-- ============ AVISOS ============
local toastId = 0
local function notify(t, d)
  print("[BF] " .. tostring(t))
  if not toastLbl then return end
  toastId += 1
  local id = toastId
  toastLbl.Text = tostring(t)
  toastLbl.Visible = true
  task.delay(d or 3, function()
    if toastId == id and toastLbl then toastLbl.Visible = false end
  end)
end

-- ============ HELPERS ============
local function getChar()
  local c = LP.Character
  if c and c:FindFirstChild("HumanoidRootPart") and c:FindFirstChildOfClass("Humanoid") then return c end
end

local function shown(o)
  local p = o
  while p and p ~= game do
    if p:IsA("GuiObject") and not p.Visible then return false end
    if p:IsA("ScreenGui") and not p.Enabled then return false end
    p = p.Parent
  end
  return true
end

local function inGui(b, sub)
  local p = b.Parent
  while p do
    if p:IsA("GuiObject") and p.Name:lower():find(sub, 1, true) then return true end
    p = p.Parent
  end
  return false
end

local function press(b)
  if type(getconnections) == "function" then
    local ok = false
    for _, c in ipairs(getconnections(b.MouseButton1Click)) do
      pcall(function() c:Fire() end)
      ok = true
    end
    if ok then return true end
  end
  if type(firesignal) == "function" and pcall(firesignal, b.MouseButton1Click) then return true end
  local p = b.AbsolutePosition + b.AbsoluteSize / 2 + GuiService:GetGuiInset()
  pcall(function()
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
  end)
  return true
end

local function findButtons(match)
  local pg = LP:FindFirstChild("PlayerGui")
  if not pg then return false end
  for _, b in ipairs(pg:GetDescendants()) do
    if b:IsA("TextButton") and (not gui or not b:IsDescendantOf(gui)) and shown(b) and match(b) then
      press(b)
      return true
    end
  end
  return false
end

local function pivotPos(o)
  if o:IsA("BasePart") then return o.Position end
  local ok, cf = pcall(function() return o:GetPivot() end)
  return ok and cf.Position or Vector3.zero
end

-- ============ NÍVEL / DINHEIRO (descobertos) ============
local function numValue(names)
  for _, d in ipairs(LP:GetDescendants()) do
    if (d:IsA("IntValue") or d:IsA("NumberValue")) and names[d.Name:lower()] then return d end
  end
end

local function getLevel()
  if S.lvObj and S.lvObj.Parent then return S.lvObj.Value end
  local a = tonumber(LP:GetAttribute("Level"))
  if a then return a end
  S.lvObj = numValue({ level = true, lvl = true })
  if S.lvObj then return S.lvObj.Value end
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, l in ipairs(pg:GetDescendants()) do
      if l:IsA("TextLabel") then
        local t = l.Text:lower()
        local n = t:match("^%s*lv%.?%s*(%d+)") or t:match("^%s*level%s*:?%s*(%d+)")
        if n then return tonumber(n) end
      end
    end
  end
  return nil
end

local function curLevel()
  local o = tonumber(cfg.LevelOverride) or 0
  if o > 0 then return o end
  return getLevel()
end

local function getMoney()
  if S.moneyObj and S.moneyObj.Parent then return S.moneyObj.Value end
  S.moneyObj = numValue({ money = true, cash = true, beli = true, coins = true, gold = true })
  return S.moneyObj and S.moneyObj.Value or 0
end

-- ============ INIMIGOS (descobertos) ============
local function isMob(m)
  return m:IsA("Model") and m ~= LP.Character and not Players:GetPlayerFromCharacter(m)
    and m:FindFirstChildOfClass("Humanoid") ~= nil and m:FindFirstChild("HumanoidRootPart") ~= nil
end

local function alive(m)
  local h = m and m.Parent and m:FindFirstChildOfClass("Humanoid")
  return h and h.Health > 0
end

local function lvOf(m)
  local a = tonumber(m:GetAttribute("Level"))
  if a then return a end
  local n = m.Name:lower()
  local h = m:FindFirstChildOfClass("Humanoid")
  if h and h.DisplayName ~= "" then n = n .. " " .. h.DisplayName:lower() end
  return tonumber(n:match("lv%.?%s*(%d+)") or n:match("level%s*(%d+)") or n:match("%[(%d+)%]"))
end

local function mobFolder()
  if S.folder and S.folder.Parent then return S.folder end
  if tick() - S.folderT < 15 then return WS end
  S.folderT = tick()
  local f = WS:FindFirstChild("Enemies")
  if not f then
    local counts, bestN = {}, 0
    for _, h in ipairs(WS:GetDescendants()) do
      if h:IsA("Humanoid") then
        local m = h.Parent
        if m and m.Parent and m.Parent ~= WS and isMob(m) then
          counts[m.Parent] = (counts[m.Parent] or 0) + 1
          if counts[m.Parent] > bestN then bestN, f = counts[m.Parent], m.Parent end
        end
      end
    end
  end
  S.folder = f
  return f or WS
end

local function mobs()
  local out = {}
  for _, m in ipairs(mobFolder():GetChildren()) do
    if isMob(m) then out[#out + 1] = m end
  end
  if #out == 0 then -- pasta vazia/errada: varre o mapa inteiro (a cada 8s)
    if tick() - S.gT > 8 then
      S.gT, S.gList = tick(), {}
      for _, h in ipairs(WS:GetDescendants()) do
        if h:IsA("Humanoid") then
          local m = h.Parent
          if m and isMob(m) then S.gList[#S.gList + 1] = m end
        end
      end
    end
    for _, m in ipairs(S.gList) do
      if m.Parent and isMob(m) then out[#out + 1] = m end
    end
  end
  return out
end

-- escolhe o inimigo do SEU nível: o de maior nível que você aguenta (até nível+margem)
local function pickTarget(r)
  local lvl, best, bs = curLevel(), nil, -math.huge
  S.dTotal, S.dElig, S.dMin = 0, 0, nil
  for _, m in ipairs(mobs()) do
    if alive(m) then
      S.dTotal += 1
      local el = lvOf(m)
      if el and (not S.dMin or el < S.dMin) then S.dMin = el end
      if not (S.black[m] and S.black[m] > tick()) and (not lvl or not el or el <= lvl + cfg.LevelMargin) then
        S.dElig += 1
        local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
        local sc = (el or 0) * 1000 - d
        if sc > bs then best, bs = m, sc end
      end
    end
  end
  return best
end

-- ============ MISSÃO PELO NÍVEL (descoberta) ============
local function textsOf(d)
  local t = {}
  if d:IsA("ProximityPrompt") then t[#t + 1] = d.ActionText t[#t + 1] = d.ObjectText end
  local p, n = d.Parent, 0
  while p and p ~= WS and n < 3 do t[#t + 1] = p.Name n += 1 p = p.Parent end
  return table.concat(t, " "):lower()
end

local function scanGivers()
  if tick() - S.giversT < (#S.givers > 0 and 120 or 20) then return S.givers end
  S.giversT, S.givers = tick(), {}
  for _, d in ipairs(WS:GetDescendants()) do
    if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
      local txt = textsOf(d)
      if txt:find("quest", 1, true) or txt:find("miss", 1, true) then
        local pr = d.Parent
        local part = pr and (pr:IsA("BasePart") and pr or (pr:IsA("Attachment") and pr.Parent)
          or pr:FindFirstChildWhichIsA("BasePart", true))
        if part and part:IsA("BasePart") then
          local n = tonumber(pr:GetAttribute("QuestLevel")) or tonumber(pr:GetAttribute("Level"))
            or tonumber(txt:match("lv%.?%s*(%d+)") or txt:match("level%s*(%d+)") or txt:match("(%d+)"))
          S.givers[#S.givers + 1] = { inst = d, part = part, n = n }
        end
      end
    end
  end
  return S.givers
end

local function doQuest()
  local ch = getChar()
  if not ch then return end
  local lvl, best, bn = curLevel(), nil, nil
  for _, g in ipairs(scanGivers()) do
    if g.part.Parent and (not g.n or not lvl or g.n <= lvl) then
      local sc = g.n or 0 -- sempre a missão de maior nível que você já pode fazer
      if not bn or sc > bn then best, bn = g, sc end
    end
  end
  S.questT, S.questLv = tick(), lvl
  if not best then notify("Nenhum NPC de missão achado (" .. #S.givers .. " candidatos)", 4) return end
  S.busy = true
  ch.HumanoidRootPart.CFrame = best.part.CFrame * CFrame.new(0, 0, 4)
  task.wait(0.4)
  if best.inst:IsA("ProximityPrompt") then
    pcall(function() best.inst.HoldDuration = 0 end)
    if type(fireproximityprompt) == "function" then pcall(fireproximityprompt, best.inst) end
  elseif type(fireclickdetector) == "function" then
    pcall(fireclickdetector, best.inst)
  end
  task.wait(0.8)
  findButtons(function(b)
    local t = b.Text:lower()
    return t:find("accept") or t:find("aceitar") or t == "yes" or t == "sim" or t:find("start")
  end)
  S.busy = false
  notify("Missão (nível " .. tostring(best.n or "?") .. ") pedida")
end

-- ============ BAÚS (descobertos) ============
local function scanChests()
  if tick() - S.chestScanT < 20 then return S.chests end
  S.chestScanT, S.chests = tick(), {}
  for _, d in ipairs(WS:GetDescendants()) do
    if (d:IsA("Model") or d:IsA("BasePart")) and d.Name:lower():find("chest", 1, true)
       and not (d.Parent and d.Parent:IsA("Model") and d.Parent.Name:lower():find("chest", 1, true)) then
      S.chests[#S.chests + 1] = d
    end
  end
  return S.chests
end

local function chestStep()
  local ch = getChar()
  if not ch then return end
  local root, best, bd = ch.HumanoidRootPart, nil, math.huge
  for _, c in ipairs(scanChests()) do
    if c.Parent then
      local d = (pivotPos(c) - root.Position).Magnitude
      if d < bd then best, bd = c, d end
    end
  end
  if not best then return end
  S.busy = true
  root.CFrame = CFrame.new(pivotPos(best) + Vector3.new(0, 3, 0))
  task.wait(0.3)
  for _, p in ipairs(best:GetDescendants()) do
    if p:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
      pcall(function() p.HoldDuration = 0 end)
      pcall(fireproximityprompt, p)
    elseif p:IsA("ClickDetector") and type(fireclickdetector) == "function" then
      pcall(fireclickdetector, p)
    elseif p:IsA("TouchTransmitter") and type(firetouchinterest) == "function" then
      pcall(function() firetouchinterest(root, p.Parent, 0) firetouchinterest(root, p.Parent, 1) end)
    end
  end
  task.wait(0.4)
  S.busy = false
  notify("Baú: " .. best.Name, 2)
end

-- ============ FRUTA (só pela loja visível / mochila) ============
local function fruitTool(name)
  name = name:lower()
  local function scan(c)
    if not c then return nil end
    for _, t in ipairs(c:GetChildren()) do
      if t:IsA("Tool") and t.Name:lower():find(name, 1, true) then return t end
    end
  end
  return scan(LP.Character) or scan(LP:FindFirstChild("Backpack"))
end

local function fruitStep()
  local target = cfg.FruitTarget
  if target == "" or fruitTool(target) then return end
  local price = tonumber(cfg.FruitPrice) or 0
  if price > 0 and getMoney() < price then notify("Sem dinheiro para " .. target, 2) return end
  local tl = target:lower()
  local bought = findButtons(function(b)
    local t = (b.Text .. " " .. b.Name):lower()
    return t:find(tl, 1, true) and (inGui(b, "shop") or inGui(b, "fruit") or inGui(b, "stock"))
  end)
  if not bought then notify("Abra a loja de frutas (botão " .. target .. " precisa estar visível)", 3) return end
  task.wait(2.5)
  local f, ch = fruitTool(target), getChar()
  if f and ch then
    pcall(function() ch.Humanoid:EquipTool(f) end)
    task.wait(0.4)
    pcall(function() f:Activate() end)
    notify("Fruta equipada: " .. target)
  else
    notify("Compra de " .. target .. " sem confirmação")
  end
end

-- ============ REVIVER / BOUNTY ============
local function tryRevive()
  if tick() - S.reviveT < 5 then return end
  S.reviveT = tick()
  findButtons(function(b)
    local t = (b.Text .. " " .. b.Name):lower()
    return t:find("reviv", 1, true) or t:find("respawn", 1, true)
  end)
end

local function bountyStep()
  findButtons(function(b)
    local t = (b.Text .. " " .. b.Name):lower()
    return (t:find("collect", 1, true) or t:find("claim", 1, true) or t:find("coletar", 1, true)) and inGui(b, "bounty")
  end)
end

-- ============ PROCURAR INIMIGOS (spawns descobertos) ============
local function roam(r)
  if tick() - S.roamT < 4 then return end
  S.roamT = tick()
  if tick() - S.spawnT > 60 or #S.spawns == 0 then
    S.spawnT, S.spawns = tick(), {}
    for _, d in ipairs(WS:GetDescendants()) do
      if d:IsA("BasePart") then
        local n, pn = d.Name:lower(), d.Parent and d.Parent.Name:lower() or ""
        if (n:find("spawn") or pn:find("spawn")) and (n:find("enem") or pn:find("enem") or n:find("mob") or pn:find("mob")) then
          S.spawns[#S.spawns + 1] = d
        end
      end
    end
  end
  local lvl, best, bd = curLevel(), nil, math.huge
  for _, sp in ipairs(S.spawns) do
    if sp.Parent and not S.visited[sp] then
      local sl = tonumber((sp.Name .. " " .. (sp.Parent and sp.Parent.Name or "")):lower():match("lv%.?%s*(%d+)"))
      if not (sl and lvl and sl > lvl + cfg.LevelMargin) then
        local d = (sp.Position - r.Position).Magnitude
        if d < bd then best, bd = sp, d end
      end
    end
  end
  if not best then S.visited = {} return end
  S.visited[best] = true
  r.CFrame = CFrame.new(best.Position + Vector3.new(0, 8, 0))
end

-- ============ FARM: VOA EM CIMA, MIRA E ATACA ============
local function overUI(x, y)
  local pg = LP:FindFirstChild("PlayerGui")
  if not pg then return false end
  local inset = GuiService:GetGuiInset()
  for _, pt in ipairs({ Vector2.new(x, y), Vector2.new(x, y) + inset }) do
    for _, o in ipairs(pg:GetGuiObjectsAtPosition(pt.X, pt.Y)) do
      if o.Visible and (not gui or not o:IsDescendantOf(gui))
         and (o:IsA("GuiButton") or o:IsA("TextBox") or o.Active) then
        return true
      end
    end
  end
  return false
end

local function equipTool(hum)
  if tick() - S.equipT < 2 or LP.Character:FindFirstChildOfClass("Tool") then return end
  S.equipT = tick()
  local bp, pick = LP:FindFirstChild("Backpack"), nil
  if not bp then return end
  for _, t in ipairs(bp:GetChildren()) do
    if t:IsA("Tool") then
      local n = t.Name:lower()
      if n:find("combat") or n:find("melee") or n:find("punch") then pick = t break end
      pick = pick or t
    end
  end
  if pick then pcall(function() hum:EquipTool(pick) end) end
end

local function attack()
  local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
  if tool then pcall(function() tool:Activate() end) end
  local vp = WS.CurrentCamera.ViewportSize
  local x, y = vp.X / 2, vp.Y / 2 -- inimigo fica no centro; nunca clica nos botões de habilidade
  if overUI(x, y) then return end
  pcall(function()
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
  end)
end

-- a cada frame: fica parado em cima do alvo, olhando pra ele, câmera mirando nele
RUN.Heartbeat:Connect(function()
  local t = S.target
  if not cfg.AutoFarm or S.busy or not t or not alive(t) then return end
  local ch = getChar()
  local tr = t:FindFirstChild("HumanoidRootPart")
  if not ch or not tr then return end
  local r = ch.HumanoidRootPart
  local h = math.max(5, cfg.Height + S.hAdj)
  r.CFrame = CFrame.lookAt(tr.Position + Vector3.new(0, h, 1.5), tr.Position)
  r.AssemblyLinearVelocity = Vector3.zero
  r.AssemblyAngularVelocity = Vector3.zero
  local cam = WS.CurrentCamera
  cam.CameraType = Enum.CameraType.Scriptable
  cam.CFrame = CFrame.lookAt(r.Position, tr.Position)
  S.hov = true
end)

local function stopHover()
  if not S.hov then return end
  S.hov = false
  WS.CurrentCamera.CameraType = Enum.CameraType.Custom
  local ch = getChar()
  if ch then ch.Humanoid.PlatformStand = false end
end

local function farmStep()
  local ch = getChar()
  if not ch then return end
  local hum, r = ch.Humanoid, ch.HumanoidRootPart
  if hum.Health <= 0 then
    S.target = nil
    if cfg.AutoRevive then tryRevive() end
    return
  end
  if hum.Health < S.myHp - 1 then S.hAdj = math.min(S.hAdj + 3, 10) end -- tomou dano: sobe
  S.myHp = hum.Health
  if not alive(S.target) then
    S.target = pickTarget(r)
    local mh = S.target and S.target:FindFirstChildOfClass("Humanoid")
    S.tT, S.tHp = tick(), mh and mh.Health or 0
  end
  local t = S.target
  if not t then
    stopHover()
    hum.PlatformStand = false
    if S.dTotal == 0 then
      S.state = "0 inimigos carregados" .. (cfg.Roam and " - procurando spawns..." or "")
      if cfg.Roam then roam(r) end
    else
      S.state = ("%d inimigos, 0 do seu nível (menor Lv %s; seu Lv %s)"):format(S.dTotal, tostring(S.dMin), tostring(curLevel()))
    end
    return
  end
  local mh = t:FindFirstChildOfClass("Humanoid")
  if mh.Health < S.tHp - 0.01 then S.tHp, S.tT = mh.Health, tick() end -- acertou
  local idle = tick() - S.tT
  if idle > 3 and tick() - S.aT > 3 then -- não acertou: chega mais perto
    S.aT = tick()
    S.hAdj = math.max(S.hAdj - 2, 6 - cfg.Height)
  end
  if idle > 14 then S.black[t] = tick() + 30 S.target = nil S.hAdj = 0 return end -- alvo inalcançável
  S.state = ("batendo em %s (Lv %s)"):format(t.Name, tostring(lvOf(t) or "?"))
  hum.PlatformStand = true
  equipTool(hum)
  attack()
end

-- ============ MOVIMENTO / ESP / VISUAL ============
RUN.Stepped:Connect(function()
  if not cfg.NoClip then return end
  local ch = LP.Character
  if not ch then return end
  for _, p in ipairs(ch:GetDescendants()) do
    if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
  end
end)

UIS.JumpRequest:Connect(function()
  if not cfg.InfJump then return end
  local ch = getChar()
  if ch then ch.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
end)

local function espStep()
  if not cfg.ESP then
    for m, h in pairs(S.esp) do pcall(function() h:Destroy() end) S.esp[m] = nil end
    return
  end
  local ch, n = getChar(), 0
  for m, h in pairs(S.esp) do
    if not m.Parent or not h.Parent then S.esp[m] = nil else n += 1 end
  end
  if not ch then return end
  for _, m in ipairs(mobs()) do
    if n >= 20 then break end -- limite do Roblox pra Highlight
    if not S.esp[m] and (m.HumanoidRootPart.Position - ch.HumanoidRootPart.Position).Magnitude < 300 then
      local ok, hl = pcall(function()
        local h = Instance.new("Highlight")
        h.FillTransparency = 1
        h.OutlineColor = Color3.fromRGB(255, 90, 90)
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = m
        return h
      end)
      if ok then S.esp[m] = hl n += 1 end
    end
  end
end

local function listRemotes()
  local n = 0
  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
      n += 1
      print("[BF] remote:", d:GetFullName(), d.ClassName)
    end
  end
  notify(n .. " remotes listados no console (F9)")
end

-- ============ UI ============
local COLORS = { bg = Color3.fromRGB(16, 17, 20), bg2 = Color3.fromRGB(30, 33, 40),
  accent = Color3.fromRGB(0, 200, 120), red = Color3.fromRGB(220, 70, 70),
  text = Color3.fromRGB(235, 235, 235), sub = Color3.fromRGB(150, 152, 158) }

local function mk(cls, props, parent)
  local o = Instance.new(cls)
  for k, v in pairs(props) do pcall(function() o[k] = v end) end
  o.Parent = parent
  return o
end

local function buildUI()
  if gui then pcall(function() gui:Destroy() end) end
  local pg = LP:WaitForChild("PlayerGui", 15)
  local okH, hui = pcall(function() return type(gethui) == "function" and gethui() or nil end)
  gui = mk("ScreenGui", { Name = "BF_DELTA_GUI", ResetOnSpawn = false, DisplayOrder = 999 }, (okH and hui) or pg)

  local main = mk("Frame", { Size = UDim2.fromOffset(260, 430), Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = COLORS.bg, BorderSizePixel = 0 }, gui)
  local title = mk("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0,
    Text = "BF // DELTA  (toque = recolher | arraste)", TextColor3 = COLORS.bg,
    Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = false }, main)
  statusLbl = mk("TextLabel", { Position = UDim2.fromOffset(4, 30), Size = UDim2.new(1, -8, 0, 76),
    BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0, Text = "...", TextColor3 = COLORS.sub,
    Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, main)
  local body = mk("ScrollingFrame", { Position = UDim2.fromOffset(2, 110), Size = UDim2.new(1, -4, 1, -112),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y }, main)
  mk("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)
  toastLbl = mk("TextLabel", { Size = UDim2.fromOffset(340, 26), Position = UDim2.new(0.5, -170, 1, -80),
    BackgroundColor3 = COLORS.bg, BackgroundTransparency = 0.2, Text = "", TextColor3 = COLORS.text,
    Font = Enum.Font.GothamBold, TextSize = 13, Visible = false }, gui)

  local order = 0
  local function row(h)
    order += 1
    return mk("Frame", { Size = UDim2.new(1, -8, 0, h), BackgroundTransparency = 1, LayoutOrder = order }, body)
  end
  local function label(parent, t, w)
    return mk("TextLabel", { Size = UDim2.new(w, 0, 1, 0), BackgroundTransparency = 1, Text = t,
      TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 13,
      TextXAlignment = Enum.TextXAlignment.Left }, parent)
  end
  local function section(t)
    mk("TextLabel", { Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1, Text = t, TextColor3 = COLORS.accent,
      Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
      LayoutOrder = (function() order += 1 return order end)() }, body)
  end
  local function toggle(key, text)
    local r = row(24)
    label(r, text, 0.68)
    local b = mk("TextButton", { Position = UDim2.new(0.7, 0, 0, 1), Size = UDim2.new(0.3, 0, 1, -2),
      BackgroundColor3 = cfg[key] and COLORS.accent or COLORS.red, BorderSizePixel = 0,
      Text = cfg[key] and "ON" or "OFF", TextColor3 = COLORS.bg, Font = Enum.Font.GothamBold, TextSize = 13 }, r)
    b.MouseButton1Click:Connect(function()
      cfg[key] = not cfg[key]
      b.BackgroundColor3 = cfg[key] and COLORS.accent or COLORS.red
      b.Text = cfg[key] and "ON" or "OFF"
    end)
  end
  local function input(key, text, ph, minV, maxV)
    local r = row(24)
    label(r, text, 0.5)
    local tb = mk("TextBox", { Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.new(0.5, 0, 1, -2),
      BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0, Text = tostring(cfg[key]), PlaceholderText = ph or "",
      TextColor3 = COLORS.text, Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false }, r)
    tb.FocusLost:Connect(function()
      if minV then
        cfg[key] = math.clamp(tonumber(tb.Text) or cfg[key], minV, maxV)
        tb.Text = tostring(cfg[key])
      else
        cfg[key] = tb.Text
      end
    end)
  end
  local function button(text, fn)
    local r = row(24)
    local b = mk("TextButton", { Size = UDim2.new(1, 0, 1, -2), BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0,
      Text = text, TextColor3 = COLORS.text, Font = Enum.Font.GothamBold, TextSize = 13 }, r)
    b.MouseButton1Click:Connect(fn)
  end

  section("FARM")
  toggle("AutoFarm", "Lutar sozinho")
  input("Height", "Altura (voo)", nil, 6, 40)
  input("LevelMargin", "Margem de nível", nil, 0, 10)
  input("LevelOverride", "Seu Lv (0=auto)", nil, 0, 5000)
  toggle("Roam", "Procurar inimigos")
  toggle("AutoQuest", "Missão pelo nível")
  toggle("AutoRevive", "Reviver")
  toggle("Bounty", "Pegar bounty")
  section("BAÚS E FRUTA")
  toggle("AutoChest", "Abrir baús")
  toggle("AutoFruit", "Fruta automática")
  input("FruitTarget", "Fruta alvo", "Dragon")
  input("FruitPrice", "Preço (opcional)", "")
  section("MOVIMENTO")
  input("WalkSpeed", "Speed", nil, 10, 200)
  toggle("InfJump", "Pulo infinito")
  toggle("NoClip", "NoClip")
  section("VISUAL")
  toggle("ESP", "ESP inimigos")
  toggle("FullBright", "Visão noturna")
  section("TELEPORTE / EXTRAS")
  input("Coords", "x, y, z", "100, 50, 200")
  button("Ir para coordenadas", function()
    local x, y, z = cfg.Coords:match("(%-?%d+%.?%d*)[%s,]+(%-?%d+%.?%d*)[%s,]+(%-?%d+%.?%d*)")
    local ch = getChar()
    if x and ch then ch.HumanoidRootPart.CFrame = CFrame.new(tonumber(x), tonumber(y), tonumber(z)) notify("Teleportado")
    else notify("Formato: x, y, z") end
  end)
  button("Listar remotes (console)", listRemotes)
  button("Salvar config", function()
    local ok, err = pcall(function() writefile("BF_DELTA_CFG.json", HTTP:JSONEncode(cfg)) end)
    notify(ok and "Config salva" or "Falha: " .. tostring(err))
  end)
  button("Carregar config", function()
    local ok, err = pcall(function()
      for k, v in pairs(HTTP:JSONDecode(readfile("BF_DELTA_CFG.json"))) do
        if DEFAULTS[k] ~= nil then cfg[k] = v end
      end
    end)
    if ok then buildUI() notify("Config carregada") else notify("Falha: " .. tostring(err)) end
  end)

  -- recolher (toque) / arrastar
  local dragging, moved, ds, sp = false, false, nil, nil
  title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
      dragging, moved, ds, sp = true, false, i.Position, main.Position
    end
  end)
  title.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
      dragging = false
      if not moved then
        body.Visible = not body.Visible
        statusLbl.Visible = body.Visible
        main.Size = body.Visible and UDim2.fromOffset(260, 430) or UDim2.fromOffset(260, 28)
      end
    end
  end)
  UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
      local d = i.Position - ds
      if d.Magnitude > 6 then moved = true end
      main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
    end
  end)
end

-- ============ LOOP PRINCIPAL ============
local function safe(f)
  local ok, e = pcall(f)
  if not ok then
    S.busy = false
    if tostring(e) ~= S.lastErr then
      S.lastErr = tostring(e)
      warn("[BF] erro: " .. S.lastErr)
    end
  end
end

local okGui, errGui = pcall(buildUI)
if not okGui then warn("[BF] GUI falhou: " .. tostring(errGui)) end

task.spawn(function()
  local nEsp, nBounty, nChest, nFruit, nStatus = 0, 0, 0, 0, 0
  while true do
    local t = tick()
    safe(function()
      local ch = getChar()
      if ch and cfg.WalkSpeed ~= DEFAULTS.WalkSpeed and ch.Humanoid.WalkSpeed ~= cfg.WalkSpeed then
        ch.Humanoid.WalkSpeed = cfg.WalkSpeed
      end
      if cfg.FullBright then
        LIGHTING.Brightness, LIGHTING.ClockTime, LIGHTING.Ambient = 2, 14, Color3.new(1, 1, 1)
      end
    end)
    if t >= nEsp then nEsp = t + 1 safe(espStep) end
    if cfg.AutoFarm then
      if cfg.AutoQuest and (t - S.questT > 60 or curLevel() ~= S.questLv) then safe(doQuest) end
      safe(farmStep)
    else
      S.state = "parado"
      S.target = nil
      safe(stopHover)
    end
    if cfg.Bounty and t >= nBounty then nBounty = t + 6 safe(bountyStep) end
    if cfg.AutoChest and t >= nChest then nChest = t + 3 safe(chestStep) end
    if cfg.AutoFruit and t >= nFruit then nFruit = t + 10 safe(fruitStep) end
    if t >= nStatus and statusLbl then
      nStatus = t + 1
      local folder = S.folder and S.folder.Name or "(varredura)"
      statusLbl.Text = ("%s\nLv %s | $%s | Inimigos: %d (%s)\nAlvo: %s | Missões achadas: %d\n%s"):format(
        S.state, tostring(curLevel() or "?"), tostring(getMoney()), S.dTotal, folder,
        S.target and S.target.Name or "-", #S.givers, S.lastErr ~= "" and ("ERRO: " .. S.lastErr) or "sem erros")
    end
    task.wait(0.15)
  end
end)

notify("BF DELTA pronto — ligue 'Lutar sozinho'", 5)
