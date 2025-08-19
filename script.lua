--[[ 
    @author asph (Centrizo)
    @description event box stock bot
]]

--// Services
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

--// Config
local Config = {
    Enabled = true,
	AntiAFKEnabled = true,
    RolePingEnabled = true, -- if you want to ping a role in the webhook
    Webhook = "https://discord.com/api/webhooks/...", -- replace with your webhook
    Colors = {
        Common = 0x5AC73C,
        Rare = 0x3158A8,
        Epic = 0xbf1ec8,
        Legendary = 0xd09c17,
    },
    RolePings = {
        Epic = "1234567890", -- replace with your role ID
        Legendary = "0987654321" -- replace with your role ID
    }
}

--// Utility
local function GetTimestamp()
    return DateTime.now():ToIsoDate()
end

local function SendWebhook(Title: string, Content: string, Color: number, rarities: {string})
    if not Config.Enabled then return end

    local mentions = {}
    if Config.RolePingEnabled then
        for _, rarity in ipairs(rarities) do
            local roleId = Config.RolePings[rarity]
            if roleId then
                table.insert(mentions, "<@&" .. roleId .. ">")
            end
        end
    end

    local mentionStr = table.concat(mentions, " ")

    local Body = {
        content = mentionStr,
        embeds = {
            {
                title = Title,
                description = Content,
                color = Color,
                footer = { text = "Glory to Father Arlecchino" },
                timestamp = GetTimestamp()
            }
        },
        allowed_mentions = {
            roles = Config.RolePings -- only allows the listed roles
        }
    }

    local RequestData = {
        Url = Config.Webhook,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode(Body)
    }

    task.spawn(request, RequestData)
end

--// Data collector (Common/Rare/Epic/Legendary)
local function CollectData()
    local lines = {}
    local raritiesFound = {}
    local highestRarity = "Common"
    local rarityOrder = { "Legendary", "Epic", "Rare", "Common" }
    local rarityLabels = {
        Common = "Common Box",
        Rare = "Rare Box",
        Epic = "Epic Box",
        Legendary = "Legendary Box",
    }

    local guiRoot = LocalPlayer:WaitForChild("PlayerGui")
        :WaitForChild("Event")
        :WaitForChild("Canvas")
        :WaitForChild("Main")
        :WaitForChild("CanvasGroup")
        :WaitForChild("ScrollingFrame")

    local function getStockCount(name: string)
        local ok, obj = pcall(function()
            return guiRoot[name].Main.Stock
        end)
        if ok and obj and obj:IsA("TextLabel") then
            -- extract number from formats like "x3 stock" or "x0 stock"
            return tonumber(obj.Text:match("%d+")) or 0
        end
        return 0
    end

	for _, rarity in ipairs(rarityOrder) do
		local count = getStockCount(rarity)
		if count > 0 then
			table.insert(lines, rarityLabels[rarity] .. " x" .. tostring(count))
            table.insert(raritiesFound, rarity)
			if highestRarity == "Common" then
            -- only set once, at the first highest rarity found
            highestRarity = rarity
        	end
		end
	end

	return table.concat(lines, "\n"), Config.Colors[highestRarity]

end

--// Watch the refresh countdown safely
local function StartWatcher()
    local refreshLabel = LocalPlayer:WaitForChild("PlayerGui")
        :WaitForChild("Event")
        :WaitForChild("Canvas")
        :WaitForChild("Main")
        :WaitForChild("CanvasGroup")
        :WaitForChild("TextLabel") -- "Refresh stock in 9m 23s"

    local prevText = ""
    local debounce = false

    refreshLabel:GetPropertyChangedSignal("Text"):Connect(function()
        local text = refreshLabel.Text

        -- Detect reset (when it jumps back to 9m–10m range)
        if not debounce and text:match("^Refresh stock in 1[0-1]m") or text:match("^Refresh stock in 9m") then
            if not (prevText:match("^Refresh stock in 1[0-1]m") or prevText:match("^Refresh stock in 9m")) then
                debounce = true
                task.delay(1, function() -- wait for stock GUI update
                    local data, color, rarities = CollectData()
                    SendWebhook("EVENT BOX STOCK", data, color, rarities)
                    task.delay(599, function()
                        debounce = false -- allow next cycle
                    end)
                end)
            end
        end

        prevText = text
    end)
end

--// Kill switch if another player joins
local function SetupKillSwitch()
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    -- Helper: shuts down the game immediately
	local function Terminate(reason: string)
		local timestamp = DateTime.now():ToIsoDate()
		local fullReason = reason .. " at " .. timestamp

		warn("[KillSwitch] Terminating: " .. fullReason)
		LocalPlayer:Kick(fullReason)
	end



    -- Watch for new players
    Players.PlayerAdded:Connect(function(plr)
        if plr ~= LocalPlayer then
            Terminate("Another player joined: " .. plr.Name)
        end
    end)
end

LocalPlayer.Idled:Connect(function()
    if not Config.AntiAFKEnabled then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0,0)) -- simulates right click
end)

SetupKillSwitch()
task.spawn(StartWatcher)

print("Loaded")