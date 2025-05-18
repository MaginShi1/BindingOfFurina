local mod = RegisterMod("FurinaMod", 1)
local itemConfig = Isaac.GetItemConfig()

-- Familiar and RNG setup
local ITEM_NAME = "Usher"
local ITEM_ID = Isaac.GetItemIdByName(ITEM_NAME)
local CONFIG_USHER = itemConfig:GetCollectible(ITEM_ID)
local FAMILIAR_VARIANT = Isaac.GetEntityVariantByName(ITEM_NAME)
local RNG_SHIFT_INDEX = 35

-- Animation delay constants (frames at 30 FPS)
local IDLE_DELAY_FRAMES = 15        -- Delay before switching to IdleDown
local MOVE_DELAY_FRAMES = 7         -- Delay before starting movement float

-- Tear behavior constants for familiar
local BASE_TEAR_SPEED_MULTIPLIER = 10 -- Scale player.ShotSpeed to game velocity

-- Fixed familiar stat modifiers
local DAMAGE_MULTIPLIER = 3    -- Multiply base damage
local DAMAGE_FLAT = 1          -- Add flat damage
local FIREDELAY_REDUCTION = 0.4 -- Subtract from base tear delay
local SHOTSPEED_REDUCTION = 0.25 -- Subtract from base shot speed
local TEAR_DELAY_ADDED = 2.5 -- Add to base tear delay
local TEAR_SCALE = 2 -- Scale for tear size

-- Ensure integer cooldown ticks
local function ToCooldownTicks(delay)
    return math.max(math.floor(delay), 1)
end

-- Grant familiars based on cache
function mod:EvaluateCache(player)
    local count = player:GetCollectibleNum(ITEM_ID)
    local rng = RNG()
    rng:SetSeed(player:GetCollectibleRNG(ITEM_ID):GetSeed(), RNG_SHIFT_INDEX)
    player:CheckFamiliar(FAMILIAR_VARIANT, count, rng, CONFIG_USHER)
end
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.EvaluateCache, CacheFlag.CACHE_FAMILIARS)

-- Initialize familiar to follow player
function mod:HandleInit(familiar)
    familiar:AddToFollowers()
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, mod.HandleInit, FAMILIAR_VARIANT)

-- Main update per frame
function mod:HandleUpdate(familiar)
    local sprite = familiar:GetSprite()
    local player = familiar.Player

    -- Base stats from player
    local baseDamage    = player.Damage
    local baseFireDelay = player.MaxFireDelay * TEAR_DELAY_ADDED
    local baseShotSpeed = player.ShotSpeed

    -- Compute effective tear stats for familiar
    local tearDamage    = baseDamage * DAMAGE_MULTIPLIER + DAMAGE_FLAT
    local fireDelay     = baseFireDelay - FIREDELAY_REDUCTION
    local shotSpeed     = baseShotSpeed - SHOTSPEED_REDUCTION

    -- Clamp values
    tearDamage = math.max(tearDamage, 0)
    fireDelay  = math.max(fireDelay, 1)
    shotSpeed  = math.max(shotSpeed, 0.1)

    -- Convert to integer ticks for cooldown
    local cooldownTicks = ToCooldownTicks(fireDelay)

    -- Per-familiar animation counters
    local data = familiar:GetData()
    data.idleCounter = data.idleCounter or 0
    data.moveCounter = data.moveCounter or 0

    -- Handle shooting input
    local shootInput = player:GetShootingInput():Normalized()
    local sx, sy = shootInput.X, shootInput.Y
    local shooting = (math.abs(sx) + math.abs(sy)) > 0

    if shooting then
        data.moveCounter = 0 -- Freeze movement anim
        if familiar.FireCooldown <= 0 then
            local direction, anim, flip = nil, nil, false
            if sx < 0 then direction = Vector(-1,0); anim = "FloatShootSide"; flip = true
            elseif sx > 0 then direction = Vector(1,0); anim = "FloatShootSide"
            elseif sy < 0 then direction = Vector(0,-1); anim = "FloatShootUp"
            elseif sy > 0 then direction = Vector(0,1); anim = "FloatShootDown" end

            if direction then
                data.idleCounter = 0
                -- Calculate velocity using multiplier
                local velocity = direction * (shotSpeed * BASE_TEAR_SPEED_MULTIPLIER) + player:GetTearMovementInheritance(direction)
                local tear = Isaac.Spawn(EntityType.ENTITY_TEAR, TearVariant.BLUE, 0, familiar.Position, velocity, familiar):ToTear()
                tear.Scale = familiar.TearScale or TEAR_SCALE
                tear.CollisionDamage = tearDamage
                -- Add homing flag
                tear:AddTearFlags(TearFlags.TEAR_HOMING)

                familiar.FireCooldown = cooldownTicks

                sprite.FlipX = flip
                sprite:Play(anim, true)
            end
        end
    else
        -- Movement & Idle logic with delay
        local moveInput = player:GetMovementInput():Normalized()
        local ix, iy = moveInput.X, moveInput.Y
        local absX, absY = math.abs(ix), math.abs(iy)

        if absX > absY and absX > 0 then
            data.moveCounter = data.moveCounter + 1
            data.idleCounter = 0
            if data.moveCounter >= MOVE_DELAY_FRAMES then
                sprite.FlipX = ix < 0
                sprite:Play("FloatSide", true)
            end

        elseif absY > absX and absY > 0 then
            data.moveCounter = data.moveCounter + 1
            data.idleCounter = 0
            if data.moveCounter >= MOVE_DELAY_FRAMES then
                sprite.FlipX = false
                if iy < 0 then sprite:Play("FloatUp", true) else sprite:Play("FloatDown", true) end
            end

        else
            data.moveCounter = 0
            data.idleCounter = data.idleCounter + 1
            if data.idleCounter >= IDLE_DELAY_FRAMES then
                sprite.FlipX = false
                sprite:Play("IdleDown", true)
            end
        end
    end

    familiar:FollowParent()
    familiar.FireCooldown = math.max(familiar.FireCooldown - 1, 0)
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.HandleUpdate, FAMILIAR_VARIANT)