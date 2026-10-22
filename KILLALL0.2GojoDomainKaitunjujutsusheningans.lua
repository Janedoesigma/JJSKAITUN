--[[
    0.2 KILL ALL GOJO [Jujutsu Shenanigans] — v3
    by jane_doesigma — UI: WindUI
]]

--============================================================
-- 1. SERVIÇOS
--============================================================
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

--============================================================
-- 2. CONSTANTES
--============================================================
local ORIGIN_CFRAME      = CFrame.new(-76.900146, -41.295113, -213.595673)
local VOID_CFRAME        = CFrame.new(-144, -1500, -352)

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
local COUNTER_TIME       = 300
local REVERT_THRESHOLD   = 10

-- Teleport All
local TPALL_INTERVAL     = 0.6
local TPALL_OFFSET       = CFrame.new(0, 0, -2)

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
local KillAllActive     = false
local AwakenActive      = false
local TeleportAllActive = false
local Loops             = {}

local function stopAllLoops()
    KillAllActive     = false
    AwakenActive      = false
    TeleportAllActive = false
    for i = #Loops, 1, -1 do
        local t = Loops[i]
        pcall(function()
            if coroutine.status(t) ~= "dead" then task.cancel(t) end
        end)
        table.remove(Loops, i)
    end
end

local function stopKillAllOnly()
    KillAllActive = false
end

local function track(t) table.insert(Loops, t); return t end

--============================================================
-- 6. NOTIFICAÇÃO
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
-- 7. ULT
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
-- 8. HELPERS DE PERSONAGEM (corrigidos)
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

-- Mata APENAS via Health = 0 (evita ragdoll quebrado do BreakJoints)
local function killCharacter()
    local h = getHum()
    if h and h.Health > 0 then
        pcall(function() h.Health = 0 end)
    end
end

-- Espera pela morte + respawn completo (robusto)
local function waitForRespawn(timeout)
    timeout = timeout or 15
    -- 1) espera a morte registrar
    local t0 = tick()
    while tick() - t0 < 4 do
        if not isAlive() then break end
        task.wait(0.1)
    end
    -- 2) espera o respawn
    t0 = tick()
    while tick() - t0 < timeout do
        if isAlive() and getRoot() then
            task.wait(0.6) -- deixa o personagem "assentar"
            return true
        end
        task.wait(0.2)
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
-- 11. TECLAS
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
                for _, t in ipairs(getAliveTargets()) do
                    if not AwakenActive then break end
                    local root = getRoot()
                    if root and t.root and t.root.Parent then
                        pcall(function()
                            root.CFrame = t.root.CFrame * TPALL_OFFSET
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

        if #Players:GetPlayers() < MIN_PLAYERS then
            Notify("Server Hop", "Procurando servidor com " .. MIN_PLAYERS .. "+ jogadores...", "refresh-cw")
            task.wait(1)
            serverHop(MIN_PLAYERS)
        end
    end))
end

-- Monitor independente da Ult
task.spawn(function()
    while task.wait(0.2) do
        local p = getUltPercent()
        if p >= 100
            and not AwakenActive
            and (tick() - lastAwakenTime) > AWAKEN_COOLDOWN then
            stopKillAllOnly()
            Notify("Ult 100%", "Iniciando Awakening automático...", "zap")
            startAwakening()
        end
    end
end)

--============================================================
-- 13. KILL ALL (corrigido: teleporta 1x, mata 1x)
--============================================================
local function startKillAll()
    if KillAllActive then return end
    KillAllActive = true

    track(task.spawn(function()
        while KillAllActive do
            -- Se estiver morto, aguarda respawn ANTES de qualquer coisa
            if not isAlive() then
                waitForRespawn(15)
                task.wait(0.3)
                continue
            end

            local root = getRoot()
            if not root then task.wait(1); continue end
            local oldPos = root.Position

            -- Teleporta pro CFrame original (UMA VEZ)
            pcall(function() root.CFrame = ORIGIN_CFRAME end)
            task.wait(TP_INTERVAL)

            -- Checa se "voltou"
            local r2 = getRoot()
            if not r2 then task.wait(1); continue end
            local reverted = isNear(r2.Position, oldPos, REVERT_THRESHOLD)

            if reverted then
                -- ─── Volta ao lugar: teleporta 1x + mata 1x + espera respawn ───
                Notify("Kill All", "Boneco voltou — resetando...", "skull")

                local r = getRoot()
                if r then pcall(function() r.CFrame = ORIGIN_CFRAME end) end
                task.wait(TP_INTERVAL)

                killCharacter()
                waitForRespawn(20)   -- espera morte + respawn completo

                -- Se ainda estiver morto após 20s, dá mais um tempo
                if not isAlive() then
                    task.wait(3)
                end
                task.wait(0.5)
            else
                -- ─── Não voltou: contador de 5 minutos ───
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

                -- ─── Ataque ao Dummy ───
                if KillAllActive then
                    local dummy = findDummy()
                    if dummy then
                        local tr = dummy:FindFirstChild("HumanoidRootPart")
                        local r = getRoot()
                        if tr and r then
                            pcall(function()
                                r.CFrame = tr.CFrame * TPALL_OFFSET
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
                                        local nr  = getRoot()
                                        local ntr = dummy:FindFirstChild("HumanoidRootPart")
                                        if not nr or not ntr then break end
                                        pcall(function() nr.CFrame = ntr.CFrame * TPALL_OFFSET end)
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
-- 14. TELEPORT ALL 0.2 (novo)
--============================================================
local function startTeleportAll()
    if TeleportAllActive then return end
    TeleportAllActive = true

    track(task.spawn(function()
        local lastRoot = nil
        while TeleportAllActive do
            local targets = getAliveTargets()
            if #targets > 0 then
                -- Filtra pra NÃO repetir o último alvo (a não ser que só exista ele)
                local candidates = {}
                for _, t in ipairs(targets) do
                    if t.root ~= lastRoot then
                        table.insert(candidates, t)
                    end
                end
                local pool = (#candidates > 0) and candidates or targets
                local target = pool[math.random(1, #pool)]

                local root = getRoot()
                if root and target and target.root and target.root.Parent then
                    pcall(function()
                        root.CFrame = target.root.CFrame * TPALL_OFFSET
                    end)
                    lastRoot = target.root
                end
            end
            task.wait(TPALL_INTERVAL)
        end
    end))
end

--============================================================
-- 15. UI
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

if ConfigState.Theme then pcall(function() WindUI:SetTheme(ConfigState.Theme) end) end
if ConfigState.Transparent then pcall(function() Window:ToggleTransparency(true) end) end
if ConfigState.ToggleKey then pcall(function() Window:SetToggleKey(Enum.KeyCode[ConfigState.ToggleKey]) end) end

-- Aba principal -------------------------------------------------
local MainTab = Window:Tab({ Title = "Main", Icon = "bird" })

MainTab:Toggle({
    Title = "0.2 KILL ALL GOJO [BETA]",
    Desc = "Loop completo de Kill All + Awakening.",
    Icon = "sword",
    Type = "Checkbox",
    Value = getCfg("KillAllToggle", false),
    Callback = function(state)
        setCfg("KillAllToggle", state)
        if state then startKillAll() else stopKillAllOnly() end
    end,
})

MainTab:Toggle({
    Title = "Teleport All 0.2",
    Desc = "Teleporta atrás de um alvo aleatório (inclui Dummy) a cada 0.6s.",
    Icon = "move",
    Type = "Checkbox",
    Value = getCfg("TeleportAllToggle", false),
    Callback = function(state)
        setCfg("TeleportAllToggle", state)
        if state then startTeleportAll() else TeleportAllActive = false end
    end,
})

-- Botões rápidos ------------------------------------------------
MainTab:Button({
    Title = "Bypass Teleport (Void)",
    Desc = "Teleporta para X:-144 Y:-1500 Z:-352.",
    Callback = function()
        local r = getRoot()
        if r then
            pcall(function() r.CFrame = VOID_CFRAME end)
            Notify("Bypass Teleport", "Teleportado para o void.", "move")
        end
    end,
})

MainTab:Button({
    Title = "Teleport Test",
    Desc = "Teleporta para o CFrame original salvo.",
    Callback = function()
        local r = getRoot()
        if r then
            pcall(function() r.CFrame = ORIGIN_CFRAME end)
            Notify("Teleport Test", "Teleportado para o CFrame original.", "crosshair")
        end
    end,
})

-- Auto-start se estava ativo
if getCfg("KillAllToggle", false) then task.defer(startKillAll) end
if getCfg("TeleportAllToggle", false) then task.defer(startTeleportAll) end

-- Aba Status ----------------------------------------------------
local StatusTab = Window:Tab({ Title = "Status", Icon = "activity" })
local StatusPara = StatusTab:Paragraph({
    Title = "Estado Atual",
    Desc  = "Carregando...",
    Image = "",
})
task.spawn(function()
    while task.wait(0.5) do
        local txt = string.format(
            "Ult: %d%%   |   Vivo: %s   |   KillAll: %s   |   TPAll: %s   |   Awakening: %s\n" ..
            "Jogadores: %d   |   Dummy: %s",
            getUltPercent(), tostring(isAlive()),
            tostring(KillAllActive), tostring(TeleportAllActive),
            tostring(AwakenActive),
            #Players:GetPlayers(),
            findDummy() and "Sim" or "Não"
        )
        pcall(function() StatusPara:SetDesc(txt) end)
    end
end)

-- Aba Config ----------------------------------------------------
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

-- Flush notificações
for _, n in ipairs(Pending) do Notify(n[1], n[2], n[3]) end
Pending = {}
Notify("0.2 KILL ALL GOJO", "Script carregado. Ative um toggle para começar.", "check-circle")
