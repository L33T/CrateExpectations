-- Crate Expectations: core logic.
-- Catches a known container being opened from the bags, holds its loot window back, and hands the
-- real contents to the case-opening UI, which spins and then loots them.

local ADDON, ns = ...

local DEFAULTS = {
    enabled = true,     -- take over real container openings
    spinTime = 5,       -- seconds for the first spin (later spins in the same case are shorter)
    sound = true,
    debug = false,
    lastDemo = 21150,   -- Iron Bound Trunk
    style = "auto",     -- "auto": card pull for multi-item boxes, reel for single-item ones; or "pull" / "reel"
    maxSeen = {},       -- most items ever seen in one real opening, per container
    stats = {
        opened = {}, won = {}, sinceRare = 0,
        tiers = {},          -- [tier] = items found (6 Elusive, 7 Heirloom)
        items = 0, copper = 0, sheep = 0,
        expRare = 0, expEpic = 0, gotRare = 0, gotEpic = 0, -- for the luck meter
        best = {},           -- { id, tier, name } best pull ever
    },
    disabled = {},      -- [containerID or "comp"] = true: no case opening for these
    hunt = {},          -- [itemID] = true: items the player is hunting (the red Heirloom tier)
    seenOnce = {},      -- [containerID] = true: a show-once box that has had its one show
    batch = true,       -- stay open after collecting and offer the next box of the same kind
}

-- Boxes that only ever give one thing get their show once, then open normally forever after.
ns.ONCE_ONLY = { [15874] = true } -- Soft-shelled Clam: Soft-shelled Clam Meat, every time

function ns.IsHunted(itemID)
    return itemID ~= nil and ns.db ~= nil and ns.db.hunt[itemID] == true
end

function ns.IsBoxEnabled(id)
    if not ns.db then return true end
    local c = ns.Containers[id]
    if c and c.compLevel then return not ns.db.disabled.comp end
    return not ns.db.disabled[id]
end

-- free general-purpose bag slots (bags 0-4; profession bags don't count)
function ns.FreeBagSlots()
    local free = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, n, family = pcall(C_Container.GetContainerNumFreeSlots, bag)
        if ok and n and (family == nil or family == 0) then free = free + n end
    end
    return free
end

-- every supported box in the bags: { [id] = { count, bag, slot } } (bag/slot of the first stack)
function ns.BagBoxes()
    local out = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and n or 0) do
            local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            local id = ok2 and type(info) == "table" and info.itemID
            local c = id and ns.Containers[id]
            if c and not c.noLoot then
                local e = out[id]
                if not e then
                    e = { count = 0, bag = bag, slot = slot }
                    out[id] = e
                end
                e.count = e.count + (info.stackCount or 1)
            end
        end
    end
    return out
end

-- How many item cards a container gets (coins are shown separately). Wowhead has no "items per box"
-- figure; its drop chances summed give the AVERAGE items per opening, and these sit a little above that
-- (avg ~1.0-1.15 -> 2, ~1.3-1.8 -> 3, ~2.1-2.4 -> 4). A real box that gives more raises it (maxSeen).
local SLOTS = {
    -- lockboxes: ~1.03 items on average (Ornate Bronze 1.27)
    [4632] = 2, [4633] = 2, [4634] = 2, [4636] = 2, [4637] = 2, [4638] = 2, [5758] = 2, [5759] = 2, [5760] = 2,
    -- fishing trunks: 2.06-2.26
    [20708] = 4, [21113] = 4, [21150] = 4, [21228] = 4,
    -- chests: Small 2.24, Small Locked 2.40, Sturdy Locked 1.41, Reinforced Locked 1.31, Battered 1.20, Ironbound 1.13
    [6353] = 4, [6354] = 4, [6355] = 3, [13918] = 3, [6356] = 2, [13875] = 2,
    -- junkboxes: Battered 1.10, Worn 1.13, Sturdy 1.34, Heavy 1.82
    [16882] = 2, [16883] = 2, [16884] = 3, [16885] = 3,
    -- reel boxes: crates give exactly one thing; clams give their meat, plus a pearl about 1 time in 20
    [6351] = 1, [6352] = 1, [6357] = 1, [13874] = 1, [5523] = 1, [5524] = 1, [7973] = 1, [15874] = 1,
    -- mage Study bundle (2-3 scrolls); Comprehension gives one
    [277651] = 3,
}
-- the fewest items a box ever gives (demo rolls top up to this)
local MIN_ITEMS = { [277651] = 2 }
local DEFAULT_SLOTS = 3 -- anything else
-- reel boxes can still give a second thing (a clam's pearl): the reel just spins again for it
local REEL_EXTRA = { [5523] = 2, [5524] = 2, [7973] = 2 }

-- The bottom three lockboxes are low-level boxes: nothing in them shows above Rare, whatever tier the
-- same item has elsewhere (hunted items and elusive finds still beat this).
ns.BOX_MAX_TIER = { [4632] = 3, [4633] = 3, [4634] = 3 }

function ns.IsReelBox(id)
    local c = ns.Containers[id]
    return (c and c.single) or (SLOTS[id] == 1)
end

function ns.CardCount(id)
    local c = ns.Containers[id]
    if c and c.single then return 1 end -- Comprehension: always exactly one result
    local n = SLOTS[id] or DEFAULT_SLOTS
    if n == 1 then return 1 end -- reel boxes stay reels (an extra item is another spin, not a card)
    local seen = ns.db and ns.db.maxSeen[id]
    if seen and seen > n then n = seen end
    return n
end

-- most items a demo roll may give (reel boxes can spin twice)
function ns.DemoMaxItems(id)
    return REEL_EXTRA[id] or ns.CardCount(id)
end

-- "pull" or "reel" for this case
function ns.StyleFor(id, numItems)
    local style = ns.db.style
    if style == "pull" or style == "reel" then return style end
    if ns.IsReelBox(id) then return "reel" end
    return "pull"
end

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.Print(...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffb84dCrate Expectations|r: " .. strjoin(" ", tostringall(...)))
end

function ns.Debug(...)
    if ns.db and ns.db.debug then ns.Print("|cff888888[debug]|r", ...) end
end

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

function ns.ItemIcon(id)
    local icon
    if C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
    if not icon and GetItemIcon then icon = GetItemIcon(id) end
    return icon or QUESTION
end

function ns.ItemName(id, fallback)
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(id) end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name or fallback or ("Item " .. id)
end

function ns.QualityColor(q)
    q = q or 1
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

---------------------------------------------------------------------------
-- Money
---------------------------------------------------------------------------

-- The loot window gives coins as text ("12 Silver\n40 Copper"); turn it into copper.
local function AmountPattern(fmt, fallback)
    if type(fmt) == "string" and fmt:find("%%d") then
        return (fmt:gsub("%%d", "(%%d+)"))
    end
    return fallback
end
function ns.ParseMoney(text)
    if type(text) ~= "string" then return 0 end
    local g = tonumber(text:match(AmountPattern(GOLD_AMOUNT, "(%d+) Gold"))) or 0
    local s = tonumber(text:match(AmountPattern(SILVER_AMOUNT, "(%d+) Silver"))) or 0
    local c = tonumber(text:match(AmountPattern(COPPER_AMOUNT, "(%d+) Copper"))) or 0
    return g * 10000 + s * 100 + c
end

function ns.CoinIcon(copper)
    if copper >= 10000 then return "Interface\\Icons\\INV_Misc_Coin_01" end -- gold
    if copper >= 100 then return "Interface\\Icons\\INV_Misc_Coin_03" end   -- silver
    return "Interface\\Icons\\INV_Misc_Coin_05"                              -- copper
end

function ns.CoinText(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = "|cffffd700" .. g .. "g|r" end
    if s > 0 then out[#out + 1] = "|cffc7c7cf" .. s .. "s|r" end
    if c > 0 or #out == 0 then out[#out + 1] = "|cffeda55f" .. c .. "c|r" end
    return table.concat(out, " ")
end

-- Demo only: coins from Wowhead's average per box (Data.lua `money`, copper, empty boxes included).
-- Wowhead doesn't say how often coins show up; fishing trunks only "sometimes" have them, so they get
-- coins half the time at twice the average, everything else every time. Real openings read the real coins.
local FISHED = { [20708] = true, [21113] = true, [21150] = true, [21228] = true }

local function DemoCoins(id)
    local c = ns.Containers[id]
    local avg = c and c.money or 0
    if avg <= 0 then return 0 end
    local chance, scale = 1, 1
    if FISHED[id] then chance, scale = 0.5, 2 end
    if math.random() >= chance then return 0 end
    return math.max(1, math.floor(avg * scale * (0.5 + math.random()) + 0.5))
end

function ns.AverageCoins(id)
    local c = ns.Containers[id]
    return c and c.money or 0
end

-- Container entry rows are { itemID, percent, quality, name, stackMin, stackMax }
function ns.GetContainer(id)
    return ns.Containers[id]
end

---------------------------------------------------------------------------
-- Rarity tiers
-- WoW quality says little inside these boxes (a lockbox is mostly greens, a trunk mostly whites), so each
-- item gets a tier from how often THAT box gives anything of its quality, bumped for recipes, gems and
-- bags. Rough odds per box: tier 3+ ~1 in 8-10, tier 5 ~1 in 50-100 (lockbox blues, trunk recipes,
-- junkbox gems, the Golden Pearl).
---------------------------------------------------------------------------

ns.TIERS = {
    [1] = { key = "common",    label = "Common",    r = 0.78, g = 0.78, b = 0.80 },
    [2] = { key = "uncommon",  label = "Uncommon",  r = 0.30, g = 0.85, b = 0.35 },
    [3] = { key = "rare",      label = "Rare",      r = 0.25, g = 0.58, b = 1.00 },
    [4] = { key = "epic",      label = "Epic",      r = 0.72, g = 0.36, b = 1.00 },
    [5] = { key = "legendary", label = "Legendary", r = 1.00, g = 0.62, b = 0.12 },
    -- an item the box isn't known to drop at all (not in our loot list): above Legendary
    [6] = { key = "elusive", label = "Elusive", r = 0.25, g = 1.00, b = 0.85 },
    -- an item the player is hunting (settings): the red tier above everything
    [7] = { key = "heirloom", label = "Heirloom", r = 1.00, g = 0.16, b = 0.22 },
}
ns.ELUSIVE = 6
ns.HEIRLOOM = 7

-- is this item in our loot list for the box?
local poolCache = {}
function ns.InPool(containerID, itemID)
    local set = poolCache[containerID]
    if not set then
        set = {}
        local c = ns.Containers[containerID]
        if c then for _, r in ipairs(c.items) do set[r[1]] = true end end
        poolCache[containerID] = set
    end
    return itemID ~= nil and set[itemID] == true
end

local function ItemLink(id, name)
    local link
    if C_Item and C_Item.GetItemInfo then link = select(2, C_Item.GetItemInfo(id)) end
    if not link and GetItemInfo then link = select(2, GetItemInfo(id)) end
    return link or ("[" .. (name or ("item " .. id)) .. "]")
end

-- after the reveal: say so in chat and ask for a report, so the item can join the loot list
function ns.ReportElusive(containerID, slot)
    local c = ns.Containers[containerID]
    local box = c and (c.scrollName or c.name) or ("container " .. tostring(containerID))
    ns.Print(("|cff40ffd9Elusive find!|r %s isn't on our loot list for %s. Please report it (the box and the item) at github.com/L33T/CrateExpectations/issues so it can be added to the pool. (item %d, box %s)")
        :format(ItemLink(slot.itemID, slot.name), box, slot.itemID or 0, tostring(containerID)))
end

function ns.TierColor(t)
    local d = ns.TIERS[t] or ns.TIERS[1]
    return d.r, d.g, d.b
end

local RECIPE_PREFIX = { "Pattern: ", "Plans: ", "Formula: ", "Schematic: ", "Recipe: ", "Manual: ", "Design: " }
local GEM_WORDS = { "Pearl", "Ruby", "Sapphire", "Emerald", "Diamond", "Citrine", "Jade", "Opal", "Aquamarine",
    "Agate", "Shadowgem", "Malachite", "Tigerseye", "Moonstone", "Arcane Crystal" }
local BAG_WORDS = { "Knapsack", "Pouch", "Satchel", "Rucksack" }

local function IsSpecial(name)
    if type(name) ~= "string" then return false end
    for _, p in ipairs(RECIPE_PREFIX) do
        if name:sub(1, #p) == p then return true end
    end
    for _, w in ipairs(GEM_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    for _, w in ipairs(BAG_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    return name:find(" Bag$") ~= nil
end

-- tier from the chance (percent) that a box gives at least one item of a quality
local function ClassTier(c)
    if c >= 40 then return 1 elseif c >= 15 then return 2 elseif c >= 4 then return 3 elseif c >= 1.2 then return 4 end
    return 5
end

local function QualityTier(q)
    q = q or 1
    if q >= 4 then return 5 elseif q == 3 then return 4 elseif q == 2 then return 2 end
    return 1
end

local tierCache = {}

-- Boxes where every item is the same kind of thing (all scrolls, mostly white/green) rank each item by its
-- own chance instead: percent at or above cut[1] = tier 1, cut[2] = 2, cut[3] = 3, cut[4] = 4, below = 5.
-- Bundle of Scrolls: Rare+ ~1 in 5 bundles, Epic+ ~1 in 10, Legendary (Khadgar's Unlocking and the
-- rarest imbues) ~1 in 20.
local ITEM_CUTS = {
    [277651] = { 20, 5, 3, 1.8 },
}

-- Per-box adjustments on top of the rules, old tier -> new tier. Applied in one pass from the ORIGINAL
-- tiers, so a chain never cascades (Legendary -> Rare stays Rare, it doesn't carry on to Uncommon).
local TIER_REMAP = {
    [20708] = { [5] = 3, [3] = 2 }, -- Tightly Sealed Trunk: its gems/recipes and green gear felt too generous
    [21113] = { [5] = 3, [3] = 2 }, -- Watertight Trunk: same treatment
}

local BuildTiersRaw

local function BuildTiers(cid)
    local map = BuildTiersRaw(cid)
    local remap = TIER_REMAP[cid]
    if remap then
        for id, t in pairs(map) do map[id] = remap[t] or t end
    end
    return map
end

BuildTiersRaw = function(cid)
    local c = ns.Containers[cid]
    local map = {}
    tierCache[cid] = map
    if not c then return map end
    if c.tiers then -- hand-set tiers (Comprehension)
        for _, r in ipairs(c.items) do map[r[1]] = c.tiers[r[1]] or QualityTier(r[3]) end
        return map
    end
    local cuts = ITEM_CUTS[cid]
    if cuts then
        for _, r in ipairs(c.items) do
            local p, t = r[2], 5
            for i = 1, 4 do
                if p >= cuts[i] then t = i break end
            end
            map[r[1]] = t
        end
        return map
    end
    local none = {}
    for _, r in ipairs(c.items) do
        local q = r[3]
        none[q] = (none[q] or 1) * (1 - r[2] / 100)
    end
    for _, r in ipairs(c.items) do
        local p, q = r[2], r[3]
        local t = ClassTier((1 - none[q]) * 100)
        local special = IsSpecial(r[4])
        if special then t = t + 1 end
        if special and p < 0.6 then t = t + 1 end  -- a recipe or gem that's rare even among its peers
        if q <= 0 then
            t = 1                                   -- grey is grey
        elseif q == 1 then
            t = math.min(t, special and 3 or 2)
        end
        if q == 2 and t < 2 then t = 2 end
        if q == 3 and t < 4 then t = 4 end
        if q >= 4 then t = 5 end
        if p >= 20 and t > 2 then t = 2 end         -- something you get every few boxes can't be epic
        map[r[1]] = math.max(1, math.min(5, t))
    end
    return map
end

-- tier 1-5 for an item from a container; items not in the table fall back to their quality
function ns.TierOf(containerID, itemID, quality)
    if ns.IsHunted(itemID) then return ns.HEIRLOOM end -- the player's own hunt beats every rule
    -- the reviewed list (Tiers.lua) decides; the old rules are only a fallback for anything not on it
    local t = itemID and ns.ItemTiers and ns.ItemTiers[itemID]
    if not t then
        local map = tierCache[containerID] or BuildTiers(containerID)
        t = (itemID and map[itemID]) or QualityTier(quality)
    end
    local cap = ns.BOX_MAX_TIER[containerID]
    if cap and t > cap then t = cap end -- low-level boxes top out lower
    return t
end

function ns.SortedContainerIDs()
    if not ns._sortedIDs then
        local t = {}
        for id in pairs(ns.Containers) do t[#t + 1] = id end
        table.sort(t, function(a, b) return ns.Containers[a].name < ns.Containers[b].name end)
        ns._sortedIDs = t
    end
    return ns._sortedIDs
end

-- Box groups for the demo picker and the < > buttons
ns.CATEGORIES = { "Lockboxes", "Junkboxes", "Chests", "Crates", "Clams", "Fishing trunks", "Mage scrolls", "Other" }

function ns.CategoryOf(id)
    local c = ns.Containers[id]
    if c and c.category then return c.category end
    local name = c and c.name or ""
    if name:find("Lockbox") then return "Lockboxes" end
    if name:find("Junkbox") then return "Junkboxes" end
    if name:find("Trunk") then return "Fishing trunks" end
    if name:find("Clam") then return "Clams" end
    if name:find("Crate") then return "Crates" end
    if name:find("Chest") then return "Chests" end
    if name:find("Scroll") then return "Mage scrolls" end
    return "Other"
end

-- every container, grouped by category (in ns.CATEGORIES order), by name inside a group
function ns.BrowseOrder()
    if not ns._browseIDs then
        local rank = {}
        for i, cat in ipairs(ns.CATEGORIES) do rank[cat] = i end
        local t = {}
        for _, id in ipairs(ns.SortedContainerIDs()) do
            if not ns.Containers[id].hidden then t[#t + 1] = id end
        end
        table.sort(t, function(a, b)
            local ra, rb = rank[ns.CategoryOf(a)], rank[ns.CategoryOf(b)]
            if ra ~= rb then return ra < rb end
            local na, nb = ns.Containers[a].name, ns.Containers[b].name
            if na ~= nb then return na < nb end
            return a < b
        end)
        ns._browseIDs = t
    end
    return ns._browseIDs
end

---------------------------------------------------------------------------
-- Auto loot handling
---------------------------------------------------------------------------

local savedAutoLoot -- "1" when we switched auto loot off and owe it back

local function SetAutoLoot(v)
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("autoLootDefault", v) else SetCVar("autoLootDefault", v) end
end

local function AutoLootOn()
    if C_CVar and C_CVar.GetCVarBool then return C_CVar.GetCVarBool("autoLootDefault") end
    return GetCVarBool("autoLootDefault")
end

function ns.SuspendAutoLoot()
    if savedAutoLoot then return end
    if AutoLootOn() then
        savedAutoLoot = "1"
        SetAutoLoot("0")
        ns.Debug("auto loot paused")
    end
end

function ns.RestoreAutoLoot()
    if savedAutoLoot then
        SetAutoLoot(savedAutoLoot)
        savedAutoLoot = nil
        ns.Debug("auto loot restored")
    end
end

---------------------------------------------------------------------------
-- The game's loot window: hidden while we spin, shown again if anything goes wrong
---------------------------------------------------------------------------

local lootFrameHidden = false

function ns.HideLootFrame()
    if LootFrame then
        LootFrame:SetAlpha(0)
        LootFrame:EnableMouse(false)
        lootFrameHidden = true
    end
end

function ns.RevealLootFrame()
    if LootFrame and lootFrameHidden then
        LootFrame:SetAlpha(1)
        LootFrame:EnableMouse(true)
        lootFrameHidden = false
    end
end

---------------------------------------------------------------------------
-- Detecting a container being opened
---------------------------------------------------------------------------

local pending -- { itemID, at }

local function InCombat()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end
ns.InCombat = InCombat

local function OnUseContainerItem(bag, slot)
    if not ns.db or not ns.db.enabled then return end
    if ns.live then return end
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    if not ok or type(info) ~= "table" or not info.itemID then return end
    local id = info.itemID
    if ns.CompScrolls and ns.CompScrolls[id] then
        ns.NoteCompTarget(id) -- an untranslated scroll clicked = the Comprehend Scroll target
        return
    end
    if not ns.Containers[id] or ns.Containers[id].noLoot then return end
    if InCombat() then return end -- in combat: no takeover, the normal loot window it is
    if not ns.IsBoxEnabled(id) then return end -- switched off in settings
    if ns.ONCE_ONLY[id] and ns.db.seenOnce[id] then return end -- had its one show already
    -- A modifier that flips auto loot means "just loot it": leave the game alone.
    if IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") then return end
    ns.PrepareOpen(id)
end

-- get ready to catch this box's loot window (from a bag click, or our own "open another" buttons).
-- fromUI: opened from inside the case screen (My boxes / OPEN ANOTHER). That runs BEFORE the box is used,
-- so auto loot is paused in time and SpeedyAutoLoot & co. stay out of it; the player then presses OPEN.
function ns.PrepareOpen(id, fromUI)
    if pending and pending.itemID == id and GetTime() - pending.at < 1 then
        if fromUI then pending.fromUI = true end
        return
    end
    local at = GetTime()
    pending = { itemID = id, at = at, fromUI = fromUI or nil }
    ns.SuspendAutoLoot()
    ns.Debug("container used:", id, ns.Containers[id].name)

    -- A locked lockbox or a failed use never opens a loot window: give auto loot back.
    C_Timer.After(4, function()
        if pending and pending.at == at and not ns.live then
            pending = nil
            ns.RestoreAutoLoot()
        end
    end)
end

-- The next untranslated scroll to comprehend, by Comprehension skill level (the meme names don't matter,
-- the level decides the pool): any scroll of the same level first; only when that level is used up, the
-- highest level left. count = how many scrolls of the chosen level remain.
function ns.NextCompScroll(prefer)
    local wantLvl = prefer and ns.CompScrolls[prefer]
    local byLvl = {} -- level -> { first = {bag, slot, id}, count }
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and n or 0) do
            local ok2, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            local id = ok2 and type(info) == "table" and info.itemID
            local lvl = id and ns.CompScrolls[id]
            if lvl then
                local e = byLvl[lvl]
                if not e then
                    e = { id = id, bag = bag, slot = slot, level = lvl, count = 0 }
                    byLvl[lvl] = e
                end
                e.count = e.count + (info.stackCount or 1)
            end
        end
    end
    if wantLvl and byLvl[wantLvl] then return byLvl[wantLvl] end
    local best
    for lvl, e in pairs(byLvl) do
        if not best or lvl > best.level then best = e end
    end
    return best
end

function ns.CompSpellName()
    local n
    if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(1296017) end
    if not n and GetSpellInfo then n = GetSpellInfo(1296017) end
    return n or "Comprehend Scroll"
end

-- if the game refuses to let the addon use the box, say what to do instead of failing silently
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, _, addon)
    if addon == ADDON then
        ns.Print("WoW didn't let the addon open that box for you. Click it in your bags instead (the case screen still plays).")
    end
end)

if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", OnUseContainerItem)
end
if UseContainerItem and (not C_Container or UseContainerItem ~= C_Container.UseContainerItem) then
    hooksecurefunc("UseContainerItem", OnUseContainerItem)
end

local function LootIsFromItem()
    if not GetLootSourceInfo then return true end
    local ok, guid = pcall(GetLootSourceInfo, 1)
    if not ok or guid == nil then return true end
    if issecretvalue and issecretvalue(guid) then return true end
    return type(guid) ~= "string" or guid:find("^Item%-") ~= nil
end

local function ReadLootSlots()
    local slots = {}
    local n = GetNumLootItems() or 0
    local moneyType = Enum and Enum.LootSlotType and Enum.LootSlotType.Money
    for i = 1, n do
        local icon, name, qty, _, quality = GetLootSlotInfo(i)
        local slotType = GetLootSlotType and GetLootSlotType(i)
        if icon or name then
            local link = GetLootSlotLink(i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if type(name) == "string" then name = name:gsub("\n", " ") end
            slots[#slots + 1] = {
                slot = i,
                itemID = id,
                icon = icon,
                name = name,
                count = qty or 1,
                quality = quality or 1,
                money = (moneyType and slotType == moneyType) or (not link and not id),
            }
            if slots[#slots].money then slots[#slots].copper = ns.ParseMoney(name) end
        end
    end
    return slots
end

local function OnLootShown(autoLoot)
    if ns.live then
        ns.HideLootFrame() -- LOOT_OPENED after LOOT_READY: keep it hidden
        return
    end
    if not pending or GetTime() - pending.at > 5 then return end
    if not LootIsFromItem() then return end
    local slots = ReadLootSlots()
    if #slots == 0 then return end

    -- The game already decided to auto-loot this one (the auto-loot setting was read before we could pause
    -- it, so SpeedyAutoLoot & co. are taking everything now). This handler runs before theirs, so the loot
    -- is still readable: play the case anyway, as "already in your bags" (like Comprehension), no Collect.
    local manual = pending.fromUI
    if autoLoot == true then
        local id = pending.itemID
        pending = nil
        ns.Debug("auto loot is taking this box: playing it as already looted")
        local numItems = 0
        for _, s in ipairs(slots) do
            if not s.money then
                numItems = numItems + 1
                if s.itemID and not ns.InPool(id, s.itemID) then s.elusive = true end
            end
        end
        -- more items than cards: remember it, so this box deals that many from now on
        if numItems > (ns.db.maxSeen[id] or 0) and numItems > ns.CardCount(id) then ns.db.maxSeen[id] = numItems end
        if ns.ONCE_ONLY[id] then ns.db.seenOnce[id] = true end
        ns.RecordOpen(id, slots)
        C_Timer.After(0, function()
            if not ns.live and not InCombat() then ns.UI:Open(id, slots, true, true, manual) end
        end)
        return
    end

    local id = pending.itemID
    pending = nil
    local numItems = 0
    for _, s in ipairs(slots) do
        if not s.money then
            numItems = numItems + 1
            if s.itemID and not ns.InPool(id, s.itemID) then s.elusive = true end
        end
    end
    if numItems > (ns.db.maxSeen[id] or 0) and numItems > ns.CardCount(id) then
        ns.db.maxSeen[id] = numItems
    end
    if ns.ONCE_ONLY[id] then ns.db.seenOnce[id] = true end
    -- room check up front: the UI warns before Collect (stacking onto existing stacks can still save a slot)
    local free = ns.FreeBagSlots()
    ns.live = { itemID = id, slots = slots, collecting = false, free = free,
        short = math.max(0, numItems - free) }
    ns.HideLootFrame()
    C_Timer.After(0, function() if ns.live then ns.HideLootFrame() end end)
    ns.UI:Open(id, slots, true, nil, manual)
end

-- Called by the UI once the spins are done.
function ns.CollectLive()
    local live = ns.live
    if not live or live.collecting then return end
    live.collecting = true
    for i = GetNumLootItems(), 1, -1 do
        LootSlot(i)
    end
    -- Bags full or something refused: show the real window so nothing is stranded.
    C_Timer.After(1.5, function()
        if ns.live == live then ns.LootStuck(live) end
    end)
end

-- something stayed behind after Collect (usually full bags): hand the rest to the game's loot window
function ns.LootStuck(live)
    if live.stuck then return end
    live.stuck = true
    ns.RevealLootFrame()
    local left = GetNumLootItems and GetNumLootItems() or 0
    ns.UI:LootStuck(left)
    ns.Print(("Your bags are full: %d thing%s stayed in the loot window. Make room and take %s from there.")
        :format(left, left == 1 and "" or "s", left == 1 and "it" or "them"))
end

-- the game says "Inventory is full" while we collect: don't wait for the timeout
local invFull = CreateFrame("Frame")
invFull:RegisterEvent("UI_ERROR_MESSAGE")
invFull:SetScript("OnEvent", function(_, _, a1, a2)
    local live = ns.live
    if not (live and live.collecting) then return end
    local msg = type(a2) == "string" and a2 or a1
    if msg == ERR_INV_FULL or msg == ERR_BAG_FULL or msg == ERR_ITEM_MAX_COUNT then
        C_Timer.After(0.2, function() if ns.live == live then ns.LootStuck(live) end end)
    end
end)

-- How many Rare+ and Epic+ items one opening of this box gives on average, with the current tiers: the sum
-- of their drop chances (Comprehension: their share of the weights). Feeds the luck meter.
function ns.ExpectedRareEpic(cid)
    local c = ns.Containers[cid]
    if not c then return 0, 0 end
    local r, e, total = 0, 0, 0
    for _, row in ipairs(c.items) do
        local p = row[2] or 0
        total = total + p
        local t = ns.TierOf(cid, row[1], row[3])
        if t >= 3 then r = r + p end
        if t >= 4 then e = e + p end
    end
    if c.single then
        if total <= 0 then return 0, 0 end
        local hit = 1 - (c.failPct or 0) / 100
        return hit * r / total, hit * e / total
    end
    return r / 100, e / 100
end

-- the tier an item actually landed as (what the reveal showed)
function ns.LandedTier(cid, s)
    if s.heirloom or ns.IsHunted(s.itemID) then return ns.HEIRLOOM end
    if s.elusive then return ns.ELUSIVE end
    return ns.TierOf(cid, s.itemID, s.quality)
end

-- One real opening (or comprehend): counts, coins, tiers, best pull, and the luck bookkeeping.
-- sheep = a comprehend that fizzled (no item, but it was an opening)
function ns.RecordOpen(itemID, slots, sheep)
    local stats = ns.db.stats
    stats.opened[itemID] = (stats.opened[itemID] or 0) + 1
    local expR, expE = ns.ExpectedRareEpic(itemID)
    stats.expRare = (stats.expRare or 0) + expR
    stats.expEpic = (stats.expEpic or 0) + expE
    if sheep then stats.sheep = (stats.sheep or 0) + 1 end
    local rare = false
    for _, s in ipairs(slots) do
        if s.money then
            stats.copper = (stats.copper or 0) + (s.copper or 0)
        else
            if s.itemID then stats.won[s.itemID] = (stats.won[s.itemID] or 0) + (s.count or 1) end
            local t = ns.LandedTier(itemID, s)
            stats.tiers[t] = (stats.tiers[t] or 0) + 1
            stats.items = (stats.items or 0) + 1
            if t >= 3 then
                rare = true
                stats.gotRare = (stats.gotRare or 0) + 1
            end
            if t >= 4 then stats.gotEpic = (stats.gotEpic or 0) + 1 end
            local best = stats.best
            if s.itemID and (not best.tier or t > best.tier) then
                stats.best = { id = s.itemID, tier = t, name = s.name or ns.ItemName(s.itemID), box = itemID }
            end
        end
    end
    stats.sinceRare = rare and 0 or (stats.sinceRare or 0) + 1
end

-- a light-hearted verdict: actual Rare+ against what the boxes you opened should have given
function ns.Luck()
    local s = ns.db.stats
    local exp, got = s.expRare or 0, s.gotRare or 0
    if exp < 0.5 then return nil, "Open a few more boxes and the dice will start talking." end
    local ratio = got / exp
    local verdict
    if ratio >= 2.5 then verdict = "Blessed by RNG. Buy a lottery ticket."
    elseif ratio >= 1.5 then verdict = "Lucky! The boxes like you."
    elseif ratio >= 1.15 then verdict = "A bit luckier than average."
    elseif ratio >= 0.85 then verdict = "Right on the average. Perfectly balanced."
    elseif ratio >= 0.5 then verdict = "Unlucky. The next one's yours (probably)."
    else verdict = "Cursed. Have you tried opening them with your other hand?" end
    return ratio, verdict
end

local function OnLootClosed()
    pending = nil
    local live = ns.live
    if live then
        ns.live = nil
        if live.collecting then
            ns.RecordOpen(live.itemID, live.slots)
            ns.UI:OnCollected()
        else
            ns.UI:OnLootLost()
        end
    end
    ns.RevealLootFrame()
    ns.RestoreAutoLoot()
end

---------------------------------------------------------------------------
-- Demo: roll a case from the drop table, no container needed
---------------------------------------------------------------------------

-- a comprehension that went wrong (the scroll polymorphs you)
function ns.FailSlot()
    return { fail = true, name = "Polymorphed!", icon = "Interface\\Icons\\Spell_Nature_Polymorph", quality = 0,
        tier = 1, count = 1 }
end

function ns.RollDemo(id)
    local c = ns.Containers[id]
    if c.single then -- exactly one result per use (Comprehension)
        if math.random() * 100 < (c.failPct or 0) then return { ns.FailSlot() } end
        local row = ns.WeightedPick(c.items)
        return { { itemID = row[1], name = ns.ItemName(row[1], row[4]), icon = ns.ItemIcon(row[1]),
            count = row[5] or 1, quality = row[3] } }
    end
    local slots = {}
    for _, row in ipairs(c.items) do
        if math.random() * 100 < row[2] then
            local lo, hi = row[5] or 1, row[6] or 1
            slots[#slots + 1] = { itemID = row[1], name = ns.ItemName(row[1], row[4]), icon = ns.ItemIcon(row[1]),
                count = math.random(lo, math.max(lo, hi)), quality = row[3] }
        end
        if #slots >= ns.DemoMaxItems(id) then break end
    end
    local need = math.min(MIN_ITEMS[id] or 1, ns.CardCount(id))
    local tries = 0
    while #slots < need and tries < 50 do
        tries = tries + 1
        local row = ns.WeightedPick(c.items)
        local dupe = false
        for _, s in ipairs(slots) do
            if s.itemID == row[1] then dupe = true break end
        end
        if not dupe or tries > 25 then
            slots[#slots + 1] = { itemID = row[1], name = ns.ItemName(row[1], row[4]), icon = ns.ItemIcon(row[1]),
                count = row[5] or 1, quality = row[3] }
        end
    end
    local coins = DemoCoins(id)
    if coins > 0 then slots[#slots + 1] = { money = true, copper = coins } end
    return slots
end

function ns.WeightedPick(items)
    local total = 0
    for _, r in ipairs(items) do total = total + r[2] end
    local x = math.random() * total
    for _, r in ipairs(items) do
        x = x - r[2]
        if x <= 0 then return r end
    end
    return items[#items]
end

local function RowSlot(row)
    local lo, hi = row[5] or 1, row[6] or 1
    return { itemID = row[1], name = ns.ItemName(row[1], row[4]), icon = ns.ItemIcon(row[1]),
        count = math.random(lo, math.max(lo, hi)), quality = row[3] }
end

-- Demo roll whose best item is exactly tier t (0 = a fizzle), `count` of them (default 1, as many as the
-- box has cards for). nil when the box has nothing of that tier.
function ns.ForceRoll(id, t, count)
    local c = ns.Containers[id]
    if t == ns.HEIRLOOM then
        -- demo a hunted item: one of the player's hunts from this box if any, else any item standing in for one
        local pool = {}
        for _, r in ipairs(c.items) do if ns.IsHunted(r[1]) then pool[#pool + 1] = r end end
        local s = RowSlot(#pool > 0 and pool[math.random(#pool)] or ns.WeightedPick(c.items))
        s.heirloom = true
        if c.single then return { s } end
        local out = {}
        for _, x in ipairs(ns.RollDemo(id)) do
            if x.money or x.itemID ~= s.itemID then out[#out + 1] = x end
        end
        local nItems = 0
        for _, x in ipairs(out) do if not x.money then nItems = nItems + 1 end end
        if nItems >= ns.CardCount(id) then
            for i, x in ipairs(out) do if not x.money then table.remove(out, i) break end end
        end
        table.insert(out, 1, s)
        return out
    end
    if t == ns.ELUSIVE then
        -- demo an elusive find: something from a different box's list, which this box isn't known to drop
        local others = {}
        for oid, oc in pairs(ns.Containers) do
            if oid ~= id then
                for _, r in ipairs(oc.items) do
                    if not ns.InPool(id, r[1]) and r[3] >= 2 then others[#others + 1] = r end
                end
            end
        end
        if #others == 0 then return nil end
        local s = RowSlot(others[math.random(#others)])
        s.elusive = true
        if c.single then return { s } end
        local out = {}
        for _, x in ipairs(ns.RollDemo(id)) do out[#out + 1] = x end
        local nItems = 0
        for _, x in ipairs(out) do if not x.money then nItems = nItems + 1 end end
        if nItems >= ns.CardCount(id) then
            for i, x in ipairs(out) do if not x.money then table.remove(out, i) break end end
        end
        table.insert(out, 1, s)
        return out
    end
    if t == 0 then
        if c.failPct then return { ns.FailSlot() } end
        return nil
    end
    local pool = {}
    for _, r in ipairs(c.items) do
        if ns.TierOf(id, r[1], r[3]) == t then pool[#pool + 1] = r end
    end
    if #pool == 0 then return nil end
    if c.single then return { RowSlot(ns.WeightedPick(pool)) } end
    count = math.max(1, math.min(count or 1, ns.CardCount(id)))
    local forced = {}
    for _ = 1, count do forced[#forced + 1] = RowSlot(ns.WeightedPick(pool)) end
    -- a normal roll for the other slots, minus anything as good or better, plus the forced items
    local out, coins = {}, nil
    for _, s in ipairs(ns.RollDemo(id)) do
        if s.money then
            coins = s
        elseif ns.TierOf(id, s.itemID, s.quality) < t then
            out[#out + 1] = s
        end
    end
    while #out > ns.CardCount(id) - count do table.remove(out, math.random(#out)) end
    for _, s in ipairs(forced) do table.insert(out, math.random(#out + 1), s) end
    if coins then out[#out + 1] = coins end
    return out
end

function ns.Demo(id)
    if ns.live then ns.Print("A real case is open right now.") return end
    if InCombat() then ns.Print("Not in combat! Try again once you're out.") return end
    id = id or ns.db.lastDemo
    if not ns.Containers[id] then id = 21150 end
    ns.db.lastDemo = id
    local slots
    local force = ns.UI.forceTier
    if force then
        slots = ns.ForceRoll(id, force, ns.UI.forceCount)
        if not slots then
            local name = force == 0 and "fizzle" or (ns.TIERS[force] and ns.TIERS[force].label or tostring(force))
            ns.Print(("%s has nothing %s; rolling normally."):format(ns.Containers[id].name, name))
        end
    end
    ns.UI:Open(id, slots or ns.RollDemo(id), false)
end

---------------------------------------------------------------------------
-- Mage Comprehension. No loot window: the scroll goes straight to the bags. So:
--   * clicking an untranslated scroll (to give Comprehend Scroll its target) tells us which scroll, and
--     so which pool (its "Requires Comprehension" level); UNIT_SPELLCAST_SENT's target name backs it up
--   * the cast starting opens the screen with the reel already spinning
--   * the "You create/receive: [Scroll of ...]" chat line gives the result: the reel glides onto it
--   * the cast succeeding with no scroll within 3s = it fizzled (the self-polymorph): lands on the sheep
--   * an interrupted / failed cast stops the reel and closes the screen
---------------------------------------------------------------------------

local compTarget -- { id, at }: the untranslated scroll clicked as the spell's target
local sentName   -- { name, at }: UNIT_SPELLCAST_SENT's target name
local comp       -- { id, guid, at, succeeded, pending } while a comprehend is under way

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok and n then return n end
    end
    if GetSpellInfo then return (GetSpellInfo(spellID)) end
end

-- "You create: %s." etc. -> "You create: " (the bit before the link), for every "to you" loot message
local selfPrefixes
local function SelfPrefixes()
    if selfPrefixes then return selfPrefixes end
    selfPrefixes = {}
    for _, fmt in ipairs({ LOOT_ITEM_CREATED_SELF, LOOT_ITEM_CREATED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF,
        LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE }) do
        local pre = type(fmt) == "string" and fmt:match("^(.-)%%s")
        if pre and pre ~= "" then selfPrefixes[#selfPrefixes + 1] = pre end
    end
    return selfPrefixes
end

local function IsComprehension(spellID)
    if spellID == nil or (issecretvalue and issecretvalue(spellID)) then return false end
    local n = SpellName(spellID)
    return type(n) == "string" and n:lower():find("comprehen", 1, true) ~= nil
end

-- called from the UseContainerItem hook for any untranslated scroll (they have no use of their own, so a
-- click on one is the Comprehend Scroll target)
function ns.NoteCompTarget(id)
    compTarget = { id = id, at = GetTime() }
    ns.Debug("comprehend target", id, ns.Containers[id] and ns.Containers[id].scrollName)
end

-- without a known scroll: the best pool the player's skill allows
local function PoolFromSkill()
    local rank
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local ok, name, _, _, r = pcall(GetSkillLineInfo, i)
            if ok and type(name) == "string" and name:lower():find("comprehen", 1, true) then
                rank = r
                break
            end
        end
    end
    local id = ns.CompShown[1]
    for _, lvl in ipairs(ns.CompLevels) do
        if (rank or 1) >= lvl then id = ns.CompShown[lvl] end
    end
    return id
end

local function CompScrollID()
    local now = GetTime()
    if compTarget and now - compTarget.at < 8 then return compTarget.id end
    if sentName and now - sentName.at < 8 then
        for id in pairs(ns.CompScrolls) do
            if ns.Containers[id].scrollName == sentName.name then return id end
        end
    end
    return PoolFromSkill()
end

-- A comprehend that goes wrong (any tier can) turns you into a sheep for 8 sec. Wowhead: the aura is
-- "Comprehension Failure" (spell 1297068, "You made a small mistake while deciphering the scroll."); a
-- Polymorph/sheep aura is matched too in case the transform comes as its own aura.
local FAIL_AURA = 1297068

local function IsSheepAura(name, spellID)
    if spellID and not (issecretvalue and issecretvalue(spellID)) and spellID == FAIL_AURA then return true end
    if type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return false end
    name = name:lower()
    return name:find("comprehension failure", 1, true) ~= nil or name:find("polymorph", 1, true) ~= nil
        or name:find("sheep", 1, true) ~= nil
end

local function PlayerIsSheep()
    for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
        for i = 1, 40 do
            local name, spellID
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if not ok or not a then break end
                name, spellID = a.name, a.spellId
            elseif UnitAura then
                local ok, n, _, _, _, _, _, _, _, _, sid = pcall(UnitAura, "player", i, filter)
                if not ok or not n then break end
                name, spellID = n, sid
            else
                break
            end
            if IsSheepAura(name, spellID) then return true end
        end
    end
    return false
end

local function StartComprehend(guid)
    if not ns.db or not ns.db.enabled or ns.live then return end
    if ns.db.disabled.comp then return end -- switched off in settings
    local id = CompScrollID()
    compTarget, sentName = nil, nil
    comp = { id = id, guid = guid, at = GetTime(), sheepBefore = PlayerIsSheep() }
    ns.Debug("comprehend start", id, ns.Containers[id].scrollName)
    if InCombat() then
        comp.quiet = true -- comprehending in combat: no screen, the result goes to chat
    else
        comp.pending = ns.UI:OpenPending(id)
    end
end

local function FinishComprehend(slot)
    local c = comp
    comp = nil
    if not c then return end
    if not slot.fail and slot.itemID and not ns.InPool(c.id, slot.itemID) then slot.elusive = true end
    ns.RecordOpen(c.id, slot.fail and {} or { slot }, slot.fail)
    if not c.quiet and not InCombat() then
        if c.pending and ns.UI:ResolvePending(slot) then return end
        if not ns.live then ns.UI:Open(c.id, { slot }, true, true) return end -- the screen wasn't spinning: play it now
    end
    -- in combat (or the screen got closed for it): just say what it was
    local scroll = ns.Containers[c.id] and ns.Containers[c.id].scrollName or "The scroll"
    if slot.fail then
        ns.Print(scroll .. ": |cffccccccBAAA!|r Polymorphed. The scroll survives, try again.")
    else
        local tier = slot.elusive and ns.ELUSIVE or ns.TierOf(c.id, slot.itemID, slot.quality)
        local r, g, b = ns.TierColor(tier)
        ns.Print(("%s: |cff%02x%02x%02x%s|r (%s)"):format(scroll, math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), slot.name or "?",
            ns.TIERS[tier] and ns.TIERS[tier].label or ""))
        if slot.elusive then ns.ReportElusive(c.id, slot) end
    end
end

-- Comprehend Scroll (1296017) is instant: it takes the target and starts a second, 5 sec "Comprehend
-- Scroll" cast (1309965 / 1309973 / 1310029 / 1310030 on Wowhead). The 5 sec cast is the one that counts:
-- its START spins the reel, its SUCCEEDED / INTERRUPTED end it.
local function ArmFizzleTimer(c)
    C_Timer.After(3, function()
        if comp == c then
            ns.Debug("no scroll within 3s: fizzle")
            FinishComprehend(ns.FailSlot())
        end
    end)
end

local function OnCastStart(guid, spellID)
    if not IsComprehension(spellID) then return end
    if comp and not comp.succeeded then
        comp.guid = guid -- the instant part already opened the screen; follow the 5 sec cast from here
    else
        StartComprehend(guid)
    end
    if comp then
        comp.casting = true
        ns.Debug("comprehend cast", spellID)
    end
end

-- the moment a sheep aura shows up mid-comprehend, that's the result
local function CheckSheep()
    if comp and not comp.sheepBefore and PlayerIsSheep() then
        ns.Debug("polymorphed: fizzle")
        FinishComprehend(ns.FailSlot())
        return true
    end
    return false
end

-- A stopped cast is either a real interruption or the scroll fizzling (which may come through as a failed
-- cast): give the polymorph a moment to show up before calling it an interruption.
local function OnCastStopped(guid)
    if not comp or comp.succeeded or not comp.casting or not (comp.guid == nil or comp.guid == guid) then return end
    if CheckSheep() then return end
    local c = comp
    C_Timer.After(0.7, function()
        if comp ~= c or CheckSheep() then return end
        ns.Debug("comprehend interrupted")
        comp = nil
        ns.UI:CancelPending("Comprehension interrupted.")
    end)
end

local function OnSpellSucceeded(guid, spellID)
    if not IsComprehension(spellID) then return end
    if not comp then
        -- the instant part (or a START we missed): open the screen now, and give the 5 sec cast a second
        -- to show up; if none does, treat this as the whole thing
        StartComprehend(guid)
        local c = comp
        if not c then return end
        C_Timer.After(1, function()
            if comp == c and not c.casting and not c.succeeded then
                c.succeeded = true
                ArmFizzleTimer(c)
            end
        end)
        return
    end
    if comp.succeeded then return end
    if comp.casting and comp.guid ~= nil and comp.guid ~= guid then return end -- the instant part, mid-cast
    if not comp.casting then return end -- the instant part right after a START we already saw
    comp.succeeded = true
    ArmFizzleTimer(comp)
end

local function OnLootMessage(msg)
    if not comp or type(msg) ~= "string" then return end
    if issecretvalue and issecretvalue(msg) then return end
    if GetTime() - comp.at > 30 then return end
    local mine = false
    for _, pre in ipairs(SelfPrefixes()) do
        if msg:sub(1, #pre) == pre then mine = true break end
    end
    if not mine then return end
    local id = tonumber(msg:match("item:(%d+)"))
    if not id then return end
    local name = ns.ItemName(id, msg:match("%[(.-)%]"))
    if not (type(name) == "string" and name:find("^Scroll of")) then return end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or nil
    if not quality then
        for _, r in ipairs(ns.Containers[comp.id].items) do
            if r[1] == id then quality = r[3] break end
        end
    end
    ns.Debug("comprehend result", id, name)
    FinishComprehend({ itemID = id, name = name, icon = ns.ItemIcon(id), count = 1, quality = quality or 1 })
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("LOOT_READY")
ev:RegisterEvent("LOOT_OPENED")
ev:RegisterEvent("LOOT_CLOSED")
ev:RegisterEvent("LOOT_BIND_CONFIRM")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("CHAT_MSG_LOOT")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then -- unit, castGUID, spellID
        if ns.db and ns.db.debug then ns.Debug("spell", a3, SpellName(a3)) end
        OnSpellSucceeded(a2, a3)
        return
    elseif event == "UNIT_SPELLCAST_SENT" then -- unit, target, castGUID, spellID
        if IsComprehension(a4) and type(a2) == "string" and not (issecretvalue and issecretvalue(a2)) then
            sentName = { name = a2, at = GetTime() }
            ns.Debug("comprehend sent, target:", a2)
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- the screen closes for combat (UI.lua); a comprehend under way reports in chat from here on, even if
        -- combat is over by the time the scroll lands
        if comp then comp.quiet = true end
        return
    elseif event == "UNIT_AURA" then
        if comp then CheckSheep() end
        return
    elseif event == "UNIT_SPELLCAST_START" then -- unit, castGUID, spellID
        OnCastStart(a2, a3)
        return
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        OnCastStopped(a2)
        return
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(a1)
        return
    end
    if event == "ADDON_LOADED" then
        if a1 == ADDON then
            CrateExpectationsCasesDB = CrateExpectationsCasesDB or {}
            CopyDefaults(CrateExpectationsCasesDB, DEFAULTS)
            ns.db = CrateExpectationsCasesDB
            -- batch mode became the default after it shipped switched off: turn it on once for existing setups
            if not ns.db.batchDefaultOn then
                ns.db.batch = true
                ns.db.batchDefaultOn = true
            end
        end
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLootShown(a1)
    elseif event == "LOOT_CLOSED" then
        OnLootClosed()
    elseif event == "LOOT_BIND_CONFIRM" then
        if ns.live and ns.live.collecting and ConfirmLootSlot then ConfirmLootSlot(a1) end
    elseif event == "PLAYER_LOGOUT" then
        ns.RestoreAutoLoot() -- never leave auto loot switched off
    end
end)

local function FindContainer(text)
    local n = tonumber(text)
    if n and ns.Containers[n] then return n end
    text = text:lower()
    for _, id in ipairs(ns.SortedContainerIDs()) do
        if ns.Containers[id].name:lower():find(text, 1, true) then return id end
    end
end

SLASH_CRATEEXPECTATIONSCASES1 = "/crates"
SLASH_CRATEEXPECTATIONSCASES2 = "/cases"
SlashCmdList.CRATEEXPECTATIONSCASES = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "settings" or cmd == "config" or cmd == "options" then
        if InCombat() then ns.Print("Not in combat! Try again once you're out.") return end
        ns.UI:ShowSettings()
    elseif cmd == "boxes" or cmd == "mine" or cmd == "batch" then
        if InCombat() then ns.Print("Not in combat! Try again once you're out.") return end
        ns.UI:ShowMine()
    elseif cmd == "demo" then
        if rest ~= "" then
            local id = FindContainer(rest)
            if not id then ns.Print("No container matches '" .. rest .. "'. Try /crates list") return end
            ns.Demo(id)
        else
            ns.Demo()
        end
    elseif cmd == "on" or cmd == "off" then
        ns.db.enabled = (cmd == "on")
        ns.Print("Real container openings:", ns.db.enabled and "|cff40ff40ON|r" or "|cffff4040OFF|r")
    elseif cmd == "speed" then
        local s = tonumber(rest)
        if s and s >= 0.5 and s <= 15 then
            ns.db.spinTime = s
            ns.Print("Spin time set to", s, "seconds.")
        else
            ns.Print("Usage: /crates speed <0.5-15>  (now " .. ns.db.spinTime .. "s)")
        end
    elseif cmd == "style" then
        local s = rest:lower()
        if s == "auto" or s == "pull" or s == "reel" then
            ns.db.style = s
            ns.Print("Style:", s)
        else
            ns.Print("Usage: /crates style auto|pull|reel  (now " .. ns.db.style .. ")")
        end
    elseif cmd == "force" then
        local s = rest:lower()
        local map = { off = false, any = false, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5, elusive = 6,
            fizzle = 0, sheep = 0 }
        local t = map[s]
        if t == nil then t = tonumber(s) end
        if t == nil or (type(t) == "number" and (t < 0 or t > 6)) then
            ns.Print("Usage: /crates force off|common|uncommon|rare|epic|legendary|fizzle (demo only)")
        else
            ns.UI.forceTier = t or nil
            ns.Print("Demo force:", t and (t == 0 and "Fizzle" or ns.TIERS[t].label) or "off")
        end
    elseif cmd == "sound" then
        ns.db.sound = not ns.db.sound
        ns.Print("Sound", ns.db.sound and "on" or "off")
    elseif cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns.Print("Debug", ns.db.debug and "on" or "off")
    elseif cmd == "list" then
        for _, id in ipairs(ns.BrowseOrder()) do
            local c = ns.Containers[id]
            ns.Print(("%s |cff888888(%d, %d items)|r"):format(c.name, id, #c.items))
        end
    elseif cmd == "stats" then
        if InCombat() then ns.Print("Not in combat! Try again once you're out.") return end
        ns.UI:ShowStats()
    elseif FindContainer(msg) then
        ns.Demo(FindContainer(msg)) -- "/crates mithril bound", "/crates 21150"
    else
        ns.Print("No container matches '" .. msg .. "'.")
        ns.Print("/crates - settings (boxes on/off, hunting list, demo room, my boxes)")
        ns.Print("/crates demo - demo case (no container used) | /crates boxes - open your boxes one after another")
        ns.Print("/crates <name or id> - demo a specific container, e.g. /crates mithril bound")
        ns.Print("/crates list | stats | style auto|pull|reel | speed <sec> | sound | on | off | debug")
        ns.Print("/crates force common|uncommon|rare|epic|legendary|fizzle|off - force the demo's best pull")
    end
end
