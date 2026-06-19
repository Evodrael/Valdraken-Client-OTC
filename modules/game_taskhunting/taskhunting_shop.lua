-- ─────────────────────────────────────────────────────────────────────────────
-- game_taskhunting / taskhunting_shop.lua
-- Shop tab UI (buy trophies, mounts, outfits, bonus promotion)
-- ─────────────────────────────────────────────────────────────────────────────

local OPT_BUY_SHOP_OFFER = 11

function populateShop()
    if not taskBoardWindow or not cachedShopData then return end

    local shopItemsPanel = taskBoardWindow:recursiveGetChildById('shopItemsPanel')
    if not shopItemsPanel then return end
    shopItemsPanel:destroyChildren()

    -- saldo de Hunting Task Points (HTP) do jogador, p/ gatear o botao Buy por saldo
    local player = g_game.getLocalPlayer()
    local balance = (player and player.getResourceBalance) and (player:getResourceBalance(ResourceHuntingTask) or 0) or 0

    for _, offer in ipairs(cachedShopData) do
        local serverIdx = offer.serverIndex

        if offer.offerType == 4 then
            local widget = g_ui.createWidget('BonusPromotionItem', shopItemsPanel)
            if widget then
                local priceLabel = widget:recursiveGetChildById('itemPrice')
                if priceLabel then
                    priceLabel:setText(offer.nextPrice == 0 and 'MAXED' or formatPrice(offer.nextPrice))
                end

                local price = tonumber(offer.nextPrice) or 0
                local isBought = (offer.nextPrice == 0) -- MAXED
                local affordable = balance >= price
                local canBuy = (offer.promoStatus == 0) and (offer.nextPrice > 0) and affordable
                applyBuyButtonState(widget, canBuy, isBought, affordable)
                local buyBtn = widget:getChildById('buyButton')
                if buyBtn then
                    buyBtn.onClick = function()
                        taskSendAction(OPT_BUY_SHOP_OFFER, serverIdx, 0)
                    end
                end
            end
        else
            local widget = g_ui.createWidget('ShopItem', shopItemsPanel)
            if not widget then goto continue end

            widget:setText(offer.name or '')

            local priceLabel = widget:recursiveGetChildById('itemPrice')
            if priceLabel then priceLabel:setText(formatPrice(offer.price)) end

            local descLabel = widget:getChildById('itemDesc')
            if descLabel then descLabel:setText(offer.description or '') end

            local addonIcon  = widget:getChildById('addonIcon')
            local trophyIcon = widget:getChildById('trophyIcon')
            local mountIcon  = widget:getChildById('mountIcon')
            if addonIcon  then addonIcon:setVisible(offer.offerType == 2) end
            if trophyIcon then trophyIcon:setVisible(offer.offerType == 0 or offer.offerType == 3) end
            if mountIcon  then mountIcon:setVisible(offer.offerType == 1) end

            local itemReal     = widget:getChildById('itemReal')
            local itemCreature = widget:getChildById('itemCreature')

            if offer.offerType == 0 or offer.offerType == 3 then
                if itemReal then
                    itemReal:setVisible(true)
                    itemReal:setItemId(offer.looktypeOrItemId)
                end
                if itemCreature then itemCreature:setVisible(false) end

            elseif offer.offerType == 1 then
                if itemCreature then
                    itemCreature:setVisible(true)
                    itemCreature:setOutfit({ type = 128, mount = offer.looktypeOrItemId })
                end
                if itemReal then itemReal:setVisible(false) end

            elseif offer.offerType == 2 then
                if itemCreature then
                    itemCreature:setVisible(true)
                    itemCreature:setOutfit({
                        type   = offer.looktypeOrItemId,
                        head   = 0, body = 0, legs = 0, feet = 0,
                        addons = offer.addon or 0,
                    })
                end
                if itemReal then itemReal:setVisible(false) end
            end

            local price = tonumber(offer.price) or 0
            local isBought = (offer.status == 4)
            local affordable = balance >= price
            local canBuy = (offer.status == 0) and affordable
            applyBuyButtonState(widget, canBuy, isBought, affordable)
            local buyBtn = widget:getChildById('buyButton')
            if buyBtn then
                buyBtn.onClick = function()
                    purchaseShopOffer(offer, serverIdx)
                end
            end

            widget:setTooltip((offer.name or '') .. '\nPrice: ' .. formatPrice(offer.price) .. ' HTP')

            ::continue::
        end
    end
end

function purchaseShopOffer(offer, offerIndex)
    taskSendAction(OPT_BUY_SHOP_OFFER, offerIndex, 0)
end
