--[[
    register(id, name, thingId, thingType, config)
    config = {
        speed, disableWalkAnimation, shader,
        offset{x, y, onTop}, dirOffset[dir]{x, y, onTop},
        onAttach, onDetach
    }
]] --
AttachedEffectManager.register(1, 'Spoke Lighting', 12, ThingCategoryEffect, {
    speed = 0.5,
    onAttach = function(effect, owner)
        print('onAttach: ', effect:getId(), owner:getName())
    end,
    onDetach = function(effect, oldOwner)
        print('onDetach: ', effect:getId(), oldOwner:getName())
    end
})

AttachedEffectManager.register(2, 'Bat Wings', 307, ThingCategoryCreature, {
    speed = 5,
    disableWalkAnimation = true,
    shader = 'Outfit - Ghost',
    dirOffset = {
        [North] = {0, -10, true},
        [East] = {5, -5},
        [South] = {-5, 0},
        [West] = {-10, -5, true}
    }
})

AttachedEffectManager.register(3, 'Angel Light', 50, ThingCategoryEffect, {
    shader = 'Map - Party'
})

AttachedEffectManager.register(4, 'Brino - Effect', 2558, ThingCategoryCreature, {
    dirOffset = {
        [North] = {0, 0, true},
        [East] = {0, 0, true},
        [South] = {0, 0, true},
        [West] = {0, 0, true}
    }
})

AttachedEffectManager.register(5, 'Brino - Effect', 2559, ThingCategoryCreature, {
    dirOffset = {
        [North] = {0, 0, false},
        [East] = {0, 0, false},
        [South] = {0, 0, false},
        [West] = {0, 0, false}
    }
})

-- =========================
-- Elite System (game_elite) — AURAS por tier (so aplicam o shader de chama)
-- =========================
-- IMPORTANTE: `permanent = true` impede que clearTemporaryAttachedEffects (e qualquer
-- limpeza temporaria do C++) remova a aura. Sem isso, a aura sumia "depois de alguns
-- segundos" (detach -> onDetach -> setShader('Default')). A remocao agora so acontece
-- de forma explicita (EliteClient.removeVisual / morte).
AttachedEffectManager.register(101, 'Elite Aura Green', 0, 0, {
    permanent = true,
    onAttach = function(effect, owner)
        if owner then owner:setShader('Outfit - Flame Green') end
    end,
    onDetach = function(effect, oldOwner)
        if oldOwner then oldOwner:setShader('Default') end
    end
})

AttachedEffectManager.register(102, 'Elite Aura Wine', 0, 0, {
    permanent = true,
    onAttach = function(effect, owner)
        if owner then owner:setShader('Outfit - Flame Wine') end
    end,
    onDetach = function(effect, oldOwner)
        if oldOwner then oldOwner:setShader('Default') end
    end
})

AttachedEffectManager.register(103, 'Elite Aura BlackRed', 0, 0, {
    permanent = true,
    onAttach = function(effect, owner)
        if owner then owner:setShader('Outfit - Flame BlackRed') end
    end,
    onDetach = function(effect, oldOwner)
        if oldOwner then oldOwner:setShader('Default') end
    end
})

-- WARNING no tile (antes do spawn do elite): EFEITO MAGICO do TELEPORTE (CONST_ME_TELEPORT = 11,
-- ThingCategoryEffect) TINGIDO pela cor do tier. Usa EFEITO (nao item) porque:
--   * efeitos SEMPRE existem nas appearances e sao animados -> passam no guard de
--     AttachedEffect::draw (`thingType->isNull() || getAnimationPhases()==0`).
--   * o item 1949/1387 NAO e client-id valido nestas appearances -> getThingType null ->
--     guard mata o draw -> o teleporte NUNCA aparecia (a aura por shader funcionava, o item nao).
-- m_loop default = -1 (infinito), entao o efeito FICA animando (loopando) ate ser removido.
-- showWarning faz DEDUPE (1 efeito por posicao, renova nos pulsos do servidor, remove no fim).
AttachedEffectManager.register(201, 'Elite Warning Green', 11, ThingCategoryEffect, {
    color = '#33ff33', drawOrder = 1, drawOnUI = false
})
AttachedEffectManager.register(202, 'Elite Warning Red', 11, ThingCategoryEffect, {
    color = '#ff3333', drawOrder = 1, drawOnUI = false
})
AttachedEffectManager.register(203, 'Elite Warning BlackRed', 11, ThingCategoryEffect, {
    color = '#555555', drawOrder = 1, drawOnUI = false
})
