--[[
    0.2 KILL ALL GOJO [Jujutsu Shenanigans] — v8
    by jane_doesigma — UI: WindUI
]]

--============================================================
-- 1. SERVIÇOS
--============================================================
local Players             = game:GetService("Players")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

--============================================================
-- 2. CONSTANTES
--============================================================
local VOID_CFRAME          = CFrame.new(-144, -10000, -352)
local ULT_MAX              = 100
local MIN_PLAYERS          = 4

-- ✅ NOVO: offset no tronco (0,0,0) em vez de atrás (0,0,-2)
local TPALL_OFFSET         = CFrame.new(0, 0, 0)

-- ✅ NOVO: quantos teleportes ficar no mesmo alvo antes de trocar
local STICK_TELEPORTS      = 5

local DOMAIN_TP_INTERVAL   = 0.1
local DOMAIN_GR_INTERVAL   = 0.2
local DOMAIN_VOID_WAIT     = 2
local DOMAIN_GR_START_WAIT = 0.5

--============================================================
-- 3. CONFIG PERSISTENTE
--============================================================
local CONFIG_FOLDER = "0.2KillAllGojo"
local CONFIG_FILE   = CONFIG_FOLDER .. "/config.json"

local function saveConfig(data)
    if not (writefile and isfolder and makefolder) then return end
    pcall(function()
        if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
end

local function loadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return {} end
    local ok, d = pcall(function() return HttpService:JSONDecode(readfile(CONFIG_FILE)) end)
    if ok and type(d) == "table" then return d end
    return {}
end

local ConfigState = loadConfig()
local function getCfg(k, d) if ConfigState[k] ~= nil then return ConfigState[k] end return d end
local function setCfg(k, v) ConfigState[k] = v end

--============================================================
-- 4. NOTIFICAÇÃO
--============================================================
local WindUI, Pending = nil, {}
local function Notify(title, content, icon)
    if WindUI then
        WindUI:Notify({ Title = title, Content = content, Duration = 4, Icon = icon or "info" })
    else
        table.insert(Pending, { title, content, icon })
    end
end

--============================================================
-- 5. ULT
--============================================================
local ULT_ATTRS = {
    "Ultimate","Ult","Awakening","AwakeningBar",
    "SixEyes","UltimateBar","UltPercent","Domain"
}
local function getUltPercent()
    for _, n in ipairs(ULT_ATTRS) do
        local v = LocalPlayer:GetAttribute(n)
        if type(v) == "number" then
            return math.clamp(math.floor(v / ULT_MAX * 100), 0, 100)
        end
    end
    return 0
end

--============================================================
-- 6. HELPERS
--============================================================
local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function isAlive()
    local h = getHum()
    return h and h.Health > 0
end

local function forceTeleport(cf)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    pcall(function() hrp.CFrame = cf end)
    pcall(function() hrp.AssemblyLinearVelocity  = Vector3.zero end)
    pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
    return true
end

--============================================================
-- 7. ALVOS
--============================================================
local function getAlivePlayers()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local h = p.Character:FindFirstChildOfClass("Humanoid")
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and r then
                table.insert(list, { root = r })
            end
        end
    end
    return list
end

local DUMMY_PATTERNS = { "dummy", "tester1234", "trainingdummy", "training_dummy", "targetdummy", "target_dummy" }

local function isDummyName(name)
    local lower = name:lower()
    for _, p in ipairs(DUMMY_PATTERNS) do
        if lower:find(p, 1, true) then return true end
    end
    return false
end

local function getHRP(model)
    if not model then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("RootPart")
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")
        or model:FindFirstChild("Head")
end

local DummyCache = { list = {}, lastUpdate = 0 }

local function refreshDummyCache(force)
    local now = tick()
    if not force and (now - DummyCache.lastUpdate) < 0.5 then
        return DummyCache.list
    end
    DummyCache.lastUpdate = now
    local list = {}
    for _, o in ipairs(workspace:GetDescendants()) do
        if o:IsA("Model") and isDummyName(o.Name) then
            local h = o:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local r = getHRP(o)
                if r then table.insert(list, { model = o, root = r }) end
            end
        end
    end
    DummyCache.list = list
    return list
end

local function getAliveDummies()
    local list = {}
    for _, d in ipairs(refreshDummyCache()) do
        if d.root and d.root.Parent then
            local h = d.model:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                table.insert(list, { root = d.root })
            end
        end
    end
    return list
end

-- ✅ NOVO: pool unificado (players + dummies)
local function getAllAliveTargets(playersList, dummiesList)
    local list = {}
    for _, t in ipairs(playersList or getAlivePlayers())   do table.insert(list, t) end
    for _, t in ipairs(dummiesList or getAliveDummies())   do table.insert(list, t) end
    return list
end

--============================================================
-- 8. STICK HELPERS
--============================================================
-- Verifica se o último alvo ainda está vivo e válido
local function lastTargetStillValid(lastRoot)
    if not lastRoot or not lastRoot.Parent then return false end
    local hum = lastRoot.Parent:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

-- Escolhe próximo alvo (evita repetir o mesmo se houver alternativa)
local function pickNextTarget(allTargets, lastRoot)
    local candidates = {}
    for _, t in ipairs(allTargets) do
        if t.root and t.root.Parent and t.root ~= lastRoot then
            table.insert(candidates, t)
        end
    end
    local pool = (#candidates > 0) and candidates or allTargets
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

--============================================================
-- 9. SERVER HOP
--============================================================
local function serverHop(minPlayers)
    minPlayers = minPlayers or MIN_PLAYERS
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
        game.PlaceId
    )
    local ok, data = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
    if ok and data and data.data then
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and s.playing >= minPlayers and s.maxPlayers > s.playing then
                if pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                end) then return true end
            end
        end
    end
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    return false
end

--============================================================
-- 10. TECLAS
--============================================================
local function pressKey(kc)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, kc, false, game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false, kc, false, game)
    end)
end

--============================================================
-- 11. DOMAIN EXPANSION (players + dummies, com stick)
--============================================================
local DomainActive    = false
local DomainToggleRef = nil

local function stopDomain() DomainActive = false end

local function startDomain()
    local percent = getUltPercent()
    if percent < 100 then
        Notify("Domain Expansion", "Pegue Awakening primeiro! (" .. percent .. "%)", "alert-triangle")
        DomainActive = false
        setCfg("DomainToggle", false)
        if DomainToggleRef then
            task.defer(function() pcall(function() DomainToggleRef:Set(false) end) end)
        end
        return
    end

    if DomainActive then return end
    DomainActive = true

    task.spawn(function()
        forceTeleport(VOID_CFRAME)
        task.wait(DOMAIN_VOID_WAIT)
        if not DomainActive then return end

        local grLoop = task.spawn(function()
            while DomainActive do
                pressKey(Enum.KeyCode.G)
                task.wait(0.03)
                pressKey(Enum.KeyCode.R)
                task.wait(DOMAIN_GR_INTERVAL - 0.03)
            end
        end)

        task.wait(DOMAIN_GR_START_WAIT)
        if not DomainActive then
            pcall(function() if coroutine.status(grLoop) ~= "dead" then task.cancel(grLoop) end end)
            return
        end

        local lastRoot     = nil
        local stickCounter = 0

        while DomainActive do
            local alivePlayers = getAlivePlayers()
            local aliveDummies = getAliveDummies()
            local allTargets   = getAllAliveTargets(alivePlayers, aliveDummies)

            -- Server hop SÓ quando TODOS os PLAYERS morrerem (dummies não contam)
            if #alivePlayers == 0 then
                Notify("Domain Expansion", "Todos os players morreram! Server hop...", "refresh-cw")
                DomainActive = false
                pcall(function() if coroutine.status(grLoop) ~= "dead" then task.cancel(grLoop) end end)
                setCfg("DomainToggle", false)
                if DomainToggleRef then
                    task.defer(function() pcall(function() DomainToggleRef:Set(false) end) end)
                end
                task.wait(0.5)
                serverHop(MIN_PLAYERS)
                break
            end

            if isAlive() and #allTargets > 0 then
                local currentTarget = nil

                -- 1) Tenta manter o alvo atual se ainda estiver válido e stickCounter não estourou
                if lastTargetStillValid(lastRoot) and stickCounter < STICK_TELEPORTS then
                    currentTarget = { root = lastRoot }
                else
                    -- 2) Escolhe novo alvo (alternando players ↔ dummies)
                    currentTarget = pickNextTarget(allTargets, lastRoot)
                    lastRoot = currentTarget and currentTarget.root or nil
                    stickCounter = 0
                end

                if currentTarget and currentTarget.root and currentTarget.root.Parent then
                    -- ✅ Teleporta NO TRONCO (offset 0,0,0)
                    forceTeleport(currentTarget.root.CFrame * TPALL_OFFSET)
                    stickCounter = stickCounter + 1
                end
            end

            task.wait(DOMAIN_TP_INTERVAL)
        end

        pcall(function() if coroutine.status(grLoop) ~= "dead" then task.cancel(grLoop) end end)
    end)
end

--============================================================
-- 12. TEST DOMAIN DUMMY (só dummies, com stick)
--============================================================
local DummyDomainActive = false
local DummyToggleRef    = nil

local function stopDummyDomain() DummyDomainActive = false end

local function startDummyDomain()
    local percent = getUltPercent()
    if percent < 100 then
        Notify("Test Domain Dummy", "Pegue Awakening primeiro! (" .. percent .. "%)", "alert-triangle")
        DummyDomainActive = false
        setCfg("DummyDomainToggle", false)
        if DummyToggleRef then
            task.defer(function() pcall(function() DummyToggleRef:Set(false) end) end)
        end
        return
    end

    if DummyDomainActive then return end
    DummyDomainActive = true

    task.spawn(function()
        forceTeleport(VOID_CFRAME)
        task.wait(DOMAIN_VOID_WAIT)
        if not DummyDomainActive then return end

        local rgLoop = task.spawn(function()
            while DummyDomainActive do
                pressKey(Enum.KeyCode.R)
                task.wait(0.03)
                pressKey(Enum.KeyCode.G)
                task.wait(DOMAIN_GR_INTERVAL - 0.03)
            end
        end)

        task.wait(DOMAIN_GR_START_WAIT)
        if not DummyDomainActive then
            pcall(function() if coroutine.status(rgLoop) ~= "dead" then task.cancel(rgLoop) end end)
            return
        end

        local lastRoot     = nil
        local stickCounter = 0

        while DummyDomainActive do
            if isAlive() then
                local aliveDummies = getAliveDummies()

                if #aliveDummies > 0 then
                    local currentTarget = nil

                    if lastTargetStillValid(lastRoot) and stickCounter < STICK_TELEPORTS then
                        currentTarget = { root = lastRoot }
                    else
                        currentTarget = pickNextTarget(aliveDummies, lastRoot)
                        lastRoot = currentTarget and currentTarget.root or nil
                        stickCounter = 0
                    end

                    if currentTarget and currentTarget.root and currentTarget.root.Parent then
                        forceTeleport(currentTarget.root.CFrame * TPALL_OFFSET)
                        stickCounter = stickCounter + 1
                    end
                end
                -- Sem dummies vivos: continua esperando (sem hop, sem parar)
            end

            task.wait(DOMAIN_TP_INTERVAL)
        end

        pcall(function() if coroutine.status(rgLoop) ~= "dead" then task.cancel(rgLoop) end end)
    end)
end

--============================================================
-- 13. UI
--============================================================
WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local Window = WindUI:CreateWindow({
    Title = "0.2 KILL ALL GOJO [Jujutsu Shenanigans]",
    Icon = "door-open",
    Author = "by jane_doesigma",
    Folder = "0.2KillAllGojo",
    Size = UDim2.fromOffset(580, 460),
    MinSize = Vector2.new(560, 350),
    MaxSize = Vector2.new(850, 560),
    Transparent = true,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 200,
    BackgroundImageTransparency = 0.42,
    HideSearchBar = true,
    ScrollBarEnabled = false,
})

if ConfigState.Theme       then pcall(function() WindUI:SetTheme(ConfigState.Theme) end) end
if ConfigState.Transparent then pcall(function() Window:ToggleTransparency(true) end) end
if ConfigState.ToggleKey   then pcall(function() Window:SetToggleKey(Enum.KeyCode[ConfigState.ToggleKey]) end) end

-- Aba principal -------------------------------------------------
local MainTab = Window:Tab({ Title = "Main", Icon = "bird" })

DomainToggleRef = MainTab:Toggle({
    Title = "Kill All 0.2 Domain Expansion [GOJO]",
    Desc  = "Void → G+R → teleporta NO TRONCO de players + Dummies. Hop quando todos players mortos.",
    Icon  = "zap",
    Type  = "Checkbox",
    Value = getCfg("DomainToggle", false),
    Callback = function(state)
        if state then
            if getUltPercent() < 100 then
                setCfg("DomainToggle", false)
                Notify("Domain Expansion", "Pegue Awakening primeiro! (" .. getUltPercent() .. "%)", "alert-triangle")
                task.defer(function() pcall(function() DomainToggleRef:Set(false) end) end)
                return
            end
            setCfg("DomainToggle", true)
            startDomain()
        else
            setCfg("DomainToggle", false)
            stopDomain()
        end
    end,
})

DummyToggleRef = MainTab:Toggle({
    Title = "Test Domain 0.2 Second Dummy",
    Desc  = "R+G → teleporta NO TRONCO de Dummies. Nunca troca de server, só para se desligar.",
    Icon  = "flask-conical",
    Type  = "Checkbox",
    Value = getCfg("DummyDomainToggle", false),
    Callback = function(state)
        if state then
            if getUltPercent() < 100 then
                setCfg("DummyDomainToggle", false)
                Notify("Test Domain Dummy", "Pegue Awakening primeiro! (" .. getUltPercent() .. "%)", "alert-triangle")
                task.defer(function() pcall(function() DummyToggleRef:Set(false) end) end)
                return
            end
            setCfg("DummyDomainToggle", true)
            startDummyDomain()
        else
            setCfg("DummyDomainToggle", false)
            stopDummyDomain()
        end
    end,
})

-- Bypass void -----------------------------------------------
MainTab:Button({
    Title = "Bypass Teleport (Void)",
    Desc  = "Teleporta direto pro void X:-144 Y:-10000 Z:-352.",
    Callback = function()
        task.spawn(function()
            for _ = 1, 25 do
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    pcall(function()
                        hrp.CFrame = VOID_CFRAME
                        hrp.Position = VOID_CFRAME.Position
                        hrp.AssemblyLinearVelocity  = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
                task.wait(0.03)
            end
            Notify("Bypass Teleport", "Teleportado pro void.", "move")
        end)
    end,
})

-- Auto-start --------------------------------------------------
if getCfg("DomainToggle", false) then
    task.defer(function()
        if getUltPercent() >= 100 then
            startDomain()
        else
            setCfg("DomainToggle", false)
            if DomainToggleRef then pcall(function() DomainToggleRef:Set(false) end) end
        end
    end)
end
if getCfg("DummyDomainToggle", false) then
    task.defer(function()
        if getUltPercent() >= 100 then
            startDummyDomain()
        else
            setCfg("DummyDomainToggle", false)
            if DummyToggleRef then pcall(function() DummyToggleRef:Set(false) end) end
        end
    end)
end

-- Aba Config --------------------------------------------------
local ConfigTab = Window:Tab({ Title = "Config", Icon = "settings" })

ConfigTab:Dropdown({
    Title  = "Theme",
    Values = (function()
        local n = {}
        for name in pairs(WindUI:GetThemes()) do table.insert(n, name) end
        table.sort(n)
        return n
    end)(),
    Value = ConfigState.Theme,
    Callback = function(sel) WindUI:SetTheme(sel); setCfg("Theme", sel) end,
})

ConfigTab:Toggle({
    Title = "Transparent",
    Value = getCfg("Transparent", false),
    Callback = function(s) Window:ToggleTransparency(s); setCfg("Transparent", s) end,
})

ConfigTab:Keybind({
    Title = "Toggle UI Key",
    Value = getCfg("ToggleKey", "RightShift"),
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
        setCfg("ToggleKey", v)
    end,
})

ConfigTab:Button({
    Title = "Salvar Configuração",
    Desc  = "Salva todas as preferências.",
    Callback = function()
        saveConfig(ConfigState)
        Notify("Configuração Salva", "Preferências salvas.", "save")
    end,
})

ConfigTab:Button({
    Title = "Resetar Configuração",
    Desc  = "Apaga preferências e restaura padrões.",
    Callback = function()
        if isfile and isfile(CONFIG_FILE) then pcall(function() delfile(CONFIG_FILE) end) end
        ConfigState = {}
        stopDomain()
        stopDummyDomain()
        if DomainToggleRef then pcall(function() DomainToggleRef:Set(false) end) end
        if DummyToggleRef    then pcall(function() DummyToggleRef:Set(false) end) end
        Notify("Configuração Resetada", "Tudo voltou ao padrão.", "refresh-cw")
    end,
})

ConfigTab:Button({
    Title = "Forçar Server Hop",
    Desc  = "Troca pra servidor com 4+ jogadores.",
    Callback = function()
        Notify("Server Hop", "Procurando servidor...", "refresh-cw")
        task.wait(0.5)
        serverHop(MIN_PLAYERS)
    end,
})

-- Flush notificações
for _, n in ipairs(Pending) do Notify(n[1], n[2], n[3]) end
Pending = {}
Notify("0.2 KILL ALL GOJO", "Script carregado. Ative um toggle pra começar.", "check-circle")
