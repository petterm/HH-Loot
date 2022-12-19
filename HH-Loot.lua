local addonName = ...
local Core = LibStub("AceAddon-3.0"):NewAddon(
    addonName,
    "AceConsole-3.0",
    "AceEvent-3.0",
    "AceTimer-3.0"
)
local L = LibStub("AceLocale-3.0"):GetLocale(addonName, true)
Core.L = L
Core.version = GetAddOnMetadata(addonName, "Version")

local GUILD_RANK_INITIATE = "Initiate"
local GUILD_RANK_CACHE = {}
local UI_CREATED = false
local LOOT_PICKUP_TIMER = nil
local LOOT_PICKUP_LIST = {}
local LOOT_BLACKLIST = {}
local LOOT_ITEM_SELF = LOOT_ITEM_SELF:gsub("%%s", "(.+)");


local defaults = {
    profile = {
        lootData = {},
        testRaid = false,
        lootWindow = false,
        lootWindowFade = 5,
        windowX = 0,
        windowY = 0,
    },
}


local optionsTable = {
    type='group',
    name = "Held Hostile Loot ("..Core.version..")",
    desc = "Loot helper",
    args = {
        lootWindow = {
            type = "toggle",
            name = "Show loot pickups",
            set = function(_, value)
                Core.db.profile.lootWindow = value
            end,
            get = function()
                return Core.db.profile.lootWindow
            end,
            order = 1,
            width = "full",
        },
        lootWindowRange = {
            type = "range",
            name = "Loot pickup window fade",
            min = 1,
            max = 30,
            step = 1,
            set = function(_, value)
                Core.db.profile.lootWindowFade = value
            end,
            get = function()
                return Core.db.profile.lootWindowFade
            end,
            order = 2,
            width = "full",
        },
        import = {
            type = "execute",
            name = "Import",
            func = function()
                Core.UIImport.edit:SetText("")
                Core.UIImport:Show()
            end,
            order = 1,
            width = "full",
        },
        testLootAction = {
            type = "execute",
            name = "Test loot pickup",
            func = function()
                LOOT_PICKUP_LIST = { "ITEM A", "ITEM B", "ITEM C" }
                Core:LootPickup("NEW ITEM")
            end,
            order = 1,
            width = "full",
        },
        testRaid = {
            type = "toggle",
            name = "Test raid",
            set = function(_, value)
                Core.db.profile.testRaid = value
            end,
            get = function()
                return Core.db.profile.testRaid
            end,
            order = 4,
            width = "full",
        }
    }
}


local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
AceConfig:RegisterOptionsTable(addonName, optionsTable, { "hhl" })
AceConfigDialog:AddToBlizOptions(addonName, "HH Loot")


function Core:OnInitialize()
    Core:RegisterEvent("GUILD_ROSTER_UPDATE")
    Core:RegisterEvent("CHAT_MSG_LOOT")

    Core.db = LibStub("AceDB-3.0"):New("HHLootDB", defaults)
    Core.UICreate()

    if _G["Gargul"] ~= nil then
        Core:HookGargul(_G["Gargul"])
    end
end


local function getArmorType(itemId)
    local itemName, _, _, _, _, itemType, itemSubType, _, itemInvType = GetItemInfo(itemId)
    if itemName == nil then
        print("Item not in cache, try again.")
        return nil
    end

    if itemType == "Armor" and itemInvType ~= "INVTYPE_CLOAK" then
        return itemSubType
    end
    return nil
end


local function isClassArmor(armorType, class)
    if armorType == "Plate" then
        return class == "WARRIOR" or class == "PALADIN" or class == "DEATHKNIGHT"
    end
    if armorType == "Mail" then
        return class == "HUNTER" or class == "SHAMAN"
    end
    if armorType == "Leather" then
        return class == "DRUID" or class == "ROGUE"
    end
    if armorType == "Cloth" then
        return class == "PRIEST" or class == "MAGE" or class == "WARLOCK"
    end

    return true
end


local function isGuildInitiate(name)
    local rank = GUILD_RANK_CACHE[name]
    return rank == GUILD_RANK_INITIATE
end


local function comparePlayers(a, b)
    -- print("comparePlayers")
    -- Members over initiates
    if a["initiate"] ~= b["initiate"] then
        return b["initiate"]
    end

    -- Primary armor over other classes
    if a["armor"] ~= b["armor"] then
        return a["armor"]
    end

    -- Highest score
    return a["score"] > b["score"]
end


function Core:GetPlayers(itemId, itemArmorType)
    -- print("GetPlayers")
    local raidPlayers = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid"..i
            local _, class = UnitClass(unit)
            local name = UnitName(unit)
            raidPlayers[name] = class
        end
    end
    if Core.db.profile.testRaid then
        raidPlayers = {
            ["Calavera"] = "DEATHKNIGHT",
            ["Kharok"] = "DEATHKNIGHT",
            ["Kekdk"] = "DEATHKNIGHT",
            ["Grillspett"] = "PRIEST",
            ["Omegakerstin"] = "MAGE",
            ["Ojiisan"] = "MAGE",
            ["Bzzyyds"] = "MAGE",
            ["Ronah"] = "WARLOCK",
            ["Hubbe"] = "HUNTER",
            ["Jalak"] = "HUNTER",
            ["Druidimies"] = "DRUID",
            ["Ecocosy"] = "PALADIN",
            ["Tindur"] = "PALADIN",
            ["Tharionas"] = "PALADIN",
            ["Wyldi"] = "SHAMAN",
            ["Kalikke"] = "SHAMAN",
            ["Billbuyers"] = "ROGUE",
            ["Xuenn"] = "ROGUE",
            ["Qbx"] = "WARRIOR",
            ["Redsoup"] = "WARRIOR",
            ["Deaurion"] = "WARRIOR",
        }
    end

    local itemData = Core.db.profile.lootData[itemId]
    local itemPlayers = {}
    if itemData then
        for _, candidate in ipairs(itemData) do
            local name = candidate["name"]
            if raidPlayers[name] ~= nil then
                tinsert(itemPlayers, {
                    ["score"] = candidate["score"],
                    ["name"] = name,
                    ["class"] = raidPlayers[name],
                    ["armor"] = isClassArmor(itemArmorType, raidPlayers[name]),
                    ["initiate"] = isGuildInitiate(name),
                })
            end
        end
    end

    table.sort(itemPlayers, comparePlayers)
    -- DevTools_Dump(itemPlayers)
    -- print(#itemPlayers)
    return itemPlayers
end


function Core:GetTopPlayers(players)
    -- print("GetTopPlayers")
    -- DevTools_Dump(players)
    local score = players[1]["score"]
    local armor = players[1]["armor"]
    local initiate = players[1]["initiate"]
    local topPlayers = {}
    for _, player in pairs(players) do
        if player["armor"] == armor and
            player["initiate"] == initiate and
            player["score"] >= score - 3 then
            tinsert(topPlayers, player)
        end
    end
    -- DevTools_Dump(topPlayers)
    return topPlayers
end


function Core:GUILD_ROSTER_UPDATE()
    Core:GuildUpdate()
end


function Core:GuildUpdate()
    if IsInGuild() then
        wipe(GUILD_RANK_CACHE)
        for i = 1, GetNumGuildMembers() do
            local name, rankName, rankIndex, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
            GUILD_RANK_CACHE[name] = rankName
        end
        -- GUILD_RANK_CACHE["Qbx"] = "Initiate"
    end
end


function parseLootMessage(msg)
    local link = string.match(msg, LOOT_ITEM_SELF);
    if link then
        local id = string.match(link, "item:(%d*)")
        return tonumber(id)
    end
    return nil
end


function Core:CHAT_MSG_LOOT(self, msg, ...)
    if IsInRaid() and Core.db.profile.lootWindow then
        local itemId = parseLootMessage(msg)
        if itemId and not LOOT_BLACKLIST[itemId] then
            local itemName, _, itemQuality = GetItemInfo(itemId)
            if itemName and itemQuality == Enum.ItemQuality["Epic"] then
                Core:LootPickup(itemName)
            end
        end
    end
end


function Core:LootPickup(name)
    tinsert(LOOT_PICKUP_LIST, name)
    Core.UILoot.edit:SetText(strjoin("\n", unpack(LOOT_PICKUP_LIST)))
    Core.UILoot:Show()

    Core:CancelTimer(LOOT_PICKUP_TIMER)
    LOOT_PICKUP_TIMER = Core:ScheduleTimer(function()
        Core.UILoot:Hide()
        wipe(LOOT_PICKUP_LIST)
    end, Core.db.profile.lootWindowFade)
end


local function OnImportTextChanged(self, arg1)
    -- ID,Name:Score,Name:Score;ID,Name:Score
    local text = self:GetText()
    if strlen(text) == 0 then return end
    -- print("Text length: "..strlen(text))

    local items = {}
    local itemsStr = strsplittable(";", text)
    local itemsFound = 0
    for _, itemStr in ipairs(itemsStr) do
        local itemId = nil
        local itemPlayers = {}
        local playersStr = strsplittable(",", itemStr)
        for i, playerStr in ipairs(playersStr) do
            if i == 1 then
                itemId = playerStr
            else
                local name, score = strsplit(":", playerStr)
                score = tonumber(score)
                if name ~= "undefined" and score ~= nil then
                    local player = {
                        ["score"] = score,
                        ["name"] = name,
                    }
                    tinsert(itemPlayers, player)
                end
            end
        end
        items[itemId] = itemPlayers
        itemsFound = itemsFound + 1
    end

    Core.UIImport:Hide()

    if itemsFound == 0 then
        print("No valid items imported!")
        return
    end
    print("Imported "..itemsFound.." items.")
    Core.db.profile.lootData = items
end


local function OnImportEscapePressed(self)
    Core.UIImport:Hide()
end


local function FrameOnDragStart(self, arg1)
    if arg1 == "LeftButton" then
        self:StartMoving()
    end
end


local function FrameOnDragStop(self)
    self:StopMovingOrSizing()
    local _, _, _, posX, posY = self:GetPoint(1)
    Core.db.profile.windowX = posX
    Core.db.profile.windowY = posY
end


local function OnLootEscapePressed(self)
    Core:CancelTimer(LOOT_PICKUP_TIMER)
    Core.UILoot:Hide()
    wipe(LOOT_PICKUP_LIST)
end


function Core:UICreate()
    if UI_CREATED then return end
    UI_CREATED = true

    local frameName = "HHLoot_UI"

    -- Create loot pickup UI
    local loot = CreateFrame("Frame", frameName.."_Loot", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    loot:SetSize(320, 220)
    loot:SetPoint("CENTER", Core.db.profile.windowX, Core.db.profile.windowY)
    loot:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    loot:SetBackdropColor(0.2,0.2,0.2,1)
    loot:SetMovable(true)
    loot:EnableMouse(true)
    loot:RegisterForDrag("LeftButton", "RightButton")
    loot:SetScript("OnMouseDown", FrameOnDragStart)
    loot:SetScript("OnMouseUp", FrameOnDragStop)

    loot.scroll = CreateFrame("ScrollFrame", frameName.."_LootScroll", loot)
    loot.scroll:SetSize(300, 200)
    loot.scroll:SetPoint("CENTER")
    
    loot.edit = CreateFrame("EditBox", frameName.."_LootEdit", loot.scroll)
    loot.edit:SetMultiLine(true)
    loot.edit:SetFontObject(ChatFontNormal)
    loot.edit:SetWidth(300)
    loot.edit:SetScript("OnEscapePressed", OnLootEscapePressed)
    loot.edit:SetAutoFocus(false)
    loot.scroll:SetScrollChild(loot.edit)
    loot:Hide()
    Core.UILoot = loot

    -- Create import UI
    local import = CreateFrame("Frame", frameName.."_Import", UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    import:SetSize(320, 220)
    import:SetPoint("CENTER")
    import:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    import:SetBackdropColor(0.2,0.2,0.2,1)
    
    import.scroll = CreateFrame("ScrollFrame", frameName.."_ImportScroll", import)
    import.scroll:SetSize(300, 200)
    import.scroll:SetPoint("CENTER")
    
    import.edit = CreateFrame("EditBox", frameName.."_ImportEdit", import.scroll)
    import.edit:SetMultiLine(true)
    import.edit:SetFontObject(ChatFontNormal)
    import.edit:SetWidth(300)
    import.edit:SetScript("OnTextChanged", OnImportTextChanged)
    import.edit:SetScript("OnEscapePressed", OnImportEscapePressed)
    import.scroll:SetScrollChild(import.edit)
    
    import.edit:SetText("Here is some text\nAnd some more text on a new line")

    import:Hide()
    Core.UIImport = import
end


local function classColor(text, class)
    if RAID_CLASS_COLORS[class] ~= nil then
        return strconcat('|c', RAID_CLASS_COLORS[class].colorStr, text, '|r')
    end
    return text
end


local function scoreWithPadding(score)
    local scoreStr = tostring(score)
    if score < 100 then
        scoreStr = "  "..tostring(score)
    end
    local decimal = string.match(scoreStr, "%.%d")
    if not decimal then
        scoreStr = scoreStr.."|cFF999999.0|r"
    end
    return scoreStr
end

function Core:AddToTooltip(tt, id)
    local armorType = getArmorType(id)
    local players = Core:GetPlayers(id, armorType)
    local left = ""
    local right = ""
    local reason = {}
    tt:AddLine(" ", 1, 1, 1)
    tt:AddLine("Held Hostile loot", 1, 0.5, 0)
    for _, player in pairs(players) do
        wipe(reason)
        if not player["armor"] then
            tinsert(reason, "Armor")
        end
        if player["initiate"] then
            tinsert(reason, "Initiate")
        end
        left = scoreWithPadding(player["score"]).." "..classColor(player["name"], player["class"])
        right = strjoin(", ", unpack(reason))

        tt:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
    end
end


local isTooltipDone = nil
GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
    if (not isTooltipDone) and tooltip then
        isTooltipDone = true

        local link = select(2, tooltip:GetItem())
        if link then
            local id = string.match(link, "item:(%d*)")
            if id and Core.db.profile.lootData[id] ~= nil then
                Core:AddToTooltip(tooltip, id)
            end
        end
    end
end)


GameTooltip:HookScript("OnTooltipCleared", function()
    isTooltipDone = nil
end)


local function playerNamesString(players)
    local names = {}
    for _, player in pairs(players) do
        tinsert(names, player["name"])
    end
    return strjoin(" ", unpack(names))
end


local function GargulMasterLooterUI_draw(MasterLooterUI, itemLink)
    -- print("GargulMasterLooterUI_draw")
    -- DevTools_Dump(itemLink)
    if itemLink then
        local id = string.match(itemLink, "item:(%d*)")
        -- print("GargulMasterLooterUI_draw", id)
        if id then
            local armorType = getArmorType(id)
            local players = Core:GetPlayers(id, armorType)
            if #(players) > 0 then
                local topPlayers = Core:GetTopPlayers(players)
                local Gargul = _G["Gargul"]
                local ItemNote = Gargul.Interface:get(Gargul.MasterLooterUI, "EditBox.ItemNote");
                ItemNote:SetText(playerNamesString(topPlayers))
            end
        end
    end
end


function Core:HookGargul(Gargul)
    hooksecurefunc(Gargul.MasterLooterUI, "draw", GargulMasterLooterUI_draw)
end
