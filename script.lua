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
local function GetTimestamp()
    return DateTime.now():ToIsoDate()
end

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
            footer = { text = "If there are no updates, stock is the same as before" },
            timestamp = GetTimestamp()
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
    for _, item in ipairs(data.items) do
        local count = item.stock
        if count > 0 then
            table.insert(lines, item.id .. " x" .. count)
            table.insert(raritiesFound, item.tier)
            if highestRarity == "Common" and (item.tier ~= "Common") then
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

print("Event Stock Bot Loaded")
