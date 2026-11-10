local _, NS = ...

local Config = {}
NS.Config = Config

Config.EDGE_MAX = 4
Config.PERCENT = 100
Config.FEATURE_KEYS = {
    "useFont", "useColors", "useShell", "itemPlates", "useEdges", "windowBorders",
    "genericBorders", "itemBorders", "hudBorders", "auraBorders", "focusCastBorder",
    "gcdBorders", "topBarBorders", "euiWindows", "euiBags",
}

Config.DEFAULTS = {
    useFont = true,
    useColors = true,
    useShell = true,
    itemPlates = true,
    useEdges = true,
    edgeMode = "actionbars",
    edgeSize = 1,
    edgeR = 0,
    edgeG = 0,
    edgeB = 0,
    windowBorders = true,
    genericBorders = true,
    itemBorders = true,
    hudBorders = true,
    auraBorders = true,
    focusCastBorder = true,
    gcdBorders = true,
    topBarBorders = true,
    borderAlpha = 12,
    buttonBorderAlpha = 30,
    euiWindows = true,
    euiBags = true,
}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

function Config:Load()
    if type(NaowhEllesmereSkinDB) ~= "table" then NaowhEllesmereSkinDB = {} end
    local db = NaowhEllesmereSkinDB

    for key, default in pairs(self.DEFAULTS) do
        if type(db[key]) ~= type(default) then db[key] = default end
    end

    db.edgeMode = db.edgeMode == "solid" and "solid" or "actionbars"
    db.edgeSize = Clamp(math.floor(db.edgeSize + 0.5), 0, self.EDGE_MAX)
    db.borderAlpha = Clamp(math.floor(db.borderAlpha + 0.5), 0, self.PERCENT)
    db.buttonBorderAlpha = Clamp(math.floor(db.buttonBorderAlpha + 0.5), 0, self.PERCENT)
    db.edgeR = Clamp(db.edgeR, 0, 1)
    db.edgeG = Clamp(db.edgeG, 0, 1)
    db.edgeB = Clamp(db.edgeB, 0, 1)

    self.db = db
    return db
end

function Config:Get()
    return self.db or self:Load()
end

function Config:Reset()
    local db = self:Get()
    for key, value in pairs(self.DEFAULTS) do db[key] = value end
end

function Config:SetAll(enabled)
    local db = self:Get()
    for _, key in ipairs(self.FEATURE_KEYS) do db[key] = enabled end
    if enabled and db.edgeSize == 0 then db.edgeSize = self.DEFAULTS.edgeSize end
end
