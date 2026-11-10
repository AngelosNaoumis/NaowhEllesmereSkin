-- NaowhEllesmereSkin.lua: paints Naowh Forever's flat "Naowh" look with EllesmereUI's theme.
--
-- Naowh Forever builds nearly every frame from a handful of shared parts on its namespace
-- (_G.NaowhForever): the colour palette ns.THEME, ns.Border, ns.Solid, ns.Font, ns.Button and
-- ns.Color. Its modules hold ns.THEME by reference and never keep their own copy of those
-- functions, so the skin only has to:
--   1. repaint the ns.THEME colour tables in place with EllesmereUI's colours,
--   2. wrap ns.ApplyThemeColors so that repaint happens right after Naowh paints its own,
--   3. wrap ns.UIFontPath (EllesmereUI's font), ns.Button (EllesmereUI's softer button edge)
--      and ns.Color (so a live accent change reaches text colour codes too),
-- all before Naowh Forever's modules load. Nothing in Naowh Forever's files is changed.
--
-- Naowh's metal "Forever" look draws Blizzard frame art instead of flat colours, so the skin
-- stays out of its way and asks for the "Naowh" look instead.

local ADDON, NS = ...
local NAOWH = NS.NAOWH
local NAOWH_COMBAT = NS.NAOWH_COMBAT

-- Border strength is "white at this percent over the background", like EllesmereUI's borders.
-- useShell: EllesmereUI's window backdrop and border on Naowh windows. itemPlates: a dark slot
-- behind Naowh's item buttons, like EllesmereUI's action buttons.
-- edgeMode: "actionbars" copies the border of EllesmereUI's main action bar onto Naowh's item
-- buttons, HUD elements and bars; "solid" draws a plain black edge of edgeSize physical pixels
-- (0 = no edge).
local EDGE_MAX = NS.Config.EDGE_MAX
local ITEM_PLATE_ALPHA = 0.85
local PERCENT = 100
-- Naowh's own steps for the derived colours (Core.lua: ACCENT_SOFT_STEP, GREY_STEP).
local ACCENT_SOFT_STEP, GREY_STEP = 0.33, 0.03
local WHITE = { r = 1, g = 1, b = 1 }

local db, ns
local installed, foreverSkinSeen, painted, naowhFirst
local hooks = {}
-- One table for every button's resting edge, repainted in place so all buttons share it.
local BUTTON_REST = { r = 0.3, g = 0.3, b = 0.3 }

local function Print(text)
    NS:Print(text)
end

local function Report(err)
    NS:Report(err)
end

-------------------------------------------------------------------------------
--  EllesmereUI's colours
-------------------------------------------------------------------------------
local Rgb = NS.Utils.Rgb

-- `over` drawn at alpha `a` on top of `base`, as one solid colour.
local Blend = NS.Utils.Blend

local function Lighten(c, amount)
    return Blend(c, WHITE, amount)
end

local function Accent()
    local E = _G.EllesmereUI
    if E.ResolveActiveAccent then
        local ok, r, g, b = pcall(E.ResolveActiveAccent)
        if ok and r and g and b then return Rgb(r, g, b) end
    end
    local c = E.ELLESMERE_GREEN
    if c and c.r then return Rgb(c.r, c.g, c.b) end
    return Rgb(E.DEFAULT_ACCENT_R or 12 / 255, E.DEFAULT_ACCENT_G or 210 / 255, E.DEFAULT_ACCENT_B or 157 / 255)
end

local function Palette()
    local E = _G.EllesmereUI
    local bg = E.DARK_BG and Rgb(E.DARK_BG.r, E.DARK_BG.g, E.DARK_BG.b) or Rgb(0.069, 0.058, 0.047)
    local panel = Rgb(E.BTN_BG_R or 0.089, E.BTN_BG_G or 0.080, E.BTN_BG_B or 0.072)
    local edge = Rgb(E.BORDER_R or 1, E.BORDER_G or 1, E.BORDER_B or 1)
    local fg = Rgb(E.TEXT_WHITE_R or 1, E.TEXT_WHITE_G or 1, E.TEXT_WHITE_B or 1)
    local dim = Rgb(E.TEXT_DIM_R or 1, E.TEXT_DIM_G or 1, E.TEXT_DIM_B or 1)
    local accent = Accent()
    local line = Blend(bg, edge, db.borderAlpha / PERCENT)
    return {
        bg = bg,
        panel = panel,
        line = line,
        fg = fg,
        muted = Blend(bg, dim, E.TEXT_DIM_A or 0.53),
        accent = accent,
        accentSoft = Lighten(accent, ACCENT_SOFT_STEP),
        grey = Lighten(line, GREY_STEP),
        buttonRest = Blend(bg, edge, db.buttonBorderAlpha / PERCENT),
    }
end

-------------------------------------------------------------------------------
--  Painting Naowh Forever
-------------------------------------------------------------------------------
local function Set(t, c)
    t.r, t.g, t.b = c.r, c.g, c.b
end

local function Skinned()
    return ns and not ns.foreverSkin
end

-- Blizzard aura containers can hand addon code restricted/forbidden buttons. Reading basic
-- properties may be allowed, but attaching scripts is blocked and produces a visible taint error.
-- These frames must retain Blizzard's own presentation; never attempt to watch or skin them.
local AccessibleFrame = NS.Utils.IsAccessibleFrame

local function Paint()
    if not ns then return end
    if ns.foreverSkin then
        foreverSkinSeen = true
        return
    end
    if not db.useColors then return end
    local colours = Palette()
    for key, c in pairs(colours) do
        local t = ns.THEME[key]
        if type(t) == "table" then Set(t, c) end
    end
    Set(BUTTON_REST, colours.buttonRest)
    painted = true
end

-------------------------------------------------------------------------------
--  Windows: EllesmereUI's own window shell, through its public skinning API
--  (EllesmereUI.RegisterSkin, EllesmereUI/SKINNING_API.md). That is the same
--  backdrop and border its Friends window and other skinned windows wear.
--
--  S.Shell fades every texture on the frame it is given, and EllesmereUI fades
--  them again whenever its window styles refresh. Naowh draws content straight
--  onto its windows, so the shell goes on a bare frame of our own laid over the
--  window at the window's frame level: at equal levels regions interleave by
--  draw layer, so the shell's BACKGROUND art sits under Naowh's content.
--  (Naowh's own character panel uses the same trick for its backdrop.)
-------------------------------------------------------------------------------
local MIN_W, MIN_H = 160, 100
local SIZE_SLACK = 2
local skin                                        -- the S facade, once EllesmereUI hands it over
local outlines = setmetatable({}, { __mode = "k" }) -- frame -> its black outline (ns.Border result)
local seen = setmetatable({}, { __mode = "k" })     -- frame -> true once watched
local shelled = setmetatable({}, { __mode = "k" })  -- frame -> shell host
local shellHosts = setmetatable({}, { __mode = "k" }) -- our own shell hosts (Naowh windows), not EllesmereUI's
local shellCount = 0
-- Why frames were passed over, for /nfeui debug.
local stats = { watched = 0, notTop = 0, small = 0, waiting = 0 }
local lastError
local evaluatePending = setmetatable({}, { __mode = "k" })
local Edge
local Evaluate, Edge, SyncShown

-- A window: a frame on UIParent, or one laid exactly over a frame on UIParent (Naowh's
-- character panel hangs its backdrop on such a frame). Cards and bars inside windows are not.
local function TopLevel(frame, w, h)
    local parent = frame:GetParent()
    if parent == nil or parent == UIParent then return true end
    if parent:GetParent() ~= UIParent then return false end
    local pw, ph = parent:GetSize()
    return math.abs(pw - w) <= SIZE_SLACK and math.abs(ph - h) <= SIZE_SLACK
end

-- Naowh's own full-size background fills on the frame itself (the flat fill, or the backdrop's
-- gradient) would cover the shell's art, so they go see-through. Child frames are left alone.
local function FadeOwnBackground(frame, w, h)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            local rw, rh = region:GetSize()
            if math.abs(rw - w) <= SIZE_SLACK and math.abs(rh - h) <= SIZE_SLACK then region:SetAlpha(0) end
        end
    end
end

local function Shell(frame, w, h)
    local host = CreateFrame("Frame", nil, frame)
    host:SetAllPoints(frame)
    host:EnableMouse(false)
    local function Level() host:SetFrameLevel(frame:GetFrameLevel()) end
    Level()
    hooksecurefunc(frame, "SetFrameLevel", Level)
    -- The shell brings the backdrop; the border is the same one every other Naowh element wears
    -- (the user's action bar border), so windows, panels and trackers match.
    shellHosts[host] = true
    skin.Shell(host, { noTopBar = true, noBorder = true })
    shelled[frame] = host
    shellCount = shellCount + 1
    FadeOwnBackground(frame, w, h)
    if db.windowBorders then Edge(frame, outlines[frame], nil, true) end
    if frame._euiAlpha then host:SetAlpha(frame._euiAlpha) end
end

local function Evaluate(frame)
    if shelled[frame] or not Skinned() then return end
    local w, h = frame:GetSize()
    -- Still being built or too small to be a window: look again the next time it shows.
    if w < MIN_W or h < MIN_H then
        stats.small = stats.small + 1
        -- Too small for a window: a bar or readout on the screen (the XP bar), so it gets the edge.
        if w > 0 and outlines[frame] and frame:GetParent() == UIParent then
            if Edge(frame) then seen[frame] = "skip" end
        end
        return
    end
    if not db.useShell then return end
    if not skin or (skin.IsEnabled and not skin.IsEnabled()) then
        stats.waiting = stats.waiting + 1
        return
    end
    if not TopLevel(frame, w, h) then
        seen[frame] = "skip"
        stats.notTop = stats.notTop + 1
        return
    end
    local ok, err = pcall(Shell, frame, w, h)
    if not ok then
        lastError = tostring(err)
        Report(err)
    end
end

local function EvaluateLater(frame)
    if evaluatePending[frame] then return end
    evaluatePending[frame] = true
    C_Timer.After(0, function()
        evaluatePending[frame] = nil
        if frame:IsVisible() then Evaluate(frame) end
    end)
end

local function Watch(frame)
    if not frame or seen[frame] or not frame.HookScript then return end
    seen[frame] = true
    stats.watched = stats.watched + 1
    frame:HookScript("OnShow", function(self)
        if not shelled[self] and seen[self] ~= "skip" then EvaluateLater(self) end
    end)
    EvaluateLater(frame)
end

local function OnSkin(S)
    skin = S
    for frame, state in pairs(seen) do
        if state ~= "skip" and frame:IsVisible() then Evaluate(frame) end
    end
end

-------------------------------------------------------------------------------
--  Edges: EllesmereUI's border on Naowh's item buttons, HUD elements and bars.
--  By default it copies the border of the user's EllesmereUI main action bar --
--  its style (Pixels, Pixels Textured, Glow, any SharedMedia border, or solid),
--  thickness, colour and offsets -- drawn by EllesmereUI.ApplyBorderStyle, the
--  same call its action buttons use. "/nfeui edge <px>" draws a plain solid
--  edge instead. Naowh's own edge on that frame goes see-through so the two
--  never double up. HUD elements get the edge in every background mode.
--  The action bar settings are read once their database is up (login), so
--  frames made before that are queued.
-------------------------------------------------------------------------------
local edged = setmetatable({}, { __mode = "k" })
local edgeQueue = setmetatable({}, { __mode = "k" })
local edgeCount = 0
local edgesReady = false
local ACTION_BARS = "EllesmereUIActionBars"
local MAIN_BAR = "MainBar"
local SOLID = "solid"
local edgeStyleCache

-- The main action bar's border settings, and EllesmereUI's resolver for its thickness.
local function ActionBarBorder()
    local E = _G.EllesmereUI
    local abns = E._ModuleNS and E._ModuleNS[ACTION_BARS]
    local EAB = abns and abns.EAB
    local bars = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars
    if type(bars) ~= "table" then return nil end
    local s = bars[MAIN_BAR]
    if type(s) ~= "table" then
        local _, first = next(bars)
        s = first
    end
    if type(s) ~= "table" then return nil end
    return s, abns.ResolveBorderThickness
end

local function EdgeStyle()
    -- Settings only take effect after /reload, so the resolved action-bar style is immutable for
    -- this session.  This function is reached by hover/show hooks and must not walk module DBs or
    -- allocate a fresh table every time combat UI elements change state.
    if edgeStyleCache then return edgeStyleCache end
    local style
    if db.edgeMode == "actionbars" then
        local s, resolve = ActionBarBorder()
        if s then
            local size, px = 1, nil
            if resolve then
                local ok, a, b = pcall(resolve, s)
                if ok and a then size, px = a, b end
            end
            local c = s.borderColor or {}
            style = {
                size = size, px = px, texture = s.borderTexture or SOLID,
                r = c.r or 0, g = c.g or 0, b = c.b or 0, a = c.a or 1,
                offX = s.borderTextureOffset, offY = s.borderTextureOffsetY,
                shiftX = s.borderTextureShiftX, shiftY = s.borderTextureShiftY,
                sizeKey = s.borderThickness or "thin",
            }
        end
    end
    style = style or {
        size = db.edgeSize, texture = SOLID,
        r = db.edgeR, g = db.edgeG, b = db.edgeB, a = 1,
    }
    if edgesReady then edgeStyleCache = style end
    return style
end

-- EllesmereUI draws a textured border at its frame's own level, so a status bar, cooldown or icon
-- on a child frame covers it. The border goes one level above the highest child instead.
local CHILD_DEPTH, LEVEL_CAP = 3, 9000
local ours = setmetatable({}, { __mode = "k" })   -- our border frames, left out of the level search
local applied = setmetatable({}, { __mode = "k" }) -- frame -> true once its border is drawn
local tints = setmetatable({}, { __mode = "k" })   -- frame -> colour Naowh last gave its own edge
local SyncShown

local function HighestLevel(frame, depth)
    local top = frame:GetFrameLevel()
    if depth <= 0 then return top end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not ours[child] then
            local level = HighestLevel(child, depth - 1)
            if level > top then top = level end
        end
    end
    return top
end

local function BorderFrames(frame)
    local E = _G.EllesmereUI
    local pp = E.PP and E.PP.GetBorders and E.PP.GetBorders(frame)
    local bd = E._bdBorderData and E._bdBorderData[frame]
    return pp, bd
end

local function Raise(frame)
    if not applied[frame] then return end
    local pp, bd = BorderFrames(frame)
    if pp then ours[pp] = true end
    if bd then ours[bd] = true end
    local level = math.min(HighestLevel(frame, CHILD_DEPTH) + 1, LEVEL_CAP)
    if pp then pp:SetFrameLevel(level) end
    if bd then bd:SetFrameLevel(level) end
end

-- The border's colour: the one Naowh asked its own edge for when that is not its resting colour
-- (an equipped gear set in the accent, a hovered button), the action bar's colour otherwise.
local function Tint(frame)
    if not applied[frame] then return end
    local E = _G.EllesmereUI
    if not E.SetBorderStyleColor then return end
    local t = tints[frame] or EdgeStyle()
    pcall(E.SetBorderStyleColor, frame, t.r, t.g, t.b, t.a or 1)
end

local function ApplyEdge(frame)
    if not db.useEdges then return end
    local E = _G.EllesmereUI
    local style = EdgeStyle()
    if style.size <= 0 then return end
    -- EllesmereUI's solid-border path calls borderFrame:Show(). Many Naowh frames are built and
    -- styled while intentionally hidden (Flight Timer, craft timer, HUD movers, pooled elements).
    -- Preserve that lifecycle state so creating a border never activates its owner.
    local wasShown = frame:IsShown()
    local ok, err
    if E.ApplyBorderStyle then
        ok, err = pcall(E.ApplyBorderStyle, frame, style.size, style.r, style.g, style.b, style.a, style.texture,
            style.offX, style.offY, style.shiftX, style.shiftY, "actionbars", style.sizeKey, nil, style.px)
    elseif E.PP and E.PP.CreateBorder then
        ok, err = pcall(E.PP.CreateBorder, frame, style.r, style.g, style.b, style.a, style.size, "OVERLAY", 7)
    end
    if not wasShown then frame:Hide() end
    if not ok then
        lastError = tostring(err)
        return
    end
    applied[frame] = true
    edgeCount = edgeCount + 1
    Raise(frame)
    if tints[frame] then Tint(frame) end
    -- Borders are positioned once after construction. Known elements with mutable geometry have
    -- their own narrow layout hooks below; a generic OnShow tree walk made every pooled element
    -- pay repeatedly for a hierarchy that normally never changes.
    SyncShown(frame)
end

-- The border shows exactly when Naowh would show its own: a HUD element set to the "Soft" or
-- "None" background hides its edge, and so does this. Elements Naowh draws no edge for (aura
-- icons, GCD icons) always show it.
local follows = setmetatable({}, { __mode = "k" }) -- frame -> Naowh's own edge frame
local shownState = setmetatable({}, { __mode = "k" }) -- frame -> last applied visibility/style

SyncShown = function(frame)
    local naowh = follows[frame]
    if not (naowh and applied[frame]) then return end
    local shown = naowh:IsShown()
    local pp, bd = BorderFrames(frame)
    local textured = EdgeStyle().texture ~= SOLID
    local key = shown and (textured and 2 or 1) or 0
    if shownState[frame] == key then return end
    shownState[frame] = key
    if bd then bd:SetShown(shown and textured) end
    if pp and not textured then pp:SetShown(shown) end
end

local function Follow(frame, naowhFrame)
    if follows[frame] then return end
    follows[frame] = naowhFrame
    local function Sync() SyncShown(frame) end
    hooksecurefunc(naowhFrame, "Show", Sync)
    hooksecurefunc(naowhFrame, "Hide", Sync)
    hooksecurefunc(naowhFrame, "SetShown", Sync)
end

local function SameColour(r, g, b, c)
    return c and math.abs(r - c.r) < 0.01 and math.abs(g - c.g) < 0.01 and math.abs(b - c.b) < 0.01
end

-- Naowh's own edge is see-through from here on. Of the colours it is given, only the accent
-- carries over (an equipped gear set, a hovered button): item quality and other per-element
-- colours (loot rows) would make borders that should match each other differ.
local function Mirror(frame, naowhEdge)
    if not (naowhEdge and type(naowhEdge.SetColor) == "function") or naowhEdge._euiMirror then return end
    naowhEdge._euiMirror = true
    local setColor = naowhEdge.SetColor
    naowhEdge.SetColor = function(self, r, g, b, a, ...)
        setColor(self, r, g, b, a, ...)
        local T = ns.THEME
        if r and (SameColour(r, g, b, T.accent) or SameColour(r, g, b, T.accentSoft)) then
            local tint = tints[frame]
            local alpha = a or 1
            if tint and tint.r == r and tint.g == g and tint.b == b and tint.a == alpha then return end
            if tint then
                tint.r, tint.g, tint.b, tint.a = r, g, b, alpha
            else
                tints[frame] = { r = r, g = g, b = b, a = alpha }
            end
        else
            if not tints[frame] then return end
            tints[frame] = nil
        end
        Tint(frame)
    end
end

-- Elements that keep no border at all: on-screen alerts and the layer readout on the minimap,
-- and the top bar, whose three groups get one each instead (TopBarGroups below). A frame is
-- left out when it or any frame it sits in has one of these names.
local EXCLUDED = {
    NaowhForeverAlerts = true, NaowhForeverCampNearby = true, NaowhForeverCombatAlert = true,
    NaowhForeverLayerTracker = true, NaowhForeverTopBar = true,
}
local CAST_BAR = "NaowhForeverFocusCastBar"

local function IsFocusCastPart(frame)
    if not frame then return false end
    if frame:GetName() == CAST_BAR then return true end
    local parent = frame:GetParent()
    return parent and parent:GetName() == CAST_BAR
end

local function Excluded(frame)
    -- The focus cast bar and its icon share one border (CastBarHull below).
    if frame:GetName() == CAST_BAR then return true end
    local parent = frame:GetParent()
    if parent and parent:GetName() == CAST_BAR and parent.icon == frame then return true end
    -- An item bar's outline (Naowh's accent box round the whole bar while it is anchored): its
    -- buttons already wear the border, so a second one round them all reads as a double edge.
    if parent and parent.outline == frame then return true end
    local node = frame
    while node and node ~= UIParent do
        local name = node.GetName and node:GetName()
        if name and EXCLUDED[name] then return true end
        node = node:GetParent()
    end
    return false
end

Edge = function(frame, naowhEdge, rest, isWindow)
    if not (frame and Skinned()) then return end
    if edged[frame] then return true end
    if not db.useEdges then return end
    if db.edgeMode ~= "actionbars" and db.edgeSize <= 0 then return end
    if not isWindow and Excluded(frame) then return end
    edged[frame] = true
    naowhEdge = naowhEdge or outlines[frame]
    if naowhEdge and naowhEdge._frame then
        naowhEdge._frame:SetAlpha(0)
        Mirror(frame, naowhEdge)
        Follow(frame, naowhEdge._frame)
    end
    if edgesReady then
        ApplyEdge(frame)
    else
        edgeQueue[frame] = true
    end
    return true
end

-------------------------------------------------------------------------------
--  Aura icons. Shared.AuraIcon is a factory for module-specific Icon tables;
--  replacing that factory taints Blizzard's CustomAuraContainer creation path.
--  PvP and Raid Debuffs expose their finished Icon tables on their namespaces.
--  A secure post-hook on Icon.New runs inside initializeFrame, after Naowh has
--  created the icon/cooldown/text regions but before Blizzard restricts the
--  aura button. The independent child overlay is created and styled exactly
--  once, inherits visibility from the pooled button, and needs no scripts.
-------------------------------------------------------------------------------
local function CreateAuraBorder(button)
    local host = CreateFrame("Frame", nil, button)
    host:SetAllPoints(button)
    host:EnableMouse(false)
    host:SetFrameLevel(math.min(button:GetFrameLevel() + 3, LEVEL_CAP))
    ours[host] = true
    ApplyEdge(host)
    if not applied[host] then
        host:Hide()
        return nil
    end
    return host
end

local function HookAuraIcons()
    if not (db and db.useEdges and db.auraBorders and ns) then return end
    local module = NS.Modules.Auras
    if not module then return end
    module:Initialize(ns, db, Skinned, AccessibleFrame, CreateAuraBorder)
    hooks.auras = module:IsHooked()
end

-------------------------------------------------------------------------------
--  Every other Naowh element: anything Naowh outlines with ns.Border, in any
--  colour, gets the edge, once it has a size, except windows (the shell skins
--  those) and anything inside a window, where Naowh's own controls stay.
-------------------------------------------------------------------------------
local MIN_EDGE = 6
local naowhEdges = setmetatable({}, { __mode = "k" }) -- frame -> { edge = ns.Border result, rest = colour }
local rejected = setmetatable({}, { __mode = "k" })
local edgeWatched = setmetatable({}, { __mode = "k" })

local function WindowLike(frame)
    if shelled[frame] then return true end
    if not seen[frame] or seen[frame] == "skip" then return false end
    local w, h = frame:GetSize()
    return w >= MIN_W and h >= MIN_H
end

local function InsideWindow(frame)
    local parent = frame:GetParent()
    while parent and parent ~= UIParent do
        if WindowLike(parent) then return true end
        parent = parent:GetParent()
    end
    return false
end

local function TryEdge(frame)
    if edged[frame] or rejected[frame] or not Skinned() then return true end
    local w, h = frame:GetSize()
    -- Not laid out yet, or a hairline track: look again the next time it shows.
    if w < MIN_EDGE or h < MIN_EDGE then return false end
    if WindowLike(frame) or InsideWindow(frame) then
        rejected[frame] = true
        return true
    end
    local entry = naowhEdges[frame]
    return Edge(frame, entry and entry.edge, entry and entry.rest) == true
end

local function EdgeLater(frame)
    if not AccessibleFrame(frame) or edgeWatched[frame] or not frame.HookScript then return end
    edgeWatched[frame] = true
    local waiting, hooksAttached, Later
    local function Try()
        waiting = false
        if TryEdge(frame) or hooksAttached then return end
        hooksAttached = true
        frame:HookScript("OnShow", Later)
        frame:HookScript("OnSizeChanged", Later)
    end
    Later = function()
        if waiting or edged[frame] or rejected[frame] then return end
        waiting = true
        C_Timer.After(0, Try)
    end
    -- Most frames finish construction before this callback and need no permanent script hooks.
    -- Unsized pooled frames receive show/size hooks only after that first attempt fails.
    Later()
end

-------------------------------------------------------------------------------
--  Elements with a layout of their own
-------------------------------------------------------------------------------

-- Focus cast bar, like EllesmereUI's cast bar: one border round the icon and the bar together,
-- and the border style's divider between them (Pixels ships one; a solid style gets a line).
-- The icon can sit left, right, above or below; above and below it keeps a border of its own.
local function CastBarHull()
    local f = _G[CAST_BAR]
    if not (f and f.icon) then return false end
    if f._euiHull then return true end
    local E = _G.EllesmereUI
    local icon = f.icon
    for _, piece in ipairs({ f, icon }) do
        local own = outlines[piece] or (naowhEdges[piece] and naowhEdges[piece].edge)
        if own and own._frame then own._frame:SetAlpha(0) end
    end
    local hull = CreateFrame("Frame", nil, f)
    hull:EnableMouse(false)
    ours[hull] = true
    f._euiHull = hull
    local alone = CreateFrame("Frame", nil, icon) -- the icon's own border when it is above or below
    alone:SetAllPoints(icon)
    alone:EnableMouse(false)
    local sep = CreateFrame("Frame", nil, hull)
    sep.tex = sep:CreateTexture(nil, "OVERLAY", nil, 7)

    local function Layout()
        local style = EdgeStyle()
        local side = "NONE"
        if icon:IsShown() then
            local x = icon:GetCenter()
            local l, r = f:GetLeft(), f:GetRight()
            if x and l and r then side = x < l and "LEFT" or x > r and "RIGHT" or "OTHER" end
        end
        hull:ClearAllPoints()
        if side == "LEFT" then
            hull:SetPoint("TOPLEFT", icon, "TOPLEFT")
            hull:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
        elseif side == "RIGHT" then
            hull:SetPoint("TOPLEFT", f, "TOPLEFT")
            hull:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
        else
            hull:SetAllPoints(f)
        end
        hull:SetFrameLevel(math.min(HighestLevel(f, CHILD_DEPTH) + 1, LEVEL_CAP))
        if applied[hull] then Raise(hull) else ApplyEdge(hull) end

        if side == "OTHER" then
            if not applied[alone] then ApplyEdge(alone) end
            alone:Show()
        else
            alone:Hide()
        end

        if side == "LEFT" or side == "RIGHT" then
            sep:ClearAllPoints()
            sep:SetAllPoints(icon)
            sep:SetFrameLevel(math.min(hull:GetFrameLevel() + 2, LEVEL_CAP))
            local right = side == "RIGHT"
            if style.texture ~= SOLID and E.PlaceBorderDividerV and E.GetBorderCompanion
                    and E.GetBorderCompanion(style.texture, "sepV") then
                pcall(E.PlaceBorderDividerV, sep.tex, sep, right, true, style.texture, style.size, style.px,
                    sep:GetEffectiveScale())
                sep.tex:SetVertexColor(style.r, style.g, style.b, style.a)
            else
                local px = (E.PP and E.PP.mult or 1) * math.max(1, style.size or 1)
                sep.tex:SetColorTexture(style.r, style.g, style.b, style.a)
                sep.tex:ClearAllPoints()
                sep.tex:SetPoint("TOP", sep, right and "TOPLEFT" or "TOPRIGHT")
                sep.tex:SetPoint("BOTTOM", sep, right and "BOTTOMLEFT" or "BOTTOMRIGHT")
                sep.tex:SetWidth(px)
                sep.tex:Show()
            end
            sep:Show()
        else
            sep:Hide()
        end
    end

    local waiting
    local function RunLayout()
        waiting = false
        local ok, err = pcall(Layout)
        if not ok then lastError = tostring(err) end
    end
    local function Later()
        if waiting then return end
        waiting = true
        C_Timer.After(0, RunLayout)
    end
    hooksecurefunc(icon, "SetPoint", Later)
    icon:HookScript("OnShow", Later)
    icon:HookScript("OnHide", Later)
    f:HookScript("OnShow", Later)
    f:HookScript("OnSizeChanged", Later)
    Later()
    return true
end

-- Top bar: one border round each of its groups (left buttons, clock, right buttons). The groups
-- are the bar's background pills (bar.segs); each border follows its pill in and out of view.
local function TopBarGroups()
    local bar = _G.NaowhForeverTopBar
    if not (bar and type(bar.segs) == "table") then return false end
    if bar._euiGroups then return true end
    bar._euiGroups = true
    local level = math.min(HighestLevel(bar, CHILD_DEPTH) + 1, LEVEL_CAP)
    for _, seg in ipairs(bar.segs) do
        local host = CreateFrame("Frame", nil, bar)
        host:EnableMouse(false)
        host:SetAllPoints(seg)
        host:SetFrameLevel(level)
        ours[host] = true
        ApplyEdge(host)
        local lastShown
        local function Sync()
            local shown = seg:IsShown()
            if shown == lastShown then return end
            lastShown = shown
            host:SetShown(shown)
        end
        hooksecurefunc(seg, "Show", Sync)
        hooksecurefunc(seg, "Hide", Sync)
        hooksecurefunc(seg, "SetShown", Sync)
        Sync()
    end
    return true
end

-- GCD tracker: its scrolling icons are pooled frames with a black edge texture of their own
-- (no ns.Border). Scan when the tracker is shown or its layout changes instead of polling every
-- half-second forever (the old ticker ran most often exactly when combat performance mattered).
local GCD = "NaowhForeverGcdTracker"
local gcdChildCount = -1

local function GcdIcons()
    local gcd = _G[GCD]
    if not gcd then return false end
    local count = gcd:GetNumChildren()
    if count == gcdChildCount then return true end
    gcdChildCount = count
    for _, child in ipairs({ gcd:GetChildren() }) do
        if not edged[child] and child.tex and child.border and child.glow then
            child.border:SetAlpha(0)
            if db.gcdBorders then Edge(child) end
        end
    end
    return true
end

local function WatchGcd()
    local gcd = _G[GCD]
    if not gcd then return false end
    if gcd._euiGcdWatched then return true end
    gcd._euiGcdWatched = true
    local waiting
    local function RunScan()
        waiting = false
        if gcd:IsVisible() then GcdIcons() end
    end
    local function Scan()
        if waiting then return end
        waiting = true
        C_Timer.After(0, RunScan)
    end
    gcd:HookScript("OnShow", Scan)
    gcd:HookScript("OnSizeChanged", Scan)
    -- New pooled icons are created by successful player casts.  An event costs nothing between
    -- casts and catches those icons without a combat-time polling ticker.
    local casts = CreateFrame("Frame")
    casts:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    casts:SetScript("OnEvent", function(_, _, unit)
        if unit == "player" and gcd:IsVisible() then Scan() end
    end)
    gcd._euiGcdEvents = casts
    if gcd:IsVisible() then Scan() end
    return true
end

local extrasWaiting, extrasPending = false, true
local function Extras()
    extrasWaiting = false
    if not (Skinned() and db.useEdges) then return end
    local castDone = not db.focusCastBorder or CastBarHull()
    local topDone = not db.topBarBorders or TopBarGroups()
    local gcdDone = not db.gcdBorders or WatchGcd()
    extrasPending = not (castDone and topDone and gcdDone)
    hooks.extras = true
end

-- Frame factories call this while Naowh modules initialize. Coalescing gives each module the rest
-- of the current frame to finish wiring its globals, without polling when modules are disabled.
local function QueueExtras()
    if extrasWaiting or not extrasPending then return end
    extrasWaiting = true
    C_Timer.After(0, Extras)
end

local function QueueExtrasFor(frame)
    if not extrasPending then return end
    local node = frame
    for _ = 1, 4 do
        if not node then return end
        local name = node.GetName and node:GetName()
        if name == CAST_BAR or name == GCD or name == "NaowhForeverTopBar" then
            QueueExtras()
            return
        end
        node = node.GetParent and node:GetParent()
    end
end

-------------------------------------------------------------------------------
--  EllesmereUI's own windows: every window its window engine skins
--  (WSkin.Shell: character sheet, Group Finder, mail, merchant, the window
--  packs and third-party shells) and its Friends window get the same border as
--  Naowh's, so all windows match. The border goes on a frame of ours laid over
--  the window (ApplyBorderStyle wants a frame its caller owns, and these are
--  Blizzard's), above the window's content. The engine's ornate atlas frame is
--  hidden where it has one; its 1px line sits under the wider border.
-------------------------------------------------------------------------------
local BLIZZARD_SKIN, FRIENDS_SKIN = "EllesmereUIBlizzardSkin", "EllesmereUIFriends"
local euiHosts = setmetatable({}, { __mode = "k" })   -- window -> our border frame, or false when skipped
local euiWatched = setmetatable({}, { __mode = "k" })
local euiCount = 0
local EUI_CHILD_DEPTH = 2

local function WindowEngine()
    local E = _G.EllesmereUI
    local bs = E._ModuleNS and E._ModuleNS[BLIZZARD_SKIN]
    return bs and bs.WSkin
end

-- Naowh already borders this window (its character panel lies over the character sheet).
local function NaowhBorders(frame, w, h)
    for _, child in ipairs({ frame:GetChildren() }) do
        if applied[child] then
            local cw, ch = child:GetSize()
            if math.abs(cw - w) <= SIZE_SLACK and math.abs(ch - h) <= SIZE_SLACK then return true end
        end
    end
    return false
end

local function EuiTry(frame)
    if euiHosts[frame] ~= nil or not (db.useEdges and db.euiWindows and edgesReady) then return end
    -- A protected window cannot take a new child in combat; it is tried again when next shown.
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
    local w, h = frame:GetSize()
    if w < MIN_W or h < MIN_H then return end
    if NaowhBorders(frame, w, h) then
        euiHosts[frame] = false
        return
    end
    local host = CreateFrame("Frame", nil, frame)
    host:EnableMouse(false)
    host:SetAllPoints(frame)
    ours[host] = true
    euiHosts[frame] = host
    local function Level() host:SetFrameLevel(math.min(HighestLevel(frame, EUI_CHILD_DEPTH) + 1, LEVEL_CAP)) end
    Level()
    ApplyEdge(host)
    frame:HookScript("OnShow", Level)
    euiCount = euiCount + 1
    local ws = WindowEngine()
    local d = ws and ws.GetFFD and ws.GetFFD(frame)
    if d and d.atlasBorderFrame then d.atlasBorderFrame:Hide() end
end

local function EuiWatch(frame)
    if not frame or euiWatched[frame] or shellHosts[frame] or not frame.HookScript then return end
    euiWatched[frame] = true
    local waiting
    local function Try()
        waiting = false
        if frame:IsVisible() and euiHosts[frame] == nil then EuiTry(frame) end
    end
    local function Later()
        if waiting or euiHosts[frame] ~= nil then return end
        waiting = true
        C_Timer.After(0, Try)
    end
    frame:HookScript("OnShow", Later)
    if frame:IsVisible() then Later() end
end

-- Hooked as early as this addon loads (EllesmereUIBlizzardSkin loads before it), so windows the
-- engine skins at login are caught too.
local function HookEllesmereWindows()
    if hooks.euiWindows or not (db.useEdges and db.euiWindows) then return end
    local ws = WindowEngine()
    if ws and type(ws.Shell) == "function" then
        hooksecurefunc(ws, "Shell", function(_, frame)
            if frame then EuiWatch(frame) end
        end)
        hooks.euiWindows = true
    end
end

local function EuiFlush()
    if not (db.useEdges and db.euiWindows) then return end
    if C_AddOns.IsAddOnLoaded(FRIENDS_SKIN) and _G.FriendsFrame then EuiWatch(_G.FriendsFrame) end
    for frame in pairs(euiWatched) do
        if frame:IsVisible() then EuiTry(frame) end
    end
end

local function FlushEdges()
    edgesReady = true
    if not db.useEdges then return end
    -- Resolve once after EllesmereUIActionBars has completed its login setup.
    edgeStyleCache = nil
    EdgeStyle()
    local okEui, errEui = pcall(EuiFlush)
    if not okEui then lastError = tostring(errEui) end
    for frame in pairs(edgeQueue) do
        edgeQueue[frame] = nil
        ApplyEdge(frame)
    end
    if db.useEdges and (db.focusCastBorder or db.topBarBorders or db.gcdBorders) then
        local ok, err = pcall(QueueExtras)
        if not ok then lastError = tostring(err) end
    end
end

-- Naowh's item buttons (consumable bar and other item bars): a dark slot behind the icon like
-- EllesmereUI's action buttons.
local function Plate(button)
    if not Skinned() or button._euiPlate then return end
    local plate = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    plate:SetAllPoints(button)
    local bg = _G.EllesmereUI.DARK_BG
    plate:SetColorTexture(bg and bg.r or 0.07, bg and bg.g or 0.06, bg and bg.b or 0.05, ITEM_PLATE_ALPHA)
    button._euiPlate = plate
end

local function HookFrames()
    local St = ns.Shared and ns.Shared.Style
    local black = St and St.BORDER_RGB
    local specialBorders = db.useEdges and (db.focusCastBorder or db.gcdBorders or db.topBarBorders)
    local needBorderHook = db.useShell or (db.useEdges and db.genericBorders) or specialBorders
    local trackGeneric = db.useEdges and db.genericBorders
    local trackFocus = db.useEdges and db.focusCastBorder

    -- Every Naowh window outline is ns.Border(frame, Style.BORDER_RGB). It is remembered so the
    -- shell's border can take its place, and a frame on UIParent drawn this way is a window
    -- candidate (the options windows use a flat fill, not a backdrop).
    local border = ns.Border
    if needBorderHook and type(border) == "function" and type(black) == "table" then
        ns.Border = function(frame, color, alpha)
            local result = border(frame, color, alpha)
            if frame and type(result) == "table" then
                local focusPart = trackFocus and IsFocusCastPart(frame)
                if color == black and (db.useShell or focusPart) then
                    outlines[frame] = result
                    if db.useShell and frame:GetParent() == UIParent then Watch(frame) end
                end
                if trackGeneric or focusPart then
                    local entry = naowhEdges[frame]
                    if entry then
                        entry.edge, entry.rest = result, color or ns.THEME.line
                    else
                        naowhEdges[frame] = { edge = result, rest = color or ns.THEME.line }
                    end
                end
                if trackGeneric then EdgeLater(frame) end
                if specialBorders then QueueExtrasFor(frame) end
            end
            return result
        end
        hooks.border = true
    end

    -- Every other window and panel paints through one backdrop class. It is reached through a
    -- throwaway backdrop, so this holds even where a module kept its own Parts.Backdrop.
    local Parts = ns.Shared and ns.Shared.Parts
    if db.useShell and Parts and type(Parts.Backdrop) == "function" then
        local probe = CreateFrame("Frame")
        probe:Hide()
        local ok, sample = pcall(Parts.Backdrop, probe)
        local class = ok and type(sample) == "table" and getmetatable(sample)
        local paint = class and class.Paint
        if type(paint) == "function" then
            class.Paint = function(self, alpha, ...)
                paint(self, alpha, ...)
                local frame = self.frame
                if frame and Skinned() then
                    frame._euiAlpha = alpha
                    local host = shelled[frame]
                    if host then
                        host:SetAlpha(alpha or 1)
                        self.gradient:SetAlpha(0)
                        if self.pattern then self.pattern:SetAlpha(0) end
                    else
                        Watch(frame)
                    end
                end
            end
            hooks.windows = true
        end
    end

    local ItemBar = ns.Shared and ns.Shared.ItemBar
    local addItemPlate = db.itemPlates
    local addItemEdge = db.useEdges and db.itemBorders
    if (addItemPlate or addItemEdge)
            and ItemBar and type(ItemBar.NewButton) == "function" then
        local newButton = ItemBar.NewButton
        ItemBar.NewButton = function(...)
            local button = newButton(...)
            if button then
                if addItemPlate then Plate(button) end
                if addItemEdge then Edge(button) end
            end
            return button
        end
        hooks.items = true
    end

    -- HUD elements (trackers, timers, cast bars, text readouts) all take their backdrop from
    -- Parts.HudBackdrop; its border only shows in "card" mode, the EllesmereUI edge in every mode.
    local addHudEdge = db.useEdges and db.hudBorders
    local findHudExtras = db.useEdges and (db.focusCastBorder or db.gcdBorders)
    if (addHudEdge or findHudExtras)
            and Parts and type(Parts.HudBackdrop) == "function" then
        local hudBackdrop = Parts.HudBackdrop
        Parts.HudBackdrop = function(frame, ...)
            local backdrop = hudBackdrop(frame, ...)
            if addHudEdge and type(backdrop) == "table" then Edge(frame, backdrop.border) end
            if findHudExtras then QueueExtrasFor(frame) end
            return backdrop
        end
        hooks.hud = true
    end

    -- Shared.AuraIcon itself is deliberately not wrapped. Its finished module-specific Icon tables
    -- are securely post-hooked by HookAuraIcons after NaowhForever_Combat has loaded.
end

-- EllesmereUI calls this when its accent changes (colour picker, profile swap, class accent at login).
-- Frames already built keep the colour they were drawn with until a /reload.
local function OnAccent(r, g, b)
    if not (Skinned() and db.useColors) then return end
    local accent = Rgb(r, g, b)
    Set(ns.THEME.accent, accent)
    Set(ns.THEME.accentSoft, Lighten(accent, ACCENT_SOFT_STEP))
end

local function EllesmereFont()
    local E = _G.EllesmereUI
    if not E.GetFontPath then return nil end
    local ok, path = pcall(E.GetFontPath)
    if ok and type(path) == "string" and path ~= "" then return path end
end

local function Install()
    if installed then return end
    ns = _G.NaowhForever
    if type(ns) ~= "table" or type(ns.THEME) ~= "table" or type(ns.ApplyThemeColors) ~= "function" then
        ns = nil
        return
    end
    installed = true

    if db.useColors then
        local applyThemeColors = ns.ApplyThemeColors
        ns.ApplyThemeColors = function(...)
            applyThemeColors(...)
            local ok, err = pcall(Paint)
            if not ok then Report(err) end
        end
    end

    -- String tokens ("muted", "accent") are cached once by Naowh; resolving them to the live table
    -- here keeps the colour codes right after a live accent change.
    local color = ns.Color
    if db.useColors and type(color) == "function" then
        ns.Color = function(token, text)
            if type(token) == "string" and type(ns.THEME[token]) == "table" then token = ns.THEME[token] end
            return color(token, text)
        end
    end

    -- EllesmereUI's font wins over the one picked in Naowh Forever's settings: Naowh looks its font
    -- up once while it loads, before font packs that load after it (SharedMedia_*) have registered
    -- theirs, and keeps its fallback for the session. /nfeui font hands the choice back to Naowh.
    local uiFontPath = ns.UIFontPath
    if db.useFont and type(uiFontPath) == "function" then
        ns.UIFontPath = function()
            if Skinned() then
                local path = EllesmereFont()
                if path then return path end
            end
            return uiFontPath()
        end
    end

    -- Naowh's button rests on the palette line colour; EllesmereUI's buttons have a brighter edge.
    -- Primary buttons swap their rest colour to the accent afterwards, which is left alone.
    local button = ns.Button
    if db.useColors and type(button) == "function" then
        ns.Button = function(...)
            local btn = button(...)
            if Skinned() and btn and btn._border and btn._rest == ns.THEME.line then
                btn._rest = BUTTON_REST
                btn._border:SetColor(BUTTON_REST.r, BUTTON_REST.g, BUTTON_REST.b, 1)
            end
            return btn
        end
    end

    local okFrames, errFrames = pcall(HookFrames)
    if not okFrames then Report(errFrames) end

    local E = _G.EllesmereUI
    if db.useColors and E.RegAccent then E.RegAccent({ type = "callback", fn = OnAccent }) end
    -- Fires at login (or right away if login already happened), and only while EllesmereUI's
    -- third-party skinning is on for this addon (Blizzard Skins+ > Window Skins > Third-Party Addons).
    if db.useShell and E.RegisterSkin then E.RegisterSkin(ADDON, OnSkin) end

    -- Naowh normally paints its theme after this hook is in place; if it already has, paint now.
    if db.useColors and ns.skin ~= nil then
        local ok, err = pcall(Paint)
        if not ok then Report(err) end
    end
end

-------------------------------------------------------------------------------
--  Settings: /nfeui
-------------------------------------------------------------------------------
local function LoadDB()
    db = NS.Config:Load()
end

local SETTINGS = { border = "borderAlpha", button = "buttonBorderAlpha" }
local SETTING_NAMES = { border = "Divider", button = "Button border" }
local SWITCHES = {
    font = { "useFont", "Using EllesmereUI's font.", "Using Naowh Forever's font." },
    colors = { "useColors", "Using EllesmereUI's colors.", "Using Naowh Forever's colors." },
    shell = { "useShell", "Windows use EllesmereUI's backdrop and border.", "Windows keep Naowh's backdrop." },
    slots = { "itemPlates", "Item buttons get a dark slot.", "Item buttons keep Naowh's look." },
    borders = { "useEdges", "Borders enabled.", "Borders disabled." },
    euiwindows = { "euiWindows", "EllesmereUI's windows get the border too.", "EllesmereUI's windows keep their own border." },
}

local function OnOff(on) return on and "on" or "off" end

local function Status()
    Print(("EllesmereUI font %s, window shell %s, item slots %s, edges %d px, dividers %d%%, button border %d%%.")
        :format(OnOff(db.useFont), OnOff(db.useShell), OnOff(db.itemPlates), db.edgeSize, db.borderAlpha,
        db.buttonBorderAlpha))
    Print("/nfeui font | colors | shell | slots | borders | euiwindows - turn each part on or off")
    Print("/nfeui edge bars | <0-4> - item button, HUD and bar border: your action bar's, or plain px (0 = off)")
    Print("/nfeui border <0-100> - divider and inner line strength")
    Print("/nfeui button <0-100> - button border strength")
    Print("/nfeui reset - back to the defaults")
    Print("/nfeui debug - show whether the skin is active")
end

local function Hex(c)
    if type(c) ~= "table" then return "?" end
    local function Byte(v) return math.floor(v * 255 + 0.5) end
    return ("%02x%02x%02x"):format(Byte(c.r), Byte(c.g), Byte(c.b))
end

local function Debug(all)
    local yes, no = "|cff4ade80yes|r", "|cfff87171no|r"
    Print("Naowh Forever loaded: " .. (C_AddOns.IsAddOnLoaded(NAOWH) and yes or no)
        .. (naowhFirst and " (it loaded before this skin)" or ""))
    Print("hooked in: " .. (installed and yes or no) .. ", colours painted: " .. (painted and yes or no)
        .. ", outlines: " .. (hooks.border and yes or no) .. ", windows: " .. (hooks.windows and yes or no)
        .. ", item buttons: " .. (hooks.items and yes or no))
    Print("EllesmereUI window skin handed over: " .. (skin and yes or no)
        .. (skin and skin.IsEnabled and not skin.IsEnabled() and " (but third-party skinning is off for it)" or "")
        .. (skin and skin.GetStyle and (", style " .. tostring(skin.GetStyle())) or "")
        .. ", windows skinned so far: " .. shellCount)
    Print(("frames seen %d, passed over: inside another window %d, too small %d, before the skin arrived %d")
        :format(stats.watched, stats.notTop, stats.small, stats.waiting))
    local style = EdgeStyle()
    Print(("edges: %s, style %s, size %s%s, on %d item buttons, HUD elements and bars (HUD hook %s)"):format(
        db.edgeMode == "actionbars" and (ActionBarBorder() and "copied from your action bar" or
            "|cfff87171action bar settings not found, plain edge|r") or "plain",
        tostring(style.texture), tostring(style.size), style.px and (" (" .. style.px .. " px)") or "",
        edgeCount, hooks.hud and yes or no))
    Print(("EllesmereUI windows: %s, hook %s, bordered so far %d"):format(OnOff(db.euiWindows),
        hooks.euiWindows and yes or no, euiCount))
    if lastError then Print("|cfff87171last error:|r " .. lastError) end
    if not skin then
        Print("No window skin: check that Blizz UI Enhanced (EllesmereUIBlizzardSkin) is enabled and that "
            .. "Third-Party Addons skinning is on under Blizzard Skins+ > Window Skins.")
    end
    if ns then
        Print(("Naowh look: %s"):format(ns.foreverSkin and "Forever (metal) - skin is off" or "Naowh (flat)"))
        local T = ns.THEME
        Print(("palette: bg #%s, panel #%s, line #%s, text #%s, muted #%s, accent #%s"):format(
            Hex(T.bg), Hex(T.panel), Hex(T.line), Hex(T.fg), Hex(T.muted), Hex(T.accent)))
        Print("font: " .. tostring(ns.UIFontPath and ns.UIFontPath()))
    end
    local ok, accent = pcall(Accent)
    if ok then Print("EllesmereUI accent: #" .. Hex(accent)) end
    if not all then
        Print("/nfeui debug all - also list every Naowh frame the skin has looked at")
        return
    end
    for frame, state in pairs(seen) do
        local name = frame.GetDebugName and frame:GetDebugName() or tostring(frame)
        local w, h = frame:GetSize()
        local status = shelled[frame] and "|cff4ade80window skin|r"
            or state == "skip" and "inside another window"
            or edged[frame] and "|cff4ade80edge|r"
            or (w < MIN_W or h < MIN_H) and "too small"
            or frame:IsVisible() and "not skinned" or "not opened yet"
        Print(("  %s  %dx%d  %s"):format(name, w, h, status))
    end
end

local function NeedsReload(text)
    Print(text .. " Type /reload to see it.")
end

SLASH_NAOWHELLESMERESKIN1 = "/nfeui"
SlashCmdList.NAOWHELLESMERESKIN = function(msg)
    local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
    if SWITCHES[cmd] then
        local switch = SWITCHES[cmd]
        db[switch[1]] = not db[switch[1]]
        NeedsReload(db[switch[1]] and switch[2] or switch[3])
    elseif SETTINGS[cmd] then
        local n = tonumber(arg)
        if not n or n < 0 or n > PERCENT then
            Print("Give a number from 0 to 100, for example /nfeui " .. cmd .. " 20")
            return
        end
        n = math.floor(n + 0.5)
        db[SETTINGS[cmd]] = n
        NeedsReload(("%s strength set to %d%%."):format(SETTING_NAMES[cmd], n))
    elseif cmd == "edge" then
        if arg == "bars" then
            db.edgeMode = "actionbars"
            NeedsReload("Edges copy your EllesmereUI action bar border.")
            return
        end
        local n = tonumber(arg)
        if not n or n < 0 or n > EDGE_MAX then
            Print("/nfeui edge bars - copy your EllesmereUI action bar border (Pixels and the rest)")
            Print("/nfeui edge <0-" .. EDGE_MAX .. "> - a plain black edge of that many pixels instead (0 = off)")
            return
        end
        db.edgeMode, db.edgeSize = "solid", math.floor(n + 0.5)
        NeedsReload(db.edgeSize == 0 and "Edges off." or ("Plain %d px edges."):format(db.edgeSize))
    elseif cmd == "debug" then
        Debug(arg == "all")
    elseif cmd == "reset" then
        NS.Config:Reset()
        NeedsReload("Settings reset.")
    else
        Status()
    end
end

-------------------------------------------------------------------------------
--  Native settings panel. It is registered once and built only when opened.
--  Changes are saved immediately and applied on /reload, avoiding frame walks or
--  protected UI changes while the player is configuring the addon.
-------------------------------------------------------------------------------
local settingsPanel, settingsCategoryID, settingsBuilt, settingsUpdating
local settingsControls = {}
local settingsNotice
local settingsControlSerial = 0

local function SettingsControlName(kind)
    settingsControlSerial = settingsControlSerial + 1
    return ADDON .. kind .. settingsControlSerial
end

local function MarkSettingsChanged()
    if settingsNotice then settingsNotice:SetText("Changes saved. Reload the UI to apply them.") end
end

local function SettingsTooltip(control, text)
    if not text then return end
    control:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- The one-argument form works with both legacy RGB and modern ColorMixin signatures.
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    control:HookScript("OnLeave", GameTooltip_Hide)
end

local function AddSettingsCheck(parent, label, key, y, tooltip, setter, x)
    local name = SettingsControlName("Check")
    local check = CreateFrame("CheckButton", name, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("TOPLEFT", x or 16, y)
    check.Text = check.Text or _G[name .. "Text"]
    check.Text:SetText(label)
    check:SetScript("OnClick", function(self)
        if settingsUpdating then return end
        if setter then setter(self:GetChecked()) else db[key] = not not self:GetChecked() end
        MarkSettingsChanged()
    end)
    SettingsTooltip(check, tooltip)
    settingsControls[key] = check
    return check
end

local function AddSettingsSlider(parent, label, key, y, minValue, maxValue, step)
    local name = SettingsControlName("Slider")
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 24, y)
    slider:SetWidth(260)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider.Text = slider.Text or _G[name .. "Text"]
    slider.Low = slider.Low or _G[name .. "Low"]
    slider.High = slider.High or _G[name .. "High"]
    slider.Text:SetText(label)
    slider.Low:SetText(tostring(minValue))
    slider.High:SetText(tostring(maxValue))
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        self.Text:SetText(("%s: %d"):format(label, value))
        if settingsUpdating then return end
        db[key] = value
        MarkSettingsChanged()
    end)
    settingsControls[key] = slider
    return slider
end

local function RefreshSettings()
    if not settingsBuilt then return end
    settingsUpdating = true
    settingsControls.useFont:SetChecked(db.useFont)
    settingsControls.useColors:SetChecked(db.useColors)
    settingsControls.useShell:SetChecked(db.useShell)
    settingsControls.itemPlates:SetChecked(db.itemPlates)
    settingsControls.useEdges:SetChecked(db.useEdges)
    settingsControls.windowBorders:SetChecked(db.windowBorders)
    settingsControls.genericBorders:SetChecked(db.genericBorders)
    settingsControls.itemBorders:SetChecked(db.itemBorders)
    settingsControls.hudBorders:SetChecked(db.hudBorders)
    settingsControls.auraBorders:SetChecked(db.auraBorders)
    settingsControls.focusCastBorder:SetChecked(db.focusCastBorder)
    settingsControls.gcdBorders:SetChecked(db.gcdBorders)
    settingsControls.topBarBorders:SetChecked(db.topBarBorders)
    settingsControls.edgeMode:SetChecked(db.edgeMode == "actionbars")
    settingsControls.euiWindows:SetChecked(db.euiWindows)
    settingsControls.edgeSize:SetValue(db.edgeSize)
    settingsControls.borderAlpha:SetValue(db.borderAlpha)
    settingsControls.buttonBorderAlpha:SetValue(db.buttonBorderAlpha)
    settingsControls.edgeColor.swatch:SetColorTexture(db.edgeR, db.edgeG, db.edgeB, 1)
    settingsUpdating = false
end

local function OpenEdgeColor()
    local oldR, oldG, oldB = db.edgeR, db.edgeG, db.edgeB
    local function Apply()
        db.edgeR, db.edgeG, db.edgeB = ColorPickerFrame:GetColorRGB()
        settingsControls.edgeColor.swatch:SetColorTexture(db.edgeR, db.edgeG, db.edgeB, 1)
        MarkSettingsChanged()
    end
    local function Cancel()
        db.edgeR, db.edgeG, db.edgeB = oldR, oldG, oldB
        settingsControls.edgeColor.swatch:SetColorTexture(oldR, oldG, oldB, 1)
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = oldR, g = oldG, b = oldB, hasOpacity = false,
            swatchFunc = Apply, cancelFunc = Cancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = Apply
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame:SetColorRGB(oldR, oldG, oldB)
        ColorPickerFrame:Show()
    end
end

local function BuildSettings()
    if settingsBuilt then return end
    settingsBuilt = true
    local panel = settingsPanel

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Naowh Ellesmere Skin")
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("Lightweight visual integration for Naowh Forever and EllesmereUI")

    local appearance = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    appearance:SetPoint("TOPLEFT", 16, -66)
    appearance:SetText("Appearance")
    AddSettingsCheck(panel, "Use EllesmereUI font", "useFont", -84,
        "Use EllesmereUI's selected font in Naowh Forever.")
    AddSettingsCheck(panel, "Use EllesmereUI colors", "useColors", -110,
        "Apply EllesmereUI's palette and accent colors.")
    AddSettingsCheck(panel, "Use EllesmereUI window shells", "useShell", -136,
        "Apply EllesmereUI backdrops to supported Naowh windows.")
    AddSettingsCheck(panel, "Dark item-button plates", "itemPlates", -162,
        "Place a dark slot behind supported item buttons.")

    local borders = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    borders:SetPoint("TOPLEFT", 16, -202)
    borders:SetText("Borders")
    AddSettingsCheck(panel, "Enable custom borders", "useEdges", -220,
        "Enable EllesmereUI-style borders on supported frames.")
    AddSettingsCheck(panel, "Copy main action-bar border style", "edgeMode", -246,
        "When disabled, use the custom solid thickness and color below.", function(checked)
            db.edgeMode = checked and "actionbars" or "solid"
        end)
    AddSettingsSlider(panel, "Custom border thickness", "edgeSize", -288, 0, EDGE_MAX, 1)

    local color = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    color:SetPoint("TOPLEFT", 16, -336)
    color:SetSize(180, 24)
    color:SetText("Custom border color")
    color:SetScript("OnClick", OpenEdgeColor)
    color.swatch = color:CreateTexture(nil, "OVERLAY")
    color.swatch:SetPoint("LEFT", color, "RIGHT", 8, 0)
    color.swatch:SetSize(22, 22)
    settingsControls.edgeColor = color

    AddSettingsSlider(panel, "Divider strength", "borderAlpha", -386, 0, PERCENT, 1)
    AddSettingsSlider(panel, "Button-border strength", "buttonBorderAlpha", -438, 0, PERCENT, 1)

    local components = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    components:SetPoint("TOPLEFT", 360, -66)
    components:SetText("Skinned Components")
    AddSettingsCheck(panel, "Naowh window borders", "windowBorders", -84,
        "Skin borders on Naowh windows that use the EllesmereUI shell.", nil, 360)
    AddSettingsCheck(panel, "General element borders", "genericBorders", -110,
        "Skin other supported Naowh buttons, bars, and outlined elements.", nil, 360)
    AddSettingsCheck(panel, "Item-button borders", "itemBorders", -136,
        "Skin borders on consumable and other item-bar buttons.", nil, 360)
    AddSettingsCheck(panel, "HUD and tracker borders", "hudBorders", -162,
        "Skin supported HUD cards, timers, trackers, and status elements.", nil, 360)
    AddSettingsCheck(panel, "PvP and Raid aura borders", "auraBorders", -188,
        "Skin Shared.AuraIcon buttons during their safe initialization phase.", nil, 360)
    AddSettingsCheck(panel, "Focus cast-bar border", "focusCastBorder", -214,
        "Use one joined border around the focus cast bar and icon.", nil, 360)
    AddSettingsCheck(panel, "GCD tracker borders", "gcdBorders", -240,
        "Skin dynamically pooled GCD tracker icons.", nil, 360)
    AddSettingsCheck(panel, "Top-bar group borders", "topBarBorders", -266,
        "Skin the left, center, and right top-bar groups.", nil, 360)

    local integrations = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    integrations:SetPoint("TOPLEFT", 360, -306)
    integrations:SetText("Integrations")
    AddSettingsCheck(panel, "Border EllesmereUI windows", "euiWindows", -324,
        "Match supported EllesmereUI and Blizzard windows to Naowh borders.", nil, 360)

    local enableAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    enableAll:SetPoint("TOPLEFT", 360, -366)
    enableAll:SetSize(115, 24)
    enableAll:SetText("Enable All")
    enableAll:SetScript("OnClick", function()
        NS.Config:SetAll(true)
        RefreshSettings()
        MarkSettingsChanged()
    end)

    local disableAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    disableAll:SetPoint("LEFT", enableAll, "RIGHT", 8, 0)
    disableAll:SetSize(115, 24)
    disableAll:SetText("Disable All")
    disableAll:SetScript("OnClick", function()
        NS.Config:SetAll(false)
        RefreshSettings()
        MarkSettingsChanged()
    end)

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetPoint("TOPLEFT", 360, -402)
    reset:SetSize(140, 24)
    reset:SetText("Reset to Defaults")
    reset:SetScript("OnClick", function()
        NS.Config:Reset()
        RefreshSettings()
        MarkSettingsChanged()
    end)

    local reload = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reload:SetPoint("LEFT", reset, "RIGHT", 10, 0)
    reload:SetSize(100, 24)
    reload:SetText("Reload UI")
    reload:SetScript("OnClick", ReloadUI)

    settingsNotice = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    settingsNotice:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -14)
    settingsNotice:SetText("Settings are applied after a UI reload.")
    RefreshSettings()
end

local function RegisterSettings()
    if settingsPanel then return end
    local panel = CreateFrame("Frame")
    panel.name = "Naowh Ellesmere Skin"
    panel:SetScript("OnShow", function()
        BuildSettings()
        RefreshSettings()
    end)
    settingsPanel = panel
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
        settingsCategoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

local function OpenSettings()
    RegisterSettings()
    if Settings and Settings.OpenToCategory and settingsCategoryID then
        Settings.OpenToCategory(settingsCategoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
        InterfaceOptionsFrame_OpenToCategory(settingsPanel)
    end
end

-- Keep the addon completely inert when Naowh Forever is disabled.  The settings page and slash
-- command remain available, but no skin hooks, frame scans, callbacks or delayed work are installed
-- until Naowh Forever has actually produced its namespace.
local function Activate()
    if installed then return true end
    Install()
    if not installed then return false end

    local okHook, errHook = pcall(HookEllesmereWindows)
    if not okHook then lastError = tostring(errHook) end
    return true
end

NS.Settings = {
    Open = OpenSettings,
    Register = RegisterSettings,
}

NS.Runtime = {}

function NS.Runtime:OnPlayerLogin()
    if db and db.useEdges and (installed or db.euiWindows) then
        -- One frame later, so EllesmereUI's action bars have finished their own login setup.
        C_Timer.After(0, FlushEdges)
    else
        edgesReady = true
    end
    if installed and foreverSkinSeen then
        Print("Naowh Forever is using its metal \"Forever\" look, so the EllesmereUI skin is off. "
            .. "Pick the \"Naowh\" look in Naowh Forever's settings to use it.")
    end
end

function NS.Runtime:OnAddonLoaded(name)
    if name == ADDON then
        LoadDB()
        RegisterSettings()
        -- EllesmereUI-window borders are an independent integration and remain available even
        -- when Naowh Forever is disabled. The hook is idempotent and gated by its own setting.
        local okHook, errHook = pcall(HookEllesmereWindows)
        if not okHook then lastError = tostring(errHook) end
        if C_AddOns.IsAddOnLoaded(NAOWH) then
            naowhFirst = not installed
            Activate()
        end
        if installed and C_AddOns.IsAddOnLoaded(NAOWH_COMBAT) then HookAuraIcons() end
    elseif name == NAOWH then
        if not db then LoadDB() end
        Activate()
    elseif name == NAOWH_COMBAT then
        if installed then HookAuraIcons() end
    elseif name == BLIZZARD_SKIN then
        local okHook, errHook = pcall(HookEllesmereWindows)
        if not okHook then lastError = tostring(errHook) end
    end
end
