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
    Webhook = "https://discord.com/api/webhooks/...", -- replace with your webhook
    Colors = {
        Common = 0x5AC73C,
        Rare = 0x3158A8,
        Epic = 0xbf1ec8,
        Legendary = 0xd09c17,
    }
}

--// Utility
local function GetTimestamp()
    return DateTime.now():ToIsoDate()
end

local function SendWebhook(Title: string, Content: string, Color: number)
    if not Config.Enabled then return end

    local Body = {
        embeds = {
            {
                title = Title,
                description = Content,
                color = Color,
                footer = { text = "Glory to Father Arlecchino" },
                timestamp = GetTimestamp()
            }
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
            local num = tonumber(obj.Text:match("%d+"))
            return num or 0
        end
        return 0
    end

    local rarityOrder = { "Legendary", "Epic", "Rare", "Common" }
    local rarityLabels = {
        Common = "Common Box",
        Rare = "Rare Box",
        Epic = "Epic Box",
        Legendary = "Legendary Box",
    }

    local highestRarity = "Common"

	for _, rarity in ipairs(rarityOrder) do
		local count = getStockCount(rarity)
		if count > 0 then
			table.insert(lines, rarityLabels[rarity] .. " x" .. tostring(count))
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
                    local data, color = CollectData()
                    SendWebhook("EVENT BOX STOCK", data, color)
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