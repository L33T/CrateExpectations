-- Crate Expectations: Mage Comprehension (WoW Forever).
-- A Mage casts Comprehend Scroll on an untranslated scroll ("Scroll: UPDOG" and other meme names). The
-- scroll's "Requires Comprehension (N)" decides the result pool: only that tier's scrolls can come out.
-- Pools (skill 1 / 15 / 50 / 175) from method.gg's Comprehension guide; required levels per untranslated
-- scroll from the Wowhead Forever tooltips (2026-11-19).
-- Nobody tracks comprehension results, so there are no odds: the weights below only drive demo rolls and
-- the reel's filler tiles (relative Bundle of Scrolls counts where those exist, guesses otherwise), and
-- are never shown. Tiers are a first pass, to be reworked.

local _, ns = ...

-- untranslated scroll -> { required Comprehension skill, name }
local UNTRANSLATED = {
    [211785] = { 1, "Scroll: CWAL" },
    [211787] = { 1, "Scroll: LOWER PING WHOMEVER" },
    [211780] = { 1, "Scroll: KWYJIBO" },
    [211786] = { 1, "Scroll: CHAP BALK WELLES" },
    [211784] = { 15, "Scroll: WUBBA WUBBA" },
    [211853] = { 15, "Scroll: VOCE WELL" },
    [211854] = { 15, "Scroll: OMIT KESA" },
    [211855] = { 15, "Scroll: STHENIC LUNATE" },
    [213543] = { 50, "Scroll: UPDOG" },
    [213545] = { 50, "Scroll: PEATCHY ATTAX" },
    [213547] = { 50, "Scroll: THAW WORDS" },
    [213546] = { 50, "Scroll: SHOOBEEDOOP" },
    [213544] = { 50, "Scroll: TOPAZ YORAK" },
    [281018] = { 175, "Scroll: RARE SERVICHI RADAR" },
    [281015] = { 175, "Scroll: DOST OREM" },
    [281016] = { 175, "Scroll: FORGOT HOOF THUD" },
    [281017] = { 175, "Scroll: KEEP CLEF FOCI" },
}

-- result pools: { itemID, demo weight, quality, name }
local POOLS = {
    [1] = {
        { 213564, 1205, 1, "Scroll of Minor Evocation" },
        { 275069, 914, 1, "Scroll of Rat Familiar" },
        { 274947, 911, 2, "Scroll of Imbue Lesser Flame" },
        { 275067, 550, 2, "Scroll of Imbue Chillknife" },
        { 215257, 300, 1, "Scroll of Comprehension" },
    },
    [15] = {
        { 217495, 482, 1, "Scroll of Cryoblast" },
        { 213550, 447, 1, "Scroll of Polymorph: Odd Melon" }, -- not in the guide's list; level 16 like this tier
        { 277483, 363, 1, "Scroll of Frog Familiar" },
        { 277484, 328, 1, "Scroll of Confuse Beast" },
        { 277489, 216, 2, "Scroll of Imbue Spark" },
        { 277488, 182, 2, "Scroll of Imbue Iceknife" },
        { 277485, 179, 2, "Scroll of Imbue Frost" },
        { 277486, 176, 2, "Scroll of Imbue Striking" },
        { 277487, 175, 2, "Scroll of Imbue Baleflame" },
        { 277490, 12, 3, "Scroll of the Saber" },
    },
    [50] = {
        { 277491, 111, 1, "Scroll of Rebuke Elemental" },
        { 277493, 107, 1, "Scroll of Cat Familiar" },
        { 213548, 101, 1, "Scroll of Liminal Passage" },
        { 277498, 61, 2, "Scroll of Imbue Manablade" },
        { 277497, 56, 2, "Scroll of Imbue Flame" },
        { 277496, 55, 2, "Scroll of Imbue Balefrost" },
        { 277492, 52, 1, "Scroll of Khadgar's Unlocking" },
        { 277495, 50, 2, "Scroll of Imbue Quickening" },
        { 277494, 49, 2, "Scroll of Imbue Accuracy" },
        { 217496, 4, 3, "Scroll of the Blade" },
    },
    [175] = {
        { 277499, 100, 1, "Scroll of Greater Cryoblast" },
        { 277500, 100, 2, "Scroll of Imbue Greater Flame" },
        { 277501, 100, 2, "Scroll of Imbue Greater Frost" },
        { 277502, 100, 2, "Scroll of Imbue Precision" },
        { 277503, 100, 2, "Scroll of Imbue Spellbreak" }, -- not in the guide's list; level 46 like this tier
        { 277504, 4, 3, "Scroll of Wit" },
    },
}

-- first-pass tiers (to be reworked): 1 Common .. 5 Legendary
local TIERS = {
    [213564] = 1, [275069] = 1, [274947] = 1, [275067] = 1, [217495] = 1, [213550] = 1,
    [215257] = 2, [277483] = 2, [277484] = 2, [277489] = 2, [277488] = 2, [277485] = 2, [277486] = 2, [277487] = 2,
    [277491] = 3, [277493] = 3, [213548] = 3, [277499] = 3, [277500] = 3, [277501] = 3, [277502] = 3, [277503] = 3,
    [277498] = 4, [277497] = 4, [277496] = 4, [277492] = 4, [277495] = 4, [277494] = 4,
    [217496] = 5, [277490] = 5, [277504] = 5,
}

-- one scroll per skill tier stands in for its pool in the demo picker; the others are hidden there but
-- still work for real comprehends and "/crates updog"
local SHOWN = { [1] = 211785, [15] = 211784, [50] = 213543, [175] = 281015 }

ns.CompScrolls = {}   -- untranslated scroll -> required skill
ns.CompLevels = { 1, 15, 50, 175 }
ns.CompShown = SHOWN

for id, info in pairs(UNTRANSLATED) do
    local lvl, name = info[1], info[2]
    ns.CompScrolls[id] = lvl
    local items = {}
    for _, r in ipairs(POOLS[lvl]) do items[#items + 1] = { r[1], r[2], r[3], r[4], 1, 1 } end
    ns.Containers[id] = {
        name = SHOWN[lvl] == id and ("Comprehension (skill %d)"):format(lvl) or name,
        scrollName = name, compLevel = lvl, opened = 0, money = 0,
        estimated = true, single = true, noLoot = true, failPct = 11.5, category = "Mage scrolls",
        hidden = SHOWN[lvl] ~= id, tiers = TIERS, items = items,
    }
end
