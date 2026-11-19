-- Crate Expectations: code-drawn effects for the case-opening screen.
-- Pooled particles, a tiny tween/timer system, screen flash, screen shake offsets and rotating
-- "halos" (light rays). Everything is driven by one call to FX:Update(elapsed) from the UI's
-- OnUpdate, so nothing ticks while the screen is hidden.
-- Only WHITE8x8 and the cooldown star are used as textures, so a missing art file can't break it.

local _, ns = ...

local FX = {}
ns.FX = FX

local WHITE = "Interface\\Buttons\\WHITE8x8"
local STAR = "Interface\\Cooldown\\star4"
local MAX_PARTICLES = 900

local sin, cos, pi, random, sqrt = math.sin, math.cos, math.pi, math.random, math.sqrt

FX.active = {}
FX.free = {}
FX.tweens = {}
FX.halos = {}
FX.sx, FX.sy = 0, 0
FX.shakeAmp, FX.shakeDur, FX.shakeT = 0, 0, 0
FX.flashA, FX.flashDur, FX.flashT = 0, 0, 0

-- layer: a frame covering the screen, drawn above everything else; particles are positioned
-- relative to its centre.
function FX:Attach(layer)
    self.layer = layer
    local t = layer:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetTexture(WHITE)
    t:SetBlendMode("ADD")
    t:SetAlpha(0)
    self.flashTex = t
end

---------------------------------------------------------------------------
-- Particles
---------------------------------------------------------------------------

-- kind: "star" (soft four-point sparkle) or "chip" (hard square fleck)
-- s0 -> s1: size over the particle's life; grav: downward pull (negative rises); drag: 0..~4
function FX:Spawn(kind, x, y, vx, vy, life, s0, s1, r, g, b, a, grav, drag, spin)
    local layer = self.layer
    if not layer or #self.active >= MAX_PARTICLES then return nil end
    local p = self.free[#self.free]
    if p then
        self.free[#self.free] = nil
    else
        p = { tex = layer:CreateTexture(nil, "OVERLAY") }
        p.tex:SetBlendMode("ADD")
    end
    local tex = p.tex
    if p.kind ~= kind then
        p.kind = kind
        tex:SetTexture(kind == "chip" and WHITE or STAR)
        tex:SetBlendMode("ADD")
    end
    p.x, p.y, p.vx, p.vy = x, y, vx, vy
    p.age, p.life = 0, life
    p.s0, p.s1 = s0, s1
    p.a = a or 1
    p.grav, p.drag = grav or 0, drag or 0
    p.spin = spin or 0
    p.rot = random() * pi * 2
    p.fadeIn = nil
    tex:SetVertexColor(r, g, b)
    tex:SetRotation(p.rot)
    tex:SetSize(s0, s0)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", layer, "CENTER", x, y)
    tex:SetAlpha(0)
    tex:Show()
    self.active[#self.active + 1] = p
    return p
end

function FX:UpdateParticles(el)
    local act = self.active
    local layer = self.layer
    local free = self.free
    local i, n = 1, #act
    while i <= n do
        local p = act[i]
        p.age = p.age + el
        if p.age >= p.life then
            p.tex:Hide()
            act[i] = act[n]
            act[n] = nil
            n = n - 1
            free[#free + 1] = p
        else
            local k = p.age / p.life
            if p.drag > 0 then
                local d = 1 - p.drag * el
                if d < 0 then d = 0 end
                p.vx = p.vx * d
                p.vy = p.vy * d
            end
            p.vy = p.vy - p.grav * el
            p.x = p.x + p.vx * el
            p.y = p.y + p.vy * el
            local s = p.s0 + (p.s1 - p.s0) * k
            local tex = p.tex
            tex:SetSize(s, s)
            tex:SetPoint("CENTER", layer, "CENTER", p.x, p.y)
            local alpha
            if p.fadeIn then
                alpha = p.a * k
            else
                local fi = k * 8
                if fi > 1 then fi = 1 end
                alpha = p.a * fi * (1 - k)
            end
            tex:SetAlpha(alpha)
            if p.spin ~= 0 then
                p.rot = p.rot + p.spin * el
                tex:SetRotation(p.rot)
            end
            i = i + 1
        end
    end
end

-- radial explosion
function FX:Burst(x, y, n, r, g, b, speed)
    speed = speed or 300
    for _ = 1, n do
        local ang = random() * pi * 2
        local sp = speed * (0.3 + random() * 0.7)
        local vx, vy = cos(ang) * sp, sin(ang) * sp
        if random() < 0.65 then
            self:Spawn("star", x, y, vx, vy, 0.5 + random() * 0.7, 10 + random() * 16, 2, r, g, b, 1, 70, 2.2, (random() - 0.5) * 6)
        else
            local s = 2 + random() * 3
            self:Spawn("chip", x, y, vx * 1.2, vy * 1.2, 0.4 + random() * 0.5, s, s * 0.5, r, g, b, 1, 120, 2.6, (random() - 0.5) * 12)
        end
    end
end

-- energy gathering into a point; each mote arrives as it brightens
function FX:Converge(x, y, n, radius, r, g, b, life)
    for _ = 1, n do
        local ang = random() * pi * 2
        local sx, sy = x + cos(ang) * radius, y + sin(ang) * radius
        local p = self:Spawn("star", sx, sy, (x - sx) / life, (y - sy) / life, life, 5 + random() * 6, 12, r, g, b, 0.9, 0, 0, 3)
        if p then p.fadeIn = true end
    end
end

-- slow rising sparkles
function FX:Fountain(x, y, n, r, g, b)
    for _ = 1, n do
        self:Spawn("star", x + (random() - 0.5) * 30, y, (random() - 0.5) * 70, 60 + random() * 120,
            1.0 + random() * 0.9, 6 + random() * 10, 2, r, g, b, 0.9, -20, 0.4, (random() - 0.5) * 3)
    end
end

-- grey flecks that fall (empty cards)
function FX:Dust(x, y, n)
    for _ = 1, n do
        local s = 2 + random() * 3
        local c = 0.35 + random() * 0.25
        self:Spawn("chip", x + (random() - 0.5) * 50, y + (random() - 0.5) * 40, (random() - 0.5) * 60, 10 + random() * 40,
            0.8 + random() * 0.6, s, s, c, c, c * 0.95, 0.7, 160, 0.8, (random() - 0.5) * 4)
    end
end

-- little stars that blink on and off around a point (an aura around an Epic / Legendary)
function FX:Twinkle(x, y, n, rx, ry, r, g, b)
    for _ = 1, n do
        local p = self:Spawn("star", x + (random() * 2 - 1) * rx, y + (random() * 2 - 1) * ry, 0, 8 + random() * 10,
            0.5 + random() * 0.5, 3 + random() * 4, 9 + random() * 7, r, g, b, 1, 0, 0, (random() - 0.5) * 5)
        if p then p.fadeIn = nil end
    end
end

-- confetti falling from the top of the screen, gold / white / tier colour
function FX:Confetti(n, r, g, b)
    local layer = self.layer
    if not layer then return end
    local w, h = layer:GetWidth() or 1200, layer:GetHeight() or 800
    for _ = 1, n do
        local pick = random()
        local cr, cg, cb = r, g, b
        if pick < 0.35 then cr, cg, cb = 1, 0.84, 0.35 elseif pick < 0.5 then cr, cg, cb = 1, 1, 1 end
        local s = 4 + random() * 5
        self:Spawn("chip", (random() - 0.5) * w, h / 2 + 10 + random() * 60, (random() - 0.5) * 80, -(40 + random() * 90),
            2.6 + random() * 1.6, s, s * 0.8, cr, cg, cb, 1, 60, 0.3, (random() - 0.5) * 10)
    end
end

-- a firework: a bright core, a ring of sparks and a few that fall
function FX:Firework(x, y, r, g, b)
    self:Ring(x, y, r, g, b, 20, 260, 0.5, 0.7)
    for i = 1, 26 do
        local ang = (i / 26) * pi * 2 + random() * 0.2
        local sp = 200 + random() * 60
        self:Spawn("star", x, y, cos(ang) * sp, sin(ang) * sp, 0.9 + random() * 0.4, 9 + random() * 6, 2, r, g, b, 1, 90, 1.6, 4)
    end
    for _ = 1, 10 do
        local s = 2 + random() * 2
        self:Spawn("chip", x, y, (random() - 0.5) * 160, random() * 120, 1 + random() * 0.6, s, s, 1, 0.95, 0.8, 1, 200, 0.8, 6)
    end
end

-- a puff of wool: big soft white blobs that bloom out and float, plus a few flecks
function FX:Wool(x, y, n)
    for _ = 1, n do
        local ang = random() * pi * 2
        local sp = 120 + random() * 260
        local c = 0.88 + random() * 0.12
        self:Spawn("star", x + (random() - 0.5) * 20, y + (random() - 0.5) * 20, cos(ang) * sp, sin(ang) * sp + 40,
            0.8 + random() * 0.7, 16 + random() * 14, 34 + random() * 18, c, c * 0.97, c * 0.95, 0.85, -30, 3.2,
            (random() - 0.5) * 2)
    end
    for _ = 1, 14 do
        local s = 3 + random() * 3
        self:Spawn("chip", x, y, (random() - 0.5) * 420, (random() - 0.3) * 360, 0.7 + random() * 0.5, s, s,
            1, 1, 1, 0.9, 260, 1.2, (random() - 0.5) * 10)
    end
end

-- an expanding soft shockwave
function FX:Ring(x, y, r, g, b, s0, s1, life, a)
    local p = self:Spawn("star", x, y, 0, 0, life or 0.5, s0, s1, r, g, b, a or 0.9, 0, 0, 1.5)
    return p
end

---------------------------------------------------------------------------
-- Flash and shake
---------------------------------------------------------------------------

function FX:Flash(r, g, b, a, dur)
    if not self.flashTex then return end
    self.flashTex:SetVertexColor(r, g, b)
    -- a stronger flash wins over a fading weaker one
    local cur = 0
    if self.flashDur > 0 then
        local k = 1 - self.flashT / self.flashDur
        if k > 0 then cur = self.flashA * k * k end
    end
    if a < cur then return end
    self.flashA, self.flashDur, self.flashT = a, dur or 0.5, 0
    self.flashTex:SetAlpha(a)
end

function FX:Shake(amp, dur)
    local cur = 0
    if self.shakeDur > 0 then
        local k = 1 - self.shakeT / self.shakeDur
        if k > 0 then cur = self.shakeAmp * k end
    end
    if amp < cur then return end
    self.shakeAmp, self.shakeDur, self.shakeT = amp, dur or 0.4, 0
end

---------------------------------------------------------------------------
-- Tweens and timers (cancelled together by FX:Clear)
---------------------------------------------------------------------------

-- fn(k) is called every frame with k going 0..1; done() once at the end
function FX:Tween(dur, fn, done)
    local tw = { t = 0, dur = (dur and dur > 0) and dur or 0.0001, fn = fn, done = done }
    self.tweens[#self.tweens + 1] = tw
    return tw
end

function FX:After(sec, fn)
    return self:Tween(sec, nil, fn)
end

function FX:Cancel(tw)
    if tw then tw.dead = true end
end

-- jump a tween to its end on the next update
function FX:Finish(tw)
    if tw and not tw.dead then tw.t = tw.dur end
end

function FX:UpdateTweens(el)
    local list = self.tweens
    local n = #list
    for i = 1, n do
        local tw = list[i]
        if not tw.dead then
            tw.t = tw.t + el
            local k = tw.t / tw.dur
            if k > 1 then k = 1 end
            if tw.fn then tw.fn(k) end
            if k >= 1 and not tw.dead then
                tw.dead = true
                if tw.done then tw.done() end
            end
        end
    end
    if self.tweens == list then
        local j = 0
        local total = #list
        for i = 1, total do
            local tw = list[i]
            if not tw.dead then
                j = j + 1
                list[j] = tw
            end
        end
        for i = total, j + 1, -1 do list[i] = nil end
    end
end

function FX:Clear()
    for _, tw in ipairs(self.tweens) do tw.dead = true end
    self.tweens = {}
    local act, free = self.active, self.free
    for i = #act, 1, -1 do
        act[i].tex:Hide()
        free[#free + 1] = act[i]
        act[i] = nil
    end
    self.shakeAmp, self.shakeDur, self.shakeT = 0, 0, 0
    self.sx, self.sy = 0, 0
    self.flashA, self.flashDur, self.flashT = 0, 0, 0
    if self.flashTex then self.flashTex:SetAlpha(0) end
end

---------------------------------------------------------------------------
-- Halo: rotating light rays (lines) over three turning stars
---------------------------------------------------------------------------

-- Returns a 2x2 frame to anchor by its CENTER. Drive it with h.size (diameter), h.spin
-- (rotation speed multiplier) and h:SetAlpha (intensity).
function FX:CreateHalo(parent, nRays)
    local h = CreateFrame("Frame", nil, parent)
    h:SetSize(2, 2)
    h.size, h.spin, h.t = 300, 1, random() * 10
    h.stars = {}
    local rel = { 1.0, 0.72, 1.4 }
    local speed = { 0.25, -0.4, 0.12 }
    local alpha = { 0.55, 0.7, 0.3 }
    for i = 1, 3 do
        local t = h:CreateTexture(nil, "BACKGROUND", nil, i)
        t:SetTexture(STAR)
        t:SetBlendMode("ADD")
        t:SetPoint("CENTER")
        t:SetAlpha(alpha[i])
        h.stars[i] = { tex = t, rel = rel[i], speed = speed[i], off = i * 0.8 }
    end
    h.core = h:CreateTexture(nil, "BACKGROUND", nil, 5)
    h.core:SetTexture(STAR)
    h.core:SetBlendMode("ADD")
    h.core:SetPoint("CENTER")
    h.core:SetAlpha(0.9)

    h.rays = {}
    nRays = nRays or 12
    if h.CreateLine then
        for i = 1, nRays do
            local ok, line = pcall(h.CreateLine, h, nil, "BACKGROUND", nil, 0)
            if ok and line then
                line:SetTexture(WHITE)
                line:SetBlendMode("ADD")
                line:SetThickness((i % 2 == 0) and 6 or 14)
                h.rays[#h.rays + 1] = {
                    line = line,
                    ang = (i - 1) * 2 * pi / nRays + (random() - 0.5) * 0.25,
                    len = 0.55 + random() * 0.45,
                    phase = random() * pi * 2,
                    wide = (i % 2 ~= 0),
                }
            end
        end
    end
    self.halos[#self.halos + 1] = h
    FX.HaloColor(h, 1, 0.8, 0.4)
    return h
end

local CA, CB
local function RayGradient(line, r, g, b, a)
    if CreateColor and line.SetGradient then
        if not CA then CA, CB = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0) end
        CA:SetRGBA(r, g, b, a)
        CB:SetRGBA(r, g, b, 0)
        if pcall(line.SetGradient, line, "HORIZONTAL", CA, CB) then return end
    end
    line:SetVertexColor(r, g, b, a * 0.5)
end

function FX.HaloColor(h, r, g, b)
    h.r, h.g, h.b = r, g, b
    for _, s in ipairs(h.stars) do s.tex:SetVertexColor(r, g, b) end
    h.core:SetVertexColor(0.6 + r * 0.4, 0.6 + g * 0.4, 0.6 + b * 0.4)
    for _, ray in ipairs(h.rays) do
        RayGradient(ray.line, r, g, b, ray.wide and 0.28 or 0.6)
    end
end

function FX.HaloStep(h, el)
    h.t = h.t + el * (h.spin or 1)
    local t = h.t
    local size = h.size or 300
    for _, s in ipairs(h.stars) do
        local z = size * s.rel
        s.tex:SetSize(z, z)
        s.tex:SetRotation(t * s.speed + s.off)
    end
    h.core:SetSize(size * 0.3, size * 0.3)
    local r0 = size * 0.05
    local rot = t * 0.18
    for i = 1, #h.rays do
        local ray = h.rays[i]
        local a = ray.ang + rot
        local L = size * 0.5 * ray.len * (0.85 + 0.15 * sin(t * 1.7 + ray.phase))
        local c, s = cos(a), sin(a)
        ray.line:SetStartPoint("CENTER", h, c * r0, s * r0)
        ray.line:SetEndPoint("CENTER", h, c * L, s * L)
    end
end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------

function FX:Update(el)
    self:UpdateTweens(el)
    self:UpdateParticles(el)

    if self.shakeDur > 0 then
        self.shakeT = self.shakeT + el
        local k = 1 - self.shakeT / self.shakeDur
        if k <= 0 then
            self.shakeDur = 0
            self.sx, self.sy = 0, 0
        else
            local amp = self.shakeAmp * k * k
            self.sx = (random() * 2 - 1) * amp
            self.sy = (random() * 2 - 1) * amp
        end
    end

    if self.flashDur > 0 then
        self.flashT = self.flashT + el
        local k = 1 - self.flashT / self.flashDur
        if k <= 0 then
            self.flashDur = 0
            self.flashTex:SetAlpha(0)
        else
            self.flashTex:SetAlpha(self.flashA * k * k)
        end
    end

    for i = 1, #self.halos do
        local h = self.halos[i]
        if h:IsVisible() and h:GetAlpha() > 0.01 then FX.HaloStep(h, el) end
    end
end
