--[[ 
    @author asph (Centrizo)
    @description event box stock bot (using EventStock RemoteFunction)
]]  

--// Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

--// Config
local Config = {
    Enabled = true,
    AntiAFKEnabled = true,
    RolePingEnabled = true,
    KillSwitchEnabled = true,
    Webhook = "https://discord.com/api/webhooks/...", -- replace with your actual webhook URL
    Colors = {
        Common = 0x5AC73C,
        Rare = 0x3158A8,
        Epic = 0xbf1ec8,
        Legendary = 0xd09c17,
    },
    RolePings = {
        Epic = "1234567890",  -- replace with actual role IDs
        Legendary = "0987654321" -- replace with actual role IDs
    }
}

--// Utility
local function SendWebhook(Title, Content, Color, rarities)
    if not Config.Enabled then return end

    local mentions, allowedRoles = {}, {}
    if Config.RolePingEnabled and rarities then
        for _, rarity in ipairs(rarities) do
            local roleId = Config.RolePings[rarity]
            if roleId then
                table.insert(mentions, "<@&" .. roleId .. ">")
                table.insert(allowedRoles, roleId)
            end
        end
    end

    local Body = {
        content = table.concat(mentions, " "),
        embeds = {{
            title = Title,
            description = Content,
            color = Color,
            footer = {
                text = "brought to you by arle.",
                icon_url = "https://i.imgur.com/JdlwG9w.jpeg"
            },
        }}
    }

    if #allowedRoles > 0 then
        Body.allowed_mentions = { roles = allowedRoles }
    end

    local RequestData = {
        Url = Config.Webhook,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(Body)
    }

    task.spawn(request, RequestData)
end

--// Main stock watcher
local EventStock = ReplicatedStorage:WaitForChild("NetworkContainer")
    :WaitForChild("RemoteFunctions")
    :WaitForChild("EventStock")

local rarityOrder = {"Legendary","Epic","Rare","Common"}
local rarityLabels = {Common="Common Box", Rare="Rare Box", Epic="Epic Box", Legendary="Legendary Box"}

local prevStockKey = nil
local debounce = false

local function CheckStock()
    local success, data = pcall(function()
        return EventStock:InvokeServer()
    end)
    if not success or not data then return end

    local lines, raritiesFound, highestRarity = {}, {}, "Common"
    local rarityPriority = {Common=1, Rare=2, Epic=3, Legendary=4}

    for _, item in ipairs(data.items) do
        local count = item.stock
        if count > 0 then
            table.insert(lines, item.id .. " x" .. count)
            table.insert(raritiesFound, item.tier)

            if rarityPriority[item.tier] > rarityPriority[highestRarity] then
                highestRarity = item.tier
            end
        end
    end

    local stockKey = table.concat(lines, ",")  -- simple way to compare
    if stockKey ~= prevStockKey and not debounce then
        prevStockKey = stockKey
        debounce = true
        SendWebhook("EVENT BOX STOCK", table.concat(lines, "\n"), Config.Colors[highestRarity], raritiesFound)
        -- reset debounce after a short delay
        task.delay(2, function() debounce = false end)
    end
end

--// Loop to check stock every second
task.spawn(function()
    while true do
        CheckStock()
        task.wait(1)
    end
end)

--// Anti-AFK
LocalPlayer.Idled:Connect(function()
    if not Config.AntiAFKEnabled then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0,0))
end)

--// Setup Kill / Kick Webhook
local function SetupKillSwitch()
    if not Config.KillSwitchEnabled then return end

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local function SendKickWebhook(reason)
        SendWebhook(
            "DISCONNECTED",
            "Reason: " .. tostring(reason),
            0xFF0000,
            {}
        )
    end

    -- Trigger if local player is removed (kicked, ban, server shutdown)
    Players.PlayerRemoving:Connect(function(player)
        if player == LocalPlayer then
            SendKickWebhook("Bot removed (kicked or server shutdown)")
        end
    end)

    -- Watch for other players joining, and leave if someone joins
    Players.PlayerAdded:Connect(function(plr)
        if plr ~= LocalPlayer then
            local timestamp = DateTime.now():ToIsoDate()
            SendKickWebhook(
                "Another player joined: " .. plr.Name .. "\nTime: " .. timestamp)
            -- Kick yourself safely to leave
            LocalPlayer:Kick("Another player joined: " .. plr.Name)
        end
    end)
end

SetupKillSwitch()

print("Event Stock Bot Loaded")
