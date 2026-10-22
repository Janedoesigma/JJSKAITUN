--[[
    0.2 KILL ALL GOJO [Jujutsu Shenanigans]
    by jane_doesigma
    UI: WindUI
]]

---------------------------------------------------------------------
-- 1. SERVIÇOS E VARIÁVEIS GLOBAIS
---------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- CFrames e constantes -------------------------------------------------
local ORIGIN_CFRAME = CFrame.new(-76.900146, -41.295113, -213.595673)
local ULT_MAX = 100                     -- valor máximo da barra de Ult (ajuste se necessário)
local ATTACK_INTERVAL = 3               -- segundos entre cada skill (Lapse/Reversal/Twofold)
local TP_TO_ORIGIN_WAIT = 0.6           -- espera antes de voltar ao CFrame original após Rapid Punches
local SAFE_DISTANCE = 50                -- studs de “área segura”
local SAFE_WAIT = 15.5                  -- espera se estiver longe do alvo
local AWAKEN_LOOP_TIME = 9.5            -- duração do loop de teleporte no Awakening
local AWAKEN_TP_INTERVAL = 0.25         -- intervalo entre teleportes no Awakening
local MIN_PLAYERS_TO_STAY = 4           -- mínimo de jogadores para NÃO trocar de servidor

-- RemoteEvents ----------------------------------------------------------
local RapidPunchesRE = ReplicatedStorage:WaitForChild("Knit")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("RapidPunchesService")
    :WaitForChild("RE")
    :WaitForChild("Activated")

local GojoRE = ReplicatedStorage:WaitForChild("Knit")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("GojoService")
    :WaitForChild("RE")
    :WaitForChild("Activated")

local LapseBlueRE = ReplicatedStorage:WaitForChild("Knit")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("LapseBlueService")
    :WaitForChild("RE")
    :WaitForChild("Activated")

local ReversalRedRE = ReplicatedStorage:WaitForChild("Knit")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("ReversalRedService")
    :WaitForChild("RE")
    :WaitForChild("Activated")

local TwofoldKickRE = ReplicatedStorage:WaitForChild("Knit")
    :WaitForChild("Knit")
    :WaitForChild("Services")
    :WaitForChild("TwofoldKickService")
    :WaitForChild("RE")
    :WaitForChild("Activated")

---------------------------------------------------------------------
-- 2. CONFIGURAÇÃO E SALVAMENTO (WindUI ConfigManager)
---------------------------------------------------------------------
-- O WindUI já tem um ConfigManager integrado que usa a pasta do Window.
-- Vamos usar as funções nativas do executor para persistência extra.
local CONFIG_FOLDER = "0.2KillAllGojo"
local CONFIG_FILE = CONFIG_FOLDER .. "/config.json"

local function saveConfig(data)
    if not (writefile and isfolder and makefolder) then return end
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
    writefile(CONFIG_FILE, HttpService:JSONEncode(data))
end

local function loadConfig()
    if not (isfile and readfile) then return {} end
    if isfile(CONFIG_FILE) then
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_FILE))
        end)
        if ok then return decoded end
    end
    return {}
end

---------------------------------------------------------------------
-- 3. UTILITÁRIOS DE ESTADO
---------------------------------------------------------------------
-- Tabela que guarda o estado de cada toggle/slider para salvamento.
local ConfigState = loadConfig()   -- carrega valores salvos (ou tabela vazia)

local function getConfig(key, default)
    return ConfigState[key] ~= nil and ConfigState[key] or default
end

local function setConfig(key, value)
    ConfigState[key] = value
end

-- Controle de loops -----------------------------------------------------
local KillAllActive = false
local AwakenActive = false
local CurrentLoopThreads = {}

local function stopAllLoops()
    KillAllActive = false
    AwakenActive = false
    for _, thread in pairs(CurrentLoopThreads) do
        if coroutine.status(thread) ~= "dead" then
            task.cancel(thread)
        end
    end
    CurrentLoopThreads = {}
end

---------------------------------------------------------------------
-- 4. DETECÇÃO DE ULT (AttributeChanged)
---------------------------------------------------------------------
-- Função que verifica o atributo da Ult e retorna a porcentagem (0-100).
local function getUltPercent()
    -- O nome do atributo pode variar; tente os mais comuns.
    local possibleNames = {
        "Ultimate", "Ult", "Awakening", "AwakeningBar",
        "SixEyes", "UltimateBar", "UltPercent"
    }
    for _, name in ipairs(possibleNames) do
        local v = LocalPlayer:GetAttribute(name)
        if type(v) == "number" then
            return math.clamp(math.floor(v / ULT_MAX * 100), 0, 100)
        end
    end
    return 0
end

-- Monitoramento constante da Ult ---------------------------------------
task.spawn(function()
    while task.wait(0.2) do
        local percent = getUltPercent()
        if percent >= 100 and not AwakenActive then
            -- Ult cheia: para tudo e inicia o loop de Awakening.
            stopAllLoops()
            AwakenActive = true
            local thread = task.spawn(function()
                -- 1) Loop de pressionar G+R
                local awakenLoop = task.spawn(function()
                    while AwakenActive and getUltPercent() >= 100 do
                        -- Simula pressionar G e R (teclas de Awakening + Special)
                        -- Use VirtualInputManager ou keypress do executor.
                        if keypress then
                            keypress(0x47) -- G
                            task.wait(0.05)
                            keypress(0x52) -- R
                        end
                        task.wait(0.2)
                    end
                end)

                -- 2) Loop de teleporte para tronco de jogadores vivos
                local tpLoop = task.spawn(function()
                    while AwakenActive do
                        local targets = {}
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= LocalPlayer and plr.Character then
                                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    table.insert(targets, plr)
                                end
                            end
                        end
                        -- Inclui Dummy/Tester1234 se existir
                        for _, obj in ipairs(workspace:GetChildren()) do
                            if obj.Name == "Tester1234" or obj.Name == "Dummy" then
                                local hum = obj:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    table.insert(targets, obj)
                                end
                            end
                        end

                        for _, target in ipairs(targets) do
                            if not AwakenActive then break end
                            local root = target:IsA("Model") and target:FindFirstChild("HumanoidRootPart")
                                or (target.Character and target.Character:FindFirstChild("HumanoidRootPart"))
                            if root then
                                LocalPlayer.Character.HumanoidRootPart.CFrame =
                                    root.CFrame * CFrame.new(0, 0, -2) -- teleporta para trás
                            end
                            task.wait(AWAKEN_TP_INTERVAL)
                        end
                    end
                end)

                -- 3) Timer de 9.5 segundos
                task.wait(AWAKEN_LOOP_TIME)
                AwakenActive = false
                -- Cancela loops internos
                if coroutine.status(awakenLoop) ~= "dead" then task.cancel(awakenLoop) end
                if coroutine.status(tpLoop) ~= "dead" then task.cancel(tpLoop) end

                -- 4) Troca de servidor se necessário
                local playerCount = #Players:GetPlayers()
                if playerCount < MIN_PLAYERS_TO_STAY then
                    -- Procura um servidor com pelo menos MIN_PLAYERS_TO_STAY jogadores
                    local ok, servers = pcall(function()
                        return HttpService:JSONDecode(game:HttpGet(
                            "https://games.roblox.com/v1/games/" .. game.PlaceId ..
                            "/servers/Public?limit=100"
                        ))
                    end)
                    if ok and servers and servers.data then
                        for _, srv in ipairs(servers.data) do
                            if srv.playing >= MIN_PLAYERS_TO_STAY then
                                TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, LocalPlayer)
                                break
                            end
                        end
                    else
                        -- Fallback: teleporte aleatório
                        TeleportService:Teleport(game.PlaceId, LocalPlayer)
                    end
                end
            end)
            table.insert(CurrentLoopThreads, thread)
        end
    end
end)

---------------------------------------------------------------------
-- 5. LOOP PRINCIPAL DE KILL ALL
---------------------------------------------------------------------
-- Função que executa o ciclo completo (chamada quando o toggle está ON).
local function startKillAllLoop()
    KillAllActive = true
    local thread = task.spawn(function()
        while KillAllActive do
            -- 1) Teleporta para o CFrame original
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                LocalPlayer.Character.HumanoidRootPart.CFrame = ORIGIN_CFRAME
            end
            task.wait(0.1)

            -- 2) Verifica se o jogador “voltou” (posição mudou).
            local startPos = LocalPlayer.Character.HumanoidRootPart.Position
            task.wait(1) -- janela para o jogador se mover
            local newPos = LocalPlayer.Character.HumanoidRootPart.Position
            local moved = (newPos - startPos).Magnitude > 5

            if moved then
                -- Jogador voltou: executa 3 teleportes rápidos + kill.
                for i = 1, 3 do
                    if not KillAllActive then break end
                    LocalPlayer.Character.HumanoidRootPart.CFrame = ORIGIN_CFRAME
                    task.wait(0.2)
                end
                -- Após os 3 teleportes, espera 5 minutos (contador) antes de atacar?
                -- Sua lógica: “se ele vê que voltou... contador de 5 minutos”.
                -- Vamos implementar como um wait de 300 s, mas com checagem de toggle.
                local timer = 0
                while timer < 300 and KillAllActive do
                    task.wait(1)
                    timer = timer + 1
                end
                if not KillAllActive then break end
            end

            -- 3) Encontra o alvo (Dummy / Tester1234) e teleporta para trás.
            local targetModel
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj.Name == "Dummy" or obj.Name == "Tester1234" then
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        targetModel = obj
                        break
                    end
                end
            end

            if targetModel then
                local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
                if targetRoot and LocalPlayer.Character then
                    -- Teleporta para trás do alvo.
                    LocalPlayer.Character.HumanoidRootPart.CFrame =
                        targetRoot.CFrame * CFrame.new(0, 0, -2)
                    -- Faz o alvo olhar para o jogador (opcional).
                    targetRoot.CFrame = CFrame.lookAt(targetRoot.Position, LocalPlayer.Character.HumanoidRootPart.Position)

                    -- Executa Rapid Punches.
                    RapidPunchesRE:FireServer(
                        LocalPlayer.Character.Moveset["Rapid Punches"],
                        nil
                    )

                    -- Espera 0.6 s e volta ao CFrame original.
                    task.wait(TP_TO_ORIGIN_WAIT)
                    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                        LocalPlayer.Character.HumanoidRootPart.CFrame = ORIGIN_CFRAME
                    end

                    -- Verifica distância segura.
                    local dist = (LocalPlayer.Character.HumanoidRootPart.Position - targetRoot.Position).Magnitude
                    if dist > SAFE_DISTANCE then
                        -- Longe: espera 15.5 s antes de tentar novamente.
                        task.wait(SAFE_WAIT)
                    else
                        -- Perto: mantém voo atrás das costas e dispara Gojo.
                        while KillAllActive and targetModel and targetModel.Parent do
                            local newTargetRoot = targetModel:FindFirstChild("HumanoidRootPart")
                            if not newTargetRoot then break end
                            LocalPlayer.Character.HumanoidRootPart.CFrame =
                                newTargetRoot.CFrame * CFrame.new(0, 0, -2)
                            -- Dispara GojoService (evento principal).
                            GojoRE:FireServer(false, nil)
                            -- Executa skills a cada 3 s.
                            task.wait(ATTACK_INTERVAL)
                            if not KillAllActive then break end
                            LapseBlueRE:FireServer(LocalPlayer.Character.Moveset["Lapse Blue"], nil)
                            task.wait(ATTACK_INTERVAL)
                            if not KillAllActive then break end
                            ReversalRedRE:FireServer(LocalPlayer.Character.Moveset["Reversal Red"], nil)
                            task.wait(ATTACK_INTERVAL)
                            if not KillAllActive then break end
                            TwofoldKickRE:FireServer(LocalPlayer.Character.Moveset["Twofold Kick"], nil)
                            task.wait(ATTACK_INTERVAL)
                        end
                    end
                end
            end

            task.wait(0.5) -- pequeno respiro entre ciclos
        end
    end)
    table.insert(CurrentLoopThreads, thread)
end

---------------------------------------------------------------------
-- 6. CRIAÇÃO DA UI (WindUI)
---------------------------------------------------------------------
local WindUI = loadstring(game:HttpGet(
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

-- Aba principal ---------------------------------------------------------
local MainTab = Window:Tab({
    Title = "Main",
    Icon = "bird",
})

-- Toggle principal ------------------------------------------------------
local KillAllToggle = MainTab:Toggle({
    Title = "0.2 KILL ALL GOJO [BETA]",
    Desc = "Ativa o loop completo de kill all.",
    Icon = "sword",
    Type = "Checkbox",
    Value = getConfig("KillAllToggle", false),
    Callback = function(state)
        setConfig("KillAllToggle", state)
        if state then
            startKillAllLoop()
        else
            stopAllLoops()
        end
    end,
})

-- Se o toggle já estava ativo na configuração salva, inicia automaticamente.
if getConfig("KillAllToggle", false) then
    KillAllToggle:Set(true)
    startKillAllLoop()
end

-- Aba de configurações (tema, transparência, keybind) -------------------
local ConfigTab = Window:Tab({
    Title = "Config",
    Icon = "settings",
})

ConfigTab:Dropdown({
    Title = "Theme",
    Values = (function()
        local names = {}
        for name in pairs(WindUI:GetThemes()) do
            table.insert(names, name)
        end
        table.sort(names)
        return names
    end)(),
    Callback = function(selected)
        WindUI:SetTheme(selected)
        setConfig("Theme", selected)
    end,
})

ConfigTab:Toggle({
    Title = "Transparent",
    Value = getConfig("Transparent", false),
    Callback = function(state)
        Window:ToggleTransparency(state)
        setConfig("Transparent", state)
    end,
})

ConfigTab:Keybind({
    Title = "Toggle UI Key",
    Value = getConfig("ToggleKey", "RightShift"),
    Callback = function(v)
        Window:SetToggleKey(Enum.KeyCode[v])
        setConfig("ToggleKey", v)
    end,
})

-- Botões de salvar e resetar --------------------------------------------
ConfigTab:Button({
    Title = "Salvar Configuração",
    Desc = "Salva o estado atual dos toggles e opções.",
    Callback = function()
        saveConfig(ConfigState)
        WindUI:Notify({
            Title = "Configuração Salva",
            Content = "As preferências foram salvas.",
            Duration = 3,
            Icon = "save",
        })
    end,
})

ConfigTab:Button({
    Title = "Resetar Configuração",
    Desc = "Apaga todas as preferências salvas.",
    Callback = function()
        if isfile and isfile(CONFIG_FILE) then
            delfile(CONFIG_FILE)
        end
        ConfigState = {}
        -- Reseta os elementos da UI para os padrões.
        KillAllToggle:Set(false)
        stopAllLoops()
        WindUI:Notify({
            Title = "Configuração Resetada",
            Content = "As preferências foram restauradas ao padrão.",
            Duration = 3,
            Icon = "refresh-cw",
        })
    end,
})

---------------------------------------------------------------------
-- 7. NOTIFICAÇÃO INICIAL E TRATAMENTO DE ERROS
---------------------------------------------------------------------
WindUI:Notify({
    Title = "0.2 KILL ALL GOJO",
    Content = "Script carregado. Ative o toggle para começar.",
    Duration = 4,
    Icon = "check-circle",
})

-- Wrapper para capturar erros nos loops e notificar.
local function safeLoop(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            WindUI:Notify({
                Title = "Erro no script",
                Content = tostring(err),
                Duration = 5,
                Icon = "alert-triangle",
            })
        end
    end
end

-- Substitui as chamadas de loop por versões protegidas (opcional, mas recomendado).
-- (Você pode envolver startKillAllLoop e o loop de Awakening com safeLoop se desejar.)
