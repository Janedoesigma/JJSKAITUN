--[[
    0.2 KILL ALL GOJO [Jujutsu Shenanigans]
    by jane_doesigma — UI: WindUI
]]

--============================================================
-- 1. SERVIÇOS
--============================================================
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local VirtualInputManager= game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

--============================================================
-- 2. CONSTANTES
--============================================================
local ORIGIN_CFRAME      = CFrame.new(-76.900146, -41.295113, -213.595673)
local ULT_MAX            = 100
local TP_TO_ORIGIN_WAIT  = 0.6
local SAFE_DISTANCE      = 50
local SAFE_WAIT          = 15.5
local ATTACK_INTERVAL    = 3
local AWAKEN_LOOP_TIME   = 9.5
local AWAKEN_TP_INTERVAL = 0.25
local AWAKEN_COOLDOWN    = 30
local MIN_PLAYERS        = 4

-- Kill All
local TP_INTERVAL        = 0.5
local KILL_REPEAT        = 3
local RESPAWN_WAIT       = 2
local COUNTER_TIME       = 300
local REVERT_THRESHOLD   = 10

--============================================================
-- 3. REMOTE EVENTS
--============================================================
local function getRE(svc, ev)
    return ReplicatedStorage:WaitForChild("Knit")
        :WaitForChild("Knit")
        :WaitForChild("Services")
        :WaitForChild(svc)
        :WaitForChild("RE")
        :WaitForChild(ev)
end

local RapidPunchesRE = getRE("RapidPunchesService", "Activated")
local GojoRE         = getRE("GojoService", "Activated")
local LapseBlueRE    = getRE("LapseBlueService", "Activated")
local ReversalRedRE  = getRE("ReversalRedService", "Activated")
local TwofoldKickRE  = getRE("TwofoldKickService", "Activated")

--============================================================
-- 4. CONFIG PERSISTENTE
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
-- 5. ESTADO DOS LOOPS
--============================================================
local KillAllActive = false
local AwakenActive  = false
local Loops         = {}

local function stopAllLoops()
    KillAllActive = false
    AwakenActive  = false
    for i = #Loops, 1, -1 do
        local t = Loops[i]
        pcall(function()
            if coroutine.status(t) ~= "dead" then task.cancel(t) end
        end)
        table.remove(Loops, i)
    end
end

local function track(t)
    table.insert(Loops, t)
    return t
end

--============================================================
-- 6. NOTIFICAÇÃO PENDENTE
--============================================================
local WindUI = nil
local Pending = {}

local function Notify(title, content, icon)
    if WindUI then
        WindUI:Notify({ Title = title, Content = content, Duration = 4, Icon = icon or "info" })
    else
        table.insert(Pending, { title, content, icon })
    end
end

--============================================================
-- 7. DETECÇÃO DE ULT
--============================================================
local ULT_ATTRS = {
    "Ultimate","Ult","Awakening","AwakeningBar",
    "SixEyes","UltimateBar","UltPercent","Domain"
}

local function getUltPercent()
    for _, name in ipairs(ULT_ATTRS) do
        local v = LocalPlayer:GetAttribute(name)
        if type(v) == "number" then
            return math.clamp(math.floor(v / ULT_MAX * 100), 0, 100)
        end
    end
    return 0
end

--============================================================
-- 8. HELPERS DE PERSONAGEM
--============================================================
local function getRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function isAlive()
    local h = getHum()
    return h and h.Health > 0
end
local function killCharacter()
    local h = getHum()
    if h and h.Health > 0 then
        pcall(function() h.Health = 0 end)
        local c = LocalPlayer.Character
        if c and c.BreakJoints then pcall(function() c:BreakJoints() end) end
    end
end
local function waitForRespawn(timeout)
    timeout = timeout or 10
    local t0 = tick()
    while tick() - t0 < timeout do
        if isAlive() and getRoot() then return true end
        task.wait(0.25)
    end
    return false
end
local function isNear(pos, target, thr)
    return (pos - target).Magnitude <= (thr or REVERT_THRESHOLD)
end

--============================================================
-- 9. ALVOS
--============================================================
local function findDummy()
    for _, o in ipairs(workspace:GetChildren()) do
        if o.Name == "Dummy" or o.Name == "Tester1234" then
            local h = o:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then return o end
        end
    end
end

local function getAliveTargets()
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
    for _, o in ipairs(workspace:GetChildren()) do
        if o.Name == "Dummy" or o.Name == "Tester1234" then
            local h = o:FindFirstChildOfClass("Humanoid")
            local r = o:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and r then
                table.insert(list, { root = r })
            end
        end
    end
    return list
end

--============================================================
-- 10. SERVER HOP
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
-- 11. PRESSIONAR TECLA
--============================================================
local function pressKey(kc)
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, kc, false, game)
        task.wait(0.03)
        VirtualInputManager:SendKeyEvent(false, kc, false, game)
    end)
end

--============================================================
-- 12. AWAKENING
--============================================================
local lastAwakenTime = 0

local function startAwakening()
    if AwakenActive then return end
    AwakenActive = true
    lastAwakenTime = tick()

    track(task.spawn(function()
        local gLoop = task.spawn(function()
            while AwakenActive and getUltPercent() >= 100 do
                pressKey(Enum.KeyCode.G)
                task.wait(0.05)
                pressKey(Enum.KeyCode.R)
                task.wait(0.2)
            end
        end)
        local tpLoop = task.spawn(function()
            while AwakenActive do
                local targets = getAliveTargets()
                for _, t in ipairs(targets) do
                    if not AwakenActive then break end
                    local root = getRoot()
                    if root and t.root and t.root.Parent then
                        pcall(function()
                            root.CFrame = t.root.CFrame * CFrame.new(0, 0, -2)
                        end)
                    end
                    task.wait(AWAKEN_TP_INTERVAL)
                end
                task.wait(0.05)
            end
        end)

        task.wait(AWAKEN_LOOP_TIME)
        AwakenActive = false

        pcall(function() if coroutine.status(gLoop) ~= "dead" then task.cancel(gLoop) end end)
        pcall(function() if coroutine.status(tpLoop) ~= "dead" then task.cancel(tpLoop) end end)

        local count = #Players:GetPlayers()
        if count < MIN_PLAYERS then
            Notify("Server Hop", "Procurando servidor com " .. MIN_PLAYERS .. "+ jogadores...", "refresh-cw")
            task.wait(1)
            serverHop(MIN_PLAYERS)
        end
    end))
end

-- Monitor independente da Ult (não é cancelado por stopAllLoops)
task.spawn(function()
    while task.wait(0.2) do
        local p = getUltPercent()
        if p >= 100
            and not AwakenActive
            and (tick() - lastAwakenTime) > AWAKEN_COOLDOWN then
            -- Cancelar loops de KillAll (sem parar o monitor)
            KillAllActive = false
            for i = #Loops, 1, -1 do
                local t = Loops[i]
                pcall(function()
                    if coroutine.status(t) ~= "dead" then task.cancel(t) end
                end)
                table.remove(Loops, i)
            end
            Notify("Ult 100%", "Iniciando Awakening automático...", "zap")
            startAwakening()
        end
    end
end)

--============================================================
-- 13. KILL ALL LOOP
--============================================================
local function startKillAll()
    if KillAllActive then return end
    KillAllActive = true

    track(task.spawn(function()
        while KillAllActive do
            if not isAlive() then
                waitForRespawn(15)
                task.wait(0.5)
                continue
            end

            local root = getRoot()
            if not root then task.wait(1); continue end
            local oldPos = root.Position

            -- Teleporta pro CFrame original
            pcall(function() root.CFrame = ORIGIN_CFRAME end)
            task.wait(TP_INTERVAL)

            local r2 = getRoot()
            if not r2 then task.wait(1); continue end
            local reverted = isNear(r2.Position, oldPos, REVERT_THRESHOLD)

            if reverted then
                Notify("Kill All", "Boneco voltou — resetando...", "skull")
                for i = 1, KILL_REPEAT do
                    if not KillAllActive then break end
                    local r = getRoot()
                    if r then pcall(function() r.CFrame = ORIGIN_CFRAME end) end
                    task.wait(TP_INTERVAL)
                    killCharacter()
                    task.wait(RESPAWN_WAIT)
                    if not waitForRespawn(10) then task.wait(2) end
                end
            else
                -- Contador de 5 minutos
                local elapsed, interrupted = 0, false
                while elapsed < COUNTER_TIME and KillAllActive do
                    task.wait(1)
                    elapsed = elapsed + 1
                    local r = getRoot()
                    if not r or not isAlive() then interrupted = true; break end
                    if not isNear(r.Position, ORIGIN_CFRAME.Position, 15) then
                        interrupted = true; break
                    end
                end
                if interrupted then
                    Notify("Kill All", "Saiu do CFrame — reiniciando", "alert-triangle")
                    task.wait(0.5); continue
                end

                -- Ataque ao Dummy
                if KillAllActive then
                    local dummy = findDummy()
                    if dummy then
                        local tr = dummy:FindFirstChild("HumanoidRootPart")
                        local r = getRoot()
                        if tr and r then
                            pcall(function()
                                r.CFrame = tr.CFrame * CFrame.new(0, 0, -2)
                                tr.CFrame = CFrame.lookAt(tr.Position, r.Position)
                            end)
                            pcall(function()
                                RapidPunchesRE:FireServer(
                                    LocalPlayer.Character.Moveset["Rapid Punches"], nil)
                            end)
                            task.wait(TP_TO_ORIGIN_WAIT)
                            local r2b = getRoot()
                            if r2b then pcall(function() r2b.CFrame = ORIGIN_CFRAME end) end
                            task.wait(0.2)
                            local r3 = getRoot()
                            local tr2 = dummy:FindFirstChild("HumanoidRootPart")
                            if r3 and tr2 then
                                local dist = (r3.Position - tr2.Position).Magnitude
                                if dist > SAFE_DISTANCE then
                                    task.wait(SAFE_WAIT)
                                else
                                    while KillAllActive and dummy and dummy.Parent and isAlive() do
                                        local nr = getRoot()
                                        local ntr = dummy:FindFirstChild("HumanoidRootPart")
                                        if not nr or not ntr then break end
                                        pcall(function() nr.CFrame = ntr.CFrame * CFrame.new(0,0,-2) end)
                                        pcall(function() GojoRE:FireServer(false, nil) end)
                                        task.wait(ATTACK_INTERVAL)
                                        if not KillAllActive then break end
                                        pcall(function()
                                            LapseBlueRE:FireServer(
                                                LocalPlayer.Character.Moveset["Lapse Blue"], nil)
                                        end)
                                        task.wait(ATTACK_INTERVAL)
                                        if not KillAllActive then break end
                                        pcall(function()
                                            ReversalRedRE:FireServer(
                                                LocalPlayer.Character.Moveset["Reversal Red"], nil)
                                        end)
                                        task.wait(ATTACK_INTERVAL)
                                        if not KillAllActive then break end
                                        pcall(function()
                                            TwofoldKickRE:FireServer(
                                                LocalPlayer.Character.Moveset["Twofold Kick"], nil)
                                        end)
                                        task.wait(ATTACK_INTERVAL)
                                    end
                                end
                            end
                        end
                    else
                        Notify("Kill All", "Nenhum Dummy encontrado", "alert-circle")
                        task.wait(2)
                    end
                end
            end
            task.wait(0.5)
        end
    end))
end

--============================================================
-- 14. CRIAÇÃO DA UI
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

if ConfigState.Theme then
    pcall(function() WindUI:SetTheme(ConfigState.Theme) end)
end
if ConfigState.Transparent then
    pcall(function() Window:ToggleTransparency(true) end)
end
if ConfigState.ToggleKey then
    pcall(function() Window:SetToggleKey(Enum.KeyCode[ConfigState.ToggleKey]) end)
end

local MainTab = Window:Tab({ Title = "Main", Icon = "bird" })

local KillAllToggle = MainTab:Toggle({
    Title = "0.2 KILL ALL GOJO [BETA]",
    Desc = "Ativa o loop completo de Kill All + Awakening.",
    Icon = "sword",
    Type = "Checkbox",
    Value = getCfg("KillAllToggle", false),
    Callback = function(state)
        setCfg("KillAllToggle", state)
        if state then startKillAll() else stopAllLoops() end
    end,
})

if getCfg("KillAllToggle", false) then
    task.defer(function() KillAllToggle:Set(true); startKillAll() end)
end

-- Aba de status ao vivo -----------------------------------------
local StatusTab = Window:Tab({ Title = "Status", Icon = "activity" })
local StatusPara = StatusTab:Paragraph({
    Title = "Estado Atual",
    Desc  = "Carregando...",
    Image = "",
})
task.spawn(function()
    while task.wait(0.5) do
        local txt = string.format(
            "Ult: %d%%   |   Vivo: %s   |   KillAll: %s   |   Awakening: %s\nJogadores: %d   |   Dummy: %s",
            getUltPercent(),
            tostring(isAlive()),
            tostring(KillAllActive),
            tostring(AwakenActive),
            #Players:GetPlayers(),
            findDummy() and "Sim" or "Não"
        )
        pcall(function() StatusPara:SetDesc(txt) end)
    end
end)

-- Aba Config -----------------------------------------------------
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
    Desc  = "Salva todas as preferências atuais.",
    Callback = function()
        saveConfig(ConfigState)
        Notify("Configuração Salva", "Suas preferências foram salvas.", "save")
    end,
})

ConfigTab:Button({
    Title = "Resetar Configuração",
    Desc  = "Apaga preferências e restaura padrões.",
    Callback = function()
        if isfile and isfile(CONFIG_FILE) then
            pcall(function() delfile(CONFIG_FILE) end)
        end
        ConfigState = {}
        pcall(function() KillAllToggle:Set(false) end)
        stopAllLoops()
        Notify("Configuração Resetada", "Tudo voltou ao padrão.", "refresh-cw")
    end,
})

ConfigTab:Button({
    Title = "Forçar Server Hop",
    Desc  = "Troca para servidor com 4+ jogadores.",
    Callback = function()
        Notify("Server Hop", "Procurando servidor...", "refresh-cw")
        task.wait(0.5)
        serverHop(MIN_PLAYERS)
    end,
})

-- Flush das notificações pendentes
for _, n in ipairs(Pending) do Notify(n[1], n[2], n[3]) end
Pending = {}
Notify("0.2 KILL ALL GOJO", "Script carregado. Ative o toggle para começar.", "check-circle")
