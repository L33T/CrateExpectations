-- Crate Expectations: the case-opening screen.
-- A full-screen takeover in three acts:
--   1. Pre-pull: the box floats over a slowly turning halo, with its card count and odds.
--   2. Opening: the box charges up while a colour tell shows the best tier inside (it can
--      "upgrade" mid-charge), bursts, and deals face-down cards; Rare+ cards glow through
--      their backs. Cards flip on click or with "Reveal all"; Epic+ cards get a solo cinematic.
--      Single-item boxes use a spinning reel instead of cards.
--   3. Summary: banner for the best pull, coins count up, Collect / Open again.
-- Rarity visuals come from Core's custom tiers (ns.TierOf), not item quality.

local _, ns = ...

local UI = {}
ns.UI = UI

local FX -- ns.FX (Effects.lua), picked up at build time

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sin, cos, pi, random = math.sin, math.cos, math.pi, math.random

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STAR = "Interface\\Cooldown\\star4"
local DUST = "Interface\\Icons\\INV_Enchant_DustStrange"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local MAIN_W, MAIN_H = 960, 640
local STAGE_W, STAGE_H = 920, 330
local CARD_W, CARD_H, CARD_GAP = 124, 186, 18
local FLIP = 0.3
local TILE, STEP = 92, 102
local REEL_TILES, TARGET = 60, 52
local REEL_H = 138
local CELL_W, CELL_H = 74, 66 -- (tile + its drop chance underneath)
local ODDS_H, ODDS_HEAD = 560, 44
local SHOW_SCALE, SHOW_Y = 1.7, 30
local GOLD_R, GOLD_G, GOLD_B = 1, 0.78, 0.32
local CAST_W = 220            -- a world chest's opening bar
local AUTO_COLLECT_DELAY = 1.2 -- seconds between the summary and auto-collect
local DEMO_CAST = 3.2         -- seconds the demo pretends the opening cast takes

local EMPTY_TEXT = {
    "Just dust", "Cobwebs", "A moth flew out", "Pocket lint", "An IOU from the last owner",
    "Absolutely nothing", "A very old smell", "Crumbs", "Someone's lost button", "Air. Premium air.",
}
local EMPTY_TEXT_WET = {
    "Seaweed", "Wet sand", "A crab (it left)", "Pond water", "Fish scales", "Barnacles",
}
local EMPTY_TEXT_SCROLL = {
    "A blank page", "Smudged ink", "A doodle of a sheep", "Someone's grocery list", "Mana-stained parchment",
    "An overdue library notice",
}
local SCROLLS = { [277651] = true }
-- the line over a world chest's opening bar, one per opening
local CHEST_LINES = {
    "Prying it open...", "Jiggling the lid...", "Something rattles inside...", "Creeeeeak...",
    "Blowing off the dust...", "It's stuck. Of course it's stuck.", "Lifting the lid...",
    "Checking for mimics...",
}
local EMPTY_TEXT_CHEST = {
    "Cobwebs", "A spider (it's staying)", "A very old smell", "Moth wings", "Rusty nails", "Splinters",
    "A note: \"Gone fishing\"", "Rat droppings. Lovely.",
}
local WET = { [20708] = true, [21113] = true, [21150] = true, [21228] = true, [6351] = true, [6352] = true,
    [6357] = true, [13874] = true, [5523] = true, [5524] = true, [7973] = true, [15874] = true }

---------------------------------------------------------------------------
-- Tiers (Core provides ns.TierOf / ns.TierColor / ns.TIERS; fall back to item quality)
---------------------------------------------------------------------------

local TIER_FALLBACK = {
    [0] = { "Dust", 0.45, 0.45, 0.48 },
    { "Common", 0.80, 0.80, 0.84 },
    { "Uncommon", 0.30, 0.90, 0.40 },
    { "Rare", 0.25, 0.60, 1.00 },
    { "Epic", 0.72, 0.35, 1.00 },
    { "Legendary", 1.00, 0.60, 0.12 },
}

local function ClampTier(t)
    t = floor((tonumber(t) or 1) + 0.5)
    -- 6 = Elusive (not on the box's loot list), 7 = Heirloom (an item the player is hunting)
    if t < 1 then return 1 elseif t > 7 then return 7 end
    return t
end

local function TierFor(containerID, itemID, quality)
    if ns.TierOf and itemID then
        local ok, t = pcall(ns.TierOf, containerID, itemID, quality)
        if ok and t then return ClampTier(t) end
    end
    return ClampTier(quality or 1)
end

-- tier -1 is the neutral gold used before anything is known
local function TierColor(t)
    if t and t < 0 then return GOLD_R, GOLD_G, GOLD_B end
    if t and t >= 1 then
        if ns.TierColor then
            local ok, r, g, b = pcall(ns.TierColor, t)
            if ok and type(r) == "number" then return r, g, b end
        end
        local e = ns.TIERS and ns.TIERS[t]
        if e and e.r then return e.r, e.g, e.b end
    end
    local d = TIER_FALLBACK[t or 0] or TIER_FALLBACK[1]
    return d[2], d[3], d[4]
end

local function TierLabel(t)
    if t and t >= 1 and ns.TIERS and ns.TIERS[t] and ns.TIERS[t].label then return ns.TIERS[t].label end
    local d = TIER_FALLBACK[t or 0] or TIER_FALLBACK[1]
    return d[1]
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Hex(r, g, b)
    return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

-- returns true if something was asked to play
local function Sound(kit, fallback)
    if not ns.db or not ns.db.sound then return true end
    local id = (SOUNDKIT and kit and SOUNDKIT[kit]) or fallback
    if not id then return false end
    pcall(PlaySound, id, "SFX")
    return true
end

local function TierSound(t)
    if t <= 0 then
        Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
    elseif t == 1 then
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    elseif t == 2 then
        Sound("IG_QUEST_LIST_COMPLETE", 878)
    elseif t == 3 then
        Sound("READY_CHECK", 8960)
        Sound("IG_QUEST_LIST_COMPLETE", 878)
    elseif t == 4 then
        Sound("UI_EPICLOOT_TOAST", 888)
        Sound("READY_CHECK", 8960)
    else
        Sound("UI_LEGENDARY_LOOT_TOAST")
        Sound("UI_EPICLOOT_TOAST", 888)
        Sound("READY_CHECK", 8960)
    end
end

local function Clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 end
    return x
end
local function EaseOut2(x) return 1 - (1 - x) * (1 - x) end
local function EaseOut4(x) local y = 1 - x return 1 - y * y * y * y end
local function EaseOutBack(x)
    local c1 = 1.70158
    local c3 = c1 + 1
    local y = x - 1
    return 1 + c3 * y * y * y + c1 * y * y
end

local function SpeedScale()
    local s = (ns.db and ns.db.spinTime or 5) / 5
    if s < 0.4 then return 0.4 elseif s > 2 then return 2 end
    return s
end

local function PctText(p)
    if p >= 10 then return ("%.0f%%"):format(p) end
    if p >= 1 then return ("%.1f%%"):format(p) end
    return ("%.2f%%"):format(p)
end

local CA, CB
local function Grad(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    if CreateColor and tex.SetGradient then
        if not CA then CA, CB = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0) end
        CA:SetRGBA(r1, g1, b1, a1)
        CB:SetRGBA(r2, g2, b2, a2)
        if pcall(tex.SetGradient, tex, orient, CA, CB) then return end
    end
    tex:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

local function NewTex(parent, layer, sub, blend)
    local t = parent:CreateTexture(nil, layer, nil, sub or 0)
    t:SetTexture(WHITE)
    if blend then t:SetBlendMode(blend) end
    return t
end

-- Soft glow around a frame. Normally two layers of the game's round soft-glow texture, stretched into an
-- oval a bit bigger than the frame: smooth all the way round, no visible edges or corners. If that texture
-- is missing, it falls back to stacked rectangles (smooth-ish, but square). The colour's alpha is baked
-- into each layer and the layers are hidden at zero, because region alpha alone doesn't reliably hide them
-- on this client. Draw it BEHIND the anchor (owner's lower layer or a lower frame level).
local SOFT_GLOW = "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64"
-- { scale of the frame, extra per side in units of `size`, strength }
local SOFT_LAYERS = { { 1.35, 1.6, 0.85 }, { 1.8, 3.6, 0.5 } }
local GLOW_LAYERS = 6

local function SizeSoftGlow(g)
    local w, h = g.anchor:GetWidth() or 0, g.anchor:GetHeight() or 0
    for i, L in ipairs(SOFT_LAYERS) do
        g[i]:SetSize(max(1, w * L[1] + 2 * g.size * L[2]), max(1, h * L[1] + 2 * g.size * L[2]))
    end
end

local function CreateEdgeGlow(owner, anchor, size, layer)
    local g = { r = 1, g = 0.8, b = 0.4, a = -1, anchor = anchor, size = size }
    local probe = owner:CreateTexture(nil, layer or "BACKGROUND", nil, 0)
    if probe:SetTexture(SOFT_GLOW) ~= false then
        g.soft = true
        -- frames report size changes, so the oval follows them; a texture anchor (the box border) can't,
        -- so it gets fixed margins instead
        local dynamic = anchor.IsObjectType ~= nil and anchor:IsObjectType("Frame")
        for i = 1, #SOFT_LAYERS do
            local t = i == 1 and probe or owner:CreateTexture(nil, layer or "BACKGROUND", nil, 0)
            t:SetTexture(SOFT_GLOW)
            t:SetBlendMode("ADD")
            if dynamic then
                t:SetPoint("CENTER", anchor, "CENTER")
            else
                local d = size * (SOFT_LAYERS[i][2] + 1.4)
                t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -d, d)
                t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", d, -d)
            end
            t:Hide()
            g[i] = t
        end
        if dynamic then
            SizeSoftGlow(g)
            anchor:HookScript("OnSizeChanged", function() SizeSoftGlow(g) end)
        end
        return g
    end
    probe:Hide()
    for i = 1, GLOW_LAYERS do
        local t = owner:CreateTexture(nil, layer or "BACKGROUND", nil, 0)
        t:SetTexture(WHITE)
        t:SetBlendMode("ADD")
        local d = size * i / GLOW_LAYERS
        t:SetPoint("TOPLEFT", anchor, "TOPLEFT", -d, d)
        t:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", d, -d)
        t:Hide()
        g[i] = t
    end
    return g
end

local function ApplyGlow(g)
    local a = g.a
    local n = g.soft and #SOFT_LAYERS or GLOW_LAYERS
    if a <= 0.01 then
        for i = 1, n do g[i]:Hide() end
        return
    end
    for i = 1, n do
        local t = g[i]
        -- soft: per-layer strength; square fallback: outer layers fainter, stacked (ADD) ~linear falloff
        t:SetVertexColor(g.r, g.g, g.b, g.soft and min(1, a * SOFT_LAYERS[i][3]) or (a * 0.9 / GLOW_LAYERS))
        t:Show()
    end
end

local function EdgeGlowColor(g, r, gg, b)
    g.r, g.g, g.b = r, gg, b
    if g.a > 0.01 then ApplyGlow(g) end
end

local function EdgeGlowAlpha(g, a)
    if math.abs(a - g.a) < 0.004 then return end
    g.a = a
    ApplyGlow(g)
end

local function MakePop(region, from, dur)
    local ag = region:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale")
    if s.SetScaleFrom then
        s:SetScaleFrom(from, from)
        s:SetScaleTo(1, 1)
    else
        s:SetFromScale(from, from)
        s:SetToScale(1, 1)
    end
    s:SetDuration(dur)
    s:SetSmoothing("OUT")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(dur * 0.5)
    if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
    ag:SetScript("OnFinished", function() region:SetAlpha(1) end)
    ag:SetScript("OnStop", function() region:SetAlpha(1) end)
    ag.region = region
    return ag
end

-- Start the pop invisible: otherwise the text shows at full size for a frame before the animation's
-- first update, which reads as the animation playing twice.
local function PlayPop(ag)
    ag:Stop()
    ag.region:SetAlpha(0)
    ag:Play()
end

local function ShowItemTooltip(owner, itemID, extra)
    if not itemID or itemID <= 0 then return end -- (world chests have negative ids: not items)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    if extra then
        for _, line in ipairs(extra) do GameTooltip:AddLine(line, 1, 0.82, 0.3) end
    end
    GameTooltip:Show()
end

local function MakeButton(parent, w, h, text, size)
    local b = CreateFrame("Button", nil, parent, BACKDROP)
    b:SetSize(w, h)
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b:SetBackdropColor(0.08, 0.06, 0.11, 0.95)
        b:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    b.fill = NewTex(b, "ARTWORK", 0)
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    Grad(b.fill, "VERTICAL", 0.4, 0.26, 0.06, 0, 0.4, 0.26, 0.06, 0.45)
    b.hl = NewTex(b, "HIGHLIGHT", 0, "ADD")
    b.hl:SetAllPoints(b.fill)
    Grad(b.hl, "VERTICAL", 1, 0.8, 0.4, 0.05, 1, 0.8, 0.4, 0.25)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(FONT, size or 13, "OUTLINE")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetTextColor(1, 0.86, 0.5)
    b.text:SetText(text or "")
    -- glow on its own frame one level below the button, so it surrounds the button instead of tinting it
    local gh = CreateFrame("Frame", nil, parent)
    gh:SetAllPoints(b)
    gh:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    b.glowHolder = gh
    b.glow = CreateEdgeGlow(gh, b, 10, "BACKGROUND")
    EdgeGlowColor(b.glow, 1, 0.7, 0.25)
    EdgeGlowAlpha(b.glow, 0)
    b:SetScript("OnEnable", function(self) self.text:SetTextColor(1, 0.86, 0.5) end)
    b:SetScript("OnDisable", function(self) self.text:SetTextColor(0.45, 0.42, 0.38) end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.text:SetPoint("CENTER", 1, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.text:SetPoint("CENTER", 0, 0) end)
    b.SetLabel = function(self, t) self.text:SetText(t) end
    return b
end

-- (Elusive, tier 6, shows the full five stars in its own colour)
local function LayoutStars(stars, n, size, gap, anchor, point, x, y)
    n = min(n, #stars)
    local total = n * size + (n - 1) * gap
    for i = 1, #stars do
        local s = stars[i]
        s:Hide()
        s:ClearAllPoints()
        if i <= n then
            s:SetPoint("CENTER", anchor, point, x - total / 2 + size / 2 + (i - 1) * (size + gap), y)
            s:SetSize(size, size)
        end
    end
end

local function PopStars(stars, n, size, step, sound)
    local tierN = n
    n = min(n, #stars)
    for i = 1, n do
        local s = stars[i]
        if tierN >= 7 then s:SetVertexColor(1, 0.25, 0.28)        -- Heirloom: red
        elseif tierN >= 6 then s:SetVertexColor(0.35, 1, 0.88)    -- Elusive: teal
        else s:SetVertexColor(1, 0.85, 0.35) end
        FX:After(step * (i - 1), function()
            s:Show()
            if sound then Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) end
            FX:Tween(0.25, function(k)
                local z = size * (1 + 1.2 * (1 - EaseOut2(k)))
                s:SetSize(z, z)
                s:SetAlpha(k)
            end)
        end)
    end
end

local function MakeStars(parent, layer)
    local t = {}
    for i = 1, 5 do
        local s = parent:CreateTexture(nil, layer or "OVERLAY")
        s:SetTexture(STAR)
        s:SetBlendMode("ADD")
        s:Hide()
        t[i] = s
    end
    return t
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------

local f

-- the big word under the stage; one wording for a tier everywhere, and it only pops when it changes
-- (the reel shows it on landing, the summary would otherwise pop the same word again)
local function BannerText(t)
    if (t or 1) <= 1 then return TierLabel(1) end
    if t >= 7 then return "HEIRLOOM!!!" end
    if t >= 6 then return "ELUSIVE!" end
    return TierLabel(t):upper() .. ("!"):rep(t - 1)
end

local function SetBanner(text, r, g, b)
    f.banner:SetTextColor(r, g, b)
    if f.banner:GetText() == text then return end
    f.banner:SetText(text)
    PlayPop(f.bannerAnim)
end

-- centre of a frame relative to the centre of ref, in ref's units
local function RelPos(frame, ref)
    local x, y = frame:GetCenter()
    local rx, ry = ref:GetCenter()
    if not x or not rx then return 0, 0 end
    local s, rs = frame:GetEffectiveScale(), ref:GetEffectiveScale()
    return x * s / rs - rx, y * s / rs - ry
end

local function FxPos(frame)
    return RelPos(frame, f.fx)
end

---------------------------------------------------------------------------
-- Small item tiles (reel, results row, odds grid)
---------------------------------------------------------------------------

local function CreateTile(parent, size, withName)
    local t = CreateFrame("Frame", nil, parent, BACKDROP)
    t:SetSize(size, withName and size + 20 or size)
    if t.SetBackdrop then
        t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        t:SetBackdropColor(0.07, 0.065, 0.09, 1)
    end
    t.shine = NewTex(t, "BACKGROUND", 1)
    t.shine:SetPoint("BOTTOMLEFT", 1, 1)
    t.shine:SetPoint("TOPRIGHT", -1, -1)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    local isz = floor(size * 0.62)
    t.icon:SetSize(isz, isz)
    t.icon:SetPoint("TOP", 0, -floor(size * 0.1))
    t.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    t.count = t:CreateFontString(nil, "OVERLAY")
    t.count:SetFont(FONT, size >= 60 and 13 or 10, "OUTLINE")
    t.count:SetPoint("BOTTOMRIGHT", t.icon, "BOTTOMRIGHT", 2, 0)

    t.bar = t:CreateTexture(nil, "ARTWORK")
    t.bar:SetHeight(3)
    t.bar:SetPoint("BOTTOMLEFT", 1, 1)
    t.bar:SetPoint("BOTTOMRIGHT", -1, 1)

    if withName then
        t.name = t:CreateFontString(nil, "OVERLAY")
        t.name:SetFont(FONT, 9, "")
        t.name:SetPoint("TOPLEFT", t.icon, "BOTTOMLEFT", -10, -3)
        t.name:SetPoint("TOPRIGHT", t.icon, "BOTTOMRIGHT", 10, -3)
        t.name:SetHeight(24)
        t.name:SetJustifyV("TOP")
        t.name:SetWordWrap(true)
    end

    t.flash = NewTex(t, "OVERLAY", 7, "ADD")
    t.flash:SetAllPoints()
    t.flash:SetAlpha(0)
    t.flash:Hide()
    return t
end

local function SetTile(t, d, containerID)
    if not d.tier then d.tier = TierFor(containerID, d.itemID, d.quality) end
    local r, g, b = TierColor(d.tier)
    t.icon:SetTexture(d.icon or ns.ItemIcon(d.itemID or 0))
    t.bar:SetColorTexture(r, g, b, 1)
    Grad(t.shine, "VERTICAL", r, g, b, d.tier >= 3 and 0.35 or 0.12, r, g, b, 0)
    if t.SetBackdropBorderColor then t:SetBackdropBorderColor(r * 0.7, g * 0.7, b * 0.7, 1) end
    t.count:SetText((d.count and d.count > 1) and d.count or "")
    if t.name then
        t.name:SetText(d.name or "")
        t.name:SetTextColor(ns.QualityColor(d.quality or 1))
    end
    t.data = d
    -- a flash cut off mid-fade (the screen closed during it) must not stay on the tile's next item
    t.flash:SetAlpha(0)
    t.flash:Hide()
end

local function FlashTile(t, r, g, b)
    t.flash:SetVertexColor(r, g, b)
    t.flash:SetAlpha(0.9)
    t.flash:Show()
    FX:Tween(0.8, function(k)
        t.flash:SetAlpha(0.9 * (1 - k))
        if k >= 1 then t.flash:Hide() end
    end)
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------

local function PlaceCard(c)
    local s = c.s
    if s < 0.05 then s = 0.05 end
    c:SetScale(s)
    c:SetPoint("CENTER", c.anchor, "CENTER", c.x / s, c.y / s)
end

local function CreateCard(parent, level)
    local c = CreateFrame("Button", nil, parent)
    if level then c:SetFrameLevel(level) end
    c:SetSize(CARD_W, CARD_H)
    c.x, c.y, c.s = 0, 0, 1
    c.anchor = parent
    c.cw, c.ch = CARD_W, CARD_H

    local inner = CreateFrame("Frame", nil, c, BACKDROP)
    inner:SetPoint("TOP")
    inner:SetPoint("BOTTOM")
    inner:SetWidth(CARD_W)
    if inner.SetBackdrop then
        inner:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
        inner:SetBackdropColor(0.05, 0.04, 0.07, 1)
    end
    if inner.SetClipsChildren then inner:SetClipsChildren(true) end
    c.inner = inner

    c.glow = CreateEdgeGlow(c, inner, 18, "BACKGROUND")
    EdgeGlowAlpha(c.glow, 0)

    -- back
    local back = CreateFrame("Frame", nil, inner)
    back:SetAllPoints()
    c.back = back
    c.backBg = NewTex(back, "BACKGROUND", 0)
    c.backBg:SetPoint("TOPLEFT", 2, -2)
    c.backBg:SetPoint("BOTTOMRIGHT", -2, 2)
    Grad(c.backBg, "VERTICAL", 0.05, 0.04, 0.09, 1, 0.17, 0.12, 0.24, 1)
    c.backTint = NewTex(back, "BACKGROUND", 2, "ADD")
    c.backTint:SetAllPoints(c.backBg)
    c.backTint:SetAlpha(0)
    c.backTint:Hide()
    c.backStar = back:CreateTexture(nil, "BORDER")
    c.backStar:SetTexture(STAR)
    c.backStar:SetBlendMode("ADD")
    c.backStar:SetPoint("CENTER", 0, 6)
    local inset = CreateFrame("Frame", nil, back, BACKDROP)
    inset:SetPoint("TOPLEFT", 7, -7)
    inset:SetPoint("BOTTOMRIGHT", -7, 7)
    if inset.SetBackdrop then
        inset:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
        inset:SetBackdropBorderColor(0.78, 0.6, 0.24, 0.45)
    end
    c.emblemBorder = back:CreateTexture(nil, "ARTWORK", nil, 0)
    c.emblemBorder:SetColorTexture(0, 0, 0, 0.85)
    c.emblemBorder:SetPoint("CENTER", 0, 6)
    c.emblem = back:CreateTexture(nil, "ARTWORK", nil, 1)
    c.emblem:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.emblem:SetPoint("CENTER", 0, 6)
    c.emblem:SetAlpha(0.8)
    c.backMark = back:CreateFontString(nil, "OVERLAY")
    c.backMark:SetFont(FONT, 18, "OUTLINE")
    c.backMark:SetPoint("BOTTOM", 0, 14)
    c.backMark:SetTextColor(1, 0.78, 0.3, 0.75)
    c.backMark:SetText("?")

    -- face
    local face = CreateFrame("Frame", nil, inner)
    face:SetAllPoints()
    face:Hide()
    c.face = face
    c.faceBg = NewTex(face, "BACKGROUND", 0)
    c.faceBg:SetPoint("TOPLEFT", 2, -2)
    c.faceBg:SetPoint("BOTTOMRIGHT", -2, 2)
    c.iconBorder = face:CreateTexture(nil, "BORDER", nil, 1)
    c.iconBorder:SetColorTexture(1, 1, 1, 1)
    c.icon = face:CreateTexture(nil, "ARTWORK")
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.faceRays = face:CreateTexture(nil, "BORDER", nil, 0)
    c.faceRays:SetTexture(STAR)
    c.faceRays:SetBlendMode("ADD")
    c.faceRays:SetPoint("CENTER", c.icon, "CENTER", 0, 0)
    c.count = face:CreateFontString(nil, "OVERLAY")
    c.count:SetFont(FONT, 14, "OUTLINE")
    c.count:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 3, -1)
    c.name = face:CreateFontString(nil, "OVERLAY")
    c.name:SetFont(FONT, 11, "")
    c.name:SetJustifyV("TOP")
    c.name:SetWordWrap(true)
    c.label = face:CreateFontString(nil, "OVERLAY")
    c.label:SetFont(FONT, 10, "OUTLINE")
    c.label:SetPoint("BOTTOM", 0, 10)
    c.bar = face:CreateTexture(nil, "ARTWORK")
    c.bar:SetHeight(4)
    c.bar:SetPoint("BOTTOMLEFT", 2, 2)
    c.bar:SetPoint("BOTTOMRIGHT", -2, 2)
    c.stars = MakeStars(face, "OVERLAY")
    c.sheen1 = NewTex(face, "OVERLAY", 3, "ADD")
    c.sheen2 = NewTex(face, "OVERLAY", 3, "ADD")
    c.sheen1:SetWidth(16)
    c.sheen2:SetWidth(16)
    Grad(c.sheen1, "HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, 0.45)
    Grad(c.sheen2, "HORIZONTAL", 1, 1, 1, 0.45, 1, 1, 1, 0)
    c.sheen2:SetPoint("TOPLEFT", c.sheen1, "TOPRIGHT", 0, 0)
    c.sheen2:SetPoint("BOTTOMLEFT", c.sheen1, "BOTTOMRIGHT", 0, 0)
    c.sheen1:Hide()
    c.sheen2:Hide()

    -- flash sits on its own frame above back and face
    local top = CreateFrame("Frame", nil, inner)
    top:SetAllPoints()
    top:SetFrameLevel(inner:GetFrameLevel() + 6)
    c.flash = NewTex(top, "OVERLAY", 7, "ADD")
    c.flash:SetAllPoints()
    c.flash:SetAlpha(0)

    -- group loot: a band across the card ("UP FOR ROLL", then who got it)
    local stamp = CreateFrame("Frame", nil, top)
    stamp:SetPoint("LEFT", inner, "LEFT", 2, 0)
    stamp:SetPoint("RIGHT", inner, "RIGHT", -2, 0)
    stamp:SetPoint("BOTTOM", inner, "BOTTOM", 0, 46)
    stamp:SetHeight(20)
    stamp.bg = stamp:CreateTexture(nil, "BACKGROUND")
    stamp.bg:SetAllPoints()
    stamp.bg:SetColorTexture(0, 0, 0, 0.78)
    stamp.text = stamp:CreateFontString(nil, "OVERLAY")
    stamp.text:SetFont(FONT, 10, "OUTLINE")
    stamp.text:SetPoint("LEFT", 2, 0)
    stamp.text:SetPoint("RIGHT", -2, 0)
    stamp.text:SetWordWrap(false)
    stamp:Hide()
    c.stamp = stamp

    c.isCard = true
    c:SetScript("OnClick", function(self) UI:ClickCard(self) end)
    c:SetScript("OnEnter", function(self)
        local d = self.data
        if self.revealed and d and not d.empty then
            local extra = { ("Crate tier: %s (%d/5)"):format(TierLabel(d.tier or 1), d.tier or 1) }
            if d.shared and not d.result then
                extra[2] = d.shared == "roll" and "Group loot: roll for it in the game's roll window."
                    or (d.mine and "You're the master looter: hand it out from the loot window after Collect.")
                    or "Group loot: not yours to take. Watch the chat for who gets it."
            end
            ShowItemTooltip(self, d.itemID, extra)
        end
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
    return c
end

local function LayoutCard(c, cw, ch)
    c.cw, c.ch = cw, ch
    c:SetSize(cw, ch)
    c.inner:SetWidth(cw)
    local isz = floor(cw * 0.5)
    c.icon:ClearAllPoints()
    c.icon:SetSize(isz, isz)
    c.icon:SetPoint("TOP", c.inner, "TOP", 0, -floor(ch * 0.12))
    c.iconBorder:ClearAllPoints()
    c.iconBorder:SetPoint("TOPLEFT", c.icon, "TOPLEFT", -2, 2)
    c.iconBorder:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 2, -2)
    c.faceRays:SetSize(cw * 1.5, cw * 1.5)
    c.name:ClearAllPoints()
    c.name:SetPoint("TOP", c.icon, "BOTTOM", 0, -8)
    c.name:SetWidth(cw - 12)
    c.name:SetHeight(max(14, ch - floor(ch * 0.12) - isz - 8 - 46))
    local esz = floor(cw * 0.36)
    c.emblem:SetSize(esz, esz)
    c.emblemBorder:SetSize(esz + 4, esz + 4)
    c.backStar:SetSize(cw * 1.3, cw * 1.3)
    c.sheen1:ClearAllPoints()
    c.sheen1:SetPoint("TOPLEFT", c.face, "TOPLEFT", -40, 0)
    c.sheen1:SetHeight(ch)
    c.sheen2:SetHeight(ch)
end

local function SetCardFace(c, d, containerID)
    c.data = d
    c.flipT, c.swapped, c.revealed, c.landed, c.tell = nil, false, false, false, false
    c.back:Show()
    c.face:Hide()
    c.inner:SetWidth(c.cw)
    c.emblem:SetTexture(ns.ItemIcon(containerID))
    if c.emblem.SetDesaturated then c.emblem:SetDesaturated(true) end
    -- a card from an earlier pull keeps its old tint unless it's really hidden: alpha 0 alone doesn't hide an
    -- ADD texture reliably on this client (same as the glows)
    Grad(c.backTint, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0)
    c.backTint:SetAlpha(0)
    c.backTint:Hide()
    EdgeGlowAlpha(c.glow, 0)
    c.backStar:SetVertexColor(1, 0.8, 0.4)
    c.backStar:SetAlpha(0.22)
    c.backStar:SetRotation(0)
    if c.inner.SetBackdropBorderColor then c.inner:SetBackdropBorderColor(0.62, 0.48, 0.2, 1) end
    c.sheen1:Hide()
    c.sheen2:Hide()
    c.flash:SetAlpha(0)
    c.flash:Hide()
    c.stamp:Hide()
    c.face:SetAlpha(1)
    if d.empty then
        c.icon:SetTexture(DUST)
        if c.icon.SetDesaturated then c.icon:SetDesaturated(true) end
        Grad(c.faceBg, "VERTICAL", 0.10, 0.10, 0.10, 1, 0.05, 0.05, 0.05, 1)
        c.iconBorder:SetColorTexture(0.25, 0.25, 0.25, 1)
        c.faceRays:SetAlpha(0)
        c.faceRays:Hide()
        c.bar:SetColorTexture(0.3, 0.3, 0.3, 1)
        c.name:SetText(d.text or "")
        c.name:SetTextColor(0.55, 0.55, 0.55)
        c.count:SetText("")
        c.label:SetText("EMPTY")
        c.label:SetTextColor(0.45, 0.45, 0.45)
        c.nStars = 0
    else
        local t = d.tier or 1
        local r, g, b = TierColor(t)
        c.icon:SetTexture(d.icon or ns.ItemIcon(d.itemID or 0))
        if c.icon.SetDesaturated then c.icon:SetDesaturated(false) end
        Grad(c.faceBg, "VERTICAL", r * 0.4, g * 0.4, b * 0.4, 1, 0.04, 0.035, 0.06, 1)
        c.iconBorder:SetColorTexture(r, g, b, 1)
        c.faceRays:SetVertexColor(r, g, b)
        c.faceRays:SetAlpha(t >= 3 and 0.6 or (t == 2 and 0.3 or 0.12))
        c.faceRays:Show()
        c.bar:SetColorTexture(r, g, b, 1)
        c.name:SetText(d.name or "")
        c.name:SetTextColor(ns.QualityColor(d.quality or 1))
        c.count:SetText((d.count and d.count > 1) and d.count or "")
        c.label:SetText(TierLabel(t):upper())
        c.label:SetTextColor(r, g, b)
        c.nStars = t
    end
    LayoutStars(c.stars, c.nStars, 15, 1, c.face, "BOTTOM", 0, 31)
end

-- colour the back of a face-down card (the per-card rarity tell)
local function SetCardTell(c, t)
    local r, g, b = TierColor(t)
    EdgeGlowColor(c.glow, r, g, b)
    Grad(c.backTint, "VERTICAL", r, g, b, 0.45, r, g, b, 0)
    c.backTint:SetAlpha(1)
    c.backTint:Show()
    c.backStar:SetVertexColor(r, g, b)
    c.backStar:SetAlpha(0.7)
    if c.inner.SetBackdropBorderColor then c.inner:SetBackdropBorderColor(r, g, b, 1) end
end

local function FlashCard(c, r, g, b, a)
    c.flash:SetVertexColor(r, g, b)
    c.flash:SetAlpha(a or 0.9)
    c.flash:Show()
    FX:Tween(0.5, function(k)
        c.flash:SetAlpha((a or 0.9) * (1 - k))
        if k >= 1 then c.flash:Hide() end
    end)
end

local function Sheen(c)
    c.sheen1:Show()
    c.sheen2:Show()
    FX:Tween(0.6, function(k)
        c.sheen1:SetPoint("TOPLEFT", c.face, "TOPLEFT", -40 + (c.cw + 50) * EaseOut2(k), 0)
    end, function()
        c.sheen1:Hide()
        c.sheen2:Hide()
    end)
end

-- order for "Reveal all": dust first, best last
local function Rank(d)
    if d.empty then return -1 end
    return (d.tier or 1) * 100 + (d.quality or 1) * 10 + min(9, d.count or 1)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

function UI:SetWash(r, g, b, a)
    Grad(f.washLo, "VERTICAL", r, g, b, 0, r, g, b, a)
    Grad(f.washHi, "VERTICAL", r, g, b, a, r, g, b, 0)
end

-- Chat and bags usually sit in the bottom part of the screen, where the result would show up first. So the
-- backdrop is a gradient: fully opaque across the bottom 30%, fading out by 80% of the screen height, over
-- a slightly lighter base, so the top still feels like a backdrop rather than a black void.
local SHROUD_SOLID, SHROUD_TOP = 0.30, 0.80

local function LayoutShroud()
    local h = f:GetHeight() or 0
    if h <= 0 then return end
    f.shroudSolid:SetHeight(max(1, h * SHROUD_SOLID))
    f.shroudFade:SetHeight(max(1, h * (SHROUD_TOP - SHROUD_SOLID)))
end

local function BuildBackdrop()
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.012, 0.01, 0.025, 0.88)

    f.shroudSolid = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    f.shroudSolid:SetPoint("BOTTOMLEFT")
    f.shroudSolid:SetPoint("BOTTOMRIGHT")
    f.shroudSolid:SetColorTexture(0.008, 0.006, 0.016, 1)
    f.shroudFade = NewTex(f, "BACKGROUND", -7)
    f.shroudFade:SetPoint("BOTTOMLEFT", f.shroudSolid, "TOPLEFT")
    f.shroudFade:SetPoint("BOTTOMRIGHT", f.shroudSolid, "TOPRIGHT")
    Grad(f.shroudFade, "VERTICAL", 0.008, 0.006, 0.016, 1, 0.008, 0.006, 0.016, 0)
    LayoutShroud()
    f:HookScript("OnSizeChanged", LayoutShroud)

    f.washLo = NewTex(f, "BACKGROUND", -6, "ADD")
    f.washLo:SetPoint("BOTTOMLEFT")
    f.washLo:SetPoint("BOTTOMRIGHT")
    f.washLo:SetPoint("TOP", f, "CENTER", 0, 0)
    f.washHi = NewTex(f, "BACKGROUND", -6, "ADD")
    f.washHi:SetPoint("TOPLEFT")
    f.washHi:SetPoint("TOPRIGHT")
    f.washHi:SetPoint("BOTTOM", f, "CENTER", 0, 0)

    local vt = NewTex(f, "BACKGROUND", -4)
    vt:SetPoint("TOPLEFT")
    vt:SetPoint("TOPRIGHT")
    vt:SetHeight(220)
    Grad(vt, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.75)
    local vb = NewTex(f, "BACKGROUND", -4)
    vb:SetPoint("BOTTOMLEFT")
    vb:SetPoint("BOTTOMRIGHT")
    vb:SetHeight(220)
    Grad(vb, "VERTICAL", 0, 0, 0, 0.75, 0, 0, 0, 0)
    local vl = NewTex(f, "BACKGROUND", -4)
    vl:SetPoint("TOPLEFT")
    vl:SetPoint("BOTTOMLEFT")
    vl:SetWidth(320)
    Grad(vl, "HORIZONTAL", 0, 0, 0, 0.7, 0, 0, 0, 0)
    local vr = NewTex(f, "BACKGROUND", -4)
    vr:SetPoint("TOPRIGHT")
    vr:SetPoint("BOTTOMRIGHT")
    vr:SetWidth(320)
    Grad(vr, "HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.7)
    -- the wash layers are plain white textures until tinted: tint them now, before anything can show them
    UI:SetWash(GOLD_R, GOLD_G, GOLD_B, 0.05)
end

local function BuildHeader(main)
    f.title = main:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(FONT, 26, "OUTLINE")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetTextColor(1, 0.84, 0.4)

    f.caseIcon = main:CreateTexture(nil, "ARTWORK")
    f.caseIcon:SetSize(40, 40)
    f.caseIcon:SetPoint("RIGHT", f.title, "LEFT", -12, 0)
    f.caseIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.tag = main:CreateFontString(nil, "OVERLAY")
    f.tag:SetFont(FONT, 12, "OUTLINE")
    f.tag:SetPoint("LEFT", f.title, "RIGHT", 12, 0)

    f.sub = main:CreateFontString(nil, "OVERLAY")
    f.sub:SetFont(FONT, 11, "")
    f.sub:SetTextColor(0.62, 0.6, 0.66)
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -8)

    local line = NewTex(main, "ARTWORK", 0, "ADD")
    line:SetHeight(1)
    line:SetWidth(520)
    line:SetPoint("TOP", f.sub, "BOTTOM", 0, -8)
    Grad(line, "HORIZONTAL", 1, 0.75, 0.3, 0, 1, 0.75, 0.3, 0.6)
    local line2 = NewTex(main, "ARTWORK", 0, "ADD")
    line2:SetHeight(1)
    line2:SetWidth(520)
    line2:SetPoint("LEFT", line, "RIGHT", 0, 0)
    Grad(line2, "HORIZONTAL", 1, 0.75, 0.3, 0.6, 1, 0.75, 0.3, 0)
    line:ClearAllPoints()
    line:SetPoint("TOPRIGHT", f.sub, "BOTTOM", 0, -8)
    line:SetWidth(260)
    line2:SetWidth(260)
end

local function BuildReel(stage, level)
    local reel = CreateFrame("Frame", nil, stage)
    reel:SetFrameLevel(level)
    reel:SetSize(STAGE_W, REEL_H)
    reel:SetPoint("CENTER", 0, 30)
    if reel.SetClipsChildren then reel:SetClipsChildren(true) end
    local rbg = NewTex(reel, "BACKGROUND", 0)
    rbg:SetAllPoints()
    Grad(rbg, "VERTICAL", 0.03, 0.025, 0.05, 0.9, 0.08, 0.06, 0.1, 0.9)
    f.reel = reel

    local strip = CreateFrame("Frame", nil, reel)
    strip:SetSize(STEP * REEL_TILES, TILE + 20)
    strip:SetPoint("LEFT", reel, "LEFT", 6, 0)
    f.strip = strip
    f.tiles = {}
    for i = 1, REEL_TILES do
        local t = CreateTile(strip, TILE, true)
        t:SetPoint("LEFT", strip, "LEFT", (i - 1) * STEP, 0)
        f.tiles[i] = t
    end

    local over = CreateFrame("Frame", nil, reel)
    over:SetAllPoints()
    over:SetFrameLevel(strip:GetFrameLevel() + 10)
    local fadeL = NewTex(over, "OVERLAY", 0)
    fadeL:SetPoint("TOPLEFT")
    fadeL:SetPoint("BOTTOMLEFT")
    fadeL:SetWidth(180)
    Grad(fadeL, "HORIZONTAL", 0, 0, 0, 0.95, 0, 0, 0, 0)
    local fadeR = NewTex(over, "OVERLAY", 0)
    fadeR:SetPoint("TOPRIGHT")
    fadeR:SetPoint("BOTTOMRIGHT")
    fadeR:SetWidth(180)
    Grad(fadeR, "HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.95)
    f.markGlow = NewTex(over, "OVERLAY", 1, "ADD")
    f.markGlow:SetPoint("TOP")
    f.markGlow:SetPoint("BOTTOM")
    f.markGlow:SetWidth(40)
    f.markGlow:SetAlpha(0.4)
    Grad(f.markGlow, "HORIZONTAL", 1, 0.75, 0.25, 0, 1, 0.75, 0.25, 0)
    -- two halves so the glow falls off both ways
    local mgL = NewTex(over, "OVERLAY", 1, "ADD")
    mgL:SetPoint("TOPRIGHT", over, "TOP", 0, 0)
    mgL:SetPoint("BOTTOMRIGHT", over, "BOTTOM", 0, 0)
    mgL:SetWidth(22)
    Grad(mgL, "HORIZONTAL", 1, 0.75, 0.25, 0, 1, 0.75, 0.25, 0.5)
    local mgR = NewTex(over, "OVERLAY", 1, "ADD")
    mgR:SetPoint("TOPLEFT", over, "TOP", 0, 0)
    mgR:SetPoint("BOTTOMLEFT", over, "BOTTOM", 0, 0)
    mgR:SetWidth(22)
    Grad(mgR, "HORIZONTAL", 1, 0.75, 0.25, 0.5, 1, 0.75, 0.25, 0)
    f.markL, f.markR = mgL, mgR
    local line = over:CreateTexture(nil, "OVERLAY", nil, 2)
    line:SetColorTexture(1, 0.8, 0.3, 0.95)
    line:SetWidth(2)
    line:SetPoint("TOP")
    line:SetPoint("BOTTOM")
    for _, p in ipairs({ "TOP", "BOTTOM" }) do
        local nub = over:CreateTexture(nil, "OVERLAY", nil, 3)
        nub:SetColorTexture(1, 0.8, 0.3, 1)
        nub:SetSize(14, 6)
        nub:SetPoint(p, over, p, 0, 0)
    end
    local rimT = over:CreateTexture(nil, "OVERLAY", nil, 2)
    rimT:SetColorTexture(1, 0.75, 0.3, 0.35)
    rimT:SetHeight(1)
    rimT:SetPoint("TOPLEFT")
    rimT:SetPoint("TOPRIGHT")
    local rimB = over:CreateTexture(nil, "OVERLAY", nil, 2)
    rimB:SetColorTexture(1, 0.75, 0.3, 0.35)
    rimB:SetHeight(1)
    rimB:SetPoint("BOTTOMLEFT")
    rimB:SetPoint("BOTTOMRIGHT")

    f.reelText = stage:CreateFontString(nil, "OVERLAY")
    f.reelText:SetFont(FONT, 12, "OUTLINE")
    f.reelText:SetTextColor(0.8, 0.78, 0.85)
    f.reelText:SetPoint("TOP", reel, "BOTTOM", 0, -8)
    reel:Hide()

    -- results row (reel style)
    f.results = {}
    for i = 1, 8 do
        local t = CreateTile(stage, 40, false)
        t:SetFrameLevel(level)
        t:EnableMouse(true)
        t:SetScript("OnEnter", function(self) if self.data then ShowItemTooltip(self, self.data.itemID) end end)
        t:SetScript("OnLeave", GameTooltip_Hide)
        t:Hide()
        f.results[i] = t
    end
end

-- A slim gold scrollbar in the theme for any scroll frame: a faint track and a draggable thumb sized to how
-- much of the list fits. Hidden when everything fits. Follows the wheel, resizes and new content by itself.
local function AddScrollBar(sf, child)
    local bar = CreateFrame("Frame", nil, sf:GetParent())
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
    bar:SetWidth(6)
    bar:SetFrameLevel(sf:GetFrameLevel() + 5)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    track:SetWidth(2)
    track:SetColorTexture(0.55, 0.42, 0.18, 0.35)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(6)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(1, 0.78, 0.32, 0.75)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(1, 0.86, 0.45, 1) end)
    thumb:SetScript("OnLeave", function(self) if not self.dragging then self.tex:SetColorTexture(1, 0.78, 0.32, 0.75) end end)
    bar:Hide()

    local function Update()
        local view, total = sf:GetHeight() or 0, child:GetHeight() or 0
        local range = total - view
        if view <= 0 or range <= 1 then
            bar:Hide()
            if sf:GetVerticalScroll() > 0 then sf:SetVerticalScroll(0) end
            return
        end
        bar:Show()
        local h = bar:GetHeight()
        local th = max(20, h * view / total)
        local pos = min(1, sf:GetVerticalScroll() / range)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * pos)
    end
    sf.UpdateBar = Update

    -- drag the thumb
    thumb:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        self.dragging, self.startY, self.startScroll = true, y / self:GetEffectiveScale(), sf:GetVerticalScroll()
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.dragging = nil
        self.tex:SetColorTexture(1, 0.78, 0.32, 0.75)
    end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.dragging then return end
        local _, y = GetCursorPosition()
        y = y / self:GetEffectiveScale()
        local range = (child:GetHeight() or 0) - (sf:GetHeight() or 0)
        local free = bar:GetHeight() - self:GetHeight()
        if range <= 0 or free <= 0 then return end
        local scroll = self.startScroll + (self.startY - y) * range / free
        sf:SetVerticalScroll(max(0, min(range, scroll)))
    end)
    -- click the track: jump a page
    bar:EnableMouse(true)
    bar:SetScript("OnMouseDown", function(self)
        local _, y = GetCursorPosition()
        y = y / self:GetEffectiveScale()
        local top = thumb:GetTop() or 0
        local range = (child:GetHeight() or 0) - (sf:GetHeight() or 0)
        local page = sf:GetHeight() * 0.9
        local cur = sf:GetVerticalScroll()
        sf:SetVerticalScroll(max(0, min(range, y > top and cur - page or cur + page)))
    end)

    sf:HookScript("OnVerticalScroll", Update)
    sf:HookScript("OnScrollRangeChanged", Update)
    sf:HookScript("OnSizeChanged", Update)
    child:HookScript("OnSizeChanged", Update)
    sf:HookScript("OnShow", Update)
    return bar
end

local function GetCell(i)
    local p = f.oddsPanel
    local c = p.cells[i]
    if c then return c end
    c = CreateFrame("Frame", nil, p.child)
    c:SetSize(CELL_W, CELL_H)
    c.tile = CreateTile(c, 44, false)
    c.tile:SetPoint("TOP", 0, -2)
    c.pct = c:CreateFontString(nil, "OVERLAY")
    c.pct:SetFont(FONT, 10, "OUTLINE")
    c.pct:SetPoint("TOP", c.tile, "BOTTOM", 0, -3)
    c.pct:SetTextColor(0.78, 0.76, 0.82)
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        local row = self.row
        if not row then return end
        local lines = {}
        -- no number for boxes nobody tracks (Comprehension): their percentages are only demo weights
        if not row.estimated then lines[#lines + 1] = ("Chance per opening: %s"):format(PctText(row.pct)) end
        lines[#lines + 1] = ("Crate tier: %s (%d/5)"):format(TierLabel(row.tier), row.tier)
        if (row.hi or 1) > 1 then lines[#lines + 1] = ("Stack: %d-%d"):format(row.lo or 1, row.hi) end
        lines[#lines + 1] = ns.IsHunted(row.id) and "|cffff4050Hunting this one.|r Right-click to stop."
            or "Right-click to hunt it (it becomes Heirloom)."
        ShowItemTooltip(self, row.id, lines)
    end)
    c:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or not self.row then return end
        UI:ToggleHunt(self.row.id)
        if self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
    -- the cells take the mouse (tooltips), so pass the wheel on to the list
    c:EnableMouseWheel(true)
    c:SetScript("OnMouseWheel", function(_, delta)
        local sf = p.scroll
        sf:GetScript("OnMouseWheel")(sf, delta)
    end)
    p.cells[i] = c
    return c
end

local function BuildOdds()
    local p = CreateFrame("Frame", nil, f, BACKDROP)
    p:SetFrameLevel(200)
    p:SetSize(336, ODDS_H)
    -- anchored by its top so folding it keeps the header in place
    p:SetPoint("TOPRIGHT", f, "RIGHT", -30, ODDS_H / 2)
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        p:SetBackdropColor(0.03, 0.025, 0.05, 0.96)
        p:SetBackdropBorderColor(0.55, 0.42, 0.18, 1)
    end
    p:EnableMouse(true)
    p.title = p:CreateFontString(nil, "OVERLAY")
    p.title:SetFont(FONT, 15, "OUTLINE")
    p.title:SetTextColor(1, 0.84, 0.4)
    p.title:SetPoint("TOPLEFT", 14, -12)
    p.title:SetText("WHAT'S INSIDE")
    p.note = p:CreateFontString(nil, "OVERLAY")
    p.note:SetFont(FONT, 9, "")
    p.note:SetTextColor(0.55, 0.53, 0.6)
    p.note:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -3)

    -- the header (title strip) folds and unfolds the panel; the +/- box in its corner says which
    local head = CreateFrame("Button", nil, p)
    head:SetPoint("TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(ODDS_HEAD)
    head:SetScript("OnClick", function() UI:ToggleOdds() end)
    local hl = NewTex(head, "HIGHLIGHT", 0, "ADD")
    hl:SetPoint("TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", -1, 1)
    Grad(hl, "VERTICAL", 1, 0.8, 0.4, 0, 1, 0.8, 0.4, 0.12)
    local tg = CreateFrame("Frame", nil, head, BACKDROP)
    tg:SetSize(22, 22)
    tg:SetPoint("TOPRIGHT", -10, -9)
    if tg.SetBackdrop then
        tg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        tg:SetBackdropColor(0.08, 0.06, 0.11, 0.95)
        tg:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    tg.text = tg:CreateFontString(nil, "OVERLAY")
    tg.text:SetFont(FONT, 16, "OUTLINE")
    tg.text:SetPoint("CENTER", 0, 1)
    tg.text:SetTextColor(1, 0.86, 0.5)
    tg.text:SetText("-")
    p.toggle = tg

    local sf = CreateFrame("ScrollFrame", nil, p)
    sf:SetPoint("TOPLEFT", 12, -(ODDS_HEAD + 8))
    sf:SetPoint("BOTTOMRIGHT", -12, 12)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(4 * CELL_W, 10)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local m = max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(m, max(0, self:GetVerticalScroll() - delta * CELL_H)))
    end)
    AddScrollBar(sf, child)
    p.scroll, p.child, p.cells = sf, child, {}
    p:Hide()
    f.oddsPanel = p
end

-- Demo box picker: every container, grouped, one click to switch
local PICK_COLS, PICK_W, PICK_H, PICK_HEAD = 4, 200, 26, 22 -- (4 across keeps it on screen with the world chests)

local function BuildPicker()
    local blocker = CreateFrame("Frame", nil, f)
    blocker:SetAllPoints()
    blocker:SetFrameLevel(440)
    blocker:EnableMouse(true)
    blocker:SetScript("OnMouseDown", function(self) self:Hide() end) -- click outside closes
    local dim = blocker:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.6)

    local p = CreateFrame("Frame", nil, blocker, BACKDROP)
    p:SetFrameLevel(450)
    p:SetPoint("CENTER", f, "CENTER", 0, 20)
    p:EnableMouse(true)
    p:SetScript("OnMouseDown", function() end) -- clicks inside don't close
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        p:SetBackdropColor(0.03, 0.025, 0.05, 1)
        p:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    local title = p:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 16, "OUTLINE")
    title:SetTextColor(1, 0.84, 0.4)
    title:SetPoint("TOP", 0, -12)
    title:SetText("PICK A BOX")

    local y = -42
    local col = 0
    local buttons = {}
    local lastCat
    for _, id in ipairs(ns.BrowseOrder()) do
        local cat = ns.CategoryOf(id)
        if cat ~= lastCat then
            if col > 0 then y = y - PICK_H end
            col = 0
            local h = p:CreateFontString(nil, "OVERLAY")
            h:SetFont(FONT, 11, "OUTLINE")
            h:SetTextColor(0.62, 0.6, 0.66)
            h:SetPoint("TOPLEFT", 16, y - 4)
            h:SetText(cat:upper())
            y = y - PICK_HEAD
            lastCat = cat
        end
        local b = CreateFrame("Button", nil, p)
        b:SetSize(PICK_W - 6, PICK_H - 2)
        b:SetPoint("TOPLEFT", 14 + col * PICK_W, y)
        b.sel = NewTex(b, "BACKGROUND", 0)
        b.sel:SetAllPoints()
        b.sel:SetVertexColor(1, 0.75, 0.3, 0.18)
        b.hl = NewTex(b, "HIGHLIGHT", 0, "ADD")
        b.hl:SetAllPoints()
        b.hl:SetVertexColor(1, 0.8, 0.4, 0.15)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(20, 20)
        b.icon:SetPoint("LEFT", 2, 0)
        b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.icon:SetTexture(ns.ItemIcon(id))
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetFont(FONT, 11, "")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b.text:SetText(ns.Containers[id].name)
        b.id = id
        b:SetScript("OnClick", function(self)
            blocker:Hide()
            ns.Demo(self.id)
        end)
        buttons[#buttons + 1] = b
        col = col + 1
        if col >= PICK_COLS then
            col = 0
            y = y - PICK_H
        end
    end
    if col > 0 then y = y - PICK_H end
    p:SetSize(PICK_COLS * PICK_W + 22, -y + 12)

    blocker:SetScript("OnShow", function()
        local cur = UI.itemID
        for _, b in ipairs(buttons) do
            b.sel:SetShown(b.id == cur)
            b.icon:SetTexture(ns.ItemIcon(b.id)) -- icons may have loaded since the build
            b.text:SetTextColor(b.id == cur and 1 or 0.88, b.id == cur and 0.84 or 0.86, b.id == cur and 0.4 or 0.9)
        end
        local room = (f:GetHeight() or 700) * 0.9
        p:SetScale(min(1, room / p:GetHeight()))
    end)
    blocker:Hide()
    f.picker = blocker
end

-- Demo: force the best pull to a tier (nil = normal roll, 0 = a fizzle for Comprehension)
-- "x2" (tier -1) is a toggle on top of the chosen tier: two of them in the same pull
local FORCE_OPTS = { { nil, "Any" }, { 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7 }, { -1, "x2" }, { 0, "Sheep" } }

local function BuildForceBar()
    local bar = CreateFrame("Frame", nil, f)
    bar:SetFrameLevel(210)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -20)
    bar:SetSize(10, 50)
    local label = bar:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 10, "OUTLINE")
    label:SetTextColor(0.62, 0.6, 0.66)
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText("DEMO: FORCE THE BEST PULL")
    bar.buttons = {}
    local x = 0
    for _, opt in ipairs(FORCE_OPTS) do
        local t = opt[1]
        local text = opt[2] or TierLabel(t)
        local b = CreateFrame("Button", nil, bar, BACKDROP)
        b:SetSize(t == nil and 44 or (t == 0 and 56 or (t == -1 and 34 or 80)), 24)
        b:SetPoint("TOPLEFT", x, -16)
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        end
        b.text = b:CreateFontString(nil, "OVERLAY")
        b.text:SetFont(FONT, 11, "OUTLINE")
        b.text:SetPoint("CENTER")
        b.text:SetText(text)
        local hl = NewTex(b, "HIGHLIGHT", 0, "ADD")
        hl:SetPoint("TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", -1, 1)
        hl:SetVertexColor(1, 0.85, 0.5, 0.12)
        b.tier = t
        b:SetScript("OnClick", function(self) UI:SetForce(self.tier) end)
        b:SetScript("OnEnter", function(self)
            if self.tier == -1 then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine("Two of the chosen tier in one pull", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            elseif self.missing then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine("Nothing of this tier in this box", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        bar.buttons[#bar.buttons + 1] = b
        x = x + b:GetWidth() + 4
    end
    bar:Hide()
    f.forceBar = bar
end

function UI:ShowForceBar(show)
    local bar = f.forceBar
    if not show then bar:Hide() return end
    local c = self.container
    local has = {}
    for _, r in ipairs(c.items) do has[TierFor(self.itemID, r[1], r[3])] = true end
    for _, b in ipairs(bar.buttons) do
        local t = b.tier
        local r, g, bb = 1, 0.86, 0.5
        if t and t > 0 then r, g, bb = TierColor(t) elseif t == 0 then r, g, bb = 0.7, 0.7, 0.72 end
        local multi = ns.CardCount(self.itemID) >= 2
        -- the 0 button: "Sheep" for Comprehension, "Empty" for a box that can come up empty
        local canEmpty = not c.failPct and ns.EmptyChance(self.itemID) >= 0.01
        if t == 0 then b.text:SetText(c.failPct and "Sheep" or "Empty") end
        b.missing = (t and t > 0 and t < 6 and not has[t]) or (t == 0 and not c.failPct and not canEmpty)
        if t == 7 then
            -- Heirloom: lit when one of the player's hunted items is in this box (else it demos a stand-in)
            local any = false
            for _, r in ipairs(c.items) do if ns.IsHunted(r[1]) then any = true break end end
            b.missing = not any
        end
        if t == -1 then
            b:SetShown(multi)
        else
            b:SetShown(t ~= 0 or c.failPct ~= nil or canEmpty)
        end
        local sel
        if t == -1 then sel = self.forceCount == 2 else sel = (self.forceTier == t) end
        local dim = b.missing and 0.35 or 1
        b.text:SetTextColor(r * dim, g * dim, bb * dim)
        if b.SetBackdropColor then
            b:SetBackdropColor(sel and r * 0.3 or 0.06, sel and g * 0.3 or 0.05, sel and bb * 0.3 or 0.09, 0.95)
            b:SetBackdropBorderColor(sel and r or 0.4, sel and g or 0.32, sel and bb or 0.16, 1)
        end
    end
    -- pack the visible buttons (x2 only shows on multi-card boxes, Fizzle only on Comprehension)
    local x = 0
    for _, b in ipairs(bar.buttons) do
        if b:IsShown() then
            b:SetPoint("TOPLEFT", x, -16)
            x = x + b:GetWidth() + 4
        end
    end
    bar:Show()
end

function UI:SetForce(t)
    if self.live then return end
    if t == -1 then
        self.forceCount = (self.forceCount ~= 2) and 2 or nil
    else
        self.forceTier = t
    end
    -- re-deal the box on screen so the next OPEN uses it
    if self.phase == "ready" or self.phase == "done" then
        ns.Demo(self.itemID)
    else
        self:ShowForceBar(true)
    end
end

function UI:TogglePicker()
    if self.live or not f.picker then return end
    f.picker:SetShown(not f.picker:IsShown())
end

-- The spotlight dim. The case screen underneath (header, hint, the other cards, Skip) fades out as the dim
-- comes in, so nothing ghosts through around the item in the spotlight.
local function SetDim(a)
    f.dimOver:SetAlpha(a)
    f.main:SetAlpha(1 - a)
end

local function BuildShowcase()
    f.dimOver = CreateFrame("Frame", nil, f)
    f.dimOver:SetAllPoints()
    f.dimOver:SetFrameLevel(300)
    local dt = f.dimOver:CreateTexture(nil, "BACKGROUND")
    dt:SetAllPoints()
    dt:SetColorTexture(0, 0, 0, 0.86)
    f.dimOver:Hide()
    -- whatever ends the spotlight (close, skip, combat, reset), the case screen comes back
    f.dimOver:HookScript("OnHide", function() f.main:SetAlpha(1) end)

    local show = CreateFrame("Frame", nil, f)
    show:SetPoint("TOPLEFT")
    show:SetPoint("BOTTOMRIGHT")
    show:SetFrameLevel(320)
    show:SetScript("OnMouseDown", function() UI:Skip() end)
    show:Hide()
    f.show = show

    f.showHalo = FX:CreateHalo(show, 18)
    f.showHalo:SetFrameLevel(322)
    f.showHalo:SetPoint("CENTER", show, "CENTER", 0, SHOW_Y)
    f.showHalo:SetAlpha(0)

    f.showCard = CreateCard(show, 330)
    f.showCard:EnableMouse(false)
    f.showCard.isCard = false
    f.showCard:SetScript("OnClick", nil)
    f.showCard:SetScript("OnEnter", nil)

    local tx = CreateFrame("Frame", nil, show)
    tx:SetAllPoints()
    tx:SetFrameLevel(360)
    f.showText = tx
    f.showTier = tx:CreateFontString(nil, "OVERLAY")
    f.showTier:SetFont(FONT, 44, "THICKOUTLINE")
    f.showTier:SetPoint("CENTER", show, "CENTER", 0, SHOW_Y + CARD_H * SHOW_SCALE / 2 + 44)
    f.showTierAnim = MakePop(f.showTier, 2.2, 0.35)
    f.showName = tx:CreateFontString(nil, "OVERLAY")
    f.showName:SetFont(FONT, 22, "OUTLINE")
    f.showName:SetPoint("CENTER", show, "CENTER", 0, SHOW_Y - CARD_H * SHOW_SCALE / 2 - 26)
    f.showStars = MakeStars(tx, "OVERLAY")
    f.showSub = tx:CreateFontString(nil, "OVERLAY")
    f.showSub:SetFont(FONT, 12, "")
    f.showSub:SetTextColor(0.75, 0.72, 0.8)
    f.showSub:SetPoint("CENTER", show, "CENTER", 0, SHOW_Y - CARD_H * SHOW_SCALE / 2 - 86)
    f.showHint = tx:CreateFontString(nil, "OVERLAY")
    f.showHint:SetFont(FONT, 11, "")
    f.showHint:SetTextColor(0.6, 0.58, 0.64)
    f.showHint:SetPoint("CENTER", show, "CENTER", 0, SHOW_Y - CARD_H * SHOW_SCALE / 2 - 110)
end

local function Build()
    FX = ns.FX
    f = CreateFrame("Frame", "CrateExpectationsCasesFrame", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(10)
    f:EnableMouse(true)
    f:Hide()
    tinsert(UISpecialFrames, "CrateExpectationsCasesFrame")

    BuildBackdrop()

    local main = CreateFrame("Frame", nil, f)
    main:SetSize(MAIN_W, MAIN_H)
    main:SetPoint("CENTER", f, "CENTER", 0, 20)
    main:SetFrameLevel(20)
    f.main = main

    BuildHeader(main)

    -- stage
    local stage = CreateFrame("Frame", nil, main)
    stage:SetSize(STAGE_W, STAGE_H)
    stage:SetPoint("TOP", 0, -96)
    stage:SetFrameLevel(30)
    f.stage = stage

    f.halo = FX:CreateHalo(stage, 14)
    f.halo:SetFrameLevel(31)
    f.halo:SetPoint("CENTER", stage, "CENTER", 0, 10)
    f.halo:SetAlpha(0)

    local box = CreateFrame("Frame", nil, stage)
    box:SetFrameLevel(36)
    box:SetSize(120, 120)
    box:SetPoint("CENTER", stage, "CENTER", 0, 10)
    f.boxBorder = box:CreateTexture(nil, "ARTWORK", nil, 0)
    f.boxBorder:SetColorTexture(0, 0, 0, 0.9)
    f.boxIcon = box:CreateTexture(nil, "ARTWORK", nil, 1)
    f.boxIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.boxIcon:SetPoint("CENTER")
    f.boxIcon:SetSize(84, 84)
    f.boxBorder:SetPoint("TOPLEFT", f.boxIcon, "TOPLEFT", -3, 3)
    f.boxBorder:SetPoint("BOTTOMRIGHT", f.boxIcon, "BOTTOMRIGHT", 3, -3)
    f.boxGlow = CreateEdgeGlow(box, f.boxBorder, 16, "BACKGROUND")
    f.box = box
    box:Hide()

    f.info = stage:CreateFontString(nil, "OVERLAY")
    f.info:SetFont(FONT, 13, "OUTLINE")
    f.info:SetPoint("BOTTOM", stage, "BOTTOM", 0, 36)
    f.hint = stage:CreateFontString(nil, "OVERLAY")
    f.hint:SetFont(FONT, 11, "")
    f.hint:SetTextColor(0.62, 0.6, 0.66)
    f.hint:SetPoint("TOP", f.info, "BOTTOM", 0, -6)

    -- a world chest's opening cast, under the chest
    local cb = CreateFrame("Frame", nil, stage, BACKDROP)
    cb:SetSize(CAST_W + 4, 12)
    cb:SetPoint("TOP", box, "BOTTOM", 0, -26)
    cb:SetFrameLevel(37)
    if cb.SetBackdrop then
        cb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        cb:SetBackdropColor(0.04, 0.03, 0.06, 0.9)
        cb:SetBackdropBorderColor(0.62, 0.48, 0.2, 0.9)
    end
    cb.fill = cb:CreateTexture(nil, "ARTWORK")
    cb.fill:SetPoint("LEFT", 2, 0)
    cb.fill:SetHeight(8)
    cb.fill:SetWidth(1)
    cb.spark = NewTex(cb, "OVERLAY", 1, "ADD")
    cb.spark:SetTexture(STAR)
    cb.spark:SetSize(26, 26)
    cb.spark:SetPoint("CENTER", cb.fill, "RIGHT", 0, 0)
    cb.text = cb:CreateFontString(nil, "OVERLAY")
    cb.text:SetFont(FONT, 12, "OUTLINE")
    cb.text:SetPoint("BOTTOM", cb, "TOP", 0, 5)
    cb:Hide()
    f.castBar = cb

    BuildReel(stage, 40)
    f.cards = {}
    f.cardLevel = 44

    -- under the stage
    f.banner = main:CreateFontString(nil, "OVERLAY")
    f.banner:SetFont(FONT, 34, "THICKOUTLINE")
    f.banner:SetPoint("TOP", stage, "BOTTOM", 0, -6)
    f.bannerAnim = MakePop(f.banner, 1.9, 0.3)
    f.bannerStars = MakeStars(main, "OVERLAY")

    f.status = main:CreateFontString(nil, "OVERLAY")
    f.status:SetFont(FONT, 13, "")
    f.status:SetTextColor(0.85, 0.83, 0.9)
    f.status:SetPoint("TOP", f.banner, "BOTTOM", 0, -24)

    local purse = CreateFrame("Frame", nil, main)
    purse:SetSize(260, 40)
    purse:SetPoint("TOP", f.status, "BOTTOM", 0, -6)
    purse.icon = purse:CreateTexture(nil, "ARTWORK")
    purse.icon:SetSize(34, 34)
    purse.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    purse.text = purse:CreateFontString(nil, "OVERLAY")
    purse.text:SetFont(FONT, 20, "OUTLINE")
    purse.text:SetPoint("CENTER", 20, 0)
    purse.icon:SetPoint("RIGHT", purse.text, "LEFT", -10, 0)
    purse.flash = NewTex(purse, "OVERLAY", 7, "ADD")
    purse.flash:SetAllPoints(purse.icon)
    purse.flash:SetAlpha(0)
    purse:Hide()
    f.purse = purse

    -- buttons
    f.mainBtn = MakeButton(main, 240, 44, "OPEN", 17)
    f.mainBtn:SetPoint("BOTTOM", main, "BOTTOM", 0, 14)
    f.mainBtn:SetScript("OnClick", function() UI:OnMainButton() end)

    f.skip = MakeButton(main, 150, 32, "Skip", 13)
    f.skip:SetPoint("BOTTOM", main, "BOTTOM", 0, 20)
    f.skip:SetScript("OnClick", function() UI:Skip() end)
    f.skip:Hide()

    f.pick = MakeButton(main, 96, 32, "Boxes", 12)
    f.pick:SetPoint("RIGHT", f.mainBtn, "LEFT", -18, 0)
    f.pick:SetScript("OnClick", function() UI:TogglePicker() end)

    -- clicking the title opens the picker too; the wheel over the box flips through boxes
    local tb = CreateFrame("Button", nil, main)
    tb:SetPoint("TOPLEFT", f.caseIcon, "TOPLEFT", -4, 4)
    tb:SetPoint("BOTTOMRIGHT", f.title, "BOTTOMRIGHT", 4, -4)
    tb:SetFrameLevel(60)
    tb:SetScript("OnClick", function() UI:TogglePicker() end)
    tb:SetScript("OnEnter", function(self)
        if UI.live then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Click to pick another box", 1, 0.82, 0.3)
        GameTooltip:AddLine("Mouse wheel over the box flips through them", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    tb:SetScript("OnLeave", GameTooltip_Hide)
    stage:EnableMouseWheel(true)
    stage:SetScript("OnMouseWheel", function(_, delta)
        if UI.phase == "ready" or UI.phase == "done" then UI:Browse(delta > 0 and -1 or 1) end
    end)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -14)
    close:SetFrameLevel(400)
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close
    f.gear = MakeButton(f, 96, 26, "Settings", 12)
    f.gear:SetPoint("RIGHT", close, "LEFT", -8, 0)
    f.gear:SetFrameLevel(400)
    f.gear:SetScript("OnClick", function() UI:ShowSettings() end)

    BuildOdds()
    BuildShowcase()
    BuildPicker()
    BuildForceBar()

    -- effects layer, on top of everything
    f.fx = CreateFrame("Frame", nil, f)
    f.fx:SetAllPoints()
    f.fx:SetFrameLevel(430) -- above the spotlight, below the box picker (440+) and the next-box button
    f.fx:EnableMouse(false)
    FX:Attach(f.fx)

    f:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then UI:Skip() end
    end)
    f:SetScript("OnHide", function()
        -- closing the screen closes every view in it, so nothing reopens on its own later
        if f.settings then f.settings:Hide() end
        if f.mine then f.mine:Hide() end
        if f.stats then f.stats:Hide() end
        -- closed mid-cast: the player doesn't want the show for this chest
        if UI.pending == "chest" and ns.ChestScreenClosed then ns.ChestScreenClosed() end
        UI:RaiseLootFrames(false)
        UI:Reset()
        GameTooltip_Hide()
        if ns.live and not ns.live.collecting then
            -- closed before collecting: hand the loot back to the normal window
            ns.RevealLootFrame()
        end
    end)
    f:SetScript("OnUpdate", function(_, el)
        if el > 0.1 then el = 0.1 end
        FX:Update(el)
        UI:OnUpdate(el)
    end)
end

---------------------------------------------------------------------------
-- Odds
---------------------------------------------------------------------------

function UI:FillOdds(container)
    local p = f.oddsPanel
    local rows = {}
    for _, r in ipairs(container.items) do
        rows[#rows + 1] = { id = r[1], pct = r[2], q = r[3], name = r[4], lo = r[5], hi = r[6],
            tier = TierFor(self.itemID, r[1], r[3]), estimated = container.estimated }
    end
    table.sort(rows, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return a.pct < b.pct
    end)

    -- world chests hold hundreds of random world drops: no item grid (the surprise is the point), just the
    -- Rare+ odds line under the chest
    local perRow = 4
    local shown = container.world and 0 or #rows
    for i = 1, shown do
        local row = rows[i]
        local c = GetCell(i)
        c.row = row
        SetTile(c.tile, { itemID = row.id, quality = row.q, name = row.name, tier = row.tier }, self.itemID)
        -- the chance right under the item (none for boxes whose numbers are only demo weights)
        c.pct:SetText(row.estimated and "" or (row.pct < 0.01 and "<0.01%" or PctText(row.pct)))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", ((i - 1) % perRow) * CELL_W, -floor((i - 1) / perRow) * CELL_H)
        c:Show()
    end
    for i = shown + 1, #p.cells do p.cells[i]:Hide() end
    p.child:SetHeight(max(10, math.ceil(shown / perRow) * CELL_H))
    p.scroll:SetVerticalScroll(0)

    -- chance of at least one item of a tier or better (drops treated as independent)
    -- A tier with no items of its own (lockboxes and trunks jump from Rare straight to Legendary) would
    -- just repeat the next tier's number, so it's listed as absent instead.
    -- the line under the box on the main screen still sums up the Rare+ odds
    local summary = {}
    local exact = {}
    for _, r in ipairs(rows) do exact[r.tier] = true end
    for k = 3, 5 do
        local none = 1
        for _, r in ipairs(rows) do
            if r.tier >= k then none = none * (1 - min(100, r.pct) / 100) end
        end
        if exact[k] then
            local r, g, b = TierColor(k)
            local label = k == 5 and TierLabel(k) or (TierLabel(k) .. "+")
            if container.estimated then
                summary[#summary + 1] = ("|cff%s%s|r"):format(Hex(r, g, b), TierLabel(k)) -- which tiers, no odds
            else
                summary[#summary + 1] = ("|cff%s%s|r ~%s"):format(Hex(r, g, b), label, PctText((1 - none) * 100))
            end
        end
    end
    self.oddsSummary = table.concat(summary, "   ")
    if container.estimated and self.oddsSummary ~= "" then
        self.oddsSummary = "|cff9a9a9aCan give|r  " .. self.oddsSummary
    end

    p.note:SetText(container.estimated and "No odds known: ranked by how rare each one seems"
        or "Chance per opening. Hover an item for more")
end

-- The panel is always there before and after a pull; +/- folds it down to its header.
-- expanded == nil counts as expanded (the default)
function UI:ApplyOdds(expanded, fade)
    local p = f.oddsPanel
    if self.container and self.container.world then p:Hide() return end
    expanded = expanded ~= false
    p.expanded = expanded
    p.scroll:SetShown(expanded)
    p.note:SetShown(expanded)
    p:SetHeight(expanded and ODDS_H or ODDS_HEAD)
    p.toggle.text:SetText(expanded and "-" or "+")
    if not p:IsShown() or fade then
        p:Show()
        p:SetAlpha(0)
        FX:Tween(0.2, function(k) p:SetAlpha(k) end)
    end
end

-- the show is starting: the odds panel steps aside, unless the player wants it up the whole time
function UI:HideOddsForShow()
    if not (ns.db and ns.db.oddsAlways) then f.oddsPanel:Hide() end
end

function UI:ToggleOdds()
    local expanded = not f.oddsPanel.expanded
    if ns.db then ns.db.uiShowOdds = expanded end
    self:ApplyOdds(expanded)
end

---------------------------------------------------------------------------
-- Per-frame
---------------------------------------------------------------------------

-- the motes drifting up from the bottom of the screen (thicker and gold after a Legendary)
function UI:Ambient(el, rate)
    if self.legendary then rate = rate * 2.5 end
    self.ambAcc = min(4, (self.ambAcc or 0) + el * rate)
    if self.ambAcc < 1 then return end
    local w, h = f.fx:GetWidth() or 1000, f.fx:GetHeight() or 700
    local r, g, b = self.ambR or GOLD_R, self.ambG or GOLD_G, self.ambB or GOLD_B
    while self.ambAcc >= 1 do
        self.ambAcc = self.ambAcc - 1
        local x = (random() - 0.5) * w
        if random() < 0.25 then
            -- a bigger, slower ember
            FX:Spawn("star", x, -h / 2 + random() * 40, (random() - 0.5) * 16, 12 + random() * 18,
                6 + random() * 4, 8 + random() * 6, 3, r, g, b, 0.55, -3, 0, 0.4)
        else
            FX:Spawn("star", x, -h / 2 + random() * 80, (random() - 0.5) * 12, 18 + random() * 34,
                4 + random() * 4, 4 + random() * 5, 2, r, g, b, 0.5, -3, 0, 0.6)
        end
    end
end

function UI:OnUpdate(el)
    self.clock = (self.clock or 0) + el
    local clock = self.clock

    -- screen shake moves the main stage and the solo reveal
    local sx, sy = FX.sx, FX.sy
    if sx ~= self.lastSx or sy ~= self.lastSy then
        self.lastSx, self.lastSy = sx, sy
        f.main:SetPoint("CENTER", f, "CENTER", sx, 20 + sy)
        f.show:SetPoint("TOPLEFT", f, "TOPLEFT", sx, sy)
        f.show:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", sx, sy)
    end

    local ph = self.phase
    if ph == "ready" then
        f.box:SetPoint("CENTER", f.stage, "CENTER", 0, 10 + 5 * sin(clock * 2.2))
        self:Ambient(el, 12)
    elseif ph == "charge" then
        self:UpdateCharge(el)
    elseif ph == "opening" then
        self:UpdateOpening(el)
        self:Ambient(el, 6)
    else
        self:Ambient(el, 7)
    end

    if self.spin then self:UpdateSpin(el) end

    -- Epic / Legendary results keep a twinkling aura while they sit on the stage
    local auraOK = not self.showcase
    local n = self.numCards or 0
    for i = 1, n do
        local c = f.cards[i]
        local d = c.data
        if auraOK and c.revealed and d and not d.empty and (d.tier or 1) >= 4 then
            c.auraAcc = (c.auraAcc or 0) + el * (d.tier >= 5 and 12 or 5)
            if c.auraAcc >= 1 then
                c.auraAcc = c.auraAcc - 1
                local x, y = FxPos(c)
                local r, g, b = TierColor(d.tier)
                FX:Twinkle(x, y, 1, (c:GetWidth() or 100) * 0.55, (c:GetHeight() or 150) * 0.55, r, g, b)
            end
        end
        if c.flipT then self:UpdateFlip(c, el) end
        if c.tell then
            EdgeGlowAlpha(c.glow, 0.5 + 0.3 * sin(clock * 4 + i))
            if not c.revealed then c.backStar:SetRotation(clock * 0.9 + i) end
        end
    end

    local at = self.auraTile
    if auraOK and at and at:IsShown() then
        self.auraAcc = (self.auraAcc or 0) + el * (self.auraTier >= 5 and 12 or 5)
        if self.auraAcc >= 1 then
            self.auraAcc = self.auraAcc - 1
            local x, y = FxPos(at)
            local r, g, b = TierColor(self.auraTier)
            FX:Twinkle(x, y, 1, TILE * 0.6, TILE * 0.6, r, g, b)
        end
    end

    if self.showcase then self:UpdateShowcase(el) end

    local b = f.mainBtn
    if b:IsShown() and b:IsEnabled() then
        EdgeGlowAlpha(b.glow, 0.3 + 0.25 * sin(clock * 3))
    else
        EdgeGlowAlpha(b.glow, 0)
    end
end

---------------------------------------------------------------------------
-- Act 1: pre-pull
---------------------------------------------------------------------------

local function SubText(self)
    local c = self.container
    if c.compLevel then
        -- every untranslated scroll is its own item (dozens of names per skill level), so the count is all
        -- comprehends together, not just this one scroll's
        local n = 0
        for id in pairs(ns.CompScrolls) do n = n + (ns.db.stats.opened[id] or 0) end
        return ("No odds known for these   |   You've comprehended %d   |   %d since your last Rare+"):format(
            n, ns.db.stats.sinceRare or 0)
    end
    if c.estimated then
        return ("No odds known for this one   |   You've done %d   |   %d since your last Rare+"):format(
            ns.db.stats.opened[self.itemID] or 0, ns.db.stats.sinceRare or 0)
    end
    return ("Drop data: %s recorded openings   |   You've opened %d   |   %d since your last Rare+"):format(
        BreakUpLargeNumbers and BreakUpLargeNumbers(c.opened or 0) or (c.opened or 0),
        ns.db.stats.opened[self.itemID] or 0, ns.db.stats.sinceRare or 0)
end

function UI:PrepareDeck()
    local n = max(ns.CardCount(self.itemID), #self.items)
    local deck = {}
    for _, d in ipairs(self.items) do deck[#deck + 1] = d end
    local jokes = (WET[self.itemID] and EMPTY_TEXT_WET) or (SCROLLS[self.itemID] and EMPTY_TEXT_SCROLL)
        or (self.container.world and EMPTY_TEXT_CHEST) or EMPTY_TEXT
    while #deck < n do
        deck[#deck + 1] = { empty = true, tier = 0, text = jokes[random(#jokes)] }
    end
    for i = #deck, 2, -1 do -- shuffle so position gives nothing away
        local j = random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end

    local cw = min(CARD_W, floor((STAGE_W - 20 - (n - 1) * CARD_GAP) / n))
    local ch = min(CARD_H, floor(cw * 1.5))
    local total = n * cw + (n - 1) * CARD_GAP
    local x0 = -total / 2 + cw / 2
    for i = 1, max(n, #f.cards) do
        local c = f.cards[i]
        if i <= n then
            if not c then
                c = CreateCard(f.stage, f.cardLevel)
                f.cards[i] = c
            end
            LayoutCard(c, cw, ch)
            SetCardFace(c, deck[i], self.itemID)
            c.tx, c.ty = x0 + (i - 1) * (cw + CARD_GAP), 6
            c:SetAlpha(1)
            c:EnableMouse(false)
            c:Hide()
        elseif c then
            c:Hide()
        end
    end
    self.numCards = n
end

-- a filler tile for the reel, weighted by sqrt(chance) so it shows some variety (and the odd tease)
local THUNDERFURY = 19019

local function RandomReelData(self)
    local c = self.container
    -- the once-only box (Soft-shelled Clam) only ever holds its meat, so its one show is a reel of nothing but
    -- Thunderfury... that lands on the meat. What did you expect?
    if ns.ONCE_ONLY[self.itemID] then
        return { itemID = THUNDERFURY, quality = 5, tier = 5,
            name = ns.ItemName(THUNDERFURY, "Thunderfury, Blessed Blade of the Windseeker") }
    end
    if c.failPct and random() * 100 < c.failPct then return ns.FailSlot() end -- the odd sheep
    local items = c.items
    local total = 0
    for _, r in ipairs(items) do total = total + math.sqrt(r[2]) end
    local x = random() * total
    local pick = items[#items]
    for _, r in ipairs(items) do
        x = x - math.sqrt(r[2])
        if x <= 0 then
            pick = r
            break
        end
    end
    local lo, hi = pick[5] or 1, pick[6] or 1
    return { itemID = pick[1], quality = pick[3], name = ns.ItemName(pick[1], pick[4]), count = random(lo, max(lo, hi)) }
end

-- near miss: the rarest thing in the box sits right next to where it stops
local function NearMiss(self, index, target)
    if random() >= 0.4 then return end
    local best, bestTier
    for _, r in ipairs(self.container.items) do
        local t = TierFor(self.itemID, r[1], r[3])
        if not best or t > bestTier or (t == bestTier and r[2] < best[2]) then best, bestTier = r, t end
    end
    if best and best[1] ~= target.itemID then
        local side = random() < 0.5 and -1 or 1
        SetTile(f.tiles[index + side], { itemID = best[1], quality = best[3], name = ns.ItemName(best[1], best[4]), tier = bestTier }, self.itemID)
    end
end

function UI:FillReel(target)
    for i = 1, REEL_TILES do
        local d = (i == TARGET and target) or RandomReelData(self)
        SetTile(f.tiles[i], d, self.itemID)
        f.tiles[i]:SetAlpha(1)
    end
    if target then NearMiss(self, TARGET, target) end
end

local function SetStrip(pos)
    f.strip:SetPoint("LEFT", f.reel, "LEFT", 6 - pos, 0)
end

-- received: the result is already in the bags (Comprehension, or auto loot got there first): nothing to collect
-- manual: opened from inside the case screen (My boxes / OPEN ANOTHER): wait for OPEN instead of auto-starting
-- fromCast: a world chest's opening cast already played the build-up: straight into the tell and the deal
function UI:Open(itemID, slots, live, received, manual, fromCast)
    if not f then Build() end
    local wasShown = f:IsShown()
    f:Show() -- (OnHide of a previous case resets state, so show first and reset after)
    self:Reset()
    local c = ns.GetContainer(itemID)
    self.itemID, self.container, self.live = itemID, c, live
    self.received = received and true or nil
    -- (the settings and My boxes views share this screen: a case always brings the stage back)
    f.main:Show()
    if f.settings then f.settings:Hide() end
    if f.mine then f.mine:Hide() end
    if f.stats then f.stats:Hide() end
    f.mainBtn:ClearAllPoints() -- (the "next" button may have pushed it aside last time)
    f.mainBtn:SetPoint("BOTTOM", f.main, "BOTTOM", 0, 14)

    local items, copper = {}, 0
    local best = 0
    for _, s in ipairs(slots) do
        if s.money then
            copper = copper + (s.copper or 0)
        else
            if not s.name or s.name == "" then s.name = ns.ItemName(s.itemID or 0) end
            if not s.icon then s.icon = ns.ItemIcon(s.itemID or 0) end
            s.tier = (s.heirloom and 7) or (s.elusive and not ns.IsHunted(s.itemID) and 6)
                or TierFor(itemID, s.itemID, s.quality)
            if s.tier > best then best = s.tier end
            items[#items + 1] = s
        end
    end
    self.style = ns.StyleFor(itemID, #items)
    -- a reel box that came up empty still spins: onto a tile of dust
    if self.style == "reel" and #items == 0 and not c.single then
        items[1] = { nothing = true, tier = 0, quality = 0, icon = DUST, name = "Nothing" }
    end
    self.items, self.copper, self.bestTier = items, copper, best

    f.caseIcon:SetTexture(ns.ItemIcon(itemID))
    f.title:SetText(c.name)
    f.sub:SetText(SubText(self))
    if live then
        f.tag:SetText("|cff40ff40LIVE|r")
    else
        f.tag:SetText("|cffaaaaaaDEMO|r")
    end

    self:FillOdds(c)
    self:ApplyOdds(ns.db and ns.db.uiShowOdds, not wasShown)
    if self.style == "reel" then
        self:FillReel(nil)
        SetStrip(0)
        self.numCards = 0
    else
        self:PrepareDeck()
    end

    -- the box
    self.phase = "ready"
    f.box:Show()
    f.box:SetAlpha(1)
    f.boxIcon:SetTexture(ns.ItemIcon(itemID))
    EdgeGlowColor(f.boxGlow, GOLD_R, GOLD_G, GOLD_B)
    EdgeGlowAlpha(f.boxGlow, 0.5)
    FX.HaloColor(f.halo, GOLD_R, GOLD_G, GOLD_B)
    f.halo.size, f.halo.spin = 320, 0.35
    f.halo:SetAlpha(0.3)
    self:SetWash(GOLD_R, GOLD_G, GOLD_B, 0.05)
    self.ambR, self.ambG, self.ambB = GOLD_R, GOLD_G, GOLD_B
    if fromCast then
        f.boxIcon:SetSize(84, 84)
    else
        FX:Tween(0.4, function(k)
            local s = 84 * max(0.05, EaseOutBack(k))
            f.boxIcon:SetSize(s, s)
        end)
    end

    local n = self.style == "reel" and 1 or self.numCards
    local what = self.style == "reel" and "1 item on the reel" or ("%d cards"):format(n)
    if self.oddsSummary ~= "" then
        f.info:SetText(what .. "   |cff666666|||r   " .. self.oddsSummary)
    else
        f.info:SetText(what .. "   |cff666666|||r   |cff9a9a9aNo Rare+ drops in this box|r")
    end
    f.info:SetAlpha(1)
    if received then
        f.hint:SetText(c.compLevel and "Deciphered! It's already in your bags. Don't peek."
            or "Auto-loot already put it all in your bags. Don't peek!")
    elseif ns.ONCE_ONLY[itemID] then
        f.hint:SetText(live and "There is one thing in here. There has only ever been one thing in here. Enjoy the show, just this once."
            or "Demo: there is only ever one thing in here.")
    elseif c.world and not live then
        f.hint:SetText("Demo: plays the opening too. Nothing is used up.")
    else
        f.hint:SetText(live and "Your box is ready." or "Demo roll: nothing is used up.")
    end
    local lv = live and ns.live
    if lv and lv.short and lv.short > 0 then
        f.hint:SetText(("|cffff6060Heads up: your bags are %s. %d item%s won't fit until you make room.|r")
            :format(lv.free == 0 and "full" or "nearly full", lv.short, lv.short == 1 and "" or "s"))
    end
    f.hint:SetAlpha(1)

    f.mainBtn:SetLabel(c.single and "REVEAL" or "OPEN")
    f.mainBtn:Enable()
    f.mainBtn:Show()
    f.skip:Hide()
    f.pick:SetShown(not live)
    f.picker:Hide()
    self:ShowForceBar(not live)

    if not wasShown then
        f:SetAlpha(0)
        FX:Tween(0.3, function(k) f:SetAlpha(k) end)
    else
        f:SetAlpha(1)
    end
    Sound("IG_BACKPACK_OPEN", 862)

    -- group loot: the game's roll windows (and the master looter's loot window) must stay usable on top
    local shared = 0
    for _, d in ipairs(items) do if d.shared then shared = shared + 1 end end
    self.sharedCount = shared
    if shared > 0 then self:RaiseLootFrames(true) end

    -- A world chest whose opening cast just played: no second build-up, straight into the tell
    if fromCast then
        f.mainBtn:Hide()
        f.hint:SetAlpha(0)
        self.castDone = true
        self:StartOpen()
        return
    end

    -- A real opening: the player already opened the box (and may have heard the loot land), so the show
    -- starts by itself after the fade-in instead of waiting for OPEN. The demo keeps its button.
    -- (A comprehend switches straight to its own spinning reel, so this finds it no longer "ready".)
    if live and not manual then
        f.mainBtn:Hide()
        local lvb = ns.live
        if not received and not (lvb and lvb.short and lvb.short > 0) then f.hint:SetText("Here it comes...") end
        FX:After(0.45, function()
            if f:IsShown() and self.phase == "ready" and self.itemID == itemID then self:StartOpen() end
        end)
    end
end

---------------------------------------------------------------------------
-- Act 2a: charge (the tier tell) and burst
---------------------------------------------------------------------------

function UI:StartOpen()
    -- a world chest in the demo plays a pretend opening cast first, like the real thing
    if self.container and self.container.world and not self.live and not self.castDone then
        local now = GetTime()
        self:BeginCast(now, now + DEMO_CAST * SpeedScale(), true)
        return
    end
    self.phase = "charge"
    f.mainBtn:Hide()
    f.pick:Hide()
    f.picker:Hide()
    f.forceBar:Hide()
    self:HideOddsForShow()
    f.skip:SetLabel("Skip")
    f.skip:Show()
    f.status:SetText("")
    FX:Tween(0.25, function(k)
        f.info:SetAlpha(1 - k)
        f.hint:SetAlpha(1 - k)
    end)

    -- the tell: starts low and steps up to the best tier inside; reels stay neutral
    local best = (self.style == "reel") and -1 or self.bestTier
    local seq
    if best < 0 then
        seq = { -1 }
    elseif best <= 1 then
        seq = { best }
    elseif best == 2 then
        seq = (random() < 0.25) and { 1, 2 } or { 2 }
    else
        seq = { random(1, 2) }
        local cur = seq[1]
        while cur < best do
            local stepUp = 1
            if best - cur >= 2 and random() < 0.3 then stepUp = 2 end
            cur = cur + stepUp
            seq[#seq + 1] = cur
        end
    end
    local sp = SpeedScale()
    if self.castDone then sp = sp * 0.6 end -- the opening cast already did the waiting
    local d0 = (best < 0 and 0.55 or (best <= 2 and 0.85 or 1.0)) * sp
    local lull = 0.45 * sp
    local times = { 0 }
    for i = 2, #seq do
        local gap = (i == 2) and d0 or 0.65 * sp
        if seq[i] >= 4 then gap = gap + lull end
        times[i] = times[i - 1] + gap
    end
    local dur = (#seq == 1) and d0 or (times[#seq] + 0.5 * sp)

    local bx, by = FxPos(f.box)
    self.charge = { t = 0, seq = seq, times = times, dur = dur, lull = lull, idx = 1, acc = 0, lastTick = 0,
        bx = bx, by = by, r = GOLD_R, g = GOLD_G, b = GOLD_B }
    self:TellUpgrade(seq[1])
    if not Sound("UI_BONUS_LOOT_ROLL_START") then Sound("IG_MAINMENU_OPEN", 850) end
end

function UI:TellUpgrade(level)
    local ch = self.charge
    local r, g, b = TierColor(level)
    ch.r, ch.g, ch.b = r, g, b
    FX.HaloColor(f.halo, r, g, b)
    EdgeGlowColor(f.boxGlow, r, g, b)
    EdgeGlowAlpha(f.boxGlow, 0.9)
    local L = max(level, 0)
    self:SetWash(r, g, b, 0.07 + 0.035 * L)
    self.ambR, self.ambG, self.ambB = r, g, b
    if ch.idx > 1 then
        FX:Flash(r, g, b, 0.16 + 0.06 * L, 0.45)
        FX:Shake(2 + L, 0.35)
        FX:Burst(ch.bx, ch.by, 14 + 8 * L, r, g, b, 260)
        FX:Ring(ch.bx, ch.by, r, g, b, 60, 420, 0.45)
        Sound("IG_PLAYER_INVITE", 880)
        if level >= 4 then Sound("READY_CHECK", 8960) end
    end
end

function UI:UpdateCharge(el)
    local ch = self.charge
    if not ch then return end
    ch.t = ch.t + el
    local seq, times = ch.seq, ch.times
    while ch.idx < #seq and ch.t >= times[ch.idx + 1] do
        ch.idx = ch.idx + 1
        self:TellUpgrade(seq[ch.idx])
    end
    local k = Clamp01(ch.t / ch.dur)
    local lull = false
    local nxt = times[ch.idx + 1]
    if nxt and seq[ch.idx + 1] >= 4 and ch.t >= nxt - ch.lull then lull = true end

    -- the box rattles harder and harder (and goes still just before a big upgrade)
    local amp = lull and 0.3 or (1 + 6 * k)
    f.box:SetPoint("CENTER", f.stage, "CENTER", (random() * 2 - 1) * amp, 10 + (random() * 2 - 1) * amp)
    local bs = 84 * (1 + 0.18 * k)
    f.boxIcon:SetSize(bs, bs)
    local h = f.halo
    h.size = 300 + 220 * k
    h.spin = lull and 0.25 or (1 + 5 * k)
    h:SetAlpha(lull and 0.2 or (0.45 + 0.5 * k))

    if not lull then
        ch.acc = ch.acc + el * (25 + 70 * k)
        while ch.acc >= 1 do
            ch.acc = ch.acc - 1
            FX:Converge(ch.bx, ch.by, 1, 150 + random() * 150, ch.r, ch.g, ch.b, 0.45 + random() * 0.3)
        end
        if ch.t - ch.lastTick > 0.17 - 0.11 * k then
            ch.lastTick = ch.t
            Sound("U_CHAT_SCROLL_BUTTON", 1115)
        end
    end
    if ch.t >= ch.dur then self:Burst() end
end

function UI:Burst()
    local ch = self.charge
    if not ch then return end
    self.charge = nil
    self.phase = "burst"
    local level = ch.seq[#ch.seq]
    local r, g, b = ch.r, ch.g, ch.b
    local L = max(level, 1)
    FX:Flash(r, g, b, 0.25 + 0.1 * L, 0.7)
    FX:Shake(level >= 3 and (2 + 2 * L) or 2, 0.5)
    FX:Burst(ch.bx, ch.by, 30 + 18 * L, r, g, b, 360 + 40 * L)
    FX:Ring(ch.bx, ch.by, r, g, b, 80, 900, 0.6)
    if not Sound("UI_STORE_UNWRAP") then Sound("IG_BACKPACK_OPEN", 862) end
    f.box:SetPoint("CENTER", f.stage, "CENTER", 0, 10)
    FX:Tween(0.25, function(k)
        local s = 84 * (1.18 + 0.6 * k)
        f.boxIcon:SetSize(s, s)
        f.box:SetAlpha(1 - k)
    end, function() f.box:Hide() end)
    -- the halo settles into a faint backdrop for the cards
    local rest = level >= 3 and 0.35 or 0.15
    FX:Tween(0.6, function(k)
        f.halo.size = 520 + 200 * k
        f.halo.spin = 1.5 - k
        f.halo:SetAlpha((1 - k) * 0.9 + k * rest)
    end)
    FX:After(0.22, function()
        if self.style == "reel" then self:StartReel() else self:Deal() end
    end)
end

---------------------------------------------------------------------------
-- World chests: the opening cast. Nothing is known yet, so the chest rattles harder as the bar fills while
-- its glow hops between random tier colours (a tease, it means nothing). The loot window ends it: the real
-- tell and the deal take over (Open with fromCast). The demo pretends the cast, then does the same.
---------------------------------------------------------------------------

function UI:BeginCast(startT, endT, demo)
    self.phase = "opening"
    f.mainBtn:Hide()
    f.pick:Hide()
    f.picker:Hide()
    f.forceBar:Hide()
    f.oddsPanel:Hide()
    f.skip:Hide()
    f.status:SetText("")
    f.info:SetAlpha(0)
    f.hint:SetAlpha(0)
    f.box:Show()
    f.box:SetAlpha(1)
    local bx, by = FxPos(f.box)
    self.cast = { start = startT or GetTime(), finish = endT, t = 0, hop = 0, acc = 0, tick = 0,
        bx = bx, by = by, demo = demo, r = GOLD_R, g = GOLD_G, b = GOLD_B }
    local cb = f.castBar
    cb.fill:SetColorTexture(GOLD_R, GOLD_G, GOLD_B, 1)
    cb.fill:SetWidth(1)
    cb.text:SetText(CHEST_LINES[random(#CHEST_LINES)])
    cb.text:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
    cb:Show()
    cb:SetAlpha(0)
    FX:Tween(0.2, function(k) cb:SetAlpha(k) end)
    Sound("IG_MAINMENU_OPEN", 850)
end

function UI:UpdateOpening(el)
    local o = self.cast
    if not o then return end
    o.t = o.t + el
    local k
    if o.finish and o.finish > o.start then
        k = Clamp01((GetTime() - o.start) / (o.finish - o.start))
    else
        k = Clamp01(o.t / 5) -- (no cast times: assume the usual 5 sec)
    end

    -- the tease: a random tier colour, hopping faster as the bar fills
    o.hop = o.hop - el
    if o.hop <= 0 then
        o.hop = 0.5 - 0.32 * k
        local t = random(1, 5)
        if t == o.lastT then t = (t % 5) + 1 end
        o.lastT = t
        o.r, o.g, o.b = TierColor(t)
        EdgeGlowColor(f.boxGlow, o.r, o.g, o.b)
        FX.HaloColor(f.halo, o.r, o.g, o.b)
        self.ambR, self.ambG, self.ambB = o.r, o.g, o.b
        self:SetWash(o.r, o.g, o.b, 0.04 + 0.05 * k)
    end

    -- the chest strains against its lid
    local amp = 0.4 + 4.5 * k * k
    f.box:SetPoint("CENTER", f.stage, "CENTER", (random() * 2 - 1) * amp, 10 + (random() * 2 - 1) * amp)
    local bs = 84 * (1 + 0.14 * k)
    f.boxIcon:SetSize(bs, bs)
    EdgeGlowAlpha(f.boxGlow, 0.45 + 0.45 * k)
    local h = f.halo
    h.size = 280 + 200 * k
    h.spin = 0.4 + 3.6 * k
    h:SetAlpha(0.25 + 0.55 * k)

    o.acc = o.acc + el * (10 + 55 * k)
    while o.acc >= 1 do
        o.acc = o.acc - 1
        FX:Converge(o.bx, o.by, 1, 140 + random() * 160, o.r, o.g, o.b, 0.35 + random() * 0.3)
    end
    if o.t - o.tick > 0.34 - 0.24 * k then
        o.tick = o.t
        Sound("U_CHAT_SCROLL_BUTTON", 1115)
    end

    local cb = f.castBar
    cb.fill:SetWidth(max(1, CAST_W * k))
    cb.fill:SetColorTexture(o.r * 0.5 + GOLD_R * 0.5, o.g * 0.5 + GOLD_G * 0.5, o.b * 0.5 + GOLD_B * 0.5, 1)
    cb.spark:SetVertexColor(o.r, o.g, o.b)
    cb.spark:SetAlpha(k < 1 and (0.6 + 0.4 * sin(o.t * 20)) or 0)

    -- the demo's pretend cast is done: on with the show. (A real one waits for the loot window, the chest
    -- just keeps straining at full if the server takes a moment.)
    if o.demo and k >= 1 then
        self.cast = nil
        self.castDone = true
        self:HideCastBar()
        self:StartOpen()
    end
end

function UI:HideCastBar()
    local cb = f and f.castBar
    if not cb or not cb:IsShown() then return end
    FX:Tween(0.2, function(k) cb:SetAlpha(1 - k) end, function() cb:Hide() end)
end

-- the opening cast started on a world chest we know: open the screen on the straining chest
function UI:OpenChestPending(id, startT, endT)
    if not ns.Containers[id] then return end
    self:Open(id, {}, true, true)
    self.pending = "chest"
    self:BeginCast(startT, endT, false)
end

-- the cast was interrupted, nothing came out, or the chest isn't ours to show: let go
function UI:CancelChest(msg)
    if not f or self.pending ~= "chest" then return end
    self.pending, self.cast = nil, nil
    self.phase = "cancelled"
    self:HideCastBar()
    if not msg then f:Hide() return end
    f.hint:SetText("|cffff8060" .. msg .. "|r")
    f.hint:SetAlpha(1)
    f.box:SetPoint("CENTER", f.stage, "CENTER", 0, 10)
    FX:Tween(0.6, function(k)
        f.box:SetAlpha(1 - 0.6 * k)
        f.halo:SetAlpha(0.6 * (1 - k))
    end)
    Sound("IG_MAINMENU_CLOSE", 851)
    local token = {}
    self.cancelToken = token
    FX:After(1.6, function()
        if self.cancelToken == token and self.phase == "cancelled" then f:Hide() end
    end)
end

---------------------------------------------------------------------------
-- Group loot: items that go to a roll or the master looter are revealed like the rest, stamped, and left
-- to the game. Its roll windows (and the loot window, for the master looter) are lifted above the screen.
---------------------------------------------------------------------------

-- (the loot window itself only once it's handed back: while hidden, its buttons would sit over the cards)
local LOOT_FRAMES = { "GroupLootContainer", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3",
    "GroupLootFrame4", "MasterLooterFrame" }
local raised -- [frame] = { strata, level }

function UI:RaiseLootFrames(on, list)
    if on then
        raised = raised or {}
        for _, name in ipairs(list or LOOT_FRAMES) do
            local fr = _G[name]
            if fr and fr.SetFrameStrata and not raised[fr] and not (fr.IsProtected and fr:IsProtected() and InCombatLockdown()) then
                raised[fr] = { fr:GetFrameStrata(), fr:GetFrameLevel() }
                fr:SetFrameStrata("FULLSCREEN_DIALOG")
                fr:SetFrameLevel(470)
            end
        end
    elseif raised then
        for fr, old in pairs(raised) do
            if not (fr.IsProtected and fr:IsProtected() and InCombatLockdown()) then
                fr:SetFrameStrata(old[1])
                fr:SetFrameLevel(old[2])
            end
        end
        raised = nil
    end
end

local STAMP = {
    roll = "UP FOR ROLL", master = "LOOTER'S CALL", locked = "NOT YOUR TURN",
}

-- the stamp across a shared card; d.result once someone got it
local function SetStamp(c, d)
    local st = c.stamp
    if not d or d.empty or not d.shared then st:Hide() return end
    local text, r, g, b = STAMP[d.shared] or "SHARED", 1, 0.82, 0.3
    if d.shared == "master" and d.mine then text = "YOURS TO HAND OUT" end
    if d.result == "you" then
        text, r, g, b = "YOURS!", 0.35, 1, 0.45
    elseif d.result == "other" then
        text, r, g, b = (d.winner and d.winner ~= "") and ("TO " .. d.winner:upper()) or "TAKEN", 0.7, 0.7, 0.72
    elseif d.result == "passed" then
        text, r, g, b = "EVERYONE PASSED", 0.7, 0.7, 0.72
    end
    st.text:SetText(text)
    st.text:SetTextColor(r, g, b)
    st:Show()
    c.face:SetAlpha(d.result == "other" and 0.45 or 1)
end

-- Core: a shared item found its owner
function UI:SharedResult(slot)
    if not f or not f:IsShown() then
        if slot.result == "you" then
            local r, g, b = TierColor(slot.tier or 1)
            ns.Print(("You won |cff%s%s|r!"):format(Hex(r, g, b), slot.name or "it"))
        end
        return
    end
    for i = 1, self.numCards or 0 do
        local c = f.cards[i]
        if c.data == slot then
            if c.revealed then
                SetStamp(c, slot)
                if slot.result == "you" then
                    local r, g, b = TierColor(slot.tier or 1)
                    local x, y = FxPos(c)
                    FX:Burst(x, y, 24, r, g, b, 220)
                    FlashCard(c, r, g, b, 0.8)
                    if not Sound("UI_EPICLOOT_TOAST") then Sound("READY_CHECK", 8960) end
                end
            end
            return
        end
    end
end

-- master looter: our share is in the bags, the rest waits in the loot window
function UI:HandOut()
    if not f or not f:IsShown() then return end
    self.collectPending = nil
    self.phase = "collected"
    self:RaiseLootFrames(true, { "LootFrame", "MasterLooterFrame" })
    f.status:SetText("Your share is in your bags. Hand out the rest from the loot window.")
    f.mainBtn:SetLabel("CLOSE")
    f.mainBtn:Enable()
    f.mainBtn:Show()
end

---------------------------------------------------------------------------
-- Act 2b: cards
---------------------------------------------------------------------------

function UI:Deal()
    self.phase = "deal"
    self.dealTw = {}
    local n = self.numCards
    for i = 1, n do
        local c = f.cards[i]
        c.x, c.y, c.s = 0, 10, 0.3
        PlaceCard(c)
        c:SetAlpha(0)
        c:Show()
        local tx, ty = c.tx, c.ty
        local last = (i == n)
        self.dealTw[#self.dealTw + 1] = FX:After((i - 1) * 0.08, function()
            self.dealTw[#self.dealTw + 1] = FX:Tween(0.42, function(k)
                local e = EaseOutBack(k)
                c.x = tx * e
                c.y = 10 + (ty - 10) * e
                c.s = 0.3 + 0.7 * e
                PlaceCard(c)
                c:SetAlpha(Clamp01(k * 3))
            end, function() self:CardLanded(c, last) end)
        end)
    end
    Sound("IG_ABILITY_PAGE_TURN", 836)
end

function UI:CardLanded(c, last)
    if c.landed then return end
    c.landed = true
    c.x, c.y, c.s = c.tx, c.ty, 1
    PlaceCard(c)
    c:SetAlpha(1)
    local t = c.data.tier or 0
    if not c.data.empty and t >= 3 then
        local r, g, b = TierColor(t)
        c.tell = true
        SetCardTell(c, t)
        local x, y = FxPos(c)
        FX:Burst(x, y, 12, r, g, b, 160)
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    else
        Sound("U_CHAT_SCROLL_BUTTON", 1115)
    end
    if last then
        self.dealTw[#self.dealTw + 1] = FX:After(0.15, function() self:CardsReady() end)
    end
end

function UI:FinishDeal()
    if self.phase ~= "deal" then return end
    for _, tw in ipairs(self.dealTw or {}) do FX:Cancel(tw) end
    for i = 1, self.numCards do
        local c = f.cards[i]
        c:Show()
        self:CardLanded(c, false)
    end
    self:CardsReady()
end

function UI:CardsReady()
    if self.phase ~= "deal" then return end
    self.phase = "cards"
    for i = 1, self.numCards do f.cards[i]:EnableMouse(true) end
    f.skip:SetLabel("Reveal all")
    if self.bestTier <= 2 then
        -- nothing special inside: don't make the player work for it
        FX:After(0.3, function()
            if self.phase == "cards" and not self.autoRevealing and not self.showcase then self:RevealAll() end
        end)
    else
        f.status:SetText("Something is glowing...  click a card to flip it")
    end
end

function UI:ClickCard(c)
    if self.phase ~= "cards" or self.autoRevealing or self.showcase then return end
    if c.revealed or c.flipT then return end
    self:RevealCard(c)
end

function UI:RevealCard(c, done)
    local d = c.data
    if not d.empty and (d.tier or 1) >= 4 then
        self:Showcase(c, d, done)
    else
        self:StartFlip(c)
    end
end

function UI:StartFlip(c)
    if c.revealed or c.flipT then return end
    c.flipT = 0
    c.swapped = false
    Sound("IG_ABILITY_PAGE_TURN", 836)
end

function UI:UpdateFlip(c, el)
    c.flipT = c.flipT + el
    local x = Clamp01(c.flipT / FLIP)
    local w = c.cw * abs(cos(pi * x))
    if w < 1 then w = 1 end
    c.inner:SetWidth(w)
    c.y = c.ty + 12 * sin(pi * x)
    PlaceCard(c)
    if x >= 0.5 and not c.swapped then
        c.swapped = true
        c.back:Hide()
        c.face:Show()
    end
    if x >= 1 then
        c.flipT = nil
        c.y = c.ty
        PlaceCard(c)
        self:CardRevealed(c, false)
    end
end

function UI:CardRevealed(c, fromShowcase)
    c.revealed = true
    c.flipT = nil
    c.back:Hide()
    c.face:Show()
    c.inner:SetWidth(c.cw)
    c:SetAlpha(1)
    local d = c.data
    SetStamp(c, d)
    local t = d.empty and 0 or (d.tier or 1)
    local r, g, b = TierColor(t)
    local x, y = FxPos(c)
    FlashCard(c, r, g, b, t == 0 and 0.4 or 0.9)
    if c.inner.SetBackdropBorderColor then c.inner:SetBackdropBorderColor(r, g, b, 1) end
    if t == 0 then
        FX:Dust(x, y, 10)
    elseif not fromShowcase then
        self:RevealFX(t, x, y)
    end
    if t >= 3 then Sheen(c) end
    if not fromShowcase then TierSound(t) end
    if t >= 3 then
        c.tell = true
        EdgeGlowColor(c.glow, r, g, b)
    else
        c.tell = false
        if t == 2 then
            EdgeGlowColor(c.glow, r, g, b)
            EdgeGlowAlpha(c.glow, 0.3)
        else
            EdgeGlowAlpha(c.glow, 0)
        end
    end
    FX:Tween(0.28, function(k)
        c.s = 1 + 0.12 * (1 - EaseOut2(k))
        PlaceCard(c)
    end)
    PopStars(c.stars, c.nStars, 15, fromShowcase and 0.03 or 0.07, false)
    self:CheckAllRevealed()
end

function UI:RevealAll()
    if self.phase ~= "cards" then return end
    if self.autoRevealing then
        self.fast = true
        return
    end
    local q = {}
    for i = 1, self.numCards do
        local c = f.cards[i]
        if not c.revealed and not c.flipT then q[#q + 1] = c end
    end
    table.sort(q, function(a, b) return Rank(a.data) < Rank(b.data) end)
    self.queue = q
    self.autoRevealing = true
    f.status:SetText("")
    f.skip:SetLabel("Faster")
    self:NextInQueue()
end

function UI:NextInQueue()
    local q = self.queue
    if not q or self.phase ~= "cards" then return end
    local c = table.remove(q, 1)
    if not c then
        self.autoRevealing = false
        return
    end
    if c.revealed or c.flipT then return self:NextInQueue() end
    local d = c.data
    if not d.empty and (d.tier or 1) >= 4 then
        -- a beat before the big one
        FX:After(self.fast and 0.1 or 0.45, function()
            if self.phase == "cards" then
                self:Showcase(c, d, function() self:NextInQueue() end)
            end
        end)
    else
        self:StartFlip(c)
        FX:After(self.fast and 0.05 or 0.16, function() self:NextInQueue() end)
    end
end

function UI:CheckAllRevealed()
    if self.phase ~= "cards" or self.showcase then return end
    for i = 1, self.numCards do
        if not f.cards[i].revealed then return end
    end
    self.phase = "ending"
    f.skip:Hide()
    FX:After(0.35, function() self:Summary() end)
end

---------------------------------------------------------------------------
-- Rarity effects, escalating: Common nothing, Uncommon a puff, Rare a proper pop, Epic the solo
-- cinematic plus a lingering aura, Legendary all of that plus fireworks, confetti and gold motes.
---------------------------------------------------------------------------

-- an item revealed on the stage (Epic+ already had their cinematic by now)
function UI:RevealFX(t, x, y)
    if t <= 1 then return end
    local r, g, b = TierColor(t)
    if t == 2 then
        FX:Burst(x, y, 10, r, g, b, 140)
        return
    end
    FX:Burst(x, y, 30, r, g, b, 260)
    FX:Ring(x, y, r, g, b, 40, 340, 0.45)
    FX:Shake(3, 0.3)
    FX:Flash(r, g, b, 0.12, 0.35)
    for i = 1, 5 do
        FX:After(0.12 * i, function() FX:Fountain(x, y - 30, 4, r, g, b) end)
    end
    FX:After(0.2, function() FX:Twinkle(x, y, 10, 60, 80, r, g, b) end)
end

-- Legendary: fireworks across the screen, confetti from the top, gold motes for the rest of the pull
-- each Legendary cinematic gets its own party (again = true); the summary only throws one if none happened
function UI:LegendaryParty(again)
    if self.partyDone and not again then return end
    self.partyDone = true
    self.legendary = true
    self.ambR, self.ambG, self.ambB = TierColor(5)
    local r, g, b = TierColor(5)
    local w, h = f.fx:GetWidth() or 1200, f.fx:GetHeight() or 800
    for i = 0, 8 do
        FX:After(0.2 + i * 0.3, function()
            local gold = i % 2 == 0
            FX:Firework((random() - 0.5) * w * 0.8, h * (0.05 + random() * 0.3),
                gold and r or 1, gold and g or 0.95, gold and b or 0.75)
            if i % 3 == 0 then Sound("UI_BONUS_LOOT_ROLL_END") end
        end)
    end
    for i = 0, 10 do
        FX:After(i * 0.28, function() FX:Confetti(16, r, g, b) end)
    end
end

---------------------------------------------------------------------------
-- Solo cinematic for Epic+ pulls
---------------------------------------------------------------------------

function UI:ShowcaseTell(level)
    local sc = self.showcase
    local card = f.showCard
    local r, g, b = TierColor(level)
    sc.r, sc.g, sc.b = r, g, b
    SetCardTell(card, level)
    EdgeGlowAlpha(card.glow, 0.8)
    FX.HaloColor(f.showHalo, r, g, b)
    self:SetWash(r, g, b, 0.16)
    self.ambR, self.ambG, self.ambB = r, g, b
end

function UI:Showcase(src, d, done, opts)
    local t = d.tier or 4
    local sc = { src = src, data = d, done = done, t = 0, tier = t, acc = 0, lastTick = 0 }
    -- opts.ascend (reel): the item glows in its slot, then rises in one smooth glide to centre stage
    -- (dim, halo, trail and energy all building on the way), charges briefly there and bursts
    sc.ascend = opts and opts.ascend
    self.showcase = sc
    -- No fake "upgrade": a card's back already glows its real tier, and on the reel the item is already on
    -- screen, so the reel version rises face-up (no mystery card, no flip).
    sc.from = t
    sc.faceUp = not src.isCard
    sc.upgraded = true
    -- several Epic/Legendary in one pull: count them so the hold screen can say "2nd Legendary"
    self.showCount = self.showCount or {}
    self.showCount[t] = (self.showCount[t] or 0) + 1
    sc.nth = self.showCount[t]
    local sp = min(SpeedScale(), 1.3)
    sc.tIn = 0.55
    if sc.ascend then
        local big = t >= 5
        sc.tPre = 0.35                                      -- glow in the slot
        sc.tIn = sc.tPre + (big and 1.2 or 0.95) * sp       -- the rise
        sc.tFlip = sc.tIn + (big and 0.5 or 0.35) * sp      -- charge at centre
        sc.tHold = sc.tFlip                                 -- burst, no flip
    elseif sc.faceUp then
        sc.tFlip = sc.tIn + (t >= 5 and 0.9 or 0.6) * sp
        sc.tHold = sc.tFlip -- no flip
    else
        sc.tFlip = sc.tIn + (t >= 5 and 1.6 or 1.1) * sp
        sc.tHold = sc.tFlip + 0.32
    end
    sc.tUp = sc.tIn + (sc.tFlip - sc.tIn) * 0.55
    sc.sx, sc.sy = RelPos(src, f.show)
    local sh = src:GetHeight() or CARD_H
    sc.ss = max(0.2, sh * src:GetEffectiveScale() / (CARD_H * f.show:GetEffectiveScale()))

    local card = f.showCard
    LayoutCard(card, CARD_W, CARD_H)
    SetCardFace(card, d, self.itemID)
    for i = 1, 5 do f.showStars[i]:Hide() end
    self:ShowcaseTell(sc.from)
    card.x, card.y, card.s = sc.sx, sc.sy, sc.ss
    PlaceCard(card)
    card:SetAlpha(1)
    card:Show()
    if sc.faceUp then
        card.back:Hide()
        card.face:Show()
    end
    src:SetAlpha(0)

    SetDim(0)
    f.dimOver:Show()
    f.show:SetAlpha(1)
    f.show:Show()
    f.show:EnableMouse(true)
    f.showText:SetAlpha(0)
    f.showHalo.size = 120
    f.showHalo.spin = 0.6
    f.showHalo:SetAlpha(0)
    f.skip:SetLabel("Skip")
    f.skip:Show()
    if not Sound("UI_BONUS_LOOT_ROLL_START") then Sound("IG_MAINMENU_OPEN", 850) end
end

-- the reel item's way up: glow in the slot, then one smooth arc to centre stage, everything building
function UI:ShowcaseAscend(t)
    local sc = self.showcase
    local card, h = f.showCard, f.showHalo
    local r, g, b = sc.r, sc.g, sc.b
    if t < sc.tPre then
        local k = t / sc.tPre
        card.x, card.y, card.s = sc.sx, sc.sy, sc.ss
        PlaceCard(card)
        EdgeGlowAlpha(card.glow, 0.9 * k)
        if random() < 0.6 then FX:Converge(sc.sx, sc.sy, 1, 70 + random() * 70, r, g, b, 0.3) end
        return
    end
    local k = (t - sc.tPre) / (sc.tIn - sc.tPre)
    local e = k * k * (3 - 2 * k) -- smoothstep: eases out of the slot and into the centre
    local amp = 3 * k * k         -- trembles more as it nears the centre
    card.x = sc.sx * (1 - e) + (random() * 2 - 1) * amp
    card.y = sc.sy + (SHOW_Y - sc.sy) * e + 60 * sin(pi * e) + (random() * 2 - 1) * amp
    card.s = sc.ss + (SHOW_SCALE - sc.ss) * e
    PlaceCard(card)
    SetDim(e)
    -- ends where the centre charge starts (alpha 0.5, size 500, spin 1), so nothing jumps
    h:SetAlpha(0.5 * e)
    h.size = 120 + 380 * e
    h.spin = 0.6 + 0.4 * e
    EdgeGlowAlpha(card.glow, 0.85 + 0.15 * sin(t * 14))
    -- a trail of sparkles behind it, and energy streaming into it
    if random() < 0.85 then FX:Twinkle(card.x, card.y, 1, 26 * card.s, 34 * card.s, r, g, b) end
    if random() < 0.7 then
        FX:Converge(card.x, card.y, 1, 140 + random() * 200, r, g, b, 0.3 + random() * 0.2)
    end
end

function UI:ShowcaseBoom()
    local sc = self.showcase
    local r, g, b = sc.r, sc.g, sc.b
    local big = sc.tier >= 5
    FX:Flash(r, g, b, big and 0.95 or 0.8, big and 1.0 or 0.75)
    FX:Shake(big and 12 or 8, big and 0.9 or 0.6)
    FX:Burst(0, SHOW_Y, big and 140 or 90, r, g, b, big and 640 or 480)
    FX:Burst(0, SHOW_Y, 30, 1, 1, 1, 320)
    FX:Ring(0, SHOW_Y, r, g, b, 100, big and 1400 or 1000, 0.7)
    FX:Ring(0, SHOW_Y, 1, 1, 1, 60, 600, 0.4)
    f.showHalo.size = 780
    TierSound(sc.tier)
    -- Epic: a second shockwave and a cloud of twinkles round the card
    FX:After(0.18, function() FX:Ring(0, SHOW_Y, r, g, b, 60, big and 1100 or 800, 0.6, 0.6) end)
    FX:Twinkle(0, SHOW_Y, big and 40 or 24, 170, 230, r, g, b)
    if big then
        FX:After(0.45, function()
            Sound("READY_CHECK", 8960)
            FX:Burst(0, SHOW_Y, 60, 1, 0.85, 0.4, 420)
            FX:Flash(1, 0.85, 0.4, 0.5, 0.6)
        end)
        FX:After(0.36, function() FX:Ring(0, SHOW_Y, 1, 0.9, 0.6, 40, 1500, 0.8, 0.5) end)
        self:LegendaryParty(true)
    end
    FlashCard(f.showCard, 1, 1, 1, 1)
end

function UI:ShowcaseHold()
    local sc = self.showcase
    local d = sc.data
    local r, g, b = sc.r, sc.g, sc.b
    f.showTier:SetText(TierLabel(sc.tier):upper() .. "!")
    f.showTier:SetTextColor(r, g, b)
    local name = d.name or "?"
    if d.count and d.count > 1 then name = name .. " x" .. d.count end
    f.showName:SetText(name)
    f.showName:SetTextColor(ns.QualityColor(d.quality or 1))
    local pct
    for _, row in ipairs(self.container.items) do
        if row[1] == d.itemID then pct = row[2] end
    end
    local sub = ""
    if d.elusive then
        sub = ("Not on our loot list for %s at all!"):format(self.container.scrollName or self.container.name)
    elseif pct and pct > 0 and not self.container.estimated then
        sub = ("Drops in %s of %s  (about 1 in %d)"):format(PctText(pct), self.container.name, max(1, floor(100 / pct + 0.5)))
    end
    if (sc.nth or 1) >= 2 then
        local ord = ({ "", "2nd", "3rd" })[sc.nth] or (sc.nth .. "th")
        sub = ("|cff%s%s %s this pull!|r   %s"):format(Hex(r, g, b), ord, TierLabel(sc.tier), sub)
    end
    f.showSub:SetText(sub)
    f.showHint:SetText("Click anywhere to continue")
    FX:Tween(0.35, function(k) f.showText:SetAlpha(k) end)
    PlayPop(f.showTierAnim)
    LayoutStars(f.showStars, sc.tier, 30, 4, f.show, "CENTER", 0, SHOW_Y - CARD_H * SHOW_SCALE / 2 - 56)
    PopStars(f.showStars, sc.tier, 30, 0.13, true)
    PopStars(f.showCard.stars, f.showCard.nStars or 0, 15, 0.05, false)
end

function UI:UpdateShowcase(el)
    local sc = self.showcase
    if sc.out then return end
    sc.t = sc.t + el
    local t = sc.t
    local card = f.showCard
    local h = f.showHalo
    if t < sc.tIn and sc.ascend then
        self:ShowcaseAscend(t)
    elseif t < sc.tIn then
        local k = EaseOut4(t / sc.tIn)
        card.x = sc.sx * (1 - k)
        card.y = sc.sy + (SHOW_Y - sc.sy) * k
        card.s = sc.ss + (SHOW_SCALE - sc.ss) * k
        PlaceCard(card)
        SetDim(k)
        h:SetAlpha(0.5 * k)
        h.size = 120 + 380 * k
        h.spin = 0.6
    elseif t < sc.tFlip then
        if not sc.charged then
            sc.charged = true
            SetDim(1)
        end
        local k = (t - sc.tIn) / (sc.tFlip - sc.tIn)
        if not sc.upgraded and t >= sc.tUp then
            sc.upgraded = true
            self:ShowcaseTell(sc.tier)
            FX:Flash(sc.r, sc.g, sc.b, 0.35, 0.5)
            FX:Shake(5, 0.4)
            FX:Burst(0, SHOW_Y, 36, sc.r, sc.g, sc.b, 340)
            FX:Ring(0, SHOW_Y, sc.r, sc.g, sc.b, 80, 700, 0.5)
            Sound("IG_PLAYER_INVITE", 880)
            Sound("READY_CHECK", 8960)
        end
        local amp = 1 + 4 * k
        card.x = (random() * 2 - 1) * amp
        card.y = SHOW_Y + (random() * 2 - 1) * amp
        card.s = SHOW_SCALE * (1 + 0.05 * k)
        PlaceCard(card)
        card.backStar:SetRotation(t * (1 + 6 * k))
        EdgeGlowAlpha(card.glow, 0.6 + 0.4 * k * sin(t * 18))
        h:SetAlpha(0.5 + 0.4 * k)
        h.size = 500 + 200 * k
        h.spin = 1 + 5 * k
        sc.acc = sc.acc + el * (40 + 90 * k)
        while sc.acc >= 1 do
            sc.acc = sc.acc - 1
            FX:Converge(0, SHOW_Y, 1, 200 + random() * 220, sc.r, sc.g, sc.b, 0.4 + random() * 0.3)
        end
        if t - sc.lastTick > 0.16 - 0.12 * k then
            sc.lastTick = t
            Sound("U_CHAT_SCROLL_BUTTON", 1115)
        end
    elseif t < sc.tHold then
        if not sc.flipping then
            sc.flipping = true
            sc.acc = 0
            SetDim(1)
            card.x, card.y, card.s = 0, SHOW_Y, SHOW_SCALE
            PlaceCard(card)
            h:SetAlpha(0.9)
            h.size = 700
            h.spin = 5
            Sound("IG_ABILITY_PAGE_TURN", 836)
        end
        local x = (t - sc.tFlip) / (sc.tHold - sc.tFlip)
        local w = card.cw * abs(cos(pi * x))
        if w < 1 then w = 1 end
        card.inner:SetWidth(w)
        if x >= 0.5 and not sc.swapped then
            sc.swapped = true
            card.back:Hide()
            card.face:Show()
            self:ShowcaseBoom()
        end
    else
        if not sc.holding then
            sc.holding = true
            if not sc.swapped then
                sc.swapped = true
                card.back:Hide()
                card.face:Show()
                self:ShowcaseBoom()
            end
            card.inner:SetWidth(card.cw)
            card.x, card.s = 0, SHOW_SCALE
            SetDim(1) -- (a Skip mid-rise lands here straight away)
            EdgeGlowAlpha(card.glow, 0.9)
            Sheen(card)
            self:ShowcaseHold()
        end
        sc.acc = sc.acc + el * (sc.tier >= 5 and 55 or 30)
        while sc.acc >= 1 do
            sc.acc = sc.acc - 1
            FX:Fountain((random() - 0.5) * 260, SHOW_Y - 150, 1, sc.r, sc.g, sc.b)
            if random() < 0.35 then FX:Twinkle(0, SHOW_Y, 1, 150, 200, sc.r, sc.g, sc.b) end
        end
        h.spin = 0.8
        h:SetAlpha(0.75 + 0.15 * sin(t * 2))
        card.y = SHOW_Y + 4 * sin((t - sc.tHold) * 2)
        PlaceCard(card)
    end
end

function UI:ShowcaseClose()
    local sc = self.showcase
    if not sc or sc.out or not sc.holding then return end
    sc.out = true
    f.show:EnableMouse(false)
    FX:Tween(0.3, function(k)
        f.show:SetAlpha(1 - k)
        SetDim(1 - k)
    end, function()
        f.show:Hide()
        f.dimOver:Hide()
        f.show:SetAlpha(1)
        self.showcase = nil
        local src = sc.src
        src:SetAlpha(1)
        self:SetWash(sc.r, sc.g, sc.b, 0.08)
        local x, y = FxPos(src)
        FX:Burst(x, y, 20, sc.r, sc.g, sc.b, 200)
        if self.phase == "cards" then
            f.skip:SetLabel(self.autoRevealing and "Faster" or "Reveal all")
        end
        if src.isCard then self:CardRevealed(src, true) end
        if sc.done then sc.done() end
    end)
end

---------------------------------------------------------------------------
-- Act 2c: reel (single-item boxes)
---------------------------------------------------------------------------

function UI:StartReel()
    self.phase = "reel"
    f.reel:Show()
    f.reel:SetAlpha(0)
    FX:Tween(0.25, function(k) f.reel:SetAlpha(k) end)
    self.spinIndex, self.resultCount = 0, 0
    self:SpinNext()
end

function UI:SpinNext()
    self.spinIndex = self.spinIndex + 1
    local d = self.items[self.spinIndex]
    if not d then
        self.phase = "ending"
        f.skip:Hide()
        FX:After(0.3, function() self:Summary() end)
        return
    end
    self:FillReel(d)
    SetStrip(0)
    self.landIndex = TARGET
    local jitter = (random() - 0.5) * TILE * 0.8
    local dist = (TARGET - 1) * STEP + TILE / 2 + 6 - STAGE_W / 2 + jitter
    local dur = (ns.db.spinTime or 5) * (self.spinIndex == 1 and 1 or 0.6)
    self.spin = { t = 0, dur = dur, dist = dist, data = d, lastTick = 0 }
    f.banner:SetText("")
    f.reelText:SetText(#self.items > 1 and ("Item %d of %d"):format(self.spinIndex, #self.items) or "")
    f.skip:SetLabel("Skip")
    f.skip:Show()
end

-- the tick as each tile passes the marker
local function ReelTick(s, pos)
    local idx = floor((pos + STAGE_W / 2 - 6) / STEP)
    if idx ~= s.lastIdx then
        s.lastIdx = idx
        local now = GetTime()
        if now - (s.lastTick or 0) > 0.035 then
            s.lastTick = now
            Sound("U_CHAT_SCROLL_BUTTON", 1115)
        end
    end
end

function UI:UpdateSpin(el)
    local s = self.spin
    if s.mode == "cruise" then return self:UpdateCruise(s, el) end
    if s.mode == "land" then return self:UpdateLand(s, el) end
    s.t = min(s.t + el, s.dur)
    local x = s.t / s.dur
    local pos = EaseOut4(x) * s.dist
    SetStrip(pos)
    local glow = 0.25 + 0.5 * (1 - x)
    f.markL:SetAlpha(glow)
    f.markR:SetAlpha(glow)
    ReelTick(s, pos)
    if s.t >= s.dur then
        self.spin = nil
        self:RevealReel(s.data)
    end
end

---------------------------------------------------------------------------
-- Live Comprehension: the reel spins while the spell is cast ("cruise", wrapping round so it never
-- runs out of tiles), and when the result comes in it's placed further along the reel and the reel
-- eases onto it ("land"): a cubic ease-out whose starting speed is the cruise speed, so there's no jolt.
---------------------------------------------------------------------------

local CRUISE_V, CRUISE_ACCEL = 1700, 0.6 -- px/s, seconds to get up to speed
local WRAP_AT, WRAP_BY = 30, 20          -- tiles
local LAND_T = 2.6                       -- seconds the glide onto the result takes

function UI:OpenPending(itemID)
    if not ns.Containers[itemID] then return false end
    self:Open(itemID, {}, true, true)
    self.pending = true
    self.items, self.bestTier, self.style = {}, 0, "reel"
    -- the cast is the opening: no box, no button, straight into the spinning reel
    f.box:Hide()
    f.halo:SetAlpha(0)
    f.mainBtn:Hide()
    f.pick:Hide()
    f.forceBar:Hide()
    f.picker:Hide()
    self:HideOddsForShow()
    f.info:SetAlpha(0)
    f.hint:SetAlpha(0)
    f.skip:Hide()
    self.phase = "reel"
    f.reel:Show()
    f.reel:SetAlpha(0)
    FX:Tween(0.25, function(k) f.reel:SetAlpha(k) end)
    self.spinIndex, self.resultCount = 1, 0
    self:FillReel(nil)
    SetStrip(0)
    self.landIndex = nil
    self.spin = { mode = "cruise", t = 0, pos = 0, v = 0, lastTick = 0 }
    f.banner:SetText("")
    f.status:SetText("")
    f.reelText:SetText("|cff9a9a9aComprehending...|r")
    return true
end

-- the result is in (already in the bags): queue the landing; the reel keeps cruising for a moment first
-- if the result came in very quickly, so it still feels like a spin
function UI:ResolvePending(slot)
    local s = self.spin
    if not f or not f:IsShown() or not self.pending or not s or s.mode ~= "cruise" then return false end
    self.pending = nil
    if not slot.icon then slot.icon = slot.itemID and ns.ItemIcon(slot.itemID) end
    slot.tier = (slot.fail and 1) or (slot.elusive and not ns.IsHunted(slot.itemID) and 6)
        or TierFor(self.itemID, slot.itemID, slot.quality)
    self.items, self.bestTier = { slot }, slot.fail and 0 or slot.tier
    s.result = slot
    -- sheep: the player already knows (the sound, the wool), so no build-up: slam onto it right away
    s.abrupt = slot.fail and true or nil
    return true
end

-- interrupted / failed cast: ease the reel to a stop and close
function UI:CancelPending(msg)
    if not f or not self.pending then return end
    self.pending = nil
    local s = self.spin
    if s and s.mode == "cruise" then
        local p0, v = s.pos, s.v
        self.spin = nil
        FX:Tween(0.6, function(k)
            local u = 1 - (1 - k) * (1 - k)
            SetStrip(p0 + v * 0.3 * u)
            f.reel:SetAlpha(1 - 0.6 * k)
        end)
    end
    f.reelText:SetText("|cffff8060" .. (msg or "Interrupted.") .. "|r")
    local token = {}
    self.cancelToken = token
    FX:After(1.4, function()
        if self.cancelToken == token and not self.pending then f:Hide() end
    end)
end

function UI:WrapReel(s)
    s.pos = s.pos - WRAP_BY * STEP
    for i = 1, REEL_TILES - WRAP_BY do
        SetTile(f.tiles[i], f.tiles[i + WRAP_BY].data, self.itemID)
    end
    for i = REEL_TILES - WRAP_BY + 1, REEL_TILES do
        SetTile(f.tiles[i], RandomReelData(self), self.itemID)
    end
    s.lastIdx = nil
end

function UI:UpdateCruise(s, el)
    s.t = s.t + el
    s.v = CRUISE_V * EaseOut2(min(1, s.t / CRUISE_ACCEL))
    s.pos = s.pos + s.v * el
    if s.pos > WRAP_AT * STEP then self:WrapReel(s) end
    SetStrip(s.pos)
    f.markL:SetAlpha(0.75)
    f.markR:SetAlpha(0.75)
    ReelTick(s, s.pos)
    if s.result and (s.abrupt or (s.t >= 1.2 and s.v >= CRUISE_V * 0.99)) then
        self:LandOn(s, s.result, s.abrupt)
    end
end

-- abrupt: a hard stop a couple of tiles ahead (the sheep), instead of the long glide
function UI:LandOn(s, d, abrupt)
    local v = max(s.v, 200)
    local T = abrupt and 0.32 or LAND_T
    -- the tile a cubic ease-out of T at this speed reaches (distance = v * T / 3)
    local atMarker = (s.pos + STAGE_W / 2 - 6 - TILE / 2) / STEP + 1
    local ti = floor(atMarker + v * T / 3 / STEP + 0.5)
    if ti <= atMarker then ti = floor(atMarker) + 1 end
    ti = min(REEL_TILES - 2, ti)
    SetTile(f.tiles[ti], d, self.itemID)
    if not abrupt then NearMiss(self, ti, d) end
    local jitter = abrupt and 0 or (random() - 0.5) * TILE * 0.8
    local dest = (ti - 1) * STEP + TILE / 2 + 6 - STAGE_W / 2 + jitter
    local D = dest - s.pos
    self.landIndex = ti
    self.spin = { mode = "land", t = 0, T = abrupt and max(0.18, min(0.45, 3 * D / v)) or max(0.8, 3 * D / v),
        p0 = s.pos, D = D, data = d, lastTick = s.lastTick, lastIdx = s.lastIdx }
    f.reelText:SetText("")
end

function UI:UpdateLand(s, el)
    s.t = min(s.t + el, s.T)
    local u = s.t / s.T
    local pos = s.p0 + s.D * (1 - (1 - u) ^ 3)
    SetStrip(pos)
    local glow = 0.25 + 0.5 * (1 - u)
    f.markL:SetAlpha(glow)
    f.markR:SetAlpha(glow)
    ReelTick(s, pos)
    if s.t >= s.T then
        self.spin = nil
        self:RevealReel(s.data)
    end
end

function UI:RevealReel(d)
    local land = self.landIndex or TARGET
    local tile = f.tiles[land]
    if (d.tier or 1) >= 4 and not d.fail then
        -- hit-stop: a blink, the rest of the reel fades back, then the item rises to centre stage
        FX:Flash(1, 1, 1, 0.18, 0.25)
        Sound("IG_ABILITY_PAGE_TURN", 836)
        for i, tl in ipairs(f.tiles) do
            if i ~= land then
                local a0 = tl:GetAlpha()
                FX:Tween(0.4, function(k) tl:SetAlpha(a0 * (1 - 0.8 * k)) end)
            end
        end
        f.markL:SetAlpha(0)
        f.markR:SetAlpha(0)
        f.skip:Hide()
        FX:After(0.12, function()
            if self.phase == "reel" then
                self:Showcase(tile, d, function() self:AfterReel(d, true) end, { ascend = true })
            end
        end)
        return
    end
    self:AfterReel(d, false)
end

-- landing on the sheep: a quick, comic jolt instead of a reveal (white-pink flash, a thump, a wool puff,
-- the reel wobbling sideways for a moment)
function UI:SheepFX(tile, x, y)
    FX:Flash(1, 0.86, 0.94, 0.4, 0.3)
    FX:Shake(8, 0.3)
    FX:Wool(x, y, 34)
    FX:Ring(x, y, 1, 0.85, 0.93, 30, 420, 0.35, 0.8)
    FlashTile(tile, 1, 1, 1)
    Sound("IG_MAINMENU_OPTION_CHECKBOX_OFF", 857)
    Sound("IG_QUEST_FAILED", 847)
    local x0 = f.strip:GetLeft() and select(4, f.strip:GetPoint(1)) or nil
    if x0 then
        FX:Tween(0.3, function(k)
            f.strip:SetPoint("LEFT", f.reel, "LEFT", x0 + 10 * sin(k * pi * 5) * (1 - k), 0)
        end, function() f.strip:SetPoint("LEFT", f.reel, "LEFT", x0, 0) end)
    end
end

function UI:AfterReel(d, fromShowcase)
    local tile = f.tiles[self.landIndex or TARGET]
    local t = d.tier or 1
    local r, g, b = TierColor(t)
    FlashTile(tile, r, g, b)
    local x, y = FxPos(tile)
    if not fromShowcase then
        if d.fail then self:SheepFX(tile, x, y) else TierSound(t) self:RevealFX(t, x, y) end
    end
    if t >= 4 and not d.fail then self.auraTile, self.auraTier = tile, t end
    if d.fail then
        SetBanner("BAAA!", 0.95, 0.9, 0.92)
        f.status:SetText("The scroll read you instead. 8 seconds of wool. (The scroll survives: try again!)")
    elseif d.nothing then
        SetBanner("Nothing...", r, g, b)
        f.status:SetText(((self.copper or 0) > 0 and "No item this time, just coins.")
            or (ns.ONCE_ONLY[self.itemID] and "Not even the meat. What did you expect?")
            or "It was empty. That happens sometimes.")
    elseif ns.ONCE_ONLY[self.itemID] then
        -- straight to the punchline (no "You got ..." flashing first)
        SetBanner(BannerText(t), r, g, b)
        f.status:SetText("What did you expect?")
    else
        SetBanner(BannerText(t), r, g, b)
        f.status:SetText(("You got |cff%s%s|r%s"):format(Hex(ns.QualityColor(d.quality or 1)), d.name or "?",
            (d.count and d.count > 1) and (" x" .. d.count) or ""))
    end

    self.resultCount = (self.resultCount or 0) + 1
    local rt = f.results[self.resultCount]
    if rt then
        SetTile(rt, d, self.itemID)
        local shown = min(#self.items, #f.results)
        for i = 1, self.resultCount do
            f.results[i]:ClearAllPoints()
            f.results[i]:SetPoint("BOTTOM", f.stage, "BOTTOM", (i - (shown + 1) / 2) * 46, 2)
        end
        rt:Show()
        FlashTile(rt, r, g, b)
    end

    if self.spinIndex < #self.items then
        FX:After(1.2, function() if self.phase == "reel" then self:SpinNext() end end)
    else
        self.phase = "ending"
        f.skip:Hide()
        FX:After(0.6, function() self:Summary() end)
    end
end

---------------------------------------------------------------------------
-- Act 3: summary
---------------------------------------------------------------------------

function UI:CountCoins()
    local copper = self.copper or 0
    local p = f.purse
    if copper <= 0 then
        p:Hide()
        return
    end
    p:Show()
    p:SetAlpha(1)
    local dur = copper >= 10000 and 1.6 or (copper >= 100 and 1.1 or 0.7)
    local lastIcon
    local lastTick = 0
    self.coinTween = FX:Tween(dur, function(k)
        local v = floor(copper * EaseOut2(k) + 0.5)
        p.text:SetText(ns.CoinText(v))
        local icon = ns.CoinIcon(v)
        if icon ~= lastIcon then
            if lastIcon then
                -- copper -> silver -> gold
                p.flash:SetVertexColor(1, 0.85, 0.3)
                p.flash:SetAlpha(1)
                local x, y = FxPos(p)
                FX:Burst(x, y, 14, 1, 0.82, 0.3, 160)
                Sound("LOOT_WINDOW_COIN_SOUND", 120)
            end
            lastIcon = icon
            p.icon:SetTexture(icon)
        end
        p.flash:SetAlpha(max(0, p.flash:GetAlpha() - 0.05))
        local now = GetTime()
        if k < 1 and now - lastTick > 0.08 then
            lastTick = now
            Sound("U_CHAT_SCROLL_BUTTON", 1115)
        end
    end, function()
        self.coinTween = nil
        p.flash:SetVertexColor(1, 0.85, 0.3)
        p.flash:SetAlpha(1)
        FX:Tween(0.6, function(k) p.flash:SetAlpha(1 - k) end)
        local x, y = FxPos(p)
        FX:Burst(x, y, 20, 1, 0.82, 0.3, 200)
        Sound("LOOT_WINDOW_COIN_SOUND", 120)
    end)
end

function UI:Summary()
    if self.phase == "done" or self.phase == "collected" then return end
    self.phase = "done"
    f.skip:Hide()
    local best = self.bestTier or 0
    if #self.items == 1 and self.items[1].fail then
        SetBanner("BAAA!", 0.95, 0.9, 0.92)
        LayoutStars(f.bannerStars, 0, 18, 2, f.banner, "BOTTOM", 0, -12)
    elseif #self.items == 0 or self.items[1].nothing then
        SetBanner((self.copper or 0) > 0 and "Just coins!" or (#self.items > 0 and "Nothing..." or "Only dust..."),
            0.65, 0.65, 0.68)
        LayoutStars(f.bannerStars, 0, 18, 2, f.banner, "BOTTOM", 0, -12)
    else
        local r, g, b = TierColor(best)
        -- several of the best tier: "DOUBLE LEGENDARY!!!!", and each of them gets a pop on the stage
        local nBest = 0
        for _, d in ipairs(self.items) do
            if (d.tier or 1) == best then nBest = nBest + 1 end
        end
        local text = BannerText(best)
        if best >= 2 and nBest >= 2 then
            text = (({ "", "DOUBLE ", "TRIPLE ", "QUADRUPLE " })[nBest] or (nBest .. "x ")) .. text
        end
        SetBanner(text, r, g, b)
        LayoutStars(f.bannerStars, best, 18, 2, f.banner, "BOTTOM", 0, -12)
        PopStars(f.bannerStars, best, 18, 0.06, false)
        if best >= 3 then
            local x, y = FxPos(f.stage)
            FX:Fountain(x, y - 120, 8 + 8 * (best - 3), r, g, b)
            if nBest >= 2 and self.style == "pull" then
                for i = 1, self.numCards or 0 do
                    local c = f.cards[i]
                    if c.data and not c.data.empty and (c.data.tier or 1) == best then
                        local cx, cy = FxPos(c)
                        FX:After(0.1 * i, function()
                            FX:Ring(cx, cy, r, g, b, 40, 300, 0.45)
                            FX:Burst(cx, cy, 18, r, g, b, 220)
                        end)
                    end
                end
            end
        end
        if best >= 5 then self:LegendaryParty() end
    end
    -- an item the box isn't known to drop: once it's been revealed, ask for a report in chat
    if self.live then
        for _, d in ipairs(self.items) do
            if d.elusive and ns.ReportElusive then ns.ReportElusive(self.itemID, d) end
        end
    end
    if self.style == "pull" then
        f.status:SetText(("%d of %d slots filled"):format(#self.items, self.numCards or 0))
    end
    if (self.sharedCount or 0) > 0 then
        local n = self.sharedCount
        f.status:SetText(("%d of %d slots filled   |cffffd24d%d up to the group%s|r")
            :format(#self.items, self.numCards or 0, n, (self.received or not self.live) and "." or ": Collect takes the rest."))
    end
    self:CountCoins()
    -- (the line under the title was drawn before this opening was counted: a comprehend or an auto-looted box
    -- is in the stats by now; a box still to collect gets counted, and redrawn, on Collect)
    f.sub:SetText(SubText(self))

    if self.received then
        f.mainBtn:SetLabel("CLOSE")
    else
        f.mainBtn:SetLabel(self.live and "COLLECT" or (self.container.single and "AGAIN" or "OPEN AGAIN"))
    end
    f.mainBtn:Enable()
    f.mainBtn:Show()
    f.pick:SetShown(not self.live)
    self:ShowForceBar(not self.live)
    self:ApplyOdds(ns.db and ns.db.uiShowOdds) -- (fades back in if it was hidden for the show)

    if ns.ONCE_ONLY[self.itemID] and not (self.items[1] and self.items[1].nothing) then -- (empty: keep its line)
        f.status:SetText(self.live and "What did you expect? (That was its one show: these open normally from now on.)"
            or "What did you expect?")
    end
    local lv = self.live and ns.live
    if lv and lv.short and lv.short > 0 then
        f.status:SetText(("|cffff6060Bags full: %d item%s won't fit. Collect takes what fits; the rest stays in the loot window.|r")
            :format(lv.short, lv.short == 1 and "" or "s"))
    end
    -- Comprehension: keep going without closing the screen
    if self.received and self.container.compLevel then self:OfferNextScroll() end
    -- a box auto-loot already emptied: nothing to collect, so batch mode offers the next one right away
    if self.received and not self.container.compLevel and ns.db.batch then
        self.phase = "collected"
        self:OfferNextBox(self.itemID)
    end
    -- auto-collect: a beat to take in the banner and coins, then loot as if COLLECT was clicked
    -- (clicking COLLECT sooner still works; the timer then finds the phase moved on and does nothing)
    if self.live and not self.received then
        if ns.db.autoCollect then
            self:ScheduleAutoCollect(ns.live)
        else
            ns.Debug("auto-collect is off: waiting for COLLECT")
        end
    end
end

-- Auto-collect: wait a beat, then collect as if COLLECT was clicked. Something still on screen (a spotlight,
-- a flip finishing) only delays it: it checks again every quarter second for a while instead of giving up.
function UI:ScheduleAutoCollect(lv)
    local tries = 0
    local function Try()
        if not f:IsShown() or ns.live ~= lv or not self.live then
            return ns.Debug("auto-collect: the case closed or changed, nothing to do")
        end
        if self.phase ~= "done" or self.collectPending then
            return ns.Debug("auto-collect: already collected (phase " .. tostring(self.phase) .. ")")
        end
        if self.showcase or (lv and lv.collecting) then
            tries = tries + 1
            if tries > 40 then return ns.Debug("auto-collect: gave up waiting, COLLECT it is") end
            C_Timer.After(0.25, Try)
            return
        end
        ns.Debug("auto-collect: collecting")
        self:OnMainButton()
    end
    ns.Debug(("auto-collect in %.1fs"):format(AUTO_COLLECT_DELAY))
    C_Timer.After(AUTO_COLLECT_DELAY, Try)
end

---------------------------------------------------------------------------
-- Flow
---------------------------------------------------------------------------

function UI:Reset()
    self.phase = nil
    self.charge, self.spin, self.showcase, self.queue = nil, nil, nil, nil
    self.autoRevealing, self.fast = false, false
    self.coinTween, self.collectPending = nil, nil
    self.partyDone, self.legendary, self.auraTile, self.auraTier = nil, nil, nil, nil
    self.showCount = nil
    self.ambR, self.ambG, self.ambB = nil, nil, nil
    self.pending, self.landIndex = nil, nil
    self.cast, self.castDone, self.sharedCount = nil, nil, nil
    self.dealTw = {}
    if FX then FX:Clear() end
    self:HideNext()
    if not f then return end
    self.lastSx, self.lastSy = nil, nil
    for _, c in ipairs(f.cards) do
        c:Hide()
        c.tell = false
        c.flipT = nil
    end
    f.show:Hide()
    f.show:SetAlpha(1)
    f.dimOver:Hide()
    f.box:Hide()
    f.reel:Hide()
    for _, t in ipairs(f.results) do t:Hide() end
    for _, t in ipairs(f.tiles) do t:SetAlpha(1) end
    f.purse:Hide()
    f.banner:SetText("")
    for i = 1, 5 do f.bannerStars[i]:Hide() end
    f.status:SetText("")
    f.reelText:SetText("")
    f.halo:SetAlpha(0)
    f.castBar:Hide()
    self.numCards = 0
end

function UI:Skip()
    local sc = self.showcase
    if sc then
        if sc.out then return end
        if sc.holding then
            self:ShowcaseClose()
        elseif sc.t < sc.tFlip then
            if not sc.upgraded then
                sc.upgraded = true
                self:ShowcaseTell(sc.tier)
            end
            sc.charged = true
            sc.t = sc.tFlip
        end
        return
    end
    local ph = self.phase
    if ph == "opening" then
        local o = self.cast
        if o and o.demo then o.finish, o.start = GetTime(), GetTime() - 1 end -- (a real cast can't be hurried)
        return
    end
    if ph == "charge" then
        local ch = self.charge
        if ch and ch.idx < #ch.seq then
            ch.idx = #ch.seq
            self:TellUpgrade(ch.seq[ch.idx])
        end
        self:Burst()
    elseif ph == "deal" then
        self:FinishDeal()
    elseif ph == "cards" then
        self:RevealAll()
    elseif ph == "reel" and self.spin then
        local s = self.spin
        if s.mode == "land" then
            s.t = s.T
        elseif s.mode ~= "cruise" then -- (no skipping while the cast is still going)
            s.t = s.dur
        end
    elseif ph == "done" and self.coinTween then
        FX:Finish(self.coinTween)
    end
end

function UI:OnMainButton()
    local ph = self.phase
    if ph == "ready" then
        self:StartOpen()
    elseif ph == "done" then
        if self.received then
            f:Hide() -- already in the bags
        elseif self.live then
            if self.collectPending then return end
            self.collectPending = true
            f.mainBtn:Disable()
            ns.CollectLive()
        else
            ns.Demo(self.itemID)
            if self.phase == "ready" then self:StartOpen() end -- straight into the next one
        end
    elseif ph == "collected" then
        f:Hide()
    end
end

-- Full bags after Collect: what didn't fit is back in the game's loot window
function UI:LootStuck(left)
    if not f or not f:IsShown() then return end
    self.collectPending = nil
    f.status:SetText(("|cffff6060Your bags are full: %d thing%s stayed in the loot window. Make room and take %s from there.|r")
        :format(left, left == 1 and "" or "s", left == 1 and "it" or "them"))
    f.mainBtn:SetLabel("CLOSE")
    f.mainBtn:Enable()
    self.phase = "collected"
    self:HideNext()
end

function UI:Browse(dir)
    if self.live then return end
    local ids = ns.BrowseOrder()
    local idx = 1
    for i, id in ipairs(ids) do
        if id == self.itemID then
            idx = i
            break
        end
    end
    idx = (idx - 1 + dir) % #ids + 1
    ns.Demo(ids[idx])
end

function UI:SetStatus(text)
    if f then f.status:SetText(text) end
end

function UI:OnCollected()
    if not f or not f:IsShown() then return end
    self.phase = "collected"
    self.collectPending = nil
    f.tag:SetText("|cffaaaaaaLOOTED|r")
    f.status:SetText("Looted! Good luck on the next one.")
    f.mainBtn:SetLabel("CLOSE")
    f.mainBtn:Enable()
    f.mainBtn:Show()
    f.sub:SetText(SubText(self))
    local x, y = FxPos(f.mainBtn)
    FX:Burst(x, y, 24, GOLD_R, GOLD_G, GOLD_B, 220)
    -- batch mode: offer the next box of the same kind, without leaving the screen
    if ns.db.batch then self:OfferNextBox(self.itemID) end
end

function UI:OnLootLost()
    if f and f:IsShown() and self.live then
        f:Hide()
        ns.Print("The loot window closed before the case finished. The container keeps its loot; open it again.")
    end
end

---------------------------------------------------------------------------
-- "Next" button: OPEN ANOTHER (batch mode), COMPREHEND ANOTHER, and OPEN in My boxes.
-- Using a bag item or casting a spell needs a secure action button. It is parented to UIParent, NOT to the
-- case screen: a screen holding a secure button could no longer be hidden in combat. It is lined up over
-- the screen by position, its attributes are only touched out of combat, and if combat starts while it is
-- up it goes invisible (SetAlpha is allowed) and is hidden properly once combat ends.
---------------------------------------------------------------------------

local nextBtn
local function InLockdown() return InCombatLockdown and InCombatLockdown() end

local function BuildNext()
    local b = CreateFrame("Button", "CrateExpectationsCasesNextButton", UIParent,
        BACKDROP and "SecureActionButtonTemplate,BackdropTemplate" or "SecureActionButtonTemplate")
    b:SetSize(260, 44)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetFrameLevel(460)
    b:RegisterForClicks("AnyUp", "AnyDown")
    if b.SetBackdrop then
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b:SetBackdropColor(0.08, 0.06, 0.11, 0.95)
        b:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    b.fill = NewTex(b, "ARTWORK", 0)
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    Grad(b.fill, "VERTICAL", 0.4, 0.26, 0.06, 0, 0.4, 0.26, 0.06, 0.45)
    b.hl = NewTex(b, "HIGHLIGHT", 0, "ADD")
    b.hl:SetAllPoints(b.fill)
    Grad(b.hl, "VERTICAL", 1, 0.8, 0.4, 0.05, 1, 0.8, 0.4, 0.25)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFont(FONT, 15, "OUTLINE")
    b.text:SetPoint("CENTER")
    b.text:SetTextColor(1, 0.86, 0.5)
    -- before the secure use happens: get ready to catch a box's loot window, and pause auto loot NOW, while
    -- it still counts. From My boxes the player then presses OPEN when ready; OPEN ANOTHER just plays.
    b:SetScript("PreClick", function(self)
        if self.boxID then ns.PrepareOpen(self.boxID, self.confirm) end
    end)
    b:Hide()
    nextBtn = b
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function()
        if b.hideWhenSafe then
            b.hideWhenSafe = nil
            b:Hide()
            b:SetAlpha(1)
        end
    end)
end

-- put the button at a spot on the case screen (in screen coordinates, since it isn't the screen's child)
local function PlaceNext(anchorFrame, dx)
    local x, y = anchorFrame:GetCenter()
    if not x then return end
    local s = anchorFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    nextBtn:ClearAllPoints()
    nextBtn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * s + (dx or 0), y * s)
end

-- attrs: { type = "item", item = "bag slot" } or { type = "macro", macrotext = "..." }
-- confirm: the case then waits for OPEN (My boxes: picking a box is a choice, the press is the go-ahead).
-- Without it (OPEN ANOTHER) the show starts by itself, like opening a box from the bags.
function UI:ShowNext(label, attrs, boxID, anchorFrame, dx, confirm)
    if InLockdown() then return end
    -- never on its own: only while the case screen is actually up (it isn't the screen's child, so it would
    -- otherwise float over the game by itself)
    if not f or not f:IsShown() then return end
    if not nextBtn then BuildNext() end
    nextBtn:SetAttribute("type", attrs.type)
    nextBtn:SetAttribute("item", attrs.item)
    nextBtn:SetAttribute("macrotext", attrs.macrotext)
    nextBtn.boxID = boxID
    nextBtn.confirm = confirm or nil
    nextBtn.text:SetText(label)
    nextBtn:SetWidth(max(220, nextBtn.text:GetStringWidth() + 40))
    PlaceNext(anchorFrame or f.mainBtn, dx or 0)
    nextBtn.hideWhenSafe = nil
    nextBtn:SetAlpha(1)
    nextBtn:Show()
end

function UI:HideNext()
    if not nextBtn or not nextBtn:IsShown() then return end
    if InLockdown() then
        nextBtn:SetAlpha(0) -- can't hide a secure button in combat; invisible until it's over
        nextBtn.hideWhenSafe = true
    else
        nextBtn:Hide()
    end
end

-- batch mode, after Collect: the next box of the same kind, if there is one
function UI:OfferNextBox(id)
    if self.container and self.container.world then return end -- (a world chest isn't in the bags)
    C_Timer.After(0.35, function() -- give the bags a moment to drop the box just opened
        if not f:IsShown() or self.phase ~= "collected" or ns.live then return end
        local e = ns.BagBoxes()[id]
        if not e then
            f.status:SetText("That was your last " .. (self.container and self.container.name or "box") .. ".")
            return
        end
        if ns.FreeBagSlots() == 0 then
            f.status:SetText("|cffff6060Your bags are full: make room before the next one.|r")
            return
        end
        f.mainBtn:ClearAllPoints()
        f.mainBtn:SetPoint("BOTTOM", f.main, "BOTTOM", -140, 14)
        self:ShowNext(("OPEN ANOTHER (%d left)"):format(e.count), { type = "item", item = e.bag .. " " .. e.slot },
            id, f.mainBtn, 260)
    end)
end

-- Comprehension: cast Comprehend Scroll on the next untranslated scroll (same one first)
function UI:OfferNextScroll()
    if InLockdown() then return end
    local nx = ns.NextCompScroll(self.itemID)
    if not nx then
        f.status:SetText((f.status:GetText() or "") .. "   |cff9a9a9a(No untranslated scrolls left.)|r")
        return
    end
    f.mainBtn:ClearAllPoints()
    f.mainBtn:SetPoint("BOTTOM", f.main, "BOTTOM", -140, 14)
    local same = ns.CompScrolls[self.itemID] == nx.level
    self:ShowNext(same and ("COMPREHEND ANOTHER (%d left)"):format(nx.count)
            or ("COMPREHEND A SKILL %d SCROLL (%d)"):format(nx.level, nx.count),
        { type = "macro", macrotext = "/cast " .. ns.CompSpellName() .. "\n/use " .. nx.bag .. " " .. nx.slot },
        nil, f.mainBtn, 260)
end

-- the main button goes back to the middle whenever the next button isn't offered
local function CenterMainButton()
    f.mainBtn:ClearAllPoints()
    f.mainBtn:SetPoint("BOTTOM", f.main, "BOTTOM", 0, 14)
end

---------------------------------------------------------------------------
-- Hunting (the red Heirloom tier)
---------------------------------------------------------------------------

function UI:ToggleHunt(id)
    if not id or not ns.db then return end
    if ns.db.hunt[id] then ns.db.hunt[id] = nil else ns.db.hunt[id] = true end
    if f and f.oddsPanel and f.oddsPanel:IsShown() and self.container then self:FillOdds(self.container) end
    if f and f.settings and f.settings:IsShown() then self:FillHunt() end
end

---------------------------------------------------------------------------
-- Settings and My boxes: two more views of the same full-screen frame (backdrop, embers, theme)
---------------------------------------------------------------------------

local SET_W, SET_H = 1000, 600

local function Panel(parent, w, h)
    local p = CreateFrame("Frame", nil, parent, BACKDROP)
    p:SetSize(w, h)
    if p.SetBackdrop then
        p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        p:SetBackdropColor(0.03, 0.025, 0.05, 0.92)
        p:SetBackdropBorderColor(0.55, 0.42, 0.18, 1)
    end
    return p
end

local function Label(parent, size, r, g, b, flags)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size, flags or "")
    t:SetTextColor(r or 0.88, g or 0.86, b or 0.9)
    t:SetJustifyH("LEFT")
    return t
end

-- a themed checkbox row: square + label; onChange(checked)
local function Check(parent, text, onChange)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.box = CreateFrame("Frame", nil, b, BACKDROP)
    b.box:SetSize(16, 16)
    b.box:SetPoint("LEFT", 0, 0)
    if b.box.SetBackdrop then
        b.box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b.box:SetBackdropColor(0.08, 0.06, 0.11, 1)
        b.box:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    b.mark = NewTex(b.box, "OVERLAY", 0)
    b.mark:SetPoint("TOPLEFT", 3, -3)
    b.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    b.mark:SetVertexColor(1, 0.78, 0.32, 1)
    b.text = Label(b, 12)
    b.text:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", 0, 0)
    b.text:SetText(text)
    b.hl = NewTex(b, "HIGHLIGHT", 0, "ADD")
    b.hl:SetAllPoints()
    b.hl:SetVertexColor(1, 0.8, 0.4, 0.08)
    b.SetChecked = function(self, v) self.checked = v and true or false self.mark:SetShown(self.checked) end
    b:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        onChange(self.checked, self)
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    end)
    return b
end

-- a scroll area whose child is laid out by the caller (mouse wheel scrolls it)
local function ScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(10, 10)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local m = max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(min(m, max(0, self:GetVerticalScroll() - delta * 44)))
    end)
    sf:SetScript("OnSizeChanged", function(self, w) child:SetWidth(w) end)
    sf.child = child
    AddScrollBar(sf, child)
    return sf
end

local function BuildSettings()
    local s = Panel(f, SET_W, SET_H)
    s:SetPoint("CENTER", f, "CENTER", 0, 10)
    s:SetFrameLevel(120)
    s:EnableMouse(true)
    f.settings = s

    local title = s:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "OUTLINE")
    title:SetTextColor(1, 0.84, 0.4)
    title:SetPoint("TOP", 0, -18)
    title:SetText("CRATE EXPECTATIONS")
    local sub = Label(s, 11, 0.62, 0.6, 0.66)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText("Settings")

    -- three columns: boxes | hunting | options
    local colY, colH = -76, SET_H - 150
    local function Column(x, w, heading, note)
        local c = CreateFrame("Frame", nil, s)
        c:SetPoint("TOPLEFT", x, colY)
        c:SetSize(w, colH)
        local h = c:CreateFontString(nil, "OVERLAY")
        h:SetFont(FONT, 14, "OUTLINE")
        h:SetTextColor(1, 0.84, 0.4)
        h:SetPoint("TOPLEFT", 0, 0)
        h:SetText(heading)
        local n = Label(c, 10, 0.55, 0.53, 0.6)
        n:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
        n:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        n:SetText(note)
        c.top = -40
        return c
    end

    -- 1. which boxes get the show
    local boxes = Column(24, 300, "SHOW THE CASE OPENING FOR",
        "Unticked boxes open the normal way. The demo still has them all.")
    local bs = ScrollArea(boxes)
    bs:SetPoint("TOPLEFT", 0, boxes.top)
    bs:SetPoint("BOTTOMRIGHT", 0, 0)
    local y, lastCat = 0, nil
    s.boxChecks = {}
    local entries = {}
    for _, id in ipairs(ns.BrowseOrder()) do
        if not ns.Containers[id].compLevel then entries[#entries + 1] = id end
    end
    entries[#entries + 1] = "comp"
    for _, id in ipairs(entries) do
        local cat = id == "comp" and "Mage scrolls" or ns.CategoryOf(id)
        if cat ~= lastCat then
            local h = Label(bs.child, 10, 0.62, 0.6, 0.66, "OUTLINE")
            h:SetPoint("TOPLEFT", 0, -y - 6)
            h:SetText(cat:upper())
            y = y + 24
            lastCat = cat
        end
        local name = id == "comp" and "Comprehension (all untranslated scrolls)" or ns.Containers[id].name
        if ns.ONCE_ONLY[id] then name = name .. " |cff777777(shows once)|r" end
        local ck = Check(bs.child, name, function(on)
            ns.db.disabled[id] = (not on) or nil
        end)
        ck:SetPoint("TOPLEFT", 0, -y)
        ck:SetPoint("RIGHT", bs.child, "RIGHT", -6, 0)
        ck.id = id
        s.boxChecks[#s.boxChecks + 1] = ck
        y = y + 22
    end
    bs.child:SetHeight(y + 6)

    -- 2. hunting
    local hunt = Column(352, 330, "HUNTING",
        "Items you're after. When one drops it's an |cffff4050Heirloom|r, the rarest tier there is. Start typing a name or item ID (Tab picks, Enter hunts), shift-click a link in, or right-click an item in a box's odds list.")
    local input = CreateFrame("EditBox", nil, hunt, BACKDROP)
    input:SetSize(240, 26)
    input:SetPoint("TOPLEFT", 0, hunt.top - 22)
    input:SetAutoFocus(false)
    input:SetFont(FONT, 12, "")
    input:SetTextColor(0.95, 0.93, 0.98)
    input:SetTextInsets(8, 8, 0, 0)
    if input.SetBackdrop then
        input:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        input:SetBackdropColor(0.08, 0.06, 0.11, 1)
        input:SetBackdropBorderColor(0.45, 0.36, 0.18, 1)
    end
    s.input = input
    local add = MakeButton(hunt, 80, 26, "Hunt", 12)
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    s.huntMsg = Label(hunt, 10, 0.62, 0.6, 0.66)
    s.huntMsg:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -4)
    s.huntMsg:SetPoint("RIGHT", hunt, "RIGHT", 0, 0)

    -- every item any box can give, once: { id, name, lowercased name, quality, number of boxes }
    local index
    local function Index()
        if index then return index end
        local byId = {}
        index = {}
        for cid, c in pairs(ns.Containers) do
            if not c.hidden or c.compLevel then
                for _, r in ipairs(c.items) do
                    local e = byId[r[1]]
                    if not e then
                        e = { id = r[1], name = r[4], low = r[4]:lower(), q = r[3], boxes = {} }
                        byId[r[1]] = e
                        index[#index + 1] = e
                    end
                    e.boxes[c.compLevel and ("comp" .. c.compLevel) or cid] = true
                end
            end
        end
        for _, e in ipairs(index) do
            local n = 0
            for _ in pairs(e.boxes) do n = n + 1 end
            e.n = n
        end
        table.sort(index, function(a, b) return a.name < b.name end)
        return index
    end

    -- the suggestion list under the box, live as you type: an exact ID first, then names that start with
    -- the text, then names (or IDs) that contain it; up to 8
    local SUGG = 8
    local sugg = CreateFrame("Frame", nil, hunt, BACKDROP)
    sugg:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -2)
    sugg:SetWidth(328)
    sugg:SetFrameLevel(input:GetFrameLevel() + 20)
    if sugg.SetBackdrop then
        sugg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        sugg:SetBackdropColor(0.05, 0.04, 0.08, 0.98)
        sugg:SetBackdropBorderColor(0.78, 0.6, 0.24, 1)
    end
    sugg.rows, sugg.hits, sugg.sel = {}, {}, 1
    for i = 1, SUGG do
        local row = CreateFrame("Button", nil, sugg)
        row:SetHeight(26)
        row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 26)
        row:SetPoint("RIGHT", sugg, "RIGHT", -1, 0)
        row.sel = NewTex(row, "BACKGROUND", 0)
        row.sel:SetAllPoints()
        row.sel:SetVertexColor(1, 0.75, 0.3, 0.16)
        local hl = NewTex(row, "HIGHLIGHT", 0, "ADD")
        hl:SetAllPoints()
        hl:SetVertexColor(1, 0.8, 0.4, 0.1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.text = Label(row, 12)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", -86, 0)
        row.text:SetWordWrap(false)
        row.info = Label(row, 10, 0.55, 0.53, 0.6)
        row.info:SetPoint("RIGHT", -6, 0)
        row.info:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self) UI:HuntAdd(self.id) end)
        row:SetScript("OnEnter", function(self) ShowItemTooltip(self, self.id) end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        sugg.rows[i] = row
    end
    sugg:Hide()

    local function PaintSel()
        for i, row in ipairs(sugg.rows) do row.sel:SetShown(i == sugg.sel and row:IsShown()) end
    end

    local function Suggest()
        local text = strtrim(input:GetText() or "")
        local hits = {}
        if text ~= "" then
            local linkId = tonumber(text:match("item:(%d+)"))
            local num = linkId or tonumber(text)
            local low = text:lower()
            local starts, contains = {}, {}
            for _, e in ipairs(Index()) do
                if num and e.id == num then
                    table.insert(hits, 1, e)
                elseif not linkId then
                    local p = e.low:find(low, 1, true)
                    if p == 1 then starts[#starts + 1] = e
                    elseif p then contains[#contains + 1] = e
                    elseif num and tostring(e.id):sub(1, #text) == text then contains[#contains + 1] = e end
                end
            end
            for _, e in ipairs(starts) do hits[#hits + 1] = e end
            for _, e in ipairs(contains) do hits[#hits + 1] = e end
            -- an ID or link no box lists: still huntable (the game knows the item)
            if num and (not hits[1] or hits[1].id ~= num) then
                table.insert(hits, 1, { id = num, name = ns.ItemName(num), q = 1, n = 0 })
            end
        end
        sugg.hits, sugg.sel = hits, 1
        local shown = min(#hits, SUGG)
        for i, row in ipairs(sugg.rows) do
            local e = hits[i]
            if e then
                row.id = e.id
                row.icon:SetTexture(ns.ItemIcon(e.id))
                row.text:SetText(e.name)
                row.text:SetTextColor(ns.QualityColor(e.q))
                if ns.IsHunted(e.id) then
                    row.info:SetText("|cffff4050hunting|r")
                elseif e.n > 0 then
                    row.info:SetText(e.n == 1 and "in 1 box" or ("in %d boxes"):format(e.n))
                else
                    row.info:SetText("not in a box")
                end
                row:Show()
            else
                row:Hide()
            end
        end
        sugg:SetHeight(shown * 26 + 2)
        sugg:SetShown(shown > 0 and input:HasFocus())
        if text ~= "" and shown == 0 then
            s.huntMsg:SetText("|cffff8060No item matches \"" .. text .. "\".|r")
        else
            s.huntMsg:SetText("")
        end
        PaintSel()
    end

    function UI:HuntAdd(id)
        if not id then return end
        ns.db.hunt[id] = true
        input:SetText("")
        input:ClearFocus()
        sugg:Hide()
        s.huntMsg:SetText("Hunting " .. ns.ItemName(id) .. ".")
        UI:FillHunt()
    end

    local function AddFromInput()
        local e = sugg.hits[sugg.sel] or sugg.hits[1]
        if e then UI:HuntAdd(e.id) else Suggest() end
    end
    input:SetScript("OnTextChanged", function() Suggest() end)
    input:SetScript("OnEditFocusGained", Suggest)
    input:SetScript("OnEditFocusLost", function()
        C_Timer.After(0.15, function() if not input:HasFocus() then sugg:Hide() end end) -- let a click land first
    end)
    input:SetScript("OnEnterPressed", AddFromInput)
    input:SetScript("OnEscapePressed", function(self) sugg:Hide() self:ClearFocus() end)
    input:SetScript("OnTabPressed", function()
        local n = min(#sugg.hits, SUGG)
        if n > 0 then
            sugg.sel = (IsShiftKeyDown() and (sugg.sel - 2) or sugg.sel) % n + 1
            PaintSel()
        end
    end)
    add:SetScript("OnClick", AddFromInput)
    -- shift-clicking an item link while the box has focus puts the link in it
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if input:IsVisible() and input:HasFocus() and type(link) == "string" then input:Insert(link) end
    end)

    local hs = ScrollArea(hunt)
    hs:SetPoint("TOPLEFT", 0, hunt.top - 66)
    hs:SetPoint("BOTTOMRIGHT", 0, 0)
    s.huntScroll, s.huntRows = hs, {}
    s.huntEmpty = Label(hs.child, 11, 0.55, 0.53, 0.6)
    s.huntEmpty:SetPoint("TOPLEFT", 0, -6)
    s.huntEmpty:SetPoint("RIGHT", hs.child, "RIGHT", 0, 0)
    s.huntEmpty:SetText("Nothing yet. What's the one item you're opening these for?")

    -- 3. options
    local opt = Column(712, 264, "OPTIONS", "")
    local oy = opt.top
    local function Opt(text, get, set)
        local ck = Check(opt, text, function(on) set(on) end)
        ck:SetPoint("TOPLEFT", 0, oy)
        ck:SetPoint("RIGHT", opt, "RIGHT", 0, 0)
        ck.get = get
        oy = oy - 28
        return ck
    end
    s.opts = {
        Opt("Take over real openings", function() return ns.db.enabled end, function(v) ns.db.enabled = v end),
        Opt("Sound", function() return ns.db.sound end, function(v) ns.db.sound = v end),
        Opt("Batch mode (offer the next box)", function() return ns.db.batch end,
            function(v) ns.db.batch = v end),
        Opt("Auto-collect (no COLLECT click)", function() return ns.db.autoCollect end,
            function(v) ns.db.autoCollect = v end),
        Opt("Keep the odds up during the show", function() return ns.db.oddsAlways end,
            function(v) ns.db.oddsAlways = v end),
    }
    local spin = Label(opt, 12)
    spin:SetPoint("TOPLEFT", 0, oy - 6)
    local function SpinText() spin:SetText(("Reel spin: %.1f sec"):format(ns.db.spinTime or 5)) end
    local minus = MakeButton(opt, 30, 24, "-", 14)
    minus:SetPoint("TOPLEFT", 150, oy - 2)
    local plus = MakeButton(opt, 30, 24, "+", 14)
    plus:SetPoint("LEFT", minus, "RIGHT", 6, 0)
    minus:SetScript("OnClick", function() ns.db.spinTime = max(1, (ns.db.spinTime or 5) - 0.5) SpinText() end)
    plus:SetScript("OnClick", function() ns.db.spinTime = min(12, (ns.db.spinTime or 5) + 0.5) SpinText() end)
    s.spinText = SpinText
    local stats = Label(opt, 11, 0.62, 0.6, 0.66)
    stats:SetPoint("TOPLEFT", 0, oy - 44)
    stats:SetPoint("RIGHT", opt, "RIGHT", 0, 0)
    s.stats = stats

    -- bottom: the rooms
    local demo = MakeButton(s, 190, 40, "DEMO ROOM", 15)
    demo:SetPoint("BOTTOM", s, "BOTTOM", -315, 22)
    demo:SetScript("OnClick", function() ns.Demo() end)
    local mine = MakeButton(s, 190, 40, "MY BOXES", 15)
    mine:SetPoint("BOTTOM", s, "BOTTOM", -105, 22)
    mine:SetScript("OnClick", function() UI:ShowMine() end)
    local stats = MakeButton(s, 190, 40, "YOUR LUCK", 15)
    stats:SetPoint("BOTTOM", s, "BOTTOM", 105, 22)
    stats:SetScript("OnClick", function() UI:ShowStats() end)
    local done = MakeButton(s, 190, 40, "CLOSE", 15)
    done:SetPoint("BOTTOM", s, "BOTTOM", 315, 22)
    done:SetScript("OnClick", function() f:Hide() end)
    s:Hide()
end

function UI:FillHunt()
    local s = f.settings
    local ids = {}
    for id in pairs(ns.db.hunt) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ns.ItemName(a) < ns.ItemName(b) end)
    for i, id in ipairs(ids) do
        local row = s.huntRows[i]
        if not row then
            row = CreateFrame("Frame", nil, s.huntScroll.child)
            row:SetHeight(30)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("LEFT", 0, 0)
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            row.text = Label(row, 12)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.text:SetPoint("RIGHT", -40, 0)
            row.text:SetWordWrap(false)
            row.del = MakeButton(row, 28, 22, "x", 12)
            row.del:SetPoint("RIGHT", 0, 0)
            row.del:SetScript("OnClick", function() UI:ToggleHunt(row.id) end)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self) ShowItemTooltip(self, self.id, { "Hunting: drops as Heirloom." }) end)
            row:SetScript("OnLeave", GameTooltip_Hide)
            s.huntRows[i] = row
        end
        row.id = id
        row.icon:SetTexture(ns.ItemIcon(id))
        row.text:SetText(ns.ItemName(id))
        row.text:SetTextColor(1, 0.32, 0.36)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 32)
        row:SetPoint("RIGHT", s.huntScroll.child, "RIGHT", -6, 0)
        row:Show()
    end
    for i = #ids + 1, #s.huntRows do s.huntRows[i]:Hide() end
    s.huntEmpty:SetShown(#ids == 0)
    s.huntScroll.child:SetHeight(max(10, #ids * 32))
end

-- show one of the non-case views: stage away, embers stay
local function EnterView(self)
    if not f then Build() end
    if ns.live then return false end -- a real case is on screen
    f:Show()
    self:Reset()
    self.phase = "view"
    self.live, self.pending = nil, nil
    f.main:Hide()
    f.oddsPanel:Hide()
    f.forceBar:Hide()
    f.picker:Hide()
    if f.settings then f.settings:Hide() end
    if f.mine then f.mine:Hide() end
    if f.stats then f.stats:Hide() end
    CenterMainButton()
    -- the same dark backdrop and gold embers as a case (a previous case may have left another colour)
    self:SetWash(GOLD_R, GOLD_G, GOLD_B, 0.05)
    self.ambR, self.ambG, self.ambB = GOLD_R, GOLD_G, GOLD_B
    f.halo:SetAlpha(0)
    return true
end

function UI:ShowSettings()
    if not EnterView(self) then return end
    if not f.settings then BuildSettings() end
    local s = f.settings
    for _, ck in ipairs(s.boxChecks) do ck:SetChecked(not ns.db.disabled[ck.id]) end
    for _, ck in ipairs(s.opts) do ck:SetChecked(ck.get()) end
    s.spinText()
    local total = 0
    for _, n in pairs(ns.db.stats.opened) do total = total + n end
    s.stats:SetText(("Cases opened: %d\nSince your last Rare+: %d"):format(total, ns.db.stats.sinceRare or 0))
    s.huntMsg:SetText("")
    self:FillHunt()
    s:Show()
end

---------------------------------------------------------------------------
-- My boxes: every supported box in the bags; pick one, then OPEN (the secure button) opens it here
---------------------------------------------------------------------------

local function BuildMine()
    local m = Panel(f, 760, 520)
    m:SetPoint("CENTER", f, "CENTER", 0, 20)
    m:SetFrameLevel(120)
    m:EnableMouse(true)
    f.mine = m
    local title = m:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 24, "OUTLINE")
    title:SetTextColor(1, 0.84, 0.4)
    title:SetPoint("TOP", 0, -18)
    title:SetText("MY BOXES")
    local sub = Label(m, 11, 0.62, 0.6, 0.66)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText("Pick a box, then Open. Turn on batch mode in Settings to stay here between boxes.")
    m.grid = ScrollArea(m)
    m.grid:SetPoint("TOPLEFT", 20, -70)
    m.grid:SetPoint("BOTTOMRIGHT", -20, 80)
    m.cells = {}
    m.empty = Label(m.grid.child, 13, 0.62, 0.6, 0.66)
    m.empty:SetPoint("TOP", m.grid.child, "TOP", 0, -40)
    m.empty:SetJustifyH("CENTER")
    m.empty:SetText("No boxes in your bags. Go find some!")
    local back = MakeButton(m, 160, 36, "SETTINGS", 13)
    back:SetPoint("BOTTOMLEFT", 20, 22)
    back:SetScript("OnClick", function() UI:ShowSettings() end)
    m.anchor = CreateFrame("Frame", nil, m)
    m.anchor:SetSize(10, 10)
    m.anchor:SetPoint("BOTTOM", m, "BOTTOM", 0, 42)
    m:SetScript("OnHide", function() UI:HideNext() end)
    m:RegisterEvent("BAG_UPDATE_DELAYED")
    -- IsVisible, not IsShown: the view keeps its own "shown" flag after the whole screen closes
    m:SetScript("OnEvent", function(self) if self:IsVisible() then UI:FillMine() end end)
    m:Hide()
end

function UI:FillMine()
    local m = f.mine
    local bag = ns.BagBoxes()
    local ids = {}
    for id in pairs(bag) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ns.Containers[a].name < ns.Containers[b].name end)
    local cols, cw, ch = 3, 236, 52
    for i, id in ipairs(ids) do
        local c = m.cells[i]
        if not c then
            c = CreateFrame("Button", nil, m.grid.child, BACKDROP)
            c:SetSize(cw - 8, ch - 8)
            if c.SetBackdrop then
                c:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            end
            c.icon = c:CreateTexture(nil, "ARTWORK")
            c.icon:SetSize(34, 34)
            c.icon:SetPoint("LEFT", 6, 0)
            c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            c.name = Label(c, 12)
            c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 8, -2)
            c.name:SetPoint("RIGHT", -6, 0)
            c.name:SetWordWrap(false)
            c.count = Label(c, 11, 0.62, 0.6, 0.66)
            c.count:SetPoint("BOTTOMLEFT", c.icon, "BOTTOMRIGHT", 8, 2)
            local hl = NewTex(c, "HIGHLIGHT", 0, "ADD")
            hl:SetAllPoints()
            hl:SetVertexColor(1, 0.8, 0.4, 0.1)
            c:SetScript("OnClick", function(self) UI:SelectMine(self.id) end)
            m.cells[i] = c
        end
        c.id = id
        c.icon:SetTexture(ns.ItemIcon(id))
        c.name:SetText(ns.Containers[id].name)
        local off = not ns.IsBoxEnabled(id)
        c.count:SetText(("x%d%s"):format(bag[id].count, off and "   |cff777777(case opening off)|r" or ""))
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", ((i - 1) % cols) * cw, -floor((i - 1) / cols) * ch)
        c:Show()
    end
    for i = #ids + 1, #m.cells do m.cells[i]:Hide() end
    m.empty:SetShown(#ids == 0)
    m.grid.child:SetHeight(max(10, math.ceil(#ids / cols) * ch))
    if m.selected and not bag[m.selected] then m.selected = nil end
    if not m.selected and ids[1] then m.selected = ids[1] end
    self:SelectMine(m.selected)
end

function UI:SelectMine(id)
    local m = f.mine
    m.selected = id
    for _, c in ipairs(m.cells) do
        if c:IsShown() and c.SetBackdropColor then
            local sel = c.id == id
            c:SetBackdropColor(sel and 0.25 or 0.07, sel and 0.18 or 0.06, sel and 0.07 or 0.09, 0.95)
            c:SetBackdropBorderColor(sel and 1 or 0.4, sel and 0.78 or 0.32, sel and 0.32 or 0.16, 1)
        end
    end
    local e = id and ns.BagBoxes()[id]
    if not e then self:HideNext() return end
    if ns.FreeBagSlots() == 0 then
        self:HideNext()
        return
    end
    self:ShowNext(("OPEN %s (%d)"):format(ns.Containers[id].name:upper(), e.count),
        { type = "item", item = e.bag .. " " .. e.slot }, id, m.anchor, 0, true)
end

function UI:ShowMine()
    if not EnterView(self) then return end
    if not f.mine then BuildMine() end
    f.mine:Show()
    self:FillMine()
end

---------------------------------------------------------------------------
-- Stats: the headline numbers, what you've pulled by rarity, your best pull, and a luck meter
---------------------------------------------------------------------------

local STAT_ROWS = {
    { 1 }, { 2 }, { 3 }, { 4 }, { 5 }, { 6 }, { 7 },
    { "sheep", "Sheep", 0.82, 0.8, 0.86 },
}

local function BuildStats()
    local st = Panel(f, 900, 560)
    st:SetPoint("CENTER", f, "CENTER", 0, 20)
    st:SetFrameLevel(120)
    st:EnableMouse(true)
    f.stats = st
    local title = st:CreateFontString(nil, "OVERLAY")
    title:SetFont(FONT, 26, "OUTLINE")
    title:SetTextColor(1, 0.84, 0.4)
    title:SetPoint("TOP", 0, -18)
    title:SetText("YOUR LUCK")
    local sub = Label(st, 11, 0.62, 0.6, 0.66)
    sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
    sub:SetText("Real openings only: the demo doesn't count.")

    -- headline tiles
    st.tiles = {}
    local heads = { "Cases opened", "Items found", "Coins looted", "Since your last Rare+" }
    for i, h in ipairs(heads) do
        local t = CreateFrame("Frame", nil, st, BACKDROP)
        t:SetSize(200, 74)
        t:SetPoint("TOPLEFT", 28 + (i - 1) * 214, -70)
        if t.SetBackdrop then
            t:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            t:SetBackdropColor(0.07, 0.06, 0.1, 1)
            t:SetBackdropBorderColor(0.4, 0.32, 0.16, 1)
        end
        t.value = t:CreateFontString(nil, "OVERLAY")
        t.value:SetFont(FONT, 24, "OUTLINE")
        t.value:SetTextColor(1, 0.86, 0.5)
        t.value:SetPoint("TOP", 0, -12)
        t.label = Label(t, 11, 0.62, 0.6, 0.66)
        t.label:SetPoint("BOTTOM", 0, 10)
        t.label:SetText(h)
        st.tiles[i] = t
    end

    -- left: pulls by rarity, as bars
    local bh = Label(st, 14, 1, 0.84, 0.4, "OUTLINE")
    bh:SetPoint("TOPLEFT", 28, -168)
    bh:SetText("PULLS BY RARITY")
    st.bars = {}
    for i, row in ipairs(STAT_ROWS) do
        local y = -194 - (i - 1) * 30
        local name = Label(st, 12)
        name:SetPoint("TOPLEFT", 28, y - 4)
        name:SetWidth(90)
        local track = NewTex(st, "ARTWORK", 0)
        track:SetPoint("TOPLEFT", 124, y - 2)
        track:SetSize(260, 16)
        track:SetVertexColor(0.1, 0.09, 0.14, 1)
        local fill = NewTex(st, "ARTWORK", 1)
        fill:SetPoint("TOPLEFT", track, "TOPLEFT")
        fill:SetHeight(16)
        local count = Label(st, 12)
        count:SetPoint("LEFT", track, "RIGHT", 10, 0)
        st.bars[i] = { name = name, fill = fill, count = count, row = row }
    end

    -- right: best pull and the luck meter
    local x0 = 470
    local bp = Label(st, 14, 1, 0.84, 0.4, "OUTLINE")
    bp:SetPoint("TOPLEFT", x0, -168)
    bp:SetText("BEST PULL")
    st.bestIcon = st:CreateTexture(nil, "ARTWORK")
    st.bestIcon:SetSize(40, 40)
    st.bestIcon:SetPoint("TOPLEFT", x0, -194)
    st.bestIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    st.bestName = Label(st, 14, 1, 1, 1, "OUTLINE")
    st.bestName:SetPoint("TOPLEFT", st.bestIcon, "TOPRIGHT", 10, -2)
    st.bestName:SetWidth(360)
    st.bestInfo = Label(st, 11, 0.62, 0.6, 0.66)
    st.bestInfo:SetPoint("TOPLEFT", st.bestName, "BOTTOMLEFT", 0, -4)
    st.bestInfo:SetWidth(360)

    local lh = Label(st, 14, 1, 0.84, 0.4, "OUTLINE")
    lh:SetPoint("TOPLEFT", x0, -262)
    lh:SetText("LUCK METER")
    -- a gauge from "cursed" to "blessed": 0x .. 1x (average, the middle) .. 3x
    st.gauge = NewTex(st, "ARTWORK", 0)
    st.gauge:SetPoint("TOPLEFT", x0, -292)
    st.gauge:SetSize(400, 14)
    Grad(st.gauge, "HORIZONTAL", 0.55, 0.2, 0.25, 1, 0.25, 0.75, 0.35, 1)
    st.gaugeMid = NewTex(st, "OVERLAY", 0)
    st.gaugeMid:SetSize(2, 22)
    st.gaugeMid:SetPoint("CENTER", st.gauge, "LEFT", 400 / 3, 0)
    st.gaugeMid:SetVertexColor(1, 1, 1, 0.5)
    st.marker = NewTex(st, "OVERLAY", 2)
    st.marker:SetSize(6, 26)
    st.marker:SetVertexColor(1, 0.86, 0.45, 1)
    local l0 = Label(st, 10, 0.55, 0.53, 0.6)
    l0:SetPoint("TOPLEFT", st.gauge, "BOTTOMLEFT", 0, -6)
    l0:SetText("cursed")
    local l1 = Label(st, 10, 0.55, 0.53, 0.6)
    l1:SetPoint("TOP", st.gaugeMid, "BOTTOM", 0, -2)
    l1:SetText("average")
    local l2 = Label(st, 10, 0.55, 0.53, 0.6)
    l2:SetPoint("TOPRIGHT", st.gauge, "BOTTOMRIGHT", 0, -6)
    l2:SetText("blessed")
    st.ratio = st:CreateFontString(nil, "OVERLAY")
    st.ratio:SetFont(FONT, 22, "OUTLINE")
    st.ratio:SetPoint("TOPLEFT", st.gauge, "BOTTOMLEFT", 0, -28)
    st.verdict = Label(st, 13, 0.9, 0.88, 0.92)
    st.verdict:SetPoint("TOPLEFT", st.ratio, "BOTTOMLEFT", 0, -6)
    st.verdict:SetWidth(400)
    st.detail = Label(st, 11, 0.62, 0.6, 0.66)
    st.detail:SetPoint("TOPLEFT", st.verdict, "BOTTOMLEFT", 0, -8)
    st.detail:SetWidth(400)

    -- bottom
    local back = MakeButton(st, 160, 36, "SETTINGS", 13)
    back:SetPoint("BOTTOMLEFT", 24, 20)
    back:SetScript("OnClick", function() UI:ShowSettings() end)
    -- reset: no dialogs here, so it asks for a second click instead
    local reset = MakeButton(st, 160, 36, "Reset stats", 12)
    reset:SetPoint("BOTTOMRIGHT", -24, 20)
    reset:SetScript("OnClick", function(self)
        if self.armed and GetTime() - self.armed < 4 then
            ns.db.stats = { opened = {}, won = {}, sinceRare = 0, tiers = {}, items = 0, copper = 0, sheep = 0,
                expRare = 0, expEpic = 0, gotRare = 0, gotEpic = 0, best = {} }
            self.armed = nil
            self:SetLabel("Reset stats")
            UI:FillStats()
        else
            self.armed = GetTime()
            self:SetLabel("Click again to reset")
            C_Timer.After(4, function() if self.armed then self.armed = nil self:SetLabel("Reset stats") end end)
        end
    end)
    st:Hide()
end

function UI:FillStats()
    local st, s = f.stats, ns.db.stats
    local opened = 0
    for _, n in pairs(s.opened or {}) do opened = opened + n end
    st.tiles[1].value:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(opened) or opened)
    st.tiles[2].value:SetText(BreakUpLargeNumbers and BreakUpLargeNumbers(s.items or 0) or (s.items or 0))
    st.tiles[3].value:SetText(ns.CoinText(s.copper or 0))
    st.tiles[4].value:SetText(s.sinceRare or 0)

    local counts, top = {}, 1
    for i, b in ipairs(st.bars) do
        local key = b.row[1]
        local n = key == "sheep" and (s.sheep or 0) or ((s.tiers or {})[key] or 0)
        counts[i] = n
        if n > top then top = n end
    end
    for i, b in ipairs(st.bars) do
        local key = b.row[1]
        local r, g, bl, label
        if key == "sheep" then r, g, bl, label = b.row[3], b.row[4], b.row[5], b.row[2]
        else r, g, bl = TierColor(key) label = TierLabel(key) end
        b.name:SetText(label)
        b.name:SetTextColor(r, g, bl)
        b.fill:SetVertexColor(r, g, bl, 0.85)
        b.fill:SetWidth(max(1, 260 * counts[i] / top))
        b.fill:SetShown(counts[i] > 0)
        b.count:SetText(counts[i])
        b.count:SetTextColor(counts[i] > 0 and 0.95 or 0.4, counts[i] > 0 and 0.93 or 0.4, counts[i] > 0 and 0.97 or 0.45)
    end

    local best = s.best or {}
    if best.id then
        local r, g, b = TierColor(best.tier or 1)
        st.bestIcon:SetTexture(ns.ItemIcon(best.id))
        st.bestName:SetText(best.name or ns.ItemName(best.id))
        st.bestName:SetTextColor(r, g, b)
        local box = best.box and ns.Containers[best.box]
        st.bestInfo:SetText(("%s%s"):format(TierLabel(best.tier or 1),
            box and ("  from " .. (box.scrollName or box.name)) or ""))
    else
        st.bestIcon:SetTexture(DUST)
        st.bestName:SetText("Nothing yet")
        st.bestName:SetTextColor(0.6, 0.6, 0.65)
        st.bestInfo:SetText("Open a box for real and it shows up here.")
    end

    local ratio, verdict = ns.Luck()
    st.verdict:SetText(verdict)
    if ratio then
        local pos = min(1, ratio / 3)
        st.marker:ClearAllPoints()
        st.marker:SetPoint("CENTER", st.gauge, "LEFT", 400 * pos, 0)
        st.marker:Show()
        local r, g, b = ratio >= 1 and 0.4 or 1, ratio >= 1 and 1 or 0.45, ratio >= 1 and 0.45 or 0.4
        st.ratio:SetText(("%.2fx average"):format(ratio))
        st.ratio:SetTextColor(r, g, b)
        st.detail:SetText(("Rare or better: you got %d, the boxes you opened average %.1f.\nEpic or better: you got %d, they average %.1f.")
            :format(s.gotRare or 0, s.expRare or 0, s.gotEpic or 0, s.expEpic or 0))
    else
        st.marker:Hide()
        st.ratio:SetText("")
        st.detail:SetText("")
    end
end

function UI:ShowStats()
    if not EnterView(self) then return end
    if not f.stats then BuildStats() end
    f.stats:Show()
    self:FillStats()
end

-- Never keep the screen up in combat (or through death / a loading screen): close it. A live case falls
-- back to the normal loot window (OnHide shows it again); a comprehend still under way reports in chat.
local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("PLAYER_DEAD")
combat:RegisterEvent("PLAYER_ENTERING_WORLD")
combat:SetScript("OnEvent", function(_, event)
    if not (f and f:IsShown()) then return end
    local live, pending = UI.live and ns.live, UI.pending
    f:Hide()
    if event ~= "PLAYER_REGEN_DISABLED" then return end
    if live then
        ns.Print("Combat! Closed the case screen; your loot is in the normal loot window.")
    elseif pending then
        ns.Print("Combat! Closed the reel; the scroll you get will show up in chat.")
    else
        ns.Print("Combat! Case screen closed.")
    end
end)
