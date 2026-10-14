--[[ BLOX FRUITS // DELTA PRO — v7 dano em grupo (sem inimigos congelados)
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
  AutoFarm = false, Height = 12, LevelMargin = 2, LevelOverride = 0, Roam = true, TouchClick = true, BringMobs = true, BringRadius = 350,
  AllowBoss = true, BossWait = 60, SearchWait = 120, IgnoreFor = 300, TpRadius = 150, MaxTp = 10, ExploreAll = false,
  TravelSpeed = 300, InstantMax = 400, HitRange = 60,
  AutoQuest = true, AutoChest = false, Bounty = true, AutoRevive = true,
  AutoStats = false, StatMelee = false, StatDefense = false, StatSword = false, StatGun = false, StatFruit = false,
  AutoFruit = false, FruitTarget = "Dragon", FruitPrice = "",
  WalkSpeed = 16, InfJump = false, NoClip = false, ESP = true, FullBright = false,
  Coords = "",
}
local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
getgenv().BFCFG = cfg

local S = { target = nil, black = {}, state = "parado", hAdj = 0, myHp = 0, tT = 0, tHp = 0, aT = 0,
  busy = false, hov = false, folder = nil, folderT = 0, givers = {}, giversT = 0, questT = 0, questLv = -1,
  chests = {}, chestScanT = 0, reviveT = 0, equipT = 0, esp = {}, lvObj = nil, moneyObj = nil, lastErr = "", gT = 0, gList = {}, spawns = {}, spawnT = 0, roamT = 0, visited = {}, dTotal = 0, dElig = 0, dMin = nil, hitMode = 1, rr = 0, failW = 0, modeTries = 0, okMode = false, bringBad = false, winT = 0,
  winSeen = {}, winHit = {}, hpSeen = {}, hitShape = nil,
  known = {}, qStrong = 0, chestDone = {}, questText = nil,
  hum = {}, inter = {}, chestSet = {}, spawnSet = {}, rlog = {}, dataQ = {}, dataT = 0, dataMods = {}, lastQuestCall = nil, spy = false,
  questPos = {}, atkT = 0, qChkT = 0, qOkT = 0, seaT = 0, qVerified = false, learnDirty = false,
  mobPos = {}, group = {}, gather = nil, grpT = 0, exploring = false, exploreSeen = {},
  ignored = {}, searchT0 = 0, exploreT0 = 0, tpT = 0, tpCount = 0, dest = nil, forceQuest = false,
  tpLog = {}, learnLog = {}, lastTpResult = "nenhuma tentativa", lastExplore = "ainda não explorou" }
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

-- O servidor reverte saltos instantâneos longos (anti-teleporte): o personagem "chega" e poucos
-- segundos depois volta ao ponto de origem. Viagens longas viram um deslocamento contínuo.
local function groundBelow(pos)
  local ok, res = pcall(function()
    local rp = RaycastParams.new()
    rp.FilterDescendantsInstances = { LP.Character }
    rp.FilterType = Enum.RaycastFilterType.Exclude
    return WS:Raycast(pos, Vector3.new(0, -300, 0), rp)
  end)
  if not ok then return true end
  return res ~= nil
end

local function holdAt(pos, secs) -- fica parado no ponto. NUNCA usar Anchored: peça ancorada não replica a posição
  local t0 = tick()
  while tick() - t0 < secs do
    local ch = getChar()
    if not ch then return end
    local r = ch.HumanoidRootPart
    r.CFrame = CFrame.new(pos)
    r.AssemblyLinearVelocity = Vector3.zero
    RUN.Heartbeat:Wait()
  end
end

local function travelTo(dest)
  local ch = getChar()
  if not ch then return false, "sem personagem", 0 end
  local function curSpeed() return math.clamp((tonumber(cfg.TravelSpeed) or 300) * (S.speedMul or 1), 60, 700) end
  task.spawn(function() pcall(function() LP:RequestStreamAroundAsync(dest, 6) end) end) -- pré-carrega o destino
  local prevBusy = S.busy
  S.busy, S.travel = true, true
  ch.Humanoid.PlatformStand = true
  local total = (dest - ch.HumanoidRootPart.Position).Magnitude
  local t0, lastUi = tick(), 0
  local deadline = t0 + total / curSpeed() + 20
  local arrived, why, expected, rb = false, "tempo esgotado", nil, 0
  while tick() < deadline do
    local dt = math.min(RUN.Heartbeat:Wait(), 0.1)
    local c = getChar()
    if not c or c.Humanoid.Health <= 0 then why = "personagem morreu" break end
    local r = c.HumanoidRootPart
    if expected and (r.Position - expected).Magnitude > 60 then -- o servidor desfez o último passo: está rápido demais
      rb += 1
      S.speedMul = math.max(0.3, (S.speedMul or 1) * 0.75) -- desacelera na hora
      deadline += 8
      if rb >= 8 then why = "servidor reverteu a viagem " .. rb .. "x" break end
    end
    local delta = dest - r.Position
    local dist = delta.Magnitude
    if dist < 6 then arrived = true break end
    local np = r.Position + delta.Unit * math.min(dist, curSpeed() * dt)
    r.CFrame = CFrame.new(np)
    expected = np
    r.AssemblyLinearVelocity = Vector3.zero
    r.AssemblyAngularVelocity = Vector3.zero
    if statusLbl and tick() - lastUi > 0.5 then
      lastUi = tick()
      statusLbl.Text = ("viajando: %d%% | faltam %d studs | %d studs/s%s"):format(
        math.floor(100 * (1 - dist / math.max(total, 1))), math.floor(dist), math.floor(curSpeed()),
        rb > 0 and (" | reversões: " .. rb) or "")
    end
  end
  S.busy, S.travel = prevBusy, false
  S.ccBack = S.ccBack or {}
  for part, was in pairs(S.ccBack) do -- devolve a colisão que o noclip da viagem desligou
    if part.Parent then part.CanCollide = was end
    S.ccBack[part] = nil
  end
  local c = getChar()
  if c then c.Humanoid.PlatformStand = false end
  return arrived, why, rb
end

local function tpTo(cf) -- teleporte com confirmação e histórico para diagnóstico
  local beforeChar = getChar()
  local before = beforeChar and beforeChar.HumanoidRootPart.Position
  local destination = cf.Position
  local entry = { t = os.date("%H:%M:%S"), from = before, to = destination, ok = false, reason = "sem personagem", mode = "-" }
  if beforeChar then
    local dist = (before - destination).Magnitude
    entry.dist = dist
    local failWhy, rb = nil, 0
    if dist > (tonumber(cfg.InstantMax) or 400) then
      entry.mode = "viagem"
      local arrived, why, n = travelTo(destination)
      rb = n or 0
      if arrived then holdAt(destination, 1.0) else failWhy = "viagem incompleta: " .. tostring(why) end
    else
      entry.mode = "instantâneo"
      pcall(function() LP:RequestStreamAroundAsync(destination, 2) end)
      local ch = getChar()
      if ch then pcall(function() ch.HumanoidRootPart.CFrame = cf end) end
      holdAt(destination, 0.4)
    end
    local extra = 0 -- se o chão ainda não carregou, segura o personagem (não cai no vazio)
    while not failWhy and not groundBelow(destination) and extra < 5 do
      holdAt(destination, 0.5)
      extra += 0.5
    end
    -- verificação PASSIVA: solta o personagem e só observa. (Forçar a posição aqui esconderia a reversão do servidor.)
    if not failWhy then task.wait(1.0) end
    local afterChar = getChar()
    local after = afterChar and afterChar.HumanoidRootPart.Position
    entry.after = after
    local near = after ~= nil and (after - destination).Magnitude < 80
    entry.ok = near
    entry.reason = near and "destino confirmado" or (failWhy or "revertido pelo servidor (posição final distante)")
    if entry.mode == "viagem" then -- velocidade adaptativa: ok = volta a acelerar; reversão silenciosa = mais devagar
      if near then S.speedMul = math.min(1, (S.speedMul or 1) * 1.1)
      elseif rb == 0 then S.speedMul = math.max(0.3, (S.speedMul or 1) * 0.75) end
    end
  end
  table.insert(S.tpLog, 1, entry)
  while #S.tpLog > 60 do table.remove(S.tpLog) end
  S.lastTpResult = entry.reason
  return entry.ok
end

local function cleanName(n)
  return (n:lower():gsub("%b[]", ""):gsub("lv%.?%s*%d+", ""):gsub("%d+", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local icache = setmetatable({}, { __mode = "k" })
local function interactive(m) -- modelo com prompt/click/dialog = NPC, não inimigo
  local v = icache[m]
  if v == nil then
    v = false
    for _, d in ipairs(m:GetDescendants()) do
      if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Dialog") then v = true break end
    end
    icache[m] = v
  end
  return v
end

local function guiTexts()
  local set, pg = {}, LP:FindFirstChild("PlayerGui")
  if not pg then return set end
  for _, o in ipairs(pg:GetDescendants()) do
    if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text ~= "" and (not gui or not o:IsDescendantOf(gui)) and shown(o) then
      set[o.Text] = true
    end
  end
  return set
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

-- ============ MONITORAMENTO DO WORKSPACE (streaming) ============
-- Em vez de varrer o mapa toda hora: escuta tudo que carrega/descarrega e mantém um índice vivo.
local function track(d)
  if d:IsA("Humanoid") then S.hum[d] = true
  elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") or d:IsA("Dialog") then S.inter[d] = true
  elseif d:IsA("Model") or d:IsA("BasePart") then
    local n = d.Name:lower()
    if n:find("chest", 1, true) then S.chestSet[d] = true end
    if d:IsA("BasePart") then
      local pn = d.Parent and d.Parent.Name:lower() or ""
      if n:find("spawn", 1, true) or pn:find("spawn", 1, true) then S.spawnSet[d] = true end
    end
  end
end
local function untrack(d) S.hum[d], S.inter[d], S.chestSet[d], S.spawnSet[d] = nil, nil, nil, nil end
WS.DescendantAdded:Connect(function(d) pcall(track, d) end)
WS.DescendantRemoving:Connect(untrack)
task.spawn(function() -- indexa o que já está carregado (em pedaços, sem travar)
  local n = 0
  for _, d in ipairs(WS:GetDescendants()) do
    pcall(track, d)
    n += 1
    if n % 1500 == 0 then task.wait() end
  end
end)

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

local function underNpc(m) -- modelo dentro de pasta "NPCs" ou com nome de quest giver
  local p = m.Parent
  while p and p ~= WS do
    if p.Name:lower():find("npc", 1, true) then return true end
    p = p.Parent
  end
  return m.Name:lower():find("giver", 1, true) ~= nil
end

local function mobFolder()
  if S.folder and S.folder.Parent then return S.folder end
  if tick() - S.folderT < 15 then return WS end
  S.folderT = tick()
  local f = WS:FindFirstChild("Enemies")
  if not f then
    local counts, bestN = {}, 0
    for h in pairs(S.hum) do
      local m = h.Parent
      if m and m.Parent and m.Parent ~= WS and isMob(m) and not interactive(m) and not underNpc(m) then
        counts[m.Parent] = (counts[m.Parent] or 0) + 1
        if counts[m.Parent] > bestN then bestN, f = counts[m.Parent], m.Parent end
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
  if #out == 0 then -- pasta vazia/errada: usa o índice vivo de Humanoids
    for h in pairs(S.hum) do
      local m = h.Parent
      if m and m.Parent and isMob(m) and not interactive(m) and not underNpc(m) then out[#out + 1] = m end
    end
  end
  return out
end

-- escolhe o inimigo do SEU nível: o de maior nível que você aguenta (até nível+margem)
-- Agrupar só vale se o SERVIDOR enxergar o inimigo no ponto. Mover um inimigo que o cliente não controla
-- é só visual: ele fica "congelado", fora do alcance real, não leva dano e não renasce.
local function bringOn()
  if not cfg.BringMobs or S.bringBad then return false end
  if type(isnetworkowner) == "function" then return true end -- confere inimigo por inimigo (ownsMob)
  return S.okMode -- sem como conferir: só depois de provar que o dano em vários inimigos funciona
end
local function ownsMob(hrp)
  if type(isnetworkowner) == "function" then
    local ok, res = pcall(isnetworkowner, hrp)
    return ok and res == true
  end
  return true
end
local function groupRadius() return bringOn() and cfg.BringRadius or cfg.HitRange end

local function pickTarget(r)
  local lvl, list = curLevel(), {}
  S.dTotal, S.dElig, S.dMin = 0, 0, nil
  for _, m in ipairs(mobs()) do
    if alive(m) then
      S.dTotal += 1
      local el = lvOf(m)
      if el and (not S.dMin or el < S.dMin) then S.dMin = el end
      local cn0 = cleanName(m.Name)
      local fits = S.questMobs and S.questMobs[cn0] or (not S.questMobs and (not lvl or not el or el <= lvl + cfg.LevelMargin))
      if not (S.black[m] and S.black[m] > tick()) and fits then
        S.dElig += 1
        list[#list + 1] = { m = m, el = el, cn = cn0, pos = m.HumanoidRootPart.Position }
      end
    end
  end
  local best, bs = nil, -math.huge
  local rad = groupRadius()
  for _, a in ipairs(list) do
    local n = 0 -- quantos alvos da missão estão perto deste (a região mais cheia vence)
    for _, b in ipairs(list) do
      if (S.questMobs or a.cn == b.cn) and (a.pos - b.pos).Magnitude <= rad then n += 1 end
    end
    local d = (a.pos - r.Position).Magnitude
    local sc = n * 1e5 + (a.el or 0) * 1000 - d
    if S.questText and #a.cn > 2 and S.questText:find(a.cn, 1, true) then sc += 1e6 end
    if sc > bs then best, bs = a.m, sc end
  end
  return best
end

-- ============ DADOS REPLICADOS (ReplicatedStorage não sofre streaming) ============
-- Lê módulos de dados (quest/mission/enemy/npc/spawn...) e extrai: nível, nome e posição.
local DATA_WORDS = { "quest", "mission", "enem", "mob", "npc", "spawn", "island", "level" }
local LV_KEYS = { level = true, lvl = true, levelreq = true, minlevel = true, requiredlevel = true,
  reqlevel = true, questlevel = true, recommendedlevel = true }
local NAME_KEYS = { name = true, quest = true, questname = true, mob = true, enemy = true, npc = true,
  target = true, displayname = true }
local POS_KEYS = { cframe = true, position = true, pos = true, spawn = true, location = true, origin = true }

local function toVec(v)
  if typeof(v) == "Vector3" then return v end
  if typeof(v) == "CFrame" then return v.Position end
end

local function mine(tbl, hint, parent, out, depth, seen)
  if depth > 5 or seen[tbl] or #out >= 400 then return end
  seen[tbl] = true
  local lv, nm, pos, task, tcount
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      local kl = k:lower()
      if type(v) == "number" and LV_KEYS[kl] then lv = lv or v end
      if type(v) == "string" and NAME_KEYS[kl] then nm = nm or v end
      if POS_KEYS[kl] then pos = pos or toVec(v) end
      if kl == "task" and type(v) == "table" then -- mobs que a missão manda matar
        task, tcount = {}, 0
        for tk, tv in pairs(v) do
          if type(tk) == "string" then task[#task + 1] = tk tcount += (tonumber(tv) or 1) end
        end
      end
    end
  end
  if lv then
    local name = nm or hint
    local num = tonumber(hint)
    out[#out + 1] = { n = lv, name = name, l = name:lower(), pos = pos,
      task = (task and #task > 0) and task or nil,
      key = num and parent or hint, tier = num or 1, boss = (tcount or 0) <= 1 }
  end
  for k, v in pairs(tbl) do
    if type(v) == "table" then mine(v, tostring(k), hint, out, depth + 1, seen) end
  end
end

local function scanData()
  if tick() - S.dataT < 120 then return S.dataQ end
  S.dataT, S.dataQ, S.dataMods = tick(), {}, {}
  local mods = {}
  for _, root in ipairs({ RS, game:GetService("ReplicatedFirst") }) do
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("ModuleScript") then
        local n = d.Name:lower()
        for _, w in ipairs(DATA_WORDS) do
          if n:find(w, 1, true) then mods[#mods + 1] = d break end
        end
      end
    end
  end
  for i, m in ipairs(mods) do
    if i > 25 then break end
    local ok, res, done = false, nil, false
    task.spawn(function() ok, res = pcall(require, m) done = true end)
    local t0 = tick()
    while not done and tick() - t0 < 2 do task.wait(0.05) end
    if not done then ok = false end
    if ok and type(res) == "table" then
      S.dataMods[#S.dataMods + 1] = m.Name
      pcall(mine, res, m.Name, "", S.dataQ, 0, {})
    end
  end
  return S.dataQ
end

-- ============ MISSÃO PELO NÍVEL (descoberta + aprendizado) ============
-- NPCs de compra (espada, arma, fruta...) são ignorados; só entram NPCs de missão.
local SKIP = { "shop", "store", "dealer", "merchant", "buy", "sell", "fruit", "sword", "weapon", "armor",
  "gun", "accessor", "trade", "craft", "enchant", "upgrade", "redeem", "boat", "raid", "teleport", "gift", "bank" }
local QWORDS = { "quest", "miss", "task" }

local function hasAny(txt, list)
  for _, w in ipairs(list) do if txt:find(w, 1, true) then return true end end
  return false
end

local function npcText(d, m)
  local t = { m.Name }
  local h = m:FindFirstChildOfClass("Humanoid")
  if h and h.DisplayName ~= "" then t[#t + 1] = h.DisplayName end
  if d:IsA("ProximityPrompt") then t[#t + 1] = d.ActionText t[#t + 1] = d.ObjectText end
  local n = 0
  for _, o in ipairs(m:GetDescendants()) do
    if o:IsA("TextLabel") and o.Text ~= "" and n < 6 then t[#t + 1] = o.Text n += 1 end
  end
  return table.concat(t, " "):lower()
end

local function inNpcFolder(m) -- está dentro de pasta/modelo chamado "npc" ou "quest"?
  local p = m
  while p and p ~= WS do
    local n = p.Name:lower()
    if n:find("npc", 1, true) or n:find("quest", 1, true) then return true end
    p = p.Parent
  end
  return false
end

local function scanGivers(force)
  if not force and tick() - S.giversT < (#S.givers > 0 and 30 or 8) then return S.givers end
  S.giversT, S.givers, S.qStrong = tick(), {}, 0
  scanData()
  local seen = {}
  local function add(inst, m)
    if seen[m] or m.Parent == S.folder or Players:GetPlayerFromCharacter(m) then return end
    seen[m] = true
    local txt = npcText(inst, m)
    if hasAny(txt, SKIP) or not (m:FindFirstChildOfClass("Humanoid") or hasAny(txt, QWORDS)) then return end
    local part = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart", true)
    if not part then return end
    local g = S.known[inst] or { inst = inst }
    g.model, g.part, g.txt = m, part, txt
    g.strong = hasAny(txt, QWORDS)
    g.n = g.n or tonumber(m:GetAttribute("QuestLevel")) or tonumber(m:GetAttribute("Level"))
      or tonumber(txt:match("lv%.?%s*(%d+)") or txt:match("level%s*(%d+)") or txt:match("n[ií]vel%s*(%d+)"))
    if not g.n then -- nível vindo dos dados replicados (nome do NPC bate com a entrada)
      for _, e in ipairs(S.dataQ) do
        if #e.l > 2 and txt:find(e.l, 1, true) then g.n = e.n break end
      end
    end
    S.known[inst] = g
    S.givers[#S.givers + 1] = g
    if g.strong or g.isQuest then S.qStrong += 1 end
  end
  for d in pairs(S.inter) do
    if d.Parent then
      local m = d:FindFirstAncestorWhichIsA("Model")
      while m and m.Parent and m.Parent:IsA("Model") do m = m.Parent end
      if m then add(d, m) end
    end
  end
  for h in pairs(S.hum) do -- NPC sem prompt: achado pela pasta (npc/quest); interação por clique na tela
    local m = h.Parent
    if m and m:IsA("Model") and inNpcFolder(m) then
      local part = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart", true)
      if part then add(part, m) end
    end
  end
  return S.givers
end

local function fireInst(inst, part)
  if inst:IsA("ProximityPrompt") then
    pcall(function() inst.HoldDuration = 0 end)
    if type(fireproximityprompt) == "function" then pcall(fireproximityprompt, inst) end
  elseif inst:IsA("ClickDetector") then
    if type(fireclickdetector) == "function" then pcall(fireclickdetector, inst) end
  else -- Dialog: só abre clicando no NPC na tela
    pcall(function()
      local cam = WS.CurrentCamera
      cam.CFrame = CFrame.lookAt(cam.CFrame.Position, part.Position)
      local vp = cam.ViewportSize
      VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0)
      VIM:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0)
    end)
  end
end

local function closeDialog()
  findButtons(function(b)
    local t = b.Text:lower()
    return t:find("close", 1, true) or t:find("cancel", 1, true) or t:find("fechar", 1, true)
      or t:find("sair", 1, true) or t:find("bye", 1, true) or t:find("leave", 1, true)
  end)
end

-- vai até o NPC, abre o diálogo e lê o texto novo na tela: descobre se é missão e qual nível
local function probe(g)
  local before = guiTexts()
  tpTo(g.part.CFrame * CFrame.new(0, 0, 4))
  task.wait(0.4)
  fireInst(g.inst, g.part)
  task.wait(1.2)
  local new = {}
  for t in pairs(guiTexts()) do if not before[t] then new[#new + 1] = t end end
  local txt = table.concat(new, " "):lower()
  g.probed, g.dialog = true, txt
  if hasAny(txt, { "quest", "miss", "defeat", "derrot", "kill", "accept", "aceit" }) then g.isQuest = true end
  g.n = g.n or tonumber(txt:match("lv%.?%s*(%d+)") or txt:match("level%s*(%d+)") or txt:match("n[ií]vel%s*(%d+)"))
  if g.isQuest then S.qStrong += 1 end
  return txt
end

local function doQuestNpc()
  local ch = getChar()
  if not ch then return end
  local lvl = curLevel()
  local cands = scanGivers()
  S.questT, S.questLv = tick(), lvl
  if #cands == 0 then notify("Nenhum NPC interativo achado no mapa carregado", 4) return end
  S.busy = true
  local pos = ch.HumanoidRootPart.Position
  table.sort(cands, function(a, b) return (a.part.Position - pos).Magnitude < (b.part.Position - pos).Magnitude end)
  local probes = 0 -- aprende o nível dos NPCs que ainda não sabemos (mais próximos primeiro)
  for _, g in ipairs(cands) do
    if probes >= 8 then break end
    if g.part.Parent and not g.probed and not g.n then
      probes += 1
      probe(g)
      closeDialog()
    end
  end
  local best, bn, anyN = nil, nil, false
  for _, g in ipairs(cands) do
    if g.part.Parent and (g.strong or g.isQuest) and g.n then
      anyN = true
      if (not lvl or g.n <= lvl) and (not bn or g.n > bn) then best, bn = g, g.n end -- maior nível que você já pode
    end
  end
  if not best and not anyN then
    for _, g in ipairs(cands) do if g.part.Parent and (g.strong or g.isQuest) then best = g break end end
  end
  if not best then -- NPC não carregou: vai até a posição que os dados replicados indicam
    local de, dn
    for _, e in ipairs(scanData()) do
      if e.pos and (not lvl or e.n <= lvl) and (not dn or e.n > dn) then de, dn = e, e.n end
    end
    if de then
      tpTo(CFrame.new(de.pos + Vector3.new(0, 5, 0)))
      task.wait(2.5)
      cands = scanGivers(true)
      local bd = 150
      for _, g in ipairs(cands) do
        local d = (g.part.Position - de.pos).Magnitude
        if d < bd then best, bd = g, d end
      end
      if best then best.n, best.strong = best.n or de.n, true end
    end
  end
  if not best then S.busy = false notify("Nenhuma missão de nível achada ainda (" .. #cands .. " NPCs)", 4) return end
  tpTo(best.part.CFrame * CFrame.new(0, 0, 4))
  task.wait(0.4)
  fireInst(best.inst, best.part)
  task.wait(1)
  local acc = findButtons(function(b)
    local t = b.Text:lower()
    return t:find("accept", 1, true) or t:find("aceit", 1, true) or t:find("start", 1, true)
      or t == "yes" or t == "sim" or t == "ok" or t:find("confirm", 1, true)
  end)
  S.questText = (best.dialog or "") .. " " .. best.txt
  S.busy = false
  notify(("Missão Lv %s (%s)%s"):format(tostring(best.n or "?"), best.model.Name, acc and " aceita" or " - sem botão aceitar"), 4)
end

-- ===== missão pelos DADOS do jogo + remote que o próprio jogo usa =====
local function getSea()
  if S.sea then return S.sea end
  if tick() - S.seaT < 30 then return nil end
  S.seaT = tick()
  local pg = LP:FindFirstChild("PlayerGui")
  if pg then
    for _, o in ipairs(pg:GetDescendants()) do
      if o:IsA("TextLabel") then
        local n = o.Text:lower():match("%-sea(%d)")
        if n then S.sea = tonumber(n) return S.sea end
      end
    end
  end
  local ids = { [2753915549] = 1, [4442272183] = 2, [7449423635] = 3 }
  S.sea = ids[game.PlaceId]
  return S.sea
end

local function qid(e) return tostring(e.key) .. "#" .. tostring(e.tier) end
local function isIgnored(e)
  local t = S.ignored[qid(e)]
  if t and t > tick() then return true end
  S.ignored[qid(e)] = nil
  return false
end
local function anyIgnored()
  for _, t in pairs(S.ignored) do if t > tick() then return true end end
  return false
end
local function ignoreQuest(e, why) -- ignora a missão por um tempo e força escolher outra
  S.ignored[qid(e)] = tick() + cfg.IgnoreFor
  local label = ("%s Lv%s (%s)"):format(table.concat(e.task or { tostring(e.name) }, "/"), tostring(e.n), qid(e))
  notify(("Missão %s ignorada por %ds: %s"):format(label, cfg.IgnoreFor, why), 6)
  S.questMobs, S.curEntry, S.target, S.group, S.gather = nil, nil, nil, {}, nil
  S.forceQuest = true
end

local function pickQuestEntry(lvl)
  local sea, best = getSea(), nil
  for _, e in ipairs(scanData()) do
    if e.task and e.key and e.key ~= "" and e.n <= (lvl or 1e9) and (cfg.AllowBoss or not e.boss) and not isIgnored(e) then
      local ok = true
      if sea == 1 then ok = e.n < 700 elseif sea == 2 then ok = e.n >= 700 and e.n < 1500 elseif sea == 3 then ok = e.n >= 1500 end
      if ok and (not best or e.n > best.n) then best = e end -- maior nível que você já pode fazer
    end
  end
  return best
end

local function questActive() -- tracker na tela: "Defeat <mob>" e/ou contador (0/8)
  local pg = LP:FindFirstChild("PlayerGui")
  if not pg then return false end
  local names = {}
  for _, n in ipairs(S.curEntry and S.curEntry.task or {}) do names[#names + 1] = n:lower() end
  for _, o in ipairs(pg:GetDescendants()) do
    if o:IsA("TextLabel") and (not gui or not o:IsDescendantOf(gui)) then
      local t = o.Text:lower()
      local nameHit = false
      for _, n in ipairs(names) do if t:find(n, 1, true) then nameHit = true end end
      local defeat = t:find("defeat", 1, true) or t:find("derrot", 1, true)
      local counter = t:find("%(%d+/%d+%)")
      if ((counter and (defeat or nameHit)) or (defeat and nameHit)) and shown(o) then return true, o.Text end
    end
  end
  return false
end

local function cmdRemote()
  if S.qRemote and S.qRemote.Parent then return S.qRemote end
  if S.cmdSeen and S.cmdSeen.Parent then return S.cmdSeen end
  if S.cmd and S.cmd.Parent then return S.cmd end
  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteFunction") and d.Name == "CommF_" then S.cmd = d return d end
  end
end

local function findSpawn(set, skipVisited) -- spawn dos mobs da missão (nome bate com a tarefa)
  local ch = getChar()
  local r = ch and ch.HumanoidRootPart
  local best, bd
  for sp in pairs(S.spawnSet) do
    if sp.Parent and not (skipVisited and S.visited[sp]) then
      if set[cleanName(sp.Name)] or set[cleanName(sp.Parent.Name)] then
        local d = r and (sp.Position - r.Position).Magnitude or 0
        if not bd or d < bd then best, bd = sp, d end
      end
    end
  end
  return best
end

local function mpKey(cn) return tostring(getSea() or 0) .. ":" .. cn end
local function posFor(set) -- posição já aprendida de algum mob da missão
  for cn in pairs(set) do
    local p = S.mobPos[mpKey(cn)]
    if p then return p end
  end
end

local function goDest(pos) -- tentativa controlada, com verificação e pausa após falha
  local ch = getChar()
  if not ch or not ch:FindFirstChild("HumanoidRootPart") or typeof(pos) ~= "Vector3" then return false end
  local current = ch.HumanoidRootPart.Position
  if (current - pos).Magnitude <= cfg.TpRadius then return false end
  -- Não insiste no mesmo ponto quando a posição final foi rejeitada/revertida.
  if S.lastFailedDest and (S.lastFailedDest - pos).Magnitude < 120 and tick() - (S.lastFailedTpT or 0) < 18 then
    S.lastExplore = "teleporte falhou recentemente; aguardando recuperação antes de tentar novamente"
    return false
  end
  if tick() - S.tpT < 6 then return false end
  S.tpT, S.tpCount, S.dest = tick(), S.tpCount + 1, pos
  local ok = tpTo(CFrame.new(pos + Vector3.new(0, 10, 0)))
  S.tpT = tick() -- o intervalo entre deslocamentos conta a partir da CHEGADA (a viagem pode levar 30s+)
  if not ok then
    S.lastFailedDest, S.lastFailedTpT = pos, tick()
    S.lastExplore = "destino não confirmado; pausa de recuperação ativa"
  else
    S.lastFailedDest, S.lastFailedTpT = nil, nil
    S.lastExplore = "destino confirmado; verificando spawns da missão ativa"
  end
  return ok
end

local function learnMobs() -- atualiza a posição recente de cada inimigo observado
  for _, m in ipairs(mobs()) do
    local hrp = m:FindFirstChild("HumanoidRootPart")
    if hrp and alive(m) then
      local k = mpKey(cleanName(m.Name))
      local old = S.mobPos[k]
      -- Não manter para sempre a primeira posição: inimigos podem reaparecer
      -- em outra área/ilha após streaming ou mudança de sessão.
      if not old or (old - hrp.Position).Magnitude >= 20 then
        S.mobPos[k] = hrp.Position
        S.learnDirty = true
      end
    end
  end
end

local function islandList() -- ilhas = modelos de Workspace.Map e modelos soltos no Workspace
  local out, seen = {}, {}
  local function add(inst)
    if seen[inst] or hasAny(inst.Name:lower(), SKIP) or inst.Name:lower() == "fanart" then return end
    seen[inst] = true
    local pos
    if inst:IsA("Model") then
      local ok, cf = pcall(function() return inst:GetPivot() end)
      if ok then pos = cf.Position end
    elseif inst:IsA("BasePart") then
      pos = inst.Position
    else
      local bp = inst:FindFirstChildWhichIsA("BasePart", true)
      if bp then pos = bp.Position end
    end
    if pos and pos.Magnitude > 1 then out[#out + 1] = { name = inst.Name, pos = pos } end
  end
  local map = WS:FindFirstChild("Map")
  if map then for _, c in ipairs(map:GetChildren()) do add(c) end end
  for _, c in ipairs(WS:GetChildren()) do
    if c:IsA("Model") and c ~= LP.Character and not Players:GetPlayerFromCharacter(c) then add(c) end
  end
  return out
end

-- visita as ilhas (mais perto primeiro) até os mobs da missão aparecerem; aprende a posição
local STOP = { quest = true, exp = true, island = true, area = true }
local function tokens(str)
  local out = {}
  local sp = str:gsub("(%l)(%u)", "%1 %2")
  for w in sp:lower():gmatch("%a%a%a+") do if not STOP[w] then out[w] = true end end
  return out
end

-- visita ilhas (as de nome parecido com a missão primeiro) até achar os mobs; respeita o tempo máximo
local function exploreForMobs(set, e)
  if S.exploring then return false end
  S.exploring, S.busy = true, true
  S.lastExplore = "iniciando exploração"
  local qt = tokens(e and tostring(e.key) or "")
  for n in pairs(set) do for w in pairs(tokens(n)) do qt[w] = true end end
  local list = islandList()
  for _, isl in ipairs(list) do
    local nm, sc = isl.name:lower(), 0
    for w in pairs(qt) do if nm:find(w, 1, true) then sc += 1 end end
    isl.score = sc
  end
  local ch = getChar()
  local from = ch and ch.HumanoidRootPart.Position or Vector3.zero
  table.sort(list, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.pos - from).Magnitude < (b.pos - from).Magnitude
  end)
  local found, visited = false, 0
  for _, isl in ipairs(list) do
    -- Nunca explorar ilhas aleatorias: isso causava o ciclo entre MarineStart/PirateStart.
    -- So visitar uma ilha cujo nome tenha correspondencia com a missao/alvo.
    local allowed = isl.score > 0
    if not found and allowed and visited < 25 and tick() - S.exploreT0 < cfg.SearchWait and not S.exploreSeen[isl.name] then
      S.exploreSeen[isl.name] = true
      S.lastExplore = ("visitando %s score=%d"):format(isl.name, isl.score)
      visited += 1
      if statusLbl then -- o loop principal fica preso aqui; atualiza o painel direto
        statusLbl.Text = ("explorando ilha %d: %s\nprocurando: %s"):format(visited, isl.name, table.concat(e and e.task or {}, "/"))
      end
      tpTo(CFrame.new(isl.pos + Vector3.new(0, 60, 0)))
      holdAt(isl.pos + Vector3.new(0, 60, 0), 2.5) -- espera o mapa carregar SEM ancorar (ancorado o servidor não vê a posição)
      pcall(learnMobs)
      found = posFor(set) ~= nil
    end
  end
  S.lastExplore = found and "inimigo localizado após exploração" or ("exploração terminou; ilhas visitadas=" .. tostring(visited))
  S.exploring, S.busy = false, false
  return found
end

local function needQuest()
  if S.forceQuest then S.forceQuest = false return true end
  if tick() - S.qChkT < 3 then return false end
  S.qChkT = tick()
  -- missão em andamento: subir de nível NÃO reinicia. O progresso (ex.: 4/5) continua no servidor.
  if S.questMobs and questActive() then S.questLv = curLevel() return false end
  if curLevel() ~= S.questLv and not S.questMobs then return true end
  if tick() - S.questT < 10 then return false end
  if S.qVerified then return not questActive() end
  return tick() - S.questT > 60
end

local function doQuest()
  local lvl = curLevel()
  local e = pickQuestEntry(lvl)
  S.questT, S.questLv = tick(), lvl
  if not e and anyIgnored() then
    S.qInfo, S.questMobs, S.curEntry = "missões ignoradas: farmando por nível", nil, nil
    return
  end
  if not e or not cmdRemote() then S.qInfo = "sem dados/remote: modo NPC" return doQuestNpc() end
  S.busy = true
  local set = {}
  for _, n in ipairs(e.task) do set[cleanName(n)] = true end
  S.questMobs, S.curEntry = set, e
  S.qInfo = ("%s Lv%d (%s #%d)%s"):format(table.concat(e.task, "/"), e.n, e.key, e.tier, e.boss and " [chefe]" or "")
  S.tpCount, S.searchT0, S.exploreT0, S.gather, S.dest = 0, tick(), tick(), nil, nil
  local function ask()
    local rf = cmdRemote()
    local done = false
    task.spawn(function()
      pcall(function() return rf:InvokeServer(S.verb or "StartQuest", e.key, e.tier) end)
      done = true
    end)
    local t0 = tick()
    while not done and tick() - t0 < 3 do task.wait(0.1) end
    task.wait(1)
    return questActive()
  end
  local active = ask() -- 1) de onde está (o servidor aceitou assim)
  if not active then   -- 2) vai até a região dos mobs, acha o NPC mais perto e tenta de novo
    local sp = findSpawn(set)
    local base = posFor(set) or (sp and sp.Position)
    if base then tpTo(CFrame.new(base + Vector3.new(0, 6, 0))) task.wait(2) end
    local ch = getChar()
    base = base or (ch and ch.HumanoidRootPart.Position)
    scanGivers(true)
    local npc, nd = nil, 600
    for _, g in ipairs(S.givers) do
      if (g.strong or g.isQuest) and g.part.Parent and base then
        local d = (g.part.Position - base).Magnitude
        if d < nd then npc, nd = g, d end
      end
    end
    if S.questPos[e.key] then tpTo(CFrame.new(S.questPos[e.key]))
    elseif npc then tpTo(npc.part.CFrame * CFrame.new(0, 0, 4)) end
    task.wait(0.6)
    active = ask()
    if not active and npc then
      fireInst(npc.inst, npc.part)
      task.wait(1)
      findButtons(function(b)
        local t = b.Text:lower()
        return t:find("accept", 1, true) or t:find("aceit", 1, true) or t:find("start", 1, true) or t == "yes" or t == "ok"
      end)
      task.wait(1)
      active = questActive()
    end
  end
  if active then S.qVerified, S.qOkT = true, tick() end
  S.busy = false
  notify(("Missão %s: %s"):format(S.qInfo, active and "ACEITA ✓" or "sem confirmação (aceite 1x manual p/ o script aprender)"), 5)
end

-- ============ BAÚS (descobertos): visita TODOS, um por vez ============
local function scanChests()
  if tick() - S.chestScanT < 2 then return S.chests end
  S.chestScanT, S.chests = tick(), {}
  for d in pairs(S.chestSet) do
    if d.Parent and not (d.Parent:IsA("Model") and d.Parent.Name:lower():find("chest", 1, true)) then
      S.chests[#S.chests + 1] = d
    end
  end
  return S.chests
end

local function chestStep()
  local ch = getChar()
  if not ch then return end
  local root, best, bd, left = ch.HumanoidRootPart, nil, math.huge, 0
  local list = scanChests()
  for _, c in ipairs(list) do
    if c.Parent and not (S.chestDone[c] and tick() - S.chestDone[c] < 120) then
      left += 1
      local d = (pivotPos(c) - root.Position).Magnitude
      if d < bd then best, bd = c, d end
    end
  end
  if not best then notify(("Todos os baús visitados (%d)"):format(#list), 2) return end
  S.chestDone[best] = tick() -- não volta nesse baú por 2 min
  S.busy = true
  tpTo(CFrame.new(pivotPos(best) + Vector3.new(0, 3, 0)))
  task.wait(0.35)
  local root2 = getChar() and getChar().HumanoidRootPart
  for _, p in ipairs(best:GetDescendants()) do
    if p:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
      pcall(function() p.HoldDuration = 0 end)
      pcall(fireproximityprompt, p)
    elseif p:IsA("ClickDetector") and type(fireclickdetector) == "function" then
      pcall(fireclickdetector, p)
    elseif p:IsA("TouchTransmitter") and root2 and type(firetouchinterest) == "function" then
      pcall(function() firetouchinterest(root2, p.Parent, 0) firetouchinterest(root2, p.Parent, 1) end)
    end
  end
  task.wait(0.4)
  S.busy = false
  S.chestScanT = 0 -- reescaneia: novos baús carregam quando você chega perto
  notify(("Baú %s (faltam %d)"):format(best.Name, left - 1), 2)
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
  local lvl = curLevel()
  if S.questMobs then -- destino SEMPRE ligado à missão ativa (nada de posições genéricas)
    local e = S.curEntry
    -- Shanda Lv475: ponto fixo na área celestial/Upper Skylands.
    -- Não alternar entre ilhas com nomes parecidos enquanto a região carrega.
    local isShanda = false
    for name in pairs(S.questMobs) do
      if name:find("shanda", 1, true) then isShanda = true break end
    end
    if isShanda then
      local anchor = Vector3.new(-7678, 5566, -497)
      local dist = (r.Position - anchor).Magnitude
      if dist > cfg.TpRadius then
        if tick() - S.tpT >= 5 then
          S.lastExplore = ("âncora Shanda; distância %.1f; indo para Upper Skylands"):format(dist)
          goDest(anchor)
        end
        return
      end
      -- Já está na região certa: não voltar a explorar outras ilhas.
      S.lastExplore = ("na região Shanda/Upper Skylands; distância %.1f; aguardando spawn"):format(dist)
      if tick() - S.searchT0 > 25 then S.searchT0 = tick() end
      return
    end
    local pos = posFor(S.questMobs) -- 1) última posição observada desses inimigos
    if pos then
      local nearDest = (r.Position - pos).Magnitude <= cfg.TpRadius
      local nearFarm = S.gather and (r.Position - S.gather).Magnitude <= cfg.TpRadius
      if not (nearDest or nearFarm) then
        if S.tpCount >= cfg.MaxTp then
          if e then ignoreQuest(e, "deslocamentos demais sem achar inimigos") end
          return
        end
        if goDest(pos) then S.searchT0 = tick() end
        return
      end
      -- Se chegamos à posição aprendida mas nenhum alvo apareceu, não ficar
      -- preso nesse ponto até o limite geral da missão. Invalida a memória
      -- antiga e continua para spawn/descoberta de outras áreas.
      if tick() - S.searchT0 < 20 then return end
      for cn in pairs(S.questMobs) do S.mobPos[mpKey(cn)] = nil end
      S.learnDirty = true
    end
    local sp = findSpawn(S.questMobs, true) -- 2) spawn com o nome do mob
    if sp then
      if tick() - S.tpT > 15 then -- só passa pro próximo spawn depois de esperar um pouco
        S.visited[sp] = true
        if goDest(sp.Position) then S.searchT0 = tick() end
      end
      return
    end
    if exploreForMobs(S.questMobs, e) then -- 3) explora (limitado) e aprende a posição
      S.searchT0 = tick()
    elseif not posFor(S.questMobs) and e then
      ignoreQuest(e, "inimigos não encontrados")
    end
    return
  end
  local bestE, be -- 1) posições dos dados replicados (inimigo/missão do seu nível)
  for _, e in ipairs(scanData()) do
    if e.pos and not S.visited[e] and (not lvl or e.n <= lvl + cfg.LevelMargin) and (not be or e.n > be) then
      bestE, be = e, e.n
    end
  end
  if bestE then
    S.visited[bestE] = true
    tpTo(CFrame.new(bestE.pos + Vector3.new(0, 8, 0)))
    return
  end
  local best, bd = nil, math.huge -- 2) spawns de inimigo já vistos
  for sp in pairs(S.spawnSet) do
    if sp.Parent and not S.visited[sp] then
      local n, pn = sp.Name:lower(), sp.Parent.Name:lower()
      if n:find("enem", 1, true) or pn:find("enem", 1, true) or n:find("mob", 1, true) or pn:find("mob", 1, true) then
        local sl = tonumber((n .. " " .. pn):match("lv%.?%s*(%d+)"))
        if not (sl and lvl and sl > lvl + cfg.LevelMargin) then
          local d = (sp.Position - r.Position).Magnitude
          if d < bd then best, bd = sp, d end
        end
      end
    end
  end
  if not best then S.visited = {} return end
  S.visited[best] = true
  tpTo(CFrame.new(best.Position + Vector3.new(0, 8, 0)))
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

local MODES = { "um-a-um", "lista", "so-hits" }

local function hitArgs(h, part, extra) -- clona a chamada REAL do jogo trocando só a peça (e a lista, se houver)
  local args = table.pack(table.unpack(h.args, 1, h.args.n))
  args[1] = part
  for i = 2, args.n do if type(args[i]) == "table" then args[i] = extra or {} end end
  return args
end

local function entryFor(m, hrp) -- item da lista de alvos (arg 2) no formato aprendido do jogo
  local sh = S.hitShape
  if type(sh) == "string" then return sh == "model" and m or hrp end
  if type(sh) == "table" then
    local e = {}
    for i, k in ipairs(sh) do e[i] = (k == "model") and m or ((k == "part") and hrp or nil) end
    return e
  end
  return { m, hrp } -- palpite, usado só se o formato real ainda não foi visto
end

local function remoteAttack()
  local a, h = S.atk, S.hit
  if not (a and h and a.self.Parent and h.self.Parent) then return false end
  if tick() - S.atkT < 0.22 then return true end
  S.atkT = tick()
  local ch = getChar()
  local pr = ch and ch.HumanoidRootPart
  if not pr then return false end
  local list = {} -- só quem está ao alcance REAL do golpe (o alvo principal sempre primeiro)
  local function add(m)
    local hrp = m and m.Parent and m:FindFirstChild("HumanoidRootPart")
    if hrp and alive(m) and (hrp.Position - pr.Position).Magnitude <= cfg.HitRange then list[#list + 1] = { m = m, hrp = hrp } end
  end
  add(S.target)
  for _, m in ipairs(S.group) do if m ~= S.target then add(m) end end
  if #list == 0 then return false end
  local function fireA() pcall(function() a.self:FireServer(table.unpack(a.args, 1, a.args.n)) end) end
  local function fireH(it, extra)
    local args = hitArgs(h, it.hrp, extra)
    pcall(function() h.self:FireServer(table.unpack(args, 1, args.n)) end)
  end
  local mode = MODES[S.hitMode]
  if mode == "lista" then -- 1 ataque, 1 golpe; os outros alvos vão na lista (como o jogo faz no golpe em área)
    fireA()
    local extra = {}
    for i = 2, math.min(#list, 12) do extra[#extra + 1] = entryFor(list[i].m, list[i].hrp) end
    fireH(list[1], extra)
  elseif mode == "um-a-um" then -- cada alvo recebe o SEU ataque + golpe (o servidor costuma contar 1 golpe por ataque)
    fireA() fireH(list[1])
    for _ = 1, math.min(#list - 1, 2) do
      S.rr += 1
      fireA() fireH(list[(S.rr - 1) % (#list - 1) + 2])
    end
  else -- "so-hits": 1 ataque + 1 golpe por alvo (modo antigo)
    fireA()
    for i = 1, math.min(#list, 12) do fireH(list[i]) end
  end
  return true
end

local function attack()
  if S.target and remoteAttack() then return end
  local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
  if tool then pcall(function() tool:Activate() end) end
  local vp = WS.CurrentCamera.ViewportSize
  local x, y = vp.X / 2, vp.Y / 2 -- inimigo no centro; nunca clica nos botões de habilidade
  if overUI(x, y) then return end
  pcall(function()
    VIM:SendMouseMoveEvent(x, y, game)
    VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
  end)
  if cfg.TouchClick and UIS.TouchEnabled then -- celular: toque também
    pcall(function()
      VIM:SendTouchEvent(7, 0, x, y)
      VIM:SendTouchEvent(7, 2, x, y)
    end)
  end
end

-- a cada frame: fica parado em cima do alvo, olhando pra ele, câmera mirando nele
RUN.Heartbeat:Connect(function()
  local t = S.target
  if not cfg.AutoFarm or not t or not alive(t) then return end
  if S.busy and not S.travel and not S.exploring then return end
  local ch = getChar()
  local tr = t:FindFirstChild("HumanoidRootPart")
  if not ch or not tr then return end
  local r = ch.HumanoidRootPart
  local h = math.max(5, cfg.Height + S.hAdj)
  local bringing = bringOn() and S.gather ~= nil
  if bringing and (tr.Position - S.gather).Magnitude > 8 then S.gather = tr.Position end -- o alvo andou: acompanha
  local center = bringing and S.gather or tr.Position
  if bringing then -- reúne os mobs da missão num ponto só
    local i = 0
    for _, m in ipairs(S.group) do
      local hrp = m ~= t and m.Parent and m:FindFirstChild("HumanoidRootPart")
      if hrp and ownsMob(hrp) then -- NÃO mexe no que o servidor controla: seria só visual (inimigo congelado)
        i += 1
        local slot = S.gather + Vector3.new(math.cos(i * 2.4) * 3, 0, math.sin(i * 2.4) * 3)
        if (hrp.Position - slot).Magnitude > 6 then -- só reposiciona se ele saiu do lugar (nada de mexer todo quadro)
          hrp.CFrame = CFrame.new(slot)
          hrp.AssemblyLinearVelocity = Vector3.zero
        end
      end
    end
  end
  r.CFrame = CFrame.lookAt(center + Vector3.new(0, h, 1.5), center)
  r.AssemblyLinearVelocity = Vector3.zero
  r.AssemblyAngularVelocity = Vector3.zero
  local cam = WS.CurrentCamera
  cam.CameraType = Enum.CameraType.Scriptable
  cam.CFrame = CFrame.lookAt(r.Position, center)
  S.hov = true
end)

local function stopHover()
  if not S.hov then return end
  S.hov = false
  WS.CurrentCamera.CameraType = Enum.CameraType.Custom
  local ch = getChar()
  if ch then ch.Humanoid.PlatformStand = false end
end

local function buildGroup(t) -- todos os mobs da missão (mesmo nome) perto do alvo
  local g = {}
  local tr = t:FindFirstChild("HumanoidRootPart")
  if not tr then return g end
  local tp, key, rad = tr.Position, cleanName(t.Name), groupRadius()
  for _, m in ipairs(mobs()) do
    if alive(m) and not (S.black[m] and S.black[m] > tick()) then
      local cn = cleanName(m.Name)
      local fits = S.questMobs and S.questMobs[cn] or (not S.questMobs and cn == key)
      local hrp = m:FindFirstChild("HumanoidRootPart")
      if fits and hrp and (hrp.Position - tp).Magnitude <= rad then g[#g + 1] = m end
    end
  end
  return g
end

local function trackWindow(r) -- o dano está chegando em mais de um inimigo? senão troca de estratégia
  for _, m in ipairs(S.group) do
    if not alive(m) then S.winHit[m] = true end -- morreu = foi atingido
  end
  for _, m in ipairs(S.group) do
    local hrp = m:FindFirstChild("HumanoidRootPart")
    local mh = m:FindFirstChildOfClass("Humanoid")
    if hrp and mh and (hrp.Position - r.Position).Magnitude <= cfg.HitRange then
      S.winSeen[m] = true
      local prev = S.hpSeen[m]
      if prev and mh.Health < prev - 0.01 then S.winHit[m] = true end
      S.hpSeen[m] = mh.Health
    end
  end
  if tick() - S.winT < 3 then return end
  S.winT = tick()
  local n, d = 0, 0
  for m in pairs(S.winSeen) do n += 1 if S.winHit[m] then d += 1 end end
  S.winSeen, S.winHit = {}, {}
  if n < 2 then return end
  if d >= 2 then S.failW, S.modeTries, S.okMode = 0, 0, true return end
  S.failW += 1
  if S.failW < 2 then return end
  S.failW = 0
  if bringOn() and S.okMode then -- o dano em vários já funcionou: o culpado é o agrupamento
    S.bringBad = true
    notify("Agrupar não está dando dano em todos: modo seguro (não move mais inimigos)", 6)
    return
  end
  S.modeTries += 1
  S.hitMode = S.hitMode % #MODES + 1
  if tick() - (S.noteT or 0) > 15 then
    S.noteT = tick()
    notify(("Só %d de %d inimigos levando dano: modo de golpe -> %s"):format(d, n, MODES[S.hitMode]), 5)
  end
  if S.modeTries >= #MODES then
    S.modeTries = 0
    if bringOn() then
      S.bringBad = true
      notify("Nenhum modo funcionou com agrupamento: modo seguro (não move mais inimigos)", 6)
    end
  end
end

-- Mesma limpeza que acontece ao desligar e ligar "Lutar sozinho". Usada quando o estado
-- antigo (lista de bloqueio, alvo, ponto de agrupamento) faz o script achar que não há alvo.
local function resetFarm()
  if not S.travel and not S.exploring then S.busy = false end
  S.target, S.group, S.gather = nil, {}, nil
  S.black = {}
  S.hAdj, S.aT, S.grpT, S.tHp, S.tT = 0, 0, 0, 0, tick()
  S.searchT0 = tick()
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
    if not S.target and (next(S.black) ~= nil or S.busy) then -- estado antigo: limpa e tenta de novo
      resetFarm()
      S.target = pickTarget(r)
    end
    local mh = S.target and S.target:FindFirstChildOfClass("Humanoid")
    S.tT, S.tHp = tick(), mh and mh.Health or 0
    local trr = S.target and S.target:FindFirstChild("HumanoidRootPart")
    S.gather = trr and trr.Position -- ponto onde o grupo é reunido
    S.group, S.grpT = {}, 0
  end
  local t = S.target
  if not t then
    S.group = {}
    stopHover()
    hum.PlatformStand = false
    if S.questMobs then
      local e = S.curEntry
      local limit = (e and e.boss) and cfg.BossWait or cfg.SearchWait
      local waited = math.floor(tick() - S.searchT0)
      S.state = ("%s: aguardando %s (%d/%ds)"):format(tostring(S.qInfo), (e and e.boss) and "o chefe" or "os inimigos", waited, limit)
      if e and waited > limit and not S.exploring then
        ignoreQuest(e, ((e.boss and "chefe ausente" or "inimigos ausentes")) .. " após " .. limit .. "s")
        return
      end
      if cfg.Roam then roam(r) end
    elseif S.dTotal == 0 then
      S.state = "0 inimigos carregados" .. (cfg.Roam and " - procurando spawns..." or "")
      if cfg.Roam then roam(r) end
    else
      S.state = ("%d inimigos, 0 do seu nível (menor Lv %s; seu Lv %s)"):format(S.dTotal, tostring(S.dMin), tostring(curLevel()))
    end
    return
  end
  S.searchT0 = tick() -- achou alvo: zera a espera
  if tick() - S.grpT > 0.5 then S.grpT = tick() S.group = buildGroup(t) end
  trackWindow(r)
  local mh = t:FindFirstChildOfClass("Humanoid")
  if mh.Health < S.tHp - 0.01 then S.tHp, S.tT = mh.Health, tick() end -- acertou
  local idle = tick() - S.tT
  if idle > 3 and tick() - S.aT > 3 then -- não acertou: chega mais perto
    S.aT = tick()
    S.hAdj = math.max(S.hAdj - 2, 6 - cfg.Height)
  end
  if idle > 10 then S.black[t] = tick() + 15 S.target = nil S.hAdj = 0 return end -- alvo inalcançável/congelado
  S.state = ("batendo em %s (Lv %s) | %s | %s"):format(t.Name, tostring(lvOf(t) or "?"),
    idle < 3 and "dano OK" or ("SEM DANO há " .. math.floor(idle) .. "s"), bringOn() and "agrupando" or "grupo sem mover")
  hum.PlatformStand = true
  equipTool(hum)
  attack()
end

-- ============ MOVIMENTO / ESP / VISUAL ============
RUN.Stepped:Connect(function()
  if not (cfg.NoClip or S.travel) then return end
  local ch = LP.Character
  if not ch then return end
  S.ccBack = S.ccBack or {}
  for _, p in ipairs(ch:GetDescendants()) do
    if p:IsA("BasePart") and p.CanCollide then
      if S.travel and not cfg.NoClip then S.ccBack[p] = true end -- só lembra se foi a viagem que desligou
      p.CanCollide = false
    end
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

local function simRadius() -- deixa o cliente controlar os mobs próximos (necessário p/ juntar)
  if type(sethiddenproperty) == "function" then
    pcall(sethiddenproperty, LP, "SimulationRadius", math.huge)
    pcall(sethiddenproperty, LP, "MaximumSimulationRadius", math.huge)
  end
end

-- ============ ESPIÃO DE REMOTES (aprende como o jogo fala com o servidor) ============
local function fmtArg(v, d)
  local t = typeof(v)
  if t == "string" then return '"' .. v:sub(1, 40) .. '"'
  elseif t == "number" or t == "boolean" or t == "nil" then return tostring(v)
  elseif t == "Instance" then return "<" .. v.Name .. ">"
  elseif t == "table" then
    if (d or 0) >= 1 then return "{...}" end
    local parts, n = {}, 0
    for k, x in pairs(v) do
      n += 1
      if n > 5 then parts[#parts + 1] = "..." break end
      parts[#parts + 1] = tostring(k) .. "=" .. fmtArg(x, 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return tostring(v)
end

local LEARN_FILE = "BF_DELTA_LEARN.json"
local function saveLearn()
  S.learnDirty = false
  if type(writefile) ~= "function" then return end
  local pos, mob = {}, {}
  for k, v in pairs(S.questPos) do pos[k] = { v.X, v.Y, v.Z } end
  for k, v in pairs(S.mobPos) do mob[k] = { v.X, v.Y, v.Z } end
  pcall(function() writefile(LEARN_FILE, HTTP:JSONEncode({ verb = S.verb, pos = pos, mob = mob })) end)
end
local function loadLearn()
  if type(readfile) ~= "function" or type(isfile) ~= "function" or not isfile(LEARN_FILE) then return end
  pcall(function()
    local d = HTTP:JSONDecode(readfile(LEARN_FILE))
    S.verb = d.verb
    for k, v in pairs(d.pos or {}) do S.questPos[k] = Vector3.new(v[1], v[2], v[3]) end
    for k, v in pairs(d.mob or {}) do S.mobPos[k] = Vector3.new(v[1], v[2], v[3]) end
  end)
end

local function startSpy()
  if S.spy or type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then return end
  S.spy = true
  local old
  local function hook(self, ...)
    local m = getnamecallmethod()
    if (m == "FireServer" or m == "InvokeServer") and not (type(checkcaller) == "function" and checkcaller()) then
      local args = table.pack(...)
      pcall(function()
        local key = (self.Parent and self.Parent.Name or "?") .. "/" .. self.Name
        local e = S.rlog[key]
        if not e then e = { c = 0, s = {} } S.rlog[key] = e end
        e.c += 1
        local parts = {}
        for i = 1, math.min(args.n, 6) do parts[i] = fmtArg(args[i]) end
        local str = m .. "(" .. table.concat(parts, ", ") .. ")"
        if #e.s < 3 then e.s[#e.s + 1] = str end
        local low = str:lower()
        if low:find("quest", 1, true) or low:find("mission", 1, true) then
          S.lastQuestCall = { self = self, m = m, args = args }
          e.q = str
        end
        local low2 = self.Name:lower()
        if low2:find("registerattack", 1, true) and args.n >= 1 then
          S.atk = { self = self, args = args }
        elseif low2:find("registerhit", 1, true) and typeof(args[1]) == "Instance" then
          S.hit = { self = self, args = args }
          if type(args[2]) == "table" then -- golpe em área real: copia o formato dos itens da lista
            local _, v = next(args[2])
            local function kind(x) if typeof(x) == "Instance" then return x:IsA("Model") and "model" or "part" end return typeof(x) end
            if type(v) == "table" then
              local d = {}
              for i = 1, #v do d[i] = kind(v[i]) end
              S.hitShape = d
            elseif v ~= nil then
              S.hitShape = kind(v)
            end
          end
        end
        if m == "InvokeServer" and type(args[1]) == "string" and args[1]:lower():find("point", 1, true) then
          S.statTpl = { self = self, args = args } -- comando real de somar ponto (aprendido)
          notify("Comando de status aprendido", 3)
        end
        if m == "InvokeServer" and type(args[1]) == "string" and args[1]:lower():find("quest", 1, true) then
          S.cmdSeen = self
          if type(args[2]) == "string" and type(args[3]) == "number" and not (low:find("progress", 1, true) or low:find("check", 1, true)) then
            S.verb, S.qRemote = args[1], self -- aprendeu o "verbo" de iniciar missão
            local r = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if r then S.questPos[args[2]] = r.Position end -- e onde fica o NPC dessa missão
            S.learnDirty = true
          end
        end
      end)
    end
    return old(self, ...)
  end
  old = hookmetamethod(game, "__namecall", type(newcclosure) == "function" and newcclosure(hook) or hook)
end

-- ============ DIAGNÓSTICO (copia pro clipboard) ============
local function report()
  local L = {}
  local function add(x) L[#L + 1] = tostring(x):sub(1, 140) end
  add(("== BF DIAG == Lv=%s $%s pasta=%s"):format(tostring(curLevel()), tostring(getMoney()), S.folder and S.folder:GetFullName() or "nil"))
  local ms = mobs()
  add("INIMIGOS: " .. #ms)
  for i = 1, math.min(8, #ms) do
    local h = ms[i]:FindFirstChildOfClass("Humanoid")
    add(("  %s | lv=%s | hp=%s"):format(ms[i].Name, tostring(lvOf(ms[i])), tostring(h and h.Health)))
  end
  add("WORKSPACE (filhos):")
  local wn = 0
  for _, c in ipairs(WS:GetChildren()) do
    if wn >= 40 then break end
    wn += 1 add(("  %s [%s] filhos=%d"):format(c.Name, c.ClassName, #c:GetChildren()))
  end
  local gv = scanGivers(true)
  add(("NPCS INTERATIVOS: %d (missão: %d)"):format(#gv, S.qStrong))
  for i = 1, math.min(18, #gv) do
    local g = gv[i]
    add(("  %s | %s | n=%s | missao=%s | %s"):format(g.model.Name, g.inst.ClassName, tostring(g.n), tostring(g.strong or g.isQuest), g.txt:sub(1, 50)))
  end
  local ch2 = scanChests()
  add("BAUS: " .. #ch2)
  for i = 1, math.min(4, #ch2) do add("  " .. ch2[i]:GetFullName()) end
  add("VALORES DO JOGADOR:")
  local n = 0
  for _, d in ipairs(LP:GetDescendants()) do
    if n >= 25 then break end
    if d:IsA("ValueBase") then n += 1 add(("  %s.%s = %s"):format(d.Parent and d.Parent.Name or "?", d.Name, tostring(d.Value))) end
  end
  local tools = {}
  for _, c in ipairs(LP.Character and LP.Character:GetChildren() or {}) do if c:IsA("Tool") then tools[#tools + 1] = c.Name end end
  local bp = LP:FindFirstChild("Backpack")
  for _, c in ipairs(bp and bp:GetChildren() or {}) do if c:IsA("Tool") then tools[#tools + 1] = c.Name end end
  add("FERRAMENTAS: " .. table.concat(tools, ", "))
  add("REMOTES:")
  n = 0
  for _, d in ipairs(RS:GetDescendants()) do
    if n >= 30 then break end
    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then n += 1 add(("  %s/%s"):format(d.Parent and d.Parent.Name or "?", d.Name)) end
  end
  add("BOTOES VISIVEIS:")
  n = 0
  for t in pairs(guiTexts()) do
    if n >= 20 then break end
    n += 1 add("  " .. t)
  end
  add("REPLICATEDSTORAGE (filhos):")
  local rn = 0
  for _, c in ipairs(RS:GetChildren()) do
    if rn >= 30 then break end
    rn += 1 add(("  %s [%s] filhos=%d"):format(c.Name, c.ClassName, #c:GetChildren()))
  end
  local dq = scanData()
  add(("DADOS REPLICADOS: %d entradas | modulos: %s"):format(#dq, table.concat(S.dataMods, ", ")))
  for i = 1, math.min(14, #dq) do
    add(("  Lv%s | %s | key=%s #%s | task=%s"):format(tostring(dq[i].n), tostring(dq[i].name), tostring(dq[i].key), tostring(dq[i].tier), dq[i].task and table.concat(dq[i].task, "/") or "-"))
  end
  add("REMOTES USADOS (espiao " .. (S.spy and "ativo" or "indisponivel") .. "):")
  local rc = 0
  for key, e in pairs(S.rlog) do
    if rc >= 22 then break end
    rc += 1 add(("  %s x%d %s"):format(key, e.c, e.s[1] or ""))
    if e.q then add("    QUEST: " .. e.q) end
  end
  add(("APRENDIZADO: verbo=%s | ataque=%s/%s | posicoes=%d | missao=%s | mar=%s"):format(
    tostring(S.verb), S.atk and "ok" or "nao", S.hit and "ok" or "nao", (function() local n = 0 for _ in pairs(S.questPos) do n += 1 end return n end)(),
    tostring(S.qInfo), tostring(getSea())))
  add("MOBS COM POSICAO APRENDIDA: " .. (function() local n = 0 for _ in pairs(S.mobPos) do n += 1 end return n end)())
  local function v3(v)
    if typeof(v) == "Vector3" then return ("%.1f, %.1f, %.1f"):format(v.X, v.Y, v.Z) end
    return tostring(v or "nil")
  end
  local chDiag = getChar()
  add("POSICAO ATUAL: " .. v3(chDiag and chDiag.HumanoidRootPart.Position))
  add("ULTIMO TELEPORTE: " .. tostring(S.lastTpResult))
  add("ULTIMA EXPLORACAO: " .. tostring(S.lastExplore))
  add(("DANO EM GRUPO: modo=%s okMulti=%s falhas=%d | agrupar=%s (bringBad=%s) | formato lista=%s"):format(
    MODES[S.hitMode], tostring(S.okMode), S.modeTries, tostring(bringOn()), tostring(S.bringBad),
    type(S.hitShape) == "table" and table.concat(S.hitShape, "+") or tostring(S.hitShape)))
  add(("EXECUTOR: isnetworkowner=%s sethiddenproperty=%s"):format(tostring(type(isnetworkowner) == "function"), tostring(type(sethiddenproperty) == "function")))
  add(("STATUS: pontos=%s escolhidos=%s comando=%s"):format(tostring(getPoints()),
    table.concat(pickedStats(), "+"), S.statTpl and "aprendido" or "padrão (AddPoint, não confirmado)"))
  add("DESTINO ATUAL: " .. v3(S.dest))
  add(("VELOCIDADE DE VIAGEM: %d studs/s (fator adaptativo %.2f)"):format(math.floor((tonumber(cfg.TravelSpeed) or 300) * (S.speedMul or 1)), S.speedMul or 1))
  add("HISTORICO DE TELEPORTES (mais recente primeiro):")
  for i = 1, math.min(60, #S.tpLog) do
    local t = S.tpLog[i]
    add(("  %s ok=%s modo=%s dist=%s de=[%s] para=[%s] final=[%s] motivo=%s"):format(
      tostring(t.t), tostring(t.ok), tostring(t.mode), tostring(t.dist and math.floor(t.dist)),
      v3(t.from), v3(t.to), v3(t.after), tostring(t.reason)))
  end
  add("TODAS AS POSICOES APRENDIDAS DOS MOBS:")
  local mobN = 0
  for key, pos in pairs(S.mobPos) do
    mobN += 1
    add(("  %s => [%s]"):format(tostring(key), v3(pos)))
  end
  if mobN == 0 then add("  (nenhuma posição de mob aprendida)") end
  add("POSICOES DE NPCS/MISSOES:")
  local giverN = 0
  for _, g in ipairs(S.givers or {}) do
    if g.part and g.part.Parent then
      giverN += 1
      add(("  %s | pos=[%s] | n=%s | quest=%s | texto=%s"):format(
        tostring(g.model and g.model.Name), v3(g.part.Position), tostring(g.n),
        tostring(g.strong or g.isQuest), tostring(g.txt or ""):sub(1, 70)))
    end
  end
  if giverN == 0 then add("  (nenhum NPC registrado)") end
  add("SPAWNS/LOCAIS DE INIMIGOS APRENDIDOS:")
  local spawnN = 0
  for sp in pairs(S.spawnSet) do
    if sp and sp.Parent then
      spawnN += 1
      add(("  %s | pai=%s | pos=[%s] | visitado=%s"):format(
        tostring(sp.Name), tostring(sp.Parent.Name), v3(sp.Position), tostring(S.visited[sp])))
    end
  end
  if spawnN == 0 then add("  (nenhum spawn registrado)") end
  add("ILHAS/AREAS VISITADAS:")
  local islandN = 0
  for name in pairs(S.exploreSeen) do islandN += 1 add("  " .. tostring(name)) end
  if islandN == 0 then add("  (nenhuma ilha registrada)") end
  add("POSICOES DE QUEST CONHECIDAS:")
  local questPosN = 0
  for key, pos in pairs(S.questPos) do questPosN += 1 add(("  %s => [%s]"):format(tostring(key), v3(pos))) end
  if questPosN == 0 then add("  (nenhuma posição de quest registrada)") end
  local txt = table.concat(L, "\n")
  if type(setclipboard) == "function" then
    pcall(setclipboard, txt)
    notify("Diagnóstico copiado! Cole no chat", 5)
  else
    print(txt)
    notify("Sem clipboard: veja o console (F9)", 5)
  end
end

-- ============ PONTOS DE STATUS ============
-- Você escolhe até 3 dos 5 status. Os pontos disponíveis são distribuídos entre os escolhidos.
local STAT_OPTS = {
  { key = "StatMelee", name = "Melee" },        -- Soco
  { key = "StatDefense", name = "Defense" },    -- Defesa
  { key = "StatSword", name = "Sword" },        -- Espada
  { key = "StatGun", name = "Gun" },            -- Arma
  { key = "StatFruit", name = "Demon Fruit" },  -- Blox Fruit
}
local MAX_STATS = 3

local function pickedStats()
  local out = {}
  for _, o in ipairs(STAT_OPTS) do
    if cfg[o.key] then out[#out + 1] = o.name end
  end
  while #out > MAX_STATS do table.remove(out) end -- nunca mais de 3
  return out
end

local function getPoints()
  local a = tonumber(LP:GetAttribute("Points")) or tonumber(LP:GetAttribute("StatPoints"))
  if a then return a end
  local v = numValue({ points = true, statpoints = true, statpoint = true, availablepoints = true })
  return v and v.Value or 0
end

-- Como somar um ponto: começa com o palpite padrão e troca pelo comando REAL assim que
-- você somar um ponto na mão (o espião guarda a chamada e o script copia o formato).
local function addPoint(stat)
  local tpl = S.statTpl
  local rf, args
  if tpl and tpl.self.Parent then
    rf = tpl.self
    args = table.pack(table.unpack(tpl.args, 1, tpl.args.n))
    for i = 1, args.n do
      if type(args[i]) == "string" and i > 1 then args[i] = stat end
      if type(args[i]) == "number" then args[i] = 1 end
    end
  else
    rf = cmdRemote()
    if not rf then return false end
    args = table.pack("AddPoint", stat, 1) -- palpite, até aprender o real
  end
  local done, okc = false, false
  task.spawn(function()
    okc = pcall(function() return rf:InvokeServer(table.unpack(args, 1, args.n)) end)
    done = true
  end)
  local t0 = tick()
  while not done and tick() - t0 < 3 do task.wait(0.1) end
  return okc
end

local function applyStats()
  if not cfg.AutoStats then return end
  local pts = getPoints()
  local picked = pickedStats()
  if pts <= 0 or #picked == 0 then return end
  for i = 1, math.min(pts, 15) do
    S.statIdx = (S.statIdx or 0) + 1
    addPoint(picked[(S.statIdx - 1) % #picked + 1])
    task.wait(0.25)
  end
  notify(("Pontos distribuídos: %s"):format(table.concat(picked, ", ")), 3)
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

  local main = mk("Frame", { Size = UDim2.fromOffset(280, 490), Position = UDim2.fromOffset(12, 12),
    BackgroundColor3 = COLORS.bg, BorderSizePixel = 0 }, gui)
  mk("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
  mk("UIStroke", { Color = COLORS.accent, Thickness = 1.2, Transparency = 0.25 }, main)
  local title = mk("TextButton", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = COLORS.accent, BorderSizePixel = 0,
    Text = "HTC // DELTA PRO  •  recolher / arrastar", TextColor3 = COLORS.bg,
    Font = Enum.Font.GothamBold, TextSize = 13, AutoButtonColor = false }, main)
  mk("UICorner", { CornerRadius = UDim.new(0, 9) }, title)
  statusLbl = mk("TextLabel", { Position = UDim2.fromOffset(4, 30), Size = UDim2.new(1, -8, 0, 92),
    BackgroundColor3 = COLORS.bg2, BorderSizePixel = 0, Text = "HTC // DELTA PRO\nInicializando diagnóstico...", TextColor3 = COLORS.sub,
    Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top }, main)
  mk("UICorner", { CornerRadius = UDim.new(0, 7) }, statusLbl)
  local body = mk("ScrollingFrame", { Position = UDim2.fromOffset(2, 126), Size = UDim2.new(1, -4, 1, -128),
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
  toggle("BringMobs", "Juntar inimigos (só os controlados)")
  input("HitRange", "Alcance dos golpes", nil, 20, 200)
  input("BringRadius", "Raio p/ juntar", nil, 50, 800)
  toggle("AllowBoss", "Aceitar missões de chefe")
  input("BossWait", "Espera do chefe (s)", nil, 5, 600)
  input("SearchWait", "Espera dos inimigos (s)", nil, 20, 600)
  input("IgnoreFor", "Ignorar missão por (s)", nil, 30, 1800)
  toggle("ExploreAll", "Explorar outras ilhas")
  input("TpRadius", "Raio sem teleportar", nil, 50, 500)
  input("MaxTp", "Máx. teleportes/missão", nil, 3, 30)
  input("TravelSpeed", "Velocidade de viagem", nil, 100, 700)
  input("InstantMax", "Salto instantâneo até (studs)", nil, 0, 2000)
  toggle("AutoQuest", "Missão pelo nível")
  toggle("AutoRevive", "Reviver")
  toggle("TouchClick", "Toque na tela (celular)")
  toggle("Bounty", "Pegar bounty")
  section("STATUS (máx. 3)")
  toggle("AutoStats", "Distribuir pontos")
  toggle("StatMelee", "Soco")
  toggle("StatDefense", "Defesa")
  toggle("StatSword", "Espada")
  toggle("StatGun", "Arma")
  toggle("StatFruit", "Blox Fruit")
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
  button("Copiar diagnóstico", report)
  button("Repetir última missão gravada", function()
    local q = S.lastQuestCall
    if not q then notify("Nada gravado: aceite uma missão manualmente 1x") return end
    local ok, e = pcall(function() return q.self[q.m](q.self, table.unpack(q.args, 1, q.args.n)) end)
    notify(ok and "Missão reenviada" or "Falhou: " .. tostring(e))
  end)
  button("Reaprender missões", function() S.known, S.givers, S.giversT, S.questT = {}, {}, 0, 0 notify("Missões serão reaprendidas") end)
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
        main.Size = body.Visible and UDim2.fromOffset(260, 470) or UDim2.fromOffset(260, 28)
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

pcall(loadLearn)
pcall(startSpy)
local okGui, errGui = pcall(buildUI)
if not okGui then warn("[BF] GUI falhou: " .. tostring(errGui)) end

task.spawn(function()
  local nEsp, nBounty, nChest, nFruit, nStatus, nStats = 0, 0, 0, 0, 0, 0
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
    if t >= nEsp then nEsp = t + 1 safe(espStep) safe(learnMobs) safe(simRadius) end
    if cfg.AutoFarm then
      if not cfg.AutoQuest then S.questMobs = nil end
      if cfg.AutoQuest and needQuest() then safe(doQuest) end
      safe(farmStep)
    else
      S.state = "parado"
      S.target = nil
      safe(stopHover)
    end
    if S.learnDirty then safe(saveLearn) end
    if cfg.AutoStats and t >= nStats then nStats = t + 5 safe(applyStats) end
    if cfg.Bounty and t >= nBounty then nBounty = t + 6 safe(bountyStep) end
    if cfg.AutoChest and t >= nChest then nChest = t + 1.2 safe(chestStep) end
    if cfg.AutoFruit and t >= nFruit then nFruit = t + 10 safe(fruitStep) end
    if t >= nStatus and statusLbl then
      nStatus = t + 1
      statusLbl.Text = ("%s\nLv %s | $%s | Inimigos: %d | Mar %s\nMissão: %s\nAlvo: %s (grupo %d) | Ataque: %s\n%s"):format(
        S.state, tostring(curLevel() or "?"), tostring(getMoney()), S.dTotal, tostring(getSea() or "?"),
        S.qInfo or "-", S.target and S.target.Name or "-", #S.group, (S.atk and S.hit) and ("aprendido/" .. MODES[S.hitMode]) or "BATA 1x A MÃO NUM INIMIGO",
        S.lastErr ~= "" and ("ERRO: " .. S.lastErr) or "sem erros")
    end
    task.wait(0.15)
  end
end)

notify("BF DELTA pronto — ligue 'Lutar sozinho'", 5)
