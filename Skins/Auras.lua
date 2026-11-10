local _, NS = ...

local Auras = {
    hooked = setmetatable({}, { __mode = "k" }),
    hosts = setmetatable({}, { __mode = "k" }),
}
NS:RegisterModule("Auras", Auras)

local function HideGroundRegions(...)
    for index = 1, select("#", ...) do
        local region = select(index, ...)
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            region:SetAlpha(0)
            return
        end
    end
end

local function HideGround(button)
    HideGroundRegions(button:GetRegions())
end

function Auras:Initialize(naowh, db, isSkinned, isAccessible, createBorder)
    if not (db.useEdges and db.auraBorders) then return end
    self.isSkinned = isSkinned
    self.isAccessible = isAccessible
    self.createBorder = createBorder

    if not self.skin then
        self.skin = function(button)
            if self.hosts[button] or not self.isSkinned() or not self.isAccessible(button) then return end
            if not (button.icon and button.swipe and button.timeText and button.countText) then return end

            local host = self.createBorder(button)
            if not host then return end
            self.hosts[button] = host
            HideGround(button)
        end
    end

    local function Hook(iconClass)
        if type(iconClass) ~= "table" or type(iconClass.New) ~= "function" or self.hooked[iconClass] then return end
        self.hooked[iconClass] = true
        hooksecurefunc(iconClass, "New", self.skin)
    end

    local pvp = naowh.PvP
    local raid = naowh.RaidDebuffs
    Hook(pvp and pvp.Icon)
    Hook(raid and raid.Icon)
end

function Auras:IsHooked()
    return next(self.hooked) ~= nil
end
