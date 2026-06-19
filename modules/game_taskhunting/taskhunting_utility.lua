-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_utility.lua
-- Shared utility functions used across all sub-modules
-- ─────────────────────────────────────────────────────────────────────────────

-- Send a task action packet to the server.
-- forceU16: if true, all numeric args are sent as U16 (opcodes 12-16 require this).
function taskSendAction(option, ...)
    local protocol = g_game.getProtocolGame()
    if not protocol then return end
    local msg = OutputMessage.create()
    msg:addU8(0x5F)
    msg:addU8(option)
    local args = { ... }
    -- opcodes 12-16 (preferred list actions) expect U16 for all args
    local useU16 = (option >= 12 and option <= 16)
    for _, v in ipairs(args) do
        if type(v) == 'number' then
            if useU16 then msg:addU16(v) else msg:addU8(v) end
        end
    end
    protocol:send(msg)
end

function formatPrice(price)
    if not price or price == 0 or price == '0' then return '0' end
    -- Shop entries from OTCV8 arrive with string fields (see toShopItemMap in
    -- protocolgameparse.cpp); coerce so the numeric comparison below works.
    price = tonumber(price) or 0
    if price >= 1000 then return string.format('%.1fk', price / 1000) end
    return tostring(price)
end

function getCreatureNameByRaceId(raceId)
    if not raceId or raceId == 0 then return nil end
    if g_things and g_things.getRaceData then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.raceId ~= 0 and raceData.name ~= '' then
            return raceData.name
        end
    end
    return nil
end

function setCreatureByRaceId(creatureSlot, raceId)
    local c = creatureSlot:getChildById('creatureDisplay')
    if not c then
        c = g_ui.createWidget('UICreature', creatureSlot)
        c:setId('creatureDisplay')
        c:fill('parent')
        c:setCreatureSize(56)
        c:setPhantom(true)
    end
    if not raceId or raceId == 0 then return end
    if g_things and g_things.getRaceData then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.raceId ~= 0 and raceData.outfit then
            c:setOutfit(raceData.outfit)
            c:setDirection(2)
            c:getCreature():setStaticWalking(1000)
        end
    end
end

-- canBuy   = botao clicavel (status disponivel E saldo suficiente)
-- isBought = item ja comprado -> "Bought" + icon-yes + botao AFUNDADO ($on) nao clicavel
-- affordable = jogador tem saldo p/ o preco; se NAO (e ainda compravel), o preco fica VERMELHO
function applyBuyButtonState(widget, canBuy, isBought, affordable)
    if affordable == nil then affordable = true end
    local buyBtn = widget:getChildById('buyButton')
    if not buyBtn then return end

    buyBtn:setEnabled(canBuy)
    buyBtn:setText(isBought and 'Bought' or 'Buy')
    -- $on no estilo Button = clip afundado + text-offset 1 1 -> visual "comprado/pressionado"
    buyBtn:setOn(isBought)

    local existing = buyBtn:getChildById('boughtIcon')
    if isBought then
        if not existing then
            local icon = g_ui.createWidget('UIWidget', buyBtn)
            icon:setId('boughtIcon')
            icon:setImageSource('/images/store/icon-yes')
            icon:setSize({width=11, height=11})
            icon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
            icon:addAnchor(AnchorRight, 'parent', AnchorHorizontalCenter)
            icon:setMarginRight(17)
            icon:setPhantom(true)
        end
    else
        if existing then existing:destroy() end
    end

    -- preco em vermelho quando NAO ha saldo (e o item ainda nao foi comprado)
    local priceLabel = widget:recursiveGetChildById('itemPrice')
    if priceLabel then
        if (not isBought) and (not affordable) then
            priceLabel:setColor('#ff4444')
        else
            priceLabel:setColor('#dfdfdf')
        end
    end
end
