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
local UI_CURRENT_ITEM = nil
local UI_PLAYER_FRAMES = {}


local defaults = {
    profile = {
        lootData = {},
        windowX = 0,
        windowY = 0,
        hideTimout = 20,
        testRaid = false,
    },
}


local optionsTable = {
    type='group',
    name = "Held Hostile Loot ("..Core.version..")",
    desc = "Loot helper",
    args = {
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
        reset = {
            type = "execute",
            name = "Reset position",
            func = function()
                Core.db.profile.windowX = 0
                Core.db.profile.windowY = 0
            end,
            order = 1,
            width = "full",
        },
        item = {
            type = "input",
            name = "Set item",
            usage = "itemID",
            pattern = "%d+",
            set = function(_, id)
                print("Console set item", id)
                Core:ShowItem(id)
            end,
            order = 2,
            width = "full",
        },
        hideTimout = {
            type = "input",
            name = "Window fade",
            usage = "seconds",
            pattern = "%d+",
            set = function(_, seconds)
                Core.db.profile.hideTimout = tonumber(seconds)
            end,
            get = function()
                return tostring(Core.db.profile.hideTimout)
            end,
            order = 3,
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

    Core.db = LibStub("AceDB-3.0"):New("HHLootDB", defaults)
    Core.UICreate()
end


GameTooltip:HookScript("OnTooltipSetItem", function(self)
    if IsAltKeyDown() then
        local link = select(2, self:GetItem())
        if link then
            local id = string.match(link, "item:(%d*)")
            if id then
                Core:ShowItem(id)
            end
        end
    end
end)


function Core:ShowItem(itemId)
    if UI_CURRENT_ITEM == itemId then
        Core.UI:Show()
        return
    end
    UI_CURRENT_ITEM = itemId
    -- print("ShowItem", itemId)

    -- Item info
    local itemName, itemLink, itemQuality, _, _, itemType, itemSubType, _, itemInvType = GetItemInfo(itemId)
    if itemName == nil then
        print("Item not in cache, try again.")
        return
    end

    if itemQuality < 4 then return end

    local _, _, _, itemColor = GetItemQualityColor(itemQuality)
    local typeName = _G[itemInvType]

    local isArmor = itemType == "Armor"
    local armorType = itemSubType
    local item = {
        ["id"] = itemId,
        ["icon"] = GetItemIcon(itemId),
        ["name"] = itemName,
        ["nameC"] = "|c"..itemColor..itemName.."|r",
        ["link"] = itemLink,
        ["type"] = typeName,
        ["armorType"] = isArmor and armorType or nil,
    }

    -- Get players
    local players = Core:GetPlayers(item)
    -- tinsert(players, {
    --     ["score"] = 105,
    --     ["name"] = "Calavera",
    --     ["initiate"] = false,
    --     ["armor"] = true,
    -- })
    Core:UIUpdate(item, players)
    Core.UI:Show()

    Core:CancelAllTimers()
    Core:ScheduleTimer(function()
        Core.UI.ag:Play()
    end, Core.db.profile.hideTimout)
end


local function isClassArmor(armorType, class)
    if armorType == "Plate" then
        return class == "WARRIOR" or class == "PALADIN" or class == "DEATH KNIGHT"
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


function Core:GetPlayers(item)
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

    local itemData = Core.db.profile.lootData[item["id"]]
    local itemPlayers = {}
    if itemData then
        for _, candidate in ipairs(itemData) do
            local name = candidate["name"]
            if raidPlayers[name] ~= nil then
                tinsert(itemPlayers, {
                    ["score"] = candidate["score"],
                    ["name"] = name,
                    ["class"] = raidPlayers[name],
                    ["armor"] = isClassArmor(item["armorType"], raidPlayers[name]),
                    ["initiate"] = isGuildInitiate(name),
                })
            end
        end
    end

    table.sort(itemPlayers, comparePlayers)

    return itemPlayers
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
                local player = {
                    ["score"] = tonumber(score),
                    ["name"] = name,
                }
                tinsert(itemPlayers, player)
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


function Core:UICreate()
    if UI_CREATED then return end
    UI_CREATED = true

    local frameName = "HHLoot_UI"

    local frame = CreateFrame("Frame", frameName, UIParent, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetPoint("CENTER", Core.db.profile.windowX, Core.db.profile.windowY)
    frame:SetSize(280, 37)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton", "RightButton")
    frame:SetScript("OnMouseDown", FrameOnDragStart)
    frame:SetScript("OnMouseUp", FrameOnDragStop)
    -- frame:SetScript("OnHide", OnHide)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    frame:SetBackdropColor(0.35,0.35,0.35,1)
    frame:Hide()
    -- tinsert(UISpecialFrames, frameName)	-- allow ESC close

    frame.ag = frame:CreateAnimationGroup()
    frame.ag.alpha = frame.ag:CreateAnimation("Alpha")
    frame.ag.alpha:SetFromAlpha(1)
    frame.ag.alpha:SetToAlpha(0)
    frame.ag.alpha:SetDuration(1)
    frame.ag.alpha:SetSmoothing("OUT")
    frame.ag:SetScript("OnFinished", function() frame:Hide() end)

    Core.UI = frame

    frame.item = CreateFrame("Frame", frameName.."_Item", frame)
    frame.item:SetSize(270, 28)
    frame.item:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)

    frame.item.icon = frame.item:CreateTexture(frameName.."_ItemIcon")
    frame.item.icon:SetDrawLayer("ARTWORK", 0)
    frame.item.icon:SetPoint("TOPLEFT", frame.item, "TOPLEFT", 1, -1)
    frame.item.icon:SetSize(26, 26)
    frame.item.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    frame.item.name = frame.item:CreateFontString(frameName.."_ItemName", "ARTWORK", "GameFontNormal")
    frame.item.name:SetPoint("TOPLEFT", frame.item.icon, "TOPRIGHT", 3, 0)
    frame.item.name:SetJustifyH("LEFT")
    frame.item.name:SetText("")
    frame.item.name:SetSize(230, 12)
    -- frame.item.name.Ori_SetText = frame.item.name.SetText
    -- frame.item.name.SetText = Button_ForceSetText

    frame.item.extra = frame.item:CreateFontString(frameName.."_ItemExtra", "ARTWORK", "GameFontNormalSmall")
    frame.item.extra:SetPoint("TOPLEFT", frame.item.name, "BOTTOMLEFT", 0, -1)
    frame.item.extra:SetJustifyH("LEFT")
    frame.item.extra:SetText("")
    frame.item.extra:SetSize(230, 10)
    frame.item.extra:SetTextColor(1, 1, 1, 1)

    -- Create first player Row
    tinsert(UI_PLAYER_FRAMES, Core:UICreatePlayerEntry(1, Core.UI))

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
    
    import.cancel = CreateFrame("Button", frameName.."_ImportCancel", import, "UIPanelCloseButton")
    -- import.cancel:SetScript("OnClick")
    
    import.edit:SetText("Here is some text\nAnd some more text on a new line")

    import:Hide()
    Core.UIImport = import
end

function Core:UIUpdate(item, players)
    -- print("UIUpdate")

    -- Hide all player rows
    for i, frame in ipairs(UI_PLAYER_FRAMES) do
        frame:Hide()
    end
    
    -- Show item
    Core:UIUpdateItem(item)

    -- for each player
    for i, player in ipairs(players) do
        if i > #UI_PLAYER_FRAMES then
            tinsert(UI_PLAYER_FRAMES, Core:UICreatePlayerEntry(i, UI_PLAYER_FRAMES[i-1]))
        end

        Core:UIUpdatePlayerEntry(i, UI_PLAYER_FRAMES[i], player)
    end
end

function Core:UIUpdateItem(item)
    -- print("UIUpdateItem")
    Core.UI.item.icon:SetTexture(item["icon"])
    Core.UI.item.name:SetText(item["nameC"])
    
    local extra = item["type"]
    if item["armorType"] ~= nil then
        extra = extra.." "..item["armorType"]
    end
    Core.UI.item.extra:SetText(extra)
end

function Core:UIPlayerEntry(frame, player)
    frame.score:SetText(player["score"])
    frame.player:SetText(player["name"])
end

function Core:UICreatePlayerEntry(index, anchor)
    -- print("UICreatePlayerEntry", index)
    local frameName = "HHLoot_UI_Player"..index
    local frame = CreateFrame("Frame", frameName, Core.UI, _G.BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
    frame:SetBackdropColor(0.2,0.2,0.2,1)
    frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    frame:SetWidth(280)
    frame:SetHeight(20)

    frame.score = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.score:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -4)
    frame.score:SetJustifyH("LEFT")
    frame.score:SetText("[Score]")
    frame.score:SetHeight(12)
    frame.score:SetWidth(40)

    frame.player = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.player:SetPoint("LEFT", frame.score, "RIGHT", 6, 0)
    frame.player:SetJustifyH("LEFT")
    frame.player:SetText("[Player Name]")
    frame.player:SetHeight(12)
    frame.player:SetWidth(100)

    frame.reason = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.reason:SetPoint("LEFT", frame.player, "RIGHT", 6, 0)
    frame.reason:SetJustifyH("LEFT")
    frame.reason:SetText("[Reason]")
    frame.reason:SetHeight(12)
    frame.reason:SetWidth(120)
    frame.reason:SetTextColor(1, 1, 1, 1)

    return frame
end


local function classColor(text, class)
    if RAID_CLASS_COLORS[class] ~= nil then
        return strconcat('|c', RAID_CLASS_COLORS[class].colorStr, text, '|r')
    end
    return text
end


function Core:UIUpdatePlayerEntry(index, frame, player)
    -- print("UIUpdatePlayerEntry", index)
    frame.score:SetText(player["score"])
    frame.player:SetText(classColor(player["name"], player["class"]))

    local reason = {}
    if not player["armor"] then
        tinsert(reason, "Armor")
    end
    if player["initiate"] then
        tinsert(reason, "Initiate")
    end
    frame.reason:SetText(strjoin(", ", unpack(reason)))

    frame:Show()
end
