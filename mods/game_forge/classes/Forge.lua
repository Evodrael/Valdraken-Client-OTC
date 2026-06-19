ForgeSystem = {}
ForgeSystem.__index = ForgeSystem


ForgeSystem.classPrice = {}
ForgeSystem.transferMap = {}
ForgeSystem.fusionPrices = {}
ForgeSystem.transferPrices = {}
ForgeSystem.baseMultipier = 0
ForgeSystem.slivers = 0
ForgeSystem.totalSlivers = 0
ForgeSystem.dustCost = 0
ForgeSystem.dustPrice = 0
ForgeSystem.maxDust = 0
ForgeSystem.dustFusion = 0
ForgeSystem.convergenceDustFusion = 0
ForgeSystem.dustTransfer = 0
ForgeSystem.convergenceDustTransfer = 0
ForgeSystem.success = 0
ForgeSystem.improveRateSuccess = 0
ForgeSystem.tierLoss = 0
ForgeSystem.inForgeFusion = false
ForgeSystem.fusionPrice = 0
ForgeSystem.exaltedCoreCount = 0
ForgeSystem.fusionTier = 0

ForgeSystem.fusionData = {}
ForgeSystem.fusionConvergenceData = {}
ForgeSystem.transferData = {}
ForgeSystem.transferConvergenceData = {}
ForgeSystem.maxPlayerDust = 100

ForgeSystem.fallbackClassPrices = {
	[1] = { [1] = 25000 },
	[2] = { [1] = 750000, [2] = 5000000 },
	[3] = { [1] = 4000000, [2] = 10000000, [3] = 20000000 },
	[4] = {
		[1] = 8000000,
		[2] = 20000000,
		[3] = 40000000,
		[4] = 65000000,
		[5] = 100000000,
		[6] = 250000000,
		[7] = 750000000,
		[8] = 2500000000,
		[9] = 8000000000,
		[10] = 15000000000,
	},
}

ForgeSystem.fallbackConvergenceFusionPrices = {
	[1] = 55000000,
	[2] = 110000000,
	[3] = 170000000,
	[4] = 300000000,
	[5] = 875000000,
	[6] = 2350000000,
	[7] = 6950000000,
	[8] = 21250000000,
	[9] = 50000000000,
	[10] = 125000000000,
}

ForgeSystem.fallbackConvergenceTransferPrices = {
	[1] = 65000000,
	[2] = 165000000,
	[3] = 375000000,
	[4] = 800000000,
	[5] = 2000000000,
	[6] = 5250000000,
	[7] = 14500000000,
	[8] = 42500000000,
	[9] = 100000000000,
	[10] = 300000000000,
}

local function asNumber(value, default)
	local number = tonumber(value)
	if number == nil then
		return default or 0
	end
	return number
end

local function reconstructForgeTimestamp(truncated)
	truncated = tonumber(truncated)
	if not truncated or truncated <= 0 then
		return 0
	end

	local twoPow32 = 4294967296
	local nowSec = os.time()
	local nowMs = nowSec * 1000
	local nowLow = nowMs % twoPow32
	local nowHigh = nowMs - nowLow
	local candidateMs = nowHigh + truncated
	if candidateMs > nowMs then
		candidateMs = candidateMs - twoPow32
	end

	if candidateMs >= 1000 then
		return math.floor(candidateMs / 1000)
	end

	if truncated > 100000000000 then
		return math.floor(truncated / 1000)
	end
	return truncated
end

local function formatForgeHistoryDate(timestamp)
	timestamp = tonumber(timestamp)
	if not timestamp or timestamp <= 0 then
		return ""
	end

	local seconds = reconstructForgeTimestamp(timestamp)
	if seconds <= 0 then
		return ""
	end

	local ok, formatted = pcall(os.date, "%Y-%m-%d, %H:%M:%S", seconds)
	if ok and type(formatted) == "string" then
		return formatted
	end
	return ""
end

local function stripForgeHistoryHtml(text)
	if type(text) ~= "string" or #text == 0 then
		return ""
	end

	local cleaned = text
	cleaned = cleaned:gsub("<br%s*/?>", "\n")
	cleaned = cleaned:gsub("</li>", "\n")
	cleaned = cleaned:gsub("<li>", " - ")
	cleaned = cleaned:gsub("<ul[^>]*>", "")
	cleaned = cleaned:gsub("</ul>", "")
	cleaned = cleaned:gsub("<[^>]+>", "")
	cleaned = cleaned:gsub("&nbsp;", " ")
	cleaned = cleaned:gsub("&amp;", "&")
	cleaned = cleaned:gsub("[ \t]+\n", "\n")
	cleaned = cleaned:gsub("\n\n+", "\n")
	cleaned = cleaned:gsub("^%s+", "")
	cleaned = cleaned:gsub("%s+$", "")
	return cleaned
end

local function summarizeForgeHistoryDescription(actionType, rawDescription)
	if type(rawDescription) ~= "string" or #rawDescription == 0 then
		return ""
	end

	local lower = rawDescription:lower()
	local result
	if lower:find("^successful") then
		result = "Successful"
	elseif lower:find("^unsuccessful") or lower:find("^failed") then
		result = "Failed"
	end

	if actionType == 2 or actionType == 3 or actionType == 4 then
		return stripForgeHistoryHtml(rawDescription)
	end

	local firstName, firstTier = rawDescription:match("First item:%s*([^,<]-),%s*tier%s*(%d+)")
	local secondName, secondTier = rawDescription:match("Second item:%s*([^,<]-),%s*tier%s*(%d+)")

	if not firstName then
		return stripForgeHistoryHtml(rawDescription)
	end

	firstName = firstName:gsub("^%s+", ""):gsub("%s+$", "")
	if secondName then
		secondName = secondName:gsub("^%s+", ""):gsub("%s+$", "")
	end

	local resultTier = secondTier
	if actionType == 0 then
		local resultBlock = rawDescription:match("Result:.*")
		if resultBlock then
			if resultBlock:find("First item:%s*tier%s*%+%s*1") then
				resultTier = tostring(tonumber(firstTier) + 1)
			elseif resultBlock:find("First item:%s*unchanged") then
				resultTier = firstTier
			elseif resultBlock:find("First item:%s*consumed") then
				resultTier = "consumed"
			end
		end
		secondName = firstName
	end

	local target
	if secondName and resultTier then
		target = string.format("%s, Tier %s", secondName, resultTier)
	elseif resultTier then
		target = string.format("Tier %s", resultTier)
	else
		target = "?"
	end

	local source = string.format("%s, Tier %s", firstName, firstTier)
	if result then
		return string.format("%s -> %s - %s", source, target, result)
	end
	return string.format("%s -> %s", source, target)
end

local function normalizeTierPrices(entries)
	local prices = {}
	if type(entries) ~= "table" then
		return prices
	end

	for _, entry in ipairs(entries) do
		if type(entry) == "table" then
			local tier = tonumber(entry.tier)
			local price = tonumber(entry.price)
			if tier then
				prices[tier + 1] = price or 0
			end
		end
	end
	return prices
end

local function resolveTierValue(values, candidates, default)
	if type(values) ~= "table" then
		return default or 0
	end

	for _, candidate in ipairs(candidates) do
		if candidate ~= nil then
			local value = tonumber(values[candidate])
			if value ~= nil then
				return value
			end
		end
	end

	for _, value in pairs(values) do
		value = tonumber(value)
		if value ~= nil then
			return value
		end
	end

	return default or 0
end

local function resolveAnyClassTierValue(prices, candidates, default)
	if type(prices) ~= "table" then
		return default or 0
	end

	for _, classPrices in pairs(prices) do
		if type(classPrices) == "table" then
			local value = resolveTierValue(classPrices, candidates, nil)
			if value ~= nil and value > 0 then
				return value
			end
		end
	end

	return default or 0
end

local function getForgeClassification(itemId)
	local itemPtr = Item.create(itemId, 1)
	if itemPtr and itemPtr.getClassification then
		local classification = itemPtr:getClassification()
		if classification and classification > 0 then
			return classification
		end
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType and thingType.getClassification then
		return thingType:getClassification()
	end
	return 0
end

local function resolveFallbackForgePrice(itemId, currentTier, isConvergence, isTransfer)
	local tierValue = tonumber(currentTier) or 0
	local tierIndex = tierValue + 1

	if isTransfer and isConvergence then
		return resolveTierValue(ForgeSystem.fallbackConvergenceTransferPrices, { tierIndex, tierValue + 1, tierValue }, 0)
	end

	if isConvergence then
		return resolveTierValue(ForgeSystem.fallbackConvergenceFusionPrices, { tierIndex, tierValue + 1, tierValue }, 0)
	end

	local classification = getForgeClassification(itemId)
	if classification <= 0 then
		classification = 4
	end

	local fallbackClass = ForgeSystem.fallbackClassPrices[classification] or ForgeSystem.fallbackClassPrices[4] or ForgeSystem.fallbackClassPrices[1]
	local candidates = isTransfer and { tierValue, tierIndex, tierValue + 1 } or { tierIndex, tierValue + 1, tierValue }
	return resolveTierValue(fallbackClass, candidates, 0)
end

local function normalizeClassPrices(entries)
	local prices = {}
	if type(entries) ~= "table" then
		return prices
	end

	for _, classEntry in ipairs(entries) do
		if type(classEntry) == "table" then
			local classId = tonumber(classEntry.classId)
			if classId then
				prices[classId] = normalizeTierPrices(classEntry.tiers)
			end
		end
	end
	return prices
end

local function isEmptyTable(t)
	if type(t) ~= "table" then
		return true
	end
	for _ in pairs(t) do
		return false
	end
	return true
end

local function resolveForgePrice(prices, itemId, currentTier, isConvergence, isTransfer)
	local price = 0
	local tierValue = tonumber(currentTier) or 0
	local tierIndex = tierValue + 1

	if isTransfer and isConvergence then
		local source = (not isEmptyTable(prices)) and prices or ForgeSystem.fallbackConvergenceTransferPrices
		for tier, rawPrice in pairs(source) do
			local normalizedTier = tonumber(tier) or 0
			if normalizedTier > 1 then
				normalizedTier = normalizedTier - 1
			end
			if tierValue == normalizedTier then
				price = tonumber(rawPrice) or 0
				break
			end
		end
		if price <= 0 then
			price = tonumber(ForgeSystem.fallbackConvergenceTransferPrices[tierIndex]) or 0
		end
	elseif isConvergence then
		local source = (not isEmptyTable(prices)) and prices or ForgeSystem.fallbackConvergenceFusionPrices
		price = resolveTierValue(source, { tierIndex, tierValue + 1, tierValue }, 0)
		if price <= 0 then
			price = tonumber(ForgeSystem.fallbackConvergenceFusionPrices[tierIndex]) or 0
		end
	else
		local activePrices = (not isEmptyTable(prices)) and prices or ForgeSystem.fallbackClassPrices
		local classification = getForgeClassification(itemId)
		if classification <= 0 then
			classification = 4
		end
		local classPrices = activePrices[classification] or activePrices[4] or activePrices[1]
		local candidates = isTransfer and { tierValue, tierIndex, tierValue + 1 } or { tierIndex, tierValue + 1, tierValue }
		if type(classPrices) == "table" then
			price = resolveTierValue(classPrices, candidates, 0)
		end
		if price <= 0 then
			price = resolveAnyClassTierValue(activePrices, candidates, 0)
		end
		if price <= 0 then
			local fallbackClass = ForgeSystem.fallbackClassPrices[classification] or ForgeSystem.fallbackClassPrices[4]
			price = resolveTierValue(fallbackClass, candidates, 0)
		end
	end

	if price < 0 then
		price = 0
	end

	if price <= 0 then
		price = resolveFallbackForgePrice(itemId, currentTier, isConvergence, isTransfer)
	end

	return price
end

local function findForgeChildById(widget, id)
	if not widget or not id then
		return nil
	end

	if widget.getChildById then
		local child = widget:getChildById(id)
		if child then
			return child
		end
	end

	if widget.recursiveGetChildById then
		local child = widget:recursiveGetChildById(id)
		if child then
			return child
		end
	end

	return nil
end

local function resolveForgePriceWidgets(widget)
	if not widget then
		return nil, nil, nil
	end

	local amountLabel = nil
	local goldLabel = nil
	local goldIcon = nil

	local priceGroup = findForgeChildById(widget, "priceGroup")
	if priceGroup then
		amountLabel = findForgeChildById(priceGroup, "amount")
		goldLabel = findForgeChildById(priceGroup, "gold")
		goldIcon = findForgeChildById(priceGroup, "goldIcon")
	end

	amountLabel = amountLabel or findForgeChildById(widget, "amount")
	goldLabel = goldLabel or findForgeChildById(widget, "gold")
	goldIcon = goldIcon or findForgeChildById(widget, "goldIcon")

	if not goldLabel and widget.getId and widget:getId() == "gold" then
		goldLabel = widget
		local parent = widget.getParent and widget:getParent() or nil
		amountLabel = amountLabel or findForgeChildById(parent, "amount")
		goldIcon = goldIcon or findForgeChildById(parent, "goldIcon")
	end

	if not goldIcon and widget.getId and widget:getId() == "goldIcon" then
		goldIcon = widget
		local parent = widget.getParent and widget:getParent() or nil
		amountLabel = amountLabel or findForgeChildById(parent, "amount")
		goldLabel = goldLabel or findForgeChildById(parent, "gold")
	end

	if not goldLabel and not goldIcon then
		-- Fallback legacy case where caller passes the gold label directly.
		goldLabel = widget
		local parent = widget.getParent and widget:getParent() or nil
		amountLabel = amountLabel or findForgeChildById(parent, "amount")
		goldIcon = goldIcon or findForgeChildById(parent, "goldIcon")
	end

	return amountLabel, goldLabel, goldIcon
end

local function setForgePriceLabel(targetWidget, price, canAfford)
	if not targetWidget then
		return
	end

	local amountLabel, goldLabel, goldIcon = resolveForgePriceWidgets(targetWidget)
	if not amountLabel and not goldLabel then
		return
	end

	price = tonumber(price) or 0
	local valueText = price > 0 and formatMoney(price, ",") or "???"
	local color = price > 0 and (canAfford and "$var-text-cip-color" or "#d33c3c") or "#d33c3c"
	local tooltipText = valueText .. " gold"

	if amountLabel then
		amountLabel:setText(valueText)
		amountLabel:setColor(color)
		amountLabel:setTooltip(tooltipText)
	end

	if goldLabel then
		if amountLabel then
			goldLabel:setText("")
			goldLabel:setColor("#c0c0c0")
		else
			goldLabel:setText(valueText)
			goldLabel:setColor(color)
		end
		goldLabel:setTooltip(tooltipText)
	end

	if goldIcon and goldIcon.setTooltip then
		goldIcon:setTooltip(tooltipText)
	end
end

local function setForgeButtonPressed(widget, active)
	if not widget then
		return
	end

	if widget.setChecked then
		widget:setChecked(active, true)
	end
	if widget.setOn then
		widget:setOn(active)
	end
	if widget.setOpacity then
		widget:setOpacity(active and 1.0 or 0.7)
	end
end

local function setForgeWidgetItem(widget, itemId, tier)
	if not widget then
		return
	end

	itemId = asNumber(itemId)
	tier = asNumber(tier)
	if itemId > 0 then
		local item = Item.create(itemId, 1)
		if item and item.setTier then
			item:setTier(tier)
		end
		if widget.setItem then
			widget:setItem(item)
		else
			widget:setItemId(itemId)
		end
	else
		widget:setItemId(0)
	end

	if widget.tierflags then
		if tier > 0 then
			widget.tierflags:setImageClip((tier - 1) * 18 .. " 0 18 16")
			widget.tierflags:setVisible(true)
		else
			widget.tierflags:setVisible(false)
		end
	end
end

local function updateFusionOptionButtons()
	setForgeButtonPressed(fusionMenu.itemsFusion.improveRateSuccessButton, ForgeSystem.rateSuccessActive)
	setForgeButtonPressed(fusionMenu.itemsFusion.tierLossButton, ForgeSystem.tierLossActive)
end

local function normalizeTransferMap(grades)
	local transferMap = {}
	if type(grades) ~= "table" then
		return transferMap
	end

	for _, grade in ipairs(grades) do
		if type(grade) == "table" then
			local tier = tonumber(grade.tier)
			local cores = tonumber(grade.exaltedCores)
			if tier then
				transferMap[tier] = cores or 0
				if tier > 0 and transferMap[tier - 1] == nil then
					transferMap[tier - 1] = cores or 0
				end
			end
		end
	end
	return transferMap
end

local function normalizeForgeItem(item)
	if type(item) ~= "table" then
		return { 0, 0, 0 }
	end
	return { asNumber(item.id or item[1]), asNumber(item.tier or item[2]), asNumber(item.count or item[3]) }
end

local function normalizeForgeItems(items)
	local result = {}
	if type(items) ~= "table" then
		return result
	end

	for _, item in ipairs(items) do
		if type(item) == "table" then
			table.insert(result, normalizeForgeItem(item))
		end
	end
	return result
end

local function normalizeConvergenceFusion(groups)
	local result = {}
	if type(groups) ~= "table" then
		return result
	end

	for _, group in ipairs(groups) do
		if type(group) == "table" then
			if group.id or group[1] then
				table.insert(result, normalizeForgeItem(group))
			else
				for _, item in ipairs(group) do
					table.insert(result, normalizeForgeItem(item))
				end
			end
		end
	end
	return result
end

local function normalizeTransferData(transfers)
	local result = {}
	if type(transfers) ~= "table" then
		return result
	end

	for _, transfer in ipairs(transfers) do
		if type(transfer) == "table" then
			if transfer[1] and transfer[4] then
				table.insert(result, transfer)
			else
				local receivers = {}
				for _, receiver in ipairs(transfer.receivers or {}) do
					local id = asNumber(receiver.id or receiver[1])
					if id > 0 then
						receivers[id] = (receivers[id] or 0) + asNumber(receiver.count or receiver[3], 1)
					end
				end

				for _, donor in ipairs(transfer.donors or {}) do
					local item = normalizeForgeItem(donor)
					table.insert(result, { item[1], item[2], item[3], receivers })
				end
			end
		end
	end
	return result
end

function ForgeSystem.initFromConfig(data)
	if type(data) ~= "table" then
		return
	end

	return ForgeSystem.init(
		normalizeClassPrices(data.classPrices),
		normalizeTransferMap(data.fusionGrades),
		normalizeTierPrices(data.convergenceFusionPrices),
		normalizeTierPrices(data.convergenceTransferPrices),
		asNumber(data.dustPercent),
		asNumber(data.dustToSliver),
		asNumber(data.sliverToCore),
		asNumber(data.dustPercentUpgrade),
		asNumber(data.maxDustLevel, ForgeSystem.maxPlayerDust),
		asNumber(data.maxDustCap, ForgeSystem.maxDust),
		asNumber(data.normalDustFusion),
		asNumber(data.convergenceDustFusion),
		asNumber(data.normalDustTransfer),
		asNumber(data.convergenceDustTransfer),
		asNumber(data.fusionChanceBase),
		asNumber(data.fusionChanceImproved),
		asNumber(data.fusionReduceTierLoss)
	)
end

function ForgeSystem.init(classPrice, transferMap, fusionPrices, transferPrices, baseMultipier, slivers, totalSlivers, dustCost, dustPrice, maxDust, dustFusion, convergenceDustFusion, dustTransfer, convergenceDustTransfer, success, improveRateSuccess, tierLoss)
	if type(classPrice) == "table" and classPrice.classPrices then
		return ForgeSystem.initFromConfig(classPrice)
	end

	ForgeSystem.classPrice = classPrice or {}
	ForgeSystem.transferMap = transferMap or {}
	ForgeSystem.fusionPrices = fusionPrices or {}
	ForgeSystem.transferPrices = transferPrices or {}
	ForgeSystem.baseMultipier = asNumber(baseMultipier)
	ForgeSystem.slivers = asNumber(slivers)
	ForgeSystem.totalSlivers = asNumber(totalSlivers)
	ForgeSystem.dustCost = asNumber(dustCost)
	ForgeSystem.dustPrice = asNumber(dustPrice, ForgeSystem.maxPlayerDust)
	ForgeSystem.maxPlayerDust = ForgeSystem.dustPrice
	ForgeSystem.maxDust = asNumber(maxDust, ForgeSystem.maxDust)
	ForgeSystem.dustFusion = asNumber(dustFusion)
	ForgeSystem.convergenceDustFusion = asNumber(convergenceDustFusion)
	ForgeSystem.dustTransfer = asNumber(dustTransfer)
	ForgeSystem.convergenceDustTransfer = asNumber(convergenceDustTransfer)
	ForgeSystem.success = asNumber(success)
	ForgeSystem.improveRateSuccess = asNumber(improveRateSuccess)
	ForgeSystem.tierLoss = asNumber(tierLoss)

	ForgeSystem.inForgeFusion = false

	fusionMenu.itemsFusion.dustPanel.item:setItemId(37160)
	fusionMenu.converFusion.convergencePanel.dustPanel.item:setItemId(37160)
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setText(ForgeSystem.convergenceDustFusion)
	local player = g_game.getLocalPlayer()
	--forgeWindow.dustPanel.dust:setText(player:getResourceValue(ResourceForgeDust) .. '/' ..ForgeSystem.maxDust)
	fusionMenu.itemsFusion.dustCount.dustamount:setText(ForgeSystem.dustFusion)


	fusionMenu.itemsFusion.improveRateSuccessButton:setText('Improve to '.. (ForgeSystem.success + ForgeSystem.improveRateSuccess) ..'%')

	-- configure transfer
	transferMenu.itemsFusion.itemPanel.item:setItemId(0)
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.itemCount.value:setText("0 / 1")
	transferMenu.itemsFusion.dustCount.dustamount:setText("0")
	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.dustPanel.item:setItemId(37160)
	transferMenu.itemsFusion.dustCount.dustamount:setText(ForgeSystem.dustTransfer)
	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.exaltedPanel.item:setItemId(37110)
	transferMenu.itemsFusion.exaltedCount.amount:setText("???")
	transferMenu.itemsFusion.exaltedCount.amount:setColor("#d33c3c")
	-- configure transfer
	transferMenu.converFusion.itemPanel.item:setItemId(0)
	transferMenu.converFusion.itemCount.value:setText("0 / 1")
	transferMenu.converFusion.dustCount.dustamount:setText("0")
	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.dustPanel.item:setItemId(37160)
	transferMenu.converFusion.dustCount.dustamount:setText(ForgeSystem.convergenceDustTransfer)
	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.exaltedPanel.item:setItemId(37110)
	transferMenu.converFusion.exaltedCount.amount:setText("???")
	transferMenu.converFusion.exaltedCount.amount:setColor("#d33c3c")

	conversionMenu.windowConvertDust.itemPanel.item:setItemId(37160)
	conversionMenu.windowConvertDust.itemCount.amount:setText(ForgeSystem.slivers * ForgeSystem.baseMultipier)
	conversionMenu.windowConvertDust.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowConvertDust.dustButton.item:setItemId(37109)
	conversionMenu.windowConvertDust.generateSlivers:setText("Generate ".. ForgeSystem.slivers)

	conversionMenu.windowConvertSlivers.itemPanel.item:setItemId(37109)
	conversionMenu.windowConvertSlivers.itemCount.amount:setText(ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowConvertSlivers.sliverButton.item:setItemId(37110)

	local totalDustRequired = (100 - ForgeSystem.dustCost) + (ForgeSystem.maxPlayerDust - 100)
	conversionMenu.windowIncreaseDustLimit.itemPanel.item:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setText(totalDustRequired)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowIncreaseDustLimit.increaseButton.item:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.increaseButton.itemRight:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.baseText:setText('Raise limit from')
	conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.img1:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.img2:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.currentDust:setText('100')
	conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.nextDust:setText('to 101')

	ForgeSystem.refreshSelectedFusionPrice()
end

function ForgeSystem.refreshSelectedFusionPrice()
	local player = g_game.getLocalPlayer()
	if not player or not ForgeSystem.fusionItem then
		return
	end

	local itemTier = ForgeSystem.fusionItem:getTier()
	local balance = player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)

	if fusionMenu.converFusion and fusionMenu.converFusion:isVisible() then
		local price = resolveForgePrice(ForgeSystem.fusionPrices, ForgeSystem.fusionItem:getId(), itemTier, true, false)
		ForgeSystem.fusionPrice = price
		setForgePriceLabel(fusionMenu.converFusion.convergencePanel.moneyPanel, price, balance >= price)
		ForgeSystem.checkFusionConversionButton()
	else
		local price = resolveForgePrice(ForgeSystem.classPrice, ForgeSystem.fusionItem:getId(), itemTier, false, false)
		ForgeSystem.fusionPrice = price
		setForgePriceLabel(fusionMenu.itemsFusion.moneyPanel, price, balance >= price)
		ForgeSystem.checkFusionButton()
	end
end

function ForgeSystem.onForgeData(fusionData, fusionConvergenceData, transferData, transferConvergenceData, maxPlayerDust)
	local fusionConvergenceChecked = fusionMenu
		and fusionMenu.itemFusionPanel
		and fusionMenu.itemFusionPanel.mindPanel
		and fusionMenu.itemFusionPanel.mindPanel.convergenceCheckBox
		and fusionMenu.itemFusionPanel.mindPanel.convergenceCheckBox:isChecked()
	local transferConvergenceChecked = transferMenu
		and transferMenu.itemTransferPanel
		and transferMenu.itemTransferPanel.mindPanel
		and transferMenu.itemTransferPanel.mindPanel.convergenceCheckBox
		and transferMenu.itemTransferPanel.mindPanel.convergenceCheckBox:isChecked()

	if type(fusionData) == "table" and fusionData.fusionItems then
		local data = fusionData
		fusionData = normalizeForgeItems(data.fusionItems)
		fusionConvergenceData = normalizeConvergenceFusion(data.convergenceFusion)
		transferData = normalizeTransferData(data.transfers)
		transferConvergenceData = normalizeTransferData(data.convergenceTransfers)
		maxPlayerDust = data.dustLevel
	end

	ForgeSystem.fusionData = fusionData or {}
	ForgeSystem.fusionConvergenceData = fusionConvergenceData or {}
	ForgeSystem.transferData = transferData or {}
	ForgeSystem.transferConvergenceData = transferConvergenceData or {}
	ForgeSystem.maxPlayerDust = asNumber(maxPlayerDust, ForgeSystem.maxPlayerDust)
	ForgeSystem.sideButton = false

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	-- update
	g_game.doThing(false)
	g_game.requestResource(ResourceBank)
	g_game.requestResource(ResourceInventary)
	g_game.requestResource(ResourceForgeDust)
	g_game.requestResource(ResourceForgeSlivers)
	g_game.requestResource(ResourceForgeExaltedCore)
	g_game.doThing(true)

	forgeWindow.dustPanel.dust:setText(player:getResourceValue(ResourceForgeDust) .. '/' ..ForgeSystem.maxPlayerDust)
    fusionMenu.itemFusionPanel.mindPanel.convergenceCheckBox:setChecked(fusionConvergenceChecked and true or false)
    transferMenu.itemTransferPanel.mindPanel.convergenceCheckBox:setChecked(transferConvergenceChecked and true or false)
	if not ForgeSystem.inForgeFusion then
		show()
	end
end

function ForgeSystem.onForgeResultData(data)
	if type(data) ~= "table" then
		return
	end

	local actionType = asNumber(data.actionType)
	local convergence = data.convergence and true or false
	local success = data.success and true or false
	local leftItemId = asNumber(data.leftItemId)
	local leftTier = asNumber(data.leftTier)
	local rightItemId = asNumber(data.rightItemId)
	local rightTier = asNumber(data.rightTier)
	local bonus = asNumber(data.bonus)
	local coreCount = asNumber(data.coreCount)

	if actionType == 1 then
		return ForgeSystem.onForgeTransfer(convergence, success, leftItemId, leftTier, rightItemId, rightTier)
	end

	return ForgeSystem.onForgeFusion(convergence, success, leftItemId, leftTier, rightItemId, rightTier, bonus, leftItemId, leftTier, coreCount)
end

function ForgeSystem.onForgeHistoryData(page, lastPage, currentCount, historyList)
	local history = {}
	if type(historyList) == "table" then
		for _, entry in ipairs(historyList) do
			if type(entry) == "table" then
				table.insert(history, {
					asNumber(entry.createdAt or entry[1]),
					asNumber(entry.actionType or entry[2]),
					entry.description or entry[3] or "",
					asNumber(entry.bonus or entry[4]),
				})
			end
		end
	end

	return ForgeSystem.onForgeHistory(history)
end

-- ################# FUSION
function ForgeSystem.updateFusion()
	ForgeSystem.clearFusion()
	ForgeSystem.clearTransfer()
	local itemPanel = fusionMenu.itemFusionPanel.itemsPanel
	fusionMenu.itemFusionPanel.itemsPanel:destroyChildren()

	if selectedItemFusionRadio then
		selectedItemFusionRadio:destroy()
	end

	selectedItemFusionRadio = UIRadioGroup.create()

	selectedItemFusionRadio:clearSelected()
	connect(selectedItemFusionRadio, { onSelectionChange = onSelectionChange })

	local data = ForgeSystem.fusionData

	if fusionMenu.converFusion:isVisible() then
		data = ForgeSystem.fusionConvergenceData
	end

	for _, fusion in pairs(data) do
		local widget = g_ui.createWidget('FusionItemBox', itemPanel)

		local itemPtr = Item.create(fusion[1], 1)
		itemPtr:setTier(fusion[2])

		widget.item:setItem(itemPtr)
		widget.item:setItemCount(fusion[3])
		widget.itemPtr = itemPtr

		selectedItemFusionRadio:addWidget(widget)
	end
end

-- configure panel conversion
local function ConfigureFusionConversionPanel(selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCount())
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount

	fusionMenu.itemFusionPanel.nextItem:setItemId(itemPtr:getId())
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(true)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setImageClip( itemTier * 18 .." 0 18 16")

	fusionMenu.converFusion.convergencePanel.fusionButton.item:setItemId(itemPtr:getId())
	fusionMenu.converFusion.convergencePanel.fusionButton.item.questionMark:setVisible(false)
	if itemTier > 0 then
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setImageClip( (itemTier -1)* 9 .." 0 9 8")
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(true)
	else
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(false)
	end

	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo:setItemId(itemPtr:getId())
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.questionMark:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setImageClip( (itemTier) * 9 .." 0 9 8")

	local data = ForgeSystem.fusionConvergenceData
	local itemsConvergencePanel = fusionMenu.converFusion.convergencePanel.itemsConvergencePanel

	itemsConvergencePanel:destroyChildren()

	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
	end

	selectedItemFusionConvectionRadio = UIRadioGroup.create()

	ForgeSystem.fusionSelectedItem = 0

	selectedItemFusionConvectionRadio:clearSelected()
	connect(selectedItemFusionConvectionRadio, { onSelectionChange = onSelectionForgeConvection })

	local player = g_game.getLocalPlayer()

	local function createConversionWidget(itemPtr, fusion)
		local firstCategory = getItemCategoryBySlot(fusion[1])
		local secondCategory = getItemCategoryBySlot(itemPtr:getId())

		if (firstCategory == -1 and secondCategory == -1) then
			return false
		end

		if firstCategory ~= secondCategory then
			return false
		end

		if fusion[1] == itemPtr:getId() and fusion[3] == 1 then
			return false
		end

		if fusion[2] ~= itemTier then
			return false
		end

		local showItemCount = fusion[3]

		local widget = g_ui.createWidget('FusionItemBox', itemsConvergencePanel)
		local itemPtr = Item.create(fusion[1], 1)
		itemPtr:setTier(fusion[2])

		widget.item:setItem(itemPtr)
		widget.item:setItemCount(showItemCount)
		widget.itemPtr = itemPtr

		selectedItemFusionConvectionRadio:addWidget(widget)
	end

	for i = 1, #ForgeSystem.fusionConvergenceData do
		local fusion = ForgeSystem.fusionConvergenceData[i]
		createConversionWidget(itemPtr, fusion)
	end

	local dust = player:getResourceValue(ResourceForgeDust)
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setColor(dust >= ForgeSystem.convergenceDustFusion and "$var-text-cip-color" or "#d33c3c")

	local price = resolveForgePrice(ForgeSystem.fusionPrices, itemPtr:getId(), itemTier, true, false)

	ForgeSystem.fusionPrice = price
	setForgePriceLabel(fusionMenu.converFusion.convergencePanel.moneyPanel, price, (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice)

	ForgeSystem.checkFusionConversionButton()
end

-- configure normal panel
local function ConfigureFusionPanel(selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCountOrSubType())
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount

	fusionMenu.itemFusionPanel.nextItem:setItemId(itemPtr:getId())
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(true)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setImageClip( itemTier * 18 .." 0 18 16")

	fusionMenu.itemsFusion.itemPanel.item:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.itemPanel.questionMark:setVisible(false)
	fusionMenu.itemsFusion.itemCount.value:setText(itemCount.." / 1")
	fusionMenu.itemsFusion.itemCount.value:setColor(itemCount > 1 and "$var-text-cip-color" or "#d33c3c")

	fusionMenu.itemsFusion.fusionButton.item:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.fusionButton.item.questionMark:setVisible(false)
	if itemTier > 0 then
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(true)
	else
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	fusionMenu.itemsFusion.dustCount.dustamount:setColor(dust >= ForgeSystem.dustFusion and "$var-text-cip-color" or "#d33c3c")


	fusionMenu.itemsFusion.fusionButton.itemTo:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.fusionButton.itemTo.questionMark:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setImageClip( itemTier * 9 .." 0 9 8")
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setVisible(true)

	local price = resolveForgePrice(ForgeSystem.classPrice, itemPtr:getId(), itemTier, false, false)

	ForgeSystem.fusionPrice = price
	setForgePriceLabel(fusionMenu.itemsFusion.moneyPanel, price, (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice)

	ForgeSystem.checkFusionButton()

	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()
end

-- check if ok buttons is enabled
function ForgeSystem.checkFusionButton()
	fusionMenu.itemsFusion.fusionButton.locked:setVisible(not ForgeSystem.checkFusionState())
	fusionMenu.itemsFusion.fusionButton:setEnabled(ForgeSystem.checkFusionState())
end

-- check if ok buttons is enabled
function ForgeSystem.checkFusionConversionButton()
	fusionMenu.converFusion.convergencePanel.fusionButton.locked:setVisible(not ForgeSystem.checkFusionConversionState())
	fusionMenu.converFusion.convergencePanel.fusionButton:setEnabled(ForgeSystem.checkFusionConversionState())
end

-- check core buttons
function ForgeSystem.checkFusionButtons()
	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	if ForgeSystem.rateSuccessActive then
		exaltedCore = exaltedCore - 1
		fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(true)
		fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("$var-text-cip-color")
	end
	if ForgeSystem.tierLossActive then
		exaltedCore = exaltedCore - 1
		fusionMenu.itemsFusion.tierLossButton:setEnabled(true)
		fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("$var-text-cip-color")
	end

	if exaltedCore < 1 then
		if not ForgeSystem.rateSuccessActive then
			fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(false)
			fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("#d33c3c")
		end
		if not ForgeSystem.tierLossActive then
			fusionMenu.itemsFusion.tierLossButton:setEnabled(false)
			fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("#d33c3c")
		end
	else
		if not ForgeSystem.rateSuccessActive then
			fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(true)
			fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("$var-text-cip-color")
		end
		if not ForgeSystem.tierLossActive then
			fusionMenu.itemsFusion.tierLossButton:setEnabled(true)
			fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("$var-text-cip-color")
		end
	end

	updateFusionOptionButtons()
end

-- check if has condition
function ForgeSystem.checkFusionConversionState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.convergenceDustFusion
	local hasPrice = ForgeSystem.fusionPrice > 0
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasPrice and hasDust and hasMoney and ForgeSystem.fusionSelectedItem ~= 0 and not ForgeSystem.sideButton
end

-- check if has condition
function ForgeSystem.checkFusionState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end
	local hasItemCount = ForgeSystem.fusionItemCount >= 2
	local hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.dustFusion
	local hasPrice = ForgeSystem.fusionPrice > 0
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasPrice and hasItemCount and hasDust and hasMoney and not ForgeSystem.sideButton
end

-- check color label (core)
function ForgeSystem.checkFusionLabels()
	fusionMenu.itemsFusion.successLabel:setText(ForgeSystem.rateSuccessActive and (ForgeSystem.success + ForgeSystem.improveRateSuccess) .. "%" or "50%")
	fusionMenu.itemsFusion.successLabel:setColor(ForgeSystem.rateSuccessActive and "#44ad25" or "#d33c3c")

	fusionMenu.itemsFusion.tierLossLabel:setText(ForgeSystem.tierLossActive and ForgeSystem.tierLoss .. "%" or "100%")
	fusionMenu.itemsFusion.tierLossLabel:setColor(ForgeSystem.tierLossActive and "#44ad25" or "#d33c3c")
	updateFusionOptionButtons()
end

function ForgeSystem.toggleRateSuccessButton()
	local button = fusionMenu.itemsFusion.improveRateSuccessButton
	if not ForgeSystem.rateSuccessActive and button and not button:isEnabled() then
		return
	end

	ForgeSystem.rateSuccessActive = not ForgeSystem.rateSuccessActive
	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()
end

function ForgeSystem.toggleTierLossButton()
	local button = fusionMenu.itemsFusion.tierLossButton
	if not ForgeSystem.tierLossActive and button and not button:isEnabled() then
		return
	end

	ForgeSystem.tierLossActive = not ForgeSystem.tierLossActive
	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()
end

-- reset variables
function ForgeSystem.clearFusion()
	ForgeSystem.fusionItem = nil
	ForgeSystem.fusionItemCount = 0
	ForgeSystem.exaltedCoreCount = 0
	-- ForgeSystem.fusionPrice = 0
	ForgeSystem.fusionSelectedItem = 0
	ForgeSystem.rateSuccessActive = false
	ForgeSystem.tierLossActive = false
	ForgeSystem.fusionTier = 0

	-- fusion convergence
	fusionMenu.converFusion.convergencePanel.itemsConvergencePanel:destroyChildren()
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setColor("#d33c3c")
	fusionMenu.converFusion.convergencePanel.fusionButton:setEnabled(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.locked:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.item:setItemId(0)
	fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.item.questionMark:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo:setItemId(0)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.questionMark:setVisible(true)


	setForgePriceLabel(fusionMenu.converFusion.convergencePanel.moneyPanel, 0, false)


	-- fusion normal
	fusionMenu.itemFusionPanel.nextItem:setItemId(0)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(true)

	fusionMenu.itemsFusion.itemPanel.item:setItemId(0)
	fusionMenu.itemsFusion.itemPanel.questionMark:setVisible(true)
	fusionMenu.itemsFusion.itemCount.value:setText("0 / 1")
	fusionMenu.itemsFusion.itemCount.value:setColor("#d33c3c")

	fusionMenu.itemsFusion.fusionButton.item:setItemId(0)
	fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.item.questionMark:setVisible(true)
	fusionMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	fusionMenu.itemsFusion.fusionButton.itemTo:setItemId(0)
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.itemTo.questionMark:setVisible(true)


	setForgePriceLabel(fusionMenu.itemsFusion.moneyPanel, 0, false)

	fusionMenu.itemsFusion.fusionButton.locked:setVisible(true)
	fusionMenu.itemsFusion.fusionButton:setEnabled(false)
	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()

	ForgeSystem.checkFusionConversionButton()
end

function ForgeSystem.clearTransfer()
	ForgeSystem.fusionItem = nil
	ForgeSystem.fusionItemCount = 0
	-- ForgeSystem.fusionPrice = 0
	ForgeSystem.fusionSelectedItem = 0
	ForgeSystem.exaltedCoreCount = 0
	ForgeSystem.rateSuccessActive = false
	ForgeSystem.tierLossActive = false
	ForgeSystem.fusionTier = 0

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()

	transferMenu.itemsFusion.itemPanel.item:setItemId(0)
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.itemCount.value:setText("0 / 1")
	transferMenu.itemsFusion.itemCount.value:setColor("#d33c3c")
	transferMenu.itemsFusion.itemPanel.item:setItemId(0)
	transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(false)

	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.exaltedCount.amount:setText("???")
	transferMenu.itemsFusion.exaltedCount.amount:setColor("#d33c3c")

	transferMenu.itemsFusion.transferButton.item:setItemId(0)
	transferMenu.itemsFusion.transferButton.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.transferButton.item.tierflags:setVisible(false)

	transferMenu.itemsFusion.transferButton.itemTo:setItemId(0)
	transferMenu.itemsFusion.transferButton.itemTo.questionMark:setVisible(true)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setVisible(false)

	setForgePriceLabel(transferMenu.itemsFusion.moneyPanel, 0, false)

	transferMenu.converFusion.itemPanel.item:setItemId(0)
	transferMenu.converFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.converFusion.itemCount.value:setText("0 / 1")
	transferMenu.converFusion.itemCount.value:setColor("#d33c3c")
	transferMenu.converFusion.itemPanel.item:setItemId(0)
	transferMenu.converFusion.itemPanel.item.tierflags:setVisible(false)

	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.exaltedCount.amount:setText("???")
	transferMenu.converFusion.exaltedCount.amount:setColor("#d33c3c")

	transferMenu.converFusion.transferButton.item:setItemId(0)
	transferMenu.converFusion.transferButton.item.questionMark:setVisible(true)
	transferMenu.converFusion.transferButton.item.tierflags:setVisible(false)

	transferMenu.converFusion.transferButton.itemTo:setItemId(0)
	transferMenu.converFusion.transferButton.itemTo.questionMark:setVisible(true)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setVisible(false)

	setForgePriceLabel(transferMenu.converFusion.moneyPanel, 0, false)

	ForgeSystem.checkTransferConvergenceButton()
end


function onSelectionForgeConvection(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.checkFusionConversionButton()
end

function onConvergenceFusionChange(_, isChecked)
	ForgeSystem.clearFusion()
	fusionMenu.itemsFusion:setVisible(not isChecked)
	fusionMenu.converFusion:setVisible(isChecked)
	ForgeSystem.updateFusion()
end

function ForgeSystem.onForgeFusion(convergence, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count)
	hideForge()
	resultWindow:show(true)

	resultWindow:setText('Fusion Result')

	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(false)

	local resultWindowPanel = resultWindow.contentPanel.resultWindow
	ForgeSystem.inForgeFusion = true
	resultWindowPanel:setVisible(true)
	resultWindowPanel.resultLabel:setText('')

	setForgeWidgetItem(resultWindowPanel.transferItem, otherItem, otherTier)
	resultWindowPanel.transferItem:setItemShader("item_print_white")
	resultWindowPanel.transferItem.tierflags:setVisible(false)

	setForgeWidgetItem(resultWindowPanel.recvItem, itemId, tier)
	resultWindowPanel.recvItem:setItemShader("item_black_white")
	resultWindowPanel.recvItem.tierflags:setVisible(false)

	resultWindowPanel.finishButton:setEnabled(false)
	resultWindowPanel.finishButton:setText("Close")
	resultWindowPanel.finishButton.locked:setVisible(true)
	if resultType == 0 then
		resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.closeFinish() end
	else
		resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.openBonusFinish(convergence, ForgeSystem.fusionPrice, resultType, itemResult, tierResult, count) end
		scheduleEvent(function() resultWindowPanel.finishButton:setText("Next") end, 3550)
	end

	scheduleEvent(function() ForgeSystemEventFusionColor(false, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, 1) end, 750)
end

function ForgeSystem.onForgeTransfer(convergence, success, otherItem, otherTier, itemId, tier)
	hideForge()
	resultWindow:show(true)

	resultWindow:setText('Transfer Result')

	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(false)

	local resultWindowPanel = resultWindow.contentPanel.resultWindow
	ForgeSystem.inForgeFusion = true
	resultWindowPanel:setVisible(true)
	resultWindowPanel.resultLabel:setText('')

	setForgeWidgetItem(resultWindowPanel.transferItem, otherItem, otherTier)
	resultWindowPanel.transferItem:setItemShader("item_print_white")
	resultWindowPanel.transferItem.tierflags:setVisible(true)

	setForgeWidgetItem(resultWindowPanel.recvItem, itemId, tier)
	resultWindowPanel.recvItem:setItemShader("item_black_white")
	resultWindowPanel.recvItem.tierflags:setVisible(false)

	resultWindowPanel.finishButton:setEnabled(false)
	resultWindowPanel.finishButton:setText("Close")
	resultWindowPanel.finishButton.locked:setVisible(true)
	resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.closeFinish() end

	scheduleEvent(function() ForgeSystemEventFusionColor(true, success, otherItem, otherTier, itemId, tier, 0, 0, 0, 0, 1) end, 750)
end

function ForgeSystem.sendForgeFusion(convergence)
	ForgeSystem.inForgeFusion = false
	if not convergence then
		g_game.sendForgeFusion(false, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionItem:getId(), ForgeSystem.rateSuccessActive, ForgeSystem.tierLossActive)
	else
		g_game.sendForgeFusion(true, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem, false, false)
	end
end

-- ################# FUSION
-- ################# TRANSFER
function ForgeSystem.updateTransfer()
	ForgeSystem.clearFusion()
	ForgeSystem.clearTransfer()

	local itemPanel = transferMenu.itemTransferPanel.itemsPanel
	transferMenu.itemTransferPanel.itemsPanel:destroyChildren()

	if selectedItemFusionRadio then
		selectedItemFusionRadio:destroy()
	end

	selectedItemFusionRadio = UIRadioGroup.create()

	selectedItemFusionRadio:clearSelected()
	connect(selectedItemFusionRadio, { onSelectionChange = onSelectionChange })

	local data = ForgeSystem.transferData

	if transferMenu.converFusion:isVisible() then
		data = ForgeSystem.transferConvergenceData
	end

	local itemsVec = {}
	for _, fusion in pairs(data) do
		if not itemsVec[fusion[1] .. "." ..fusion[2]] then
			local widget = g_ui.createWidget('FusionItemBox', itemPanel)

			local itemPtr = Item.create(fusion[1], 1)
			itemPtr:setTier(fusion[2])

			widget.item:setItem(itemPtr)
			widget.item:setItemCount(fusion[3])
			widget.itemPtr = itemPtr
			widget.subItems = fusion[4]

			selectedItemFusionRadio:addWidget(widget)

			itemsVec[fusion[1] .. "." ..fusion[2]] = true
		end
	end
end


local function ConfigureTransferPanel(selectedWidget)
	ForgeSystem.fusionSelectedItem = 0

	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCount())
	local itemTier = itemPtr:getTier()
	local subItems = selectedWidget.subItems

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount
	ForgeSystem.fusionTier = itemTier

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()
	local itemsTransferPanel = transferMenu.itemTransferPanel.itemsTransferPanel

	selectedItemFusionConvectionRadio = UIRadioGroup.create()

	ForgeSystem.fusionSelectedItem = 0

	selectedItemFusionConvectionRadio:clearSelected()
	connect(selectedItemFusionConvectionRadio, { onSelectionChange = onSelectionForgeTransfer })


	for item, count in pairs(subItems) do
		if item == itemPtr:getId() then
			goto continue
		end
		local widget = g_ui.createWidget('FusionItemBox', itemsTransferPanel)

		local itemPtr = Item.create(item, 1)

		widget.item:setItem(itemPtr)
		widget.item:setItemCount(count)
		widget.itemPtr = itemPtr
		selectedItemFusionConvectionRadio:addWidget(widget)
		::continue::
	end

	transferMenu.itemsFusion.itemPanel.item:setItemId(itemPtr:getId())
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(false)
	transferMenu.itemsFusion.itemCount.value:setText(itemCount.." / 1")
	transferMenu.itemsFusion.itemCount.value:setColor("$var-text-cip-color")

	transferMenu.itemsFusion.itemPanel.item:setItemId(itemPtr:getId())
	if itemTier > 0 then
		transferMenu.itemsFusion.itemPanel.item.tierflags:setImageClip( (itemTier - 1) * 18 .." 0 18 16")
		transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(true)
	else
		transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	transferMenu.itemsFusion.dustCount.dustamount:setColor((dust >= ForgeSystem.dustTransfer and "$var-text-cip-color" or "#d33c3c"))
	forgeWindow.dustPanel.dust:setText(dust .. '/' ..ForgeSystem.maxPlayerDust)

	local exaltedCoreCount = resolveTierValue(ForgeSystem.transferMap, { itemTier - 1, itemTier, itemTier + 1 }, 1)
	transferMenu.itemsFusion.exaltedCount.amount:setText(exaltedCoreCount)
	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	transferMenu.itemsFusion.exaltedCount.amount:setColor((exaltedCore >= exaltedCoreCount and "$var-text-cip-color" or "#d33c3c"))

	ForgeSystem.exaltedCoreCount = exaltedCoreCount

	transferMenu.itemsFusion.transferButton.item:setItemId(itemPtr:getId())
	transferMenu.itemsFusion.transferButton.item.questionMark:setVisible(false)
	transferMenu.itemsFusion.transferButton.item.tierflags:setVisible(true)
	transferMenu.itemsFusion.transferButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")

	local price = resolveForgePrice(ForgeSystem.classPrice, itemPtr:getId(), itemTier, false, true)
	ForgeSystem.fusionPrice = price

	setForgePriceLabel(transferMenu.itemsFusion.moneyPanel, price, (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice)


	ForgeSystem.checkTransferButton()
end

local function ConfigureTransferConvergencePanel(selectedWidget)
	ForgeSystem.fusionSelectedItem = 0

	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCount())
	local itemTier = itemPtr:getTier()
	local subItems = selectedWidget.subItems

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount
	ForgeSystem.fusionTier = itemTier

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()
	local itemsTransferPanel = transferMenu.itemTransferPanel.itemsTransferPanel

	selectedItemFusionConvectionRadio = UIRadioGroup.create()

	ForgeSystem.fusionSelectedItem = 0

	selectedItemFusionConvectionRadio:clearSelected()
	connect(selectedItemFusionConvectionRadio, { onSelectionChange = onSelectionForgeConversionTransfer })

	for item, count in pairs(subItems) do
		if item == itemPtr:getId() then
			goto continue
		end
		local widget = g_ui.createWidget('FusionItemBox', itemsTransferPanel)

		local itemPtr = Item.create(item, 1)

		widget.item:setItem(itemPtr)
		widget.item:setItemCount(count)
		widget.itemPtr = itemPtr
		selectedItemFusionConvectionRadio:addWidget(widget)
		::continue::
	end

	transferMenu.converFusion.itemPanel.item:setItemId(itemPtr:getId())
	transferMenu.converFusion.itemPanel.item.questionMark:setVisible(false)
	transferMenu.converFusion.itemCount.value:setText(itemCount.." / 1")
	transferMenu.converFusion.itemCount.value:setColor("$var-text-cip-color")

	transferMenu.converFusion.itemPanel.item:setItemId(itemPtr:getId())
	if itemTier > 0 then
		transferMenu.converFusion.itemPanel.item.tierflags:setImageClip( (itemTier - 1) * 18 .." 0 18 16")
		transferMenu.converFusion.itemPanel.item.tierflags:setVisible(true)
	else
		transferMenu.converFusion.itemPanel.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	transferMenu.converFusion.dustCount.dustamount:setColor((dust >= ForgeSystem.convergenceDustTransfer and "$var-text-cip-color" or "#d33c3c"))
	forgeWindow.dustPanel.dust:setText(dust .. '/' ..ForgeSystem.maxPlayerDust)

	local exaltedCoreCount = resolveTierValue(ForgeSystem.transferMap, { itemTier, itemTier - 1, itemTier + 1 }, 0)
	transferMenu.converFusion.exaltedCount.amount:setText(exaltedCoreCount)
	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	transferMenu.converFusion.exaltedCount.amount:setColor((exaltedCore >= exaltedCoreCount and "$var-text-cip-color" or "#d33c3c"))

	ForgeSystem.exaltedCoreCount = exaltedCoreCount

	transferMenu.converFusion.transferButton.item:setItemId(itemPtr:getId())
	transferMenu.converFusion.transferButton.item.questionMark:setVisible(false)
	transferMenu.converFusion.transferButton.item.tierflags:setVisible(true)
	transferMenu.converFusion.transferButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")

	local price = resolveForgePrice(ForgeSystem.transferPrices, itemPtr:getId(), itemTier, true, true)
	ForgeSystem.fusionPrice = price

	setForgePriceLabel(transferMenu.converFusion.moneyPanel, price, (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice)


	ForgeSystem.checkTransferButton()
end

function ForgeSystem.checkTransferConvergenceButton()
	transferMenu.converFusion.transferButton.locked:setVisible(not ForgeSystem.checkTransferState())
	transferMenu.converFusion.transferButton:setEnabled(ForgeSystem.checkTransferState())
end

function ForgeSystem.checkTransferButton()
	transferMenu.itemsFusion.transferButton.locked:setVisible(not ForgeSystem.checkTransferState())
	transferMenu.itemsFusion.transferButton:setEnabled(ForgeSystem.checkTransferState())
end

function ForgeSystem.checkTransferState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end
	local hasItemCount = ForgeSystem.fusionSelectedItem ~= 0
	local hasDust = false
	if not transferMenu.converFusion:isVisible() then
		hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.dustTransfer
	else
		hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.convergenceDustTransfer
	end

	local hasExalted = player:getResourceValue(ResourceForgeExaltedCore) >= ForgeSystem.exaltedCoreCount
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasItemCount and hasDust and hasMoney and hasExalted and not ForgeSystem.sideButton
end

function ForgeSystem.addSecondTransferItem()
	transferMenu.itemsFusion.transferButton.itemTo:setItemId(ForgeSystem.fusionSelectedItem)
	transferMenu.itemsFusion.transferButton.itemTo.questionMark:setVisible(false)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setVisible(true)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setImageClip( (ForgeSystem.fusionTier - 2) * 9 .." 0 9 8")
end

function ForgeSystem.addSecondTransferConvergenceItem()
	transferMenu.converFusion.transferButton.itemTo:setItemId(ForgeSystem.fusionSelectedItem)
	transferMenu.converFusion.transferButton.itemTo.questionMark:setVisible(false)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setVisible(true)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setImageClip( (ForgeSystem.fusionTier - 1) * 9 .." 0 9 8")
end

function onSelectionForgeTransfer(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCount())
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.addSecondTransferItem()
	ForgeSystem.checkTransferButton()
end

function onSelectionForgeConversionTransfer(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = tonumber(selectedWidget.item:getItemCount())
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.addSecondTransferConvergenceItem()
	ForgeSystem.checkTransferConvergenceButton()
end

---
function ForgeSystemEventFusionColor(transfer, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, eventCount)
	if not g_game.isOnline() then
		ForgeSystem.inForgeFusion = false
		return
	end

	local resultWindowPanel = resultWindow.contentPanel.resultWindow

	if eventCount == 1 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge")
	elseif eventCount == 2 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge")
	elseif eventCount == 3 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
	elseif eventCount == 4 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
	elseif eventCount == 5 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		ForgeSystem.inForgeFusion = false

		resultWindowPanel.transferItem:setItemShader("")
		if not success then
			resultWindowPanel.recvItem:setItemShader("item_red")
			scheduleEvent(function()
				resultWindowPanel.recvItem:setItemId(0)
			end, 500)
		else
			resultWindowPanel.transferItem:setItemId(0)
			resultWindowPanel.recvItem:setItemShader("")
			resultWindowPanel.recvItem.tierflags:setVisible(true)
		end

		-- message
		local message = {}
		setStringColor(message, "Your ".. (transfer and "transfer" or "fusion") .." attempt was ", "$var-text-cip-color-grey")
		if not success then
			setStringColor(message, "failed", "#d33c3c")
		else
			setStringColor(message, "successful", "$var-text-cip-color-green")
		end
		setStringColor(message, ".", "$var-text-cip-color-grey")

		resultWindowPanel.resultLabel:setColoredText(string.fromColoredTable(message))

		resultWindowPanel.finishButton:setEnabled(true)
		resultWindowPanel.finishButton.locked:setVisible(false)

		return
	end

	scheduleEvent(function() ForgeSystemEventFusionColor(transfer, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, eventCount + 1) end, 750)
end

function ForgeSystem.openBonusFinish(convergence, price, resultType, itemResult, tierResult, count)
	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(true)

	local bonusResult = resultWindow.contentPanel.bonusWindow

	bonusResult.bonusItem.tierflags:setVisible(false)
	bonusResult.bonusItem:setItemShader("")
	if resultType == 1 then
		bonusResult.bonusItem:setItemId(37160)
		bonusResult.resultLabel:setText("Near! The used ".. (not convergence and ForgeSystem.dustPrice or ForgeSystem.convergenceDustFusion) .." where not consumed.")
	elseif resultType == 2 then
		bonusResult.bonusItem:setItemId(37110)
		bonusResult.resultLabel:setText("Fantastic! The used ".. count .." where not consumed.")
	elseif resultType == 3 then
		bonusResult.bonusItem:setItemId(3031)
		bonusResult.resultLabel:setText("Awesome! The used ".. formatMoney(price, ",") .." where not consumed.")
	elseif resultType == 4 then
		bonusResult.bonusItem:setItemId(itemResult)
		bonusResult.bonusItem.tierflags:setImageClip((tierResult - 1) * 18 .. " 0 18 16")
		bonusResult.bonusItem.tierflags:setVisible(true)
		bonusResult.resultLabel:setText("What luck! Your item only lost one tier instead of being\n                                     consumed.")
	end
end

function ForgeSystem.closeFinish()
	resultWindow:hide()
	show()
end

function onSelectionChange(widget, selectedWidget)
	if fusionMenu.itemsFusion:isVisible() then
		ConfigureFusionPanel(selectedWidget)
	elseif fusionMenu.converFusion:isVisible() then
		ConfigureFusionConversionPanel(selectedWidget)
	elseif transferMenu.itemsFusion:isVisible() then
		ConfigureTransferPanel(selectedWidget)
	elseif transferMenu.converFusion:isVisible() then
		ConfigureTransferConvergencePanel(selectedWidget)
	end
end

function ForgeSystem.sendForgeTransfer(convergence)
	ForgeSystem.inForgeFusion = false
	if not convergence then
		g_game.sendForgeTransfer(false, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem)
	else
		g_game.sendForgeTransfer(true, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem)
	end

	g_game.doThing(false)
	g_game.requestResource(ResourceBank)
	g_game.requestResource(ResourceInventary)
	g_game.requestResource(ResourceForgeDust)
	g_game.requestResource(ResourceForgeSlivers)
	g_game.requestResource(ResourceForgeExaltedCore)
	g_game.doThing(true)
end

-- transfer convergence
function onConvergenceTransferChange(widget, isChecked)
	ForgeSystem.clearTransfer()
	if isChecked then
		transferMenu.itemsFusion:setVisible(false)
		transferMenu.converFusion:setVisible(true)
	else
		transferMenu.itemsFusion:setVisible(true)
		transferMenu.converFusion:setVisible(false)
	end
	ForgeSystem.updateTransfer()
end

function ForgeSystem.updateConversion()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local dust = player:getResourceValue(ResourceForgeDust)

	local price1 = ForgeSystem.slivers * ForgeSystem.baseMultipier
	conversionMenu.windowConvertDust.itemCount.amount:setColor(dust >= price1 and "$var-text-cip-color" or "#d33c3c")

	conversionMenu.windowConvertDust.dustButton:setEnabled(dust >= price1)
	conversionMenu.windowConvertDust.dustButton.locked:setVisible(dust < price1)

	conversionMenu.windowConvertSlivers.itemCount.amount:setText(ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.itemCount.amount:setColor(player:getResourceValue(ResourceForgeSlivers) >= ForgeSystem.totalSlivers and "$var-text-cip-color" or "#d33c3c")
	conversionMenu.windowConvertSlivers.sliverButton:setEnabled(player:getResourceValue(ResourceForgeSlivers) >= ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.sliverButton.locked:setVisible(player:getResourceValue(ResourceForgeSlivers) < ForgeSystem.totalSlivers)

	local totalDustRequired = (100 - ForgeSystem.dustCost) + (ForgeSystem.maxPlayerDust - 100)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setText(totalDustRequired)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setColor(dust >= totalDustRequired and "$var-text-cip-color" or "#d33c3c")
	conversionMenu.windowIncreaseDustLimit.currentDust:setText(ForgeSystem.maxPlayerDust)
	conversionMenu.windowIncreaseDustLimit.nextDust:setText('to ' .. math.min(ForgeSystem.maxPlayerDust + 1, ForgeSystem.maxDust))

	if ForgeSystem.maxPlayerDust >= ForgeSystem.maxDust then
		conversionMenu.windowIncreaseDustLimit.baseText:setText('Maximum Reached')
		conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.img1:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.img2:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(false)
	else
		conversionMenu.windowIncreaseDustLimit.baseText:setText('Raise limit from')
		conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.img1:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.img2:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(true)
	end

	conversionMenu.windowIncreaseDustLimit.increaseButton:setEnabled(dust >= totalDustRequired and ForgeSystem.maxPlayerDust < ForgeSystem.maxDust)
	conversionMenu.windowIncreaseDustLimit.increaseButton.locked:setVisible(not (dust >= totalDustRequired and ForgeSystem.maxPlayerDust < ForgeSystem.maxDust))
end

function ForgeSystem.onForgeHistory(history)
    if not historyMenu or not historyMenu.historyList then
        return
    end

    historyMenu.historyList:destroyChildren()
    local colors = { '#414141', '#484848' }

    for id, info in ipairs(history) do
        local createdAt = asNumber(info.createdAt or info[1])
        local actionType = asNumber(info.actionType or info[2])
        local rawDescription = tostring(info.description or info.historyMessage or info[3] or "")
        local description = summarizeForgeHistoryDescription(actionType, rawDescription)
        local widget = g_ui.createWidget('HistoryForgePanel', historyMenu.historyList)
		local backgroundColor = colors[((id-1) % #colors) + 1]

		if id == 1 then
            widget:setMarginTop(16)
        end
        widget:setBackgroundColor(backgroundColor)
        widget.date:setText(formatForgeHistoryDate(createdAt))
        widget.date:setColor("$var-text-cip-color")
        local actionText
        local actionColor
        if actionType == 0 then
            actionText = 'Fusion'
            actionColor = "$var-text-cip-color"
        elseif actionType == 1 then
            actionText = 'Transfer'
            actionColor = "$var-text-cip-color"
        else
            actionText = 'Conversion'
            actionColor = "$var-text-cip-color-blue"
        end
        widget.action:setText(actionText)
        widget.action:setColor(actionColor)
        widget.details:setText(description)
        widget.details:setColor("$var-text-cip-color")

        local _, lineCount = description:gsub("\n", "\n")
        local height = math.max(30, 14 * (lineCount + 1) + 6)
        widget:setHeight(height)
    end
end
