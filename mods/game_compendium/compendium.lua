local compendiumWindow
local compendiumEntries = {}
local currentCategory
local selectedTopButton
local selectedTreeItem
local selectedArticleButton
local currentArticle
local pendingDownloads = {}
local seenEntries = {}
local seenPath
local showArticle
local hasUnseenContentImpl
local seenTrackingEnabled = false

local COMPENDIUM_FILE = "/data/json/compendium.json"
local NEW_ICON = "/images/store/button-store-new"

local CATEGORIES = {
  { key = "PLAYER GUIDE", button = "buttonMenu1" },
  { key = "CLIENT FEATURES", button = "buttonMenu2" },
  { key = "USEFUL INFO", button = "buttonMenu3" },
  { key = "MAJOR UPDATES", button = "buttonMenu4" },
  { key = "SUPPORT", button = "buttonMenu5" }
}

local function getChild(id)
  if not compendiumWindow then
    return nil
  end

  return compendiumWindow:recursiveGetChildById(id)
end

local function setWidgetText(widget, text)
  if widget then
    widget:setText(text or "")
  end
end

local function shortLabel(text, limit)
  text = text or ""
  limit = limit or 25

  if short_text then
    return short_text(text, limit)
  end

  if #text <= limit then
    return text
  end

  return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function getPlayerSeenPath()
  if LoadedPlayer and LoadedPlayer.isLoaded and LoadedPlayer:isLoaded() then
    return "/characterdata/" .. LoadedPlayer:getId() .. "/compendium_seen.json"
  end

  local player = g_game.getLocalPlayer()
  if player then
    return "/characterdata/" .. player:getId() .. "/compendium_seen.json"
  end

  return nil
end

local function loadSeenEntries()
  local path = getPlayerSeenPath()
  if seenPath == path then
    return
  end

  seenPath = path
  seenEntries = {}

  if not seenPath or not g_resources.fileExists(seenPath) then
    return
  end

  local ok, result = pcall(function()
    return json.decode(g_resources.readFileContents(seenPath))
  end)

  if ok and type(result) == "table" and type(result.seen) == "table" then
    seenEntries = result.seen
  end
end

local function saveSeenEntries()
  if not seenPath then
    seenPath = getPlayerSeenPath()
  end

  if not seenPath then
    return
  end

  local ok, result = pcall(function()
    return json.encode({ seen = seenEntries }, 2)
  end)

  if ok then
    g_resources.writeFileContents(seenPath, result)
  else
    g_logger.error("Error while saving compendium seen data. Details: " .. tostring(result))
  end
end

local function isSeen(entry)
  return entry and seenEntries[tostring(entry.id)] == true
end

local function hasUnseen(entry)
  if not entry then
    return false
  end

  if entry.children and #entry.children > 0 then
    for _, child in ipairs(entry.children) do
      if not isSeen(child) then
        return true
      end
    end

    return false
  end

  if not isSeen(entry) then
    return true
  end

  return false
end

local function normalizeEntry(entry)
  entry.id = tonumber(entry.id) or 0
  entry.groupheaderid = tonumber(entry.groupheaderid) or 0
  entry.publishdate = tonumber(entry.publishdate) or 0
  entry.headline = entry.headline or ""
  if type(entry.message) == "table" then
    entry.message = table.concat(entry.message, "\n")
  else
    entry.message = tostring(entry.message or "")
  end
  entry.category = entry.category or ""

  return entry
end

local function sortEntries(entries, category)
  table.sort(entries, function(a, b)
    if category == "MAJOR UPDATES" and a.publishdate ~= b.publishdate then
      return a.publishdate > b.publishdate
    end

    if a.id == b.id then
      return a.headline < b.headline
    end

    return a.id < b.id
  end)
end

local function loadCompendium()
  compendiumEntries = {}

  if not g_resources.fileExists(COMPENDIUM_FILE) then
    g_logger.error("Compendium file not found: " .. COMPENDIUM_FILE)
    return false
  end

  local ok, result = pcall(function()
    return json.decode(g_resources.readFileContents(COMPENDIUM_FILE))
  end)

  if not ok or type(result) ~= "table" or type(result.gamenews) ~= "table" then
    g_logger.error("Error while reading compendium json. Details: " .. tostring(result))
    return false
  end

  for _, entry in pairs(result.gamenews) do
    if type(entry) == "table" then
      entry = normalizeEntry(entry)
      compendiumEntries[entry.category] = compendiumEntries[entry.category] or {}
      table.insert(compendiumEntries[entry.category], entry)
    end
  end

  for category, entries in pairs(compendiumEntries) do
    sortEntries(entries, category)
  end

  return true
end

hasUnseenContentImpl = function()
  loadSeenEntries()

  if not next(compendiumEntries) and not loadCompendium() then
    return false
  end

  local entriesWithChildren = {}
  for _, entries in pairs(compendiumEntries) do
    for _, entry in ipairs(entries) do
      if entry.groupheaderid and entry.groupheaderid ~= 0 then
        entriesWithChildren[entry.groupheaderid] = true
      end
    end
  end

  for _, entries in pairs(compendiumEntries) do
    for _, entry in ipairs(entries) do
      if entry.groupheaderid ~= 0 or not entriesWithChildren[entry.id] then
        if not isSeen(entry) then
          return true
        end
      end
    end
  end

  return false
end

local function syncSideButtonHighlight()
  if modules.game_sidebuttons and modules.game_sidebuttons.setCompendiumHighlight and hasUnseenContentImpl then
    modules.game_sidebuttons.setCompendiumHighlight(hasUnseenContentImpl())
  end
end

local function requestRemoteImage(url)
  if not HTTP or not HTTP.downloadImage or pendingDownloads[url] then
    return
  end

  pendingDownloads[url] = true
  local articleId = currentArticle and currentArticle.id

  local ok = pcall(function()
    HTTP.downloadImage(url, function(_, err)
      pendingDownloads[url] = nil

      if not err and currentArticle and currentArticle.id == articleId and showArticle then
        showArticle(currentArticle, selectedArticleButton, true)
      end
    end)
  end)

  if not ok then
    pendingDownloads[url] = nil
  end
end

local function normalizeHtml(html)
  html = html or ""
  html = html:gsub("&nbsp;", " ")
  html = html:gsub("&amp;", "&")
  html = html:gsub("&lt;", "<")
  html = html:gsub("&gt;", ">")
  html = html:gsub("&quot;", "\"")
  html = html:gsub("&#39;", "'")
  html = html:gsub("<[Cc][Ee][Nn][Tt][Ee][Rr]>", '<div style="text-align: center;">')
  html = html:gsub("</[Cc][Ee][Nn][Tt][Ee][Rr]>", "</div>")
  html = html:gsub('border="(%d+)"', 'border="%1 black"')
  html = html:gsub("<br>", "<br/>")
  html = html:gsub("<br >", "<br/>")
  html = html:gsub("<[Ii][Mm][Gg](%s+[^>]-)%s*/?>", function(attributes)
    local newAttributes = attributes:gsub('[Ss][Rr][Cc]="([^"]+)"', function(url)
      if url:find("^https?://") then
        if HTTP and HTTP.images and HTTP.images[url] then
          return 'src="/downloads/' .. HTTP.images[url] .. '"'
        end

        requestRemoteImage(url)
        return ""
      end

      return 'src="' .. url .. '"'
    end)

    return "<img" .. newAttributes .. "/>"
  end)

  return html
end

local function textFromHtml(html)
  html = normalizeHtml(html)
  html = html:gsub("<[Ii][Mm][Gg][^>]*>", "")

  html = html:gsub("<br%s*/?>", "\n") 
  html = html:gsub("<[Bb][Rr]>", "\n")
  
  html = html:gsub("</[Pp]>", "\n\n")
  html = html:gsub("<[Pp][^>]*>", "")
  html = html:gsub("</[Dd][Ii][Vv]>", "\n")
  html = html:gsub("<[Tt][Rr][^>]*>", "\n")
  
  html = html:gsub("</[Tt][Dd]>", "\n\n") 
  html = html:gsub("</[Tt][Hh]>", "\n")
  
  html = html:gsub("<[Ll][Ii][^>]*>", "\n* ")
  html = html:gsub("<[^>]+>", "") 

  html = html:gsub("[ \t]+\n", "\n")
  html = html:gsub("\n[ \t]+", "\n")
  html = html:gsub("\n\n\n+", "\n\n")
  
  html = html:gsub("^%s+", "")
  html = html:gsub("%s+$", "")
  
  return html
end

local function extractAttribute(attributes, name)
  return attributes:match(name .. '%s*=%s*"([^"]+)"') or
         attributes:match(name .. "%s*=%s*'([^']+)'")
end

local function getImageSource(url)
  if not url or url == "" then
    return nil
  end

  if url:find("^https?://") then
    if HTTP and HTTP.images and HTTP.images[url] then
      return "/downloads/" .. HTTP.images[url]
    end

    requestRemoteImage(url)
    return nil
  end

  return url
end

local function addTextChunk(content, text, width)
  text = textFromHtml(text)
  if text == "" then
    return
  end

  local label = g_ui.createWidget("CompendiumArticleLabel", content)
  label:setWidth(width)
  label:setText(text)
end

local function addImageChunk(content, attributes, width)
  local source = getImageSource(extractAttribute(attributes, "[Ss][Rr][Cc]"))
  if not source then
    return
  end

  local imageWidth = tonumber(extractAttribute(attributes, "[Ww][Ii][Dd][Tt][Hh]")) or 320
  local imageHeight = tonumber(extractAttribute(attributes, "[Hh][Ee][Ii][Gg][Hh][Tt]")) or 180
  local maxWidth = math.max(120, width - 20)

  local scale = 1 
  imageWidth = math.max(1, math.floor(imageWidth * scale))
  imageHeight = math.max(1, math.floor(imageHeight * scale))

  if imageWidth > maxWidth then
    local ratio = maxWidth / imageWidth
    imageWidth = maxWidth
    imageHeight = math.max(1, math.floor(imageHeight * ratio))
  end

  local container = g_ui.createWidget("UIWidget", content)
  container:setHeight(imageHeight + 12)

  local image = g_ui.createWidget("CompendiumArticleImage", container)
  image:setImageSource(source)
  image:setWidth(imageWidth)
  image:setHeight(imageHeight)
end

local function renderArticleContent(message)
  local content = getChild("compendiumContent")
  if not content then
    return
  end

  for _, child in pairs(content:getChildren()) do
    child:destroy()
  end

  local width = math.max(120, content:getWidth() - 22)
  local currentPosition = 1

  for startPosition, attributes, endPosition in message:gmatch("()<[Ii][Mm][Gg]([^>]*)>()") do
    addTextChunk(content, message:sub(currentPosition, startPosition - 1), width)
    addImageChunk(content, attributes, width)
    currentPosition = endPosition
  end

  addTextChunk(content, message:sub(currentPosition), width)
end

local function clearSelection()
  if selectedArticleButton then
    selectedArticleButton:setOn(false)
    if selectedArticleButton.text then
      selectedArticleButton.text:setColor("$var-text-cip-color")
    end
    
    if selectedArticleButton.activeArrow then
      selectedArticleButton.activeArrow:setVisible(false)
    end
  end

  selectedArticleButton = nil
end

local function setSelectedArticleButton(button)
  clearSelection()

  selectedArticleButton = button
  if selectedArticleButton then
    selectedArticleButton:setOn(true)
    if selectedArticleButton.text then
      selectedArticleButton.text:setColor("$var-text-cip-color-highlight")
    end
    
    if selectedArticleButton.activeArrow then
      selectedArticleButton.activeArrow:setVisible(true)
    end
  end
end

local function updateEntryFlag(widget, entry)
  if widget and widget.newFlag then
    local visible = hasUnseen(entry)
    widget.newFlag:setVisible(visible)

    if widget.text then
      widget.text:setMarginLeft(visible and 16 or 2)
    end
  end
end

local function refreshMenuFlags()
  local categoriesPanel = getChild("categories")
  if not categoriesPanel then
    return
  end

  for _, tree in pairs(categoriesPanel:getChildren()) do
    updateEntryFlag(tree.mainButton, tree.entry)

    local panel = tree:getChildById("panel")
    if panel then
      for _, child in pairs(panel:getChildren()) do
        updateEntryFlag(child, child.entry)
      end
    end
  end
end

local function markSeen(entry)
  if not entry then
    return
  end

  if not seenTrackingEnabled then
    return
  end

  loadSeenEntries()
  if isSeen(entry) then
    return
  end

  seenEntries[tostring(entry.id)] = true
  saveSeenEntries()
  refreshMenuFlags()
  syncSideButtonHighlight()
end

showArticle = function(entry, button, keepScroll)
  local title = getChild("contentTitle")
  local contentScroll = getChild("contentScroll")

  if not entry then
    currentArticle = nil
    setWidgetText(title, tr("No information available"))
    renderArticleContent("")
    return
  end

  currentArticle = entry
  setWidgetText(title, entry.headline)
  renderArticleContent(entry.message)

  if contentScroll and not keepScroll then
    contentScroll:setValue(0)
  end

  if button then
    setSelectedArticleButton(button)
  end

  markSeen(entry)
end

local function closeSelectedTree()
  if not selectedTreeItem or not selectedTreeItem:getParent() then
    selectedTreeItem = nil
    return
  end

  local tree = selectedTreeItem:getParent()
  local panel = tree:getChildById("panel")
  local arrow = tree:getChildById("arrow")

  tree:setHeight(20)
  selectedTreeItem:setChecked(false)

  if panel then
    panel:setVisible(false)
    panel:setHeight(0)
    for _, child in pairs(panel:getChildren()) do
      child:destroy()
    end
  end

  if arrow then
    arrow:setVisible(false)
  end

  selectedTreeItem = nil
end

local function createArticleButton(parent, entry, index)
  local button = g_ui.createWidget("CompendiumTreeButton", parent)
  button:setId("article" .. tostring(entry.id))
  button.entry = entry
  button.text:setText(shortLabel(entry.headline, 18))
  button.newFlag:setImageSource(NEW_ICON)
  updateEntryFlag(button, entry)
  button.onClick = function()
    showArticle(entry, button)
  end

  if index and parent:getParent() and parent:getParent().arrow then
    local arrowMargin = (index - 1) * 20 + 6
    button.onClick = function()
      parent:getParent().arrow:setMarginTop(arrowMargin)
      showArticle(entry, button)
    end
  end

  return button
end

local function createTreeItem(parent, entry, children)
  local treeItem = g_ui.createWidget("CompendiumTreeItem", parent)
  treeItem:setId("entry" .. tostring(entry.id))
  treeItem.entry = entry
  treeItem.mainButton.entry = entry
  treeItem.mainButton.text:setText(shortLabel(entry.headline, 20))
  treeItem.mainButton.newFlag:setImageSource(NEW_ICON)
  updateEntryFlag(treeItem.mainButton, entry)

  if children and #children > 0 then
    treeItem.mainButton.scroll:setVisible(true)
  else
    treeItem.mainButton.scroll:setHeight(0)
  end

  treeItem.mainButton.onClick = function()
    if children and #children > 0 then
      if selectedTreeItem == treeItem.mainButton then
        return true
      end

      closeSelectedTree()
      clearSelection()

      local panel = treeItem:getChildById("panel")
      local arrow = treeItem:getChildById("arrow")
      local height = 20 + (#children * 20)

      selectedTreeItem = treeItem.mainButton
      selectedTreeItem:setChecked(true)
      treeItem:setHeight(height)
      panel:setHeight((#children * 20) + 2)
      panel:setVisible(true)
      arrow:setVisible(true)
      arrow:setMarginTop(6)

      local firstButton
      for index, childEntry in ipairs(children) do
        local button = createArticleButton(panel, childEntry, index)
        if not firstButton then
          firstButton = button
        end
      end

      if firstButton then
        firstButton.onClick()
      end
    else
      closeSelectedTree()
      showArticle(entry, treeItem.mainButton)
      treeItem.mainButton:setChecked(true)
      selectedTreeItem = treeItem.mainButton
    end
  end

  return treeItem
end

local function buildMenu(category)
  local categoriesPanel = getChild("categories")
  local categoryScroll = getChild("categoryScroll")
  if not categoriesPanel then
    return
  end

  loadSeenEntries()
  closeSelectedTree()
  clearSelection()

  for _, child in pairs(categoriesPanel:getChildren()) do
    child:destroy()
  end

  local entries = compendiumEntries[category] or {}
  local childrenByHeader = {}
  local rootEntries = {}

  for _, entry in ipairs(entries) do
    if entry.groupheaderid == 0 then
      table.insert(rootEntries, entry)
    else
      childrenByHeader[entry.groupheaderid] = childrenByHeader[entry.groupheaderid] or {}
      table.insert(childrenByHeader[entry.groupheaderid], entry)
    end
  end

  sortEntries(rootEntries, category)
  for _, children in pairs(childrenByHeader) do
    sortEntries(children)
  end

  for _, entry in ipairs(rootEntries) do
    entry.children = childrenByHeader[entry.id] or {}
    createTreeItem(categoriesPanel, entry, childrenByHeader[entry.id])
  end

  if categoryScroll then
    categoryScroll:setValue(0)
  end

  local firstTree = categoriesPanel:getFirstChild()
  if firstTree and firstTree.mainButton then
    firstTree.mainButton.onClick()
  else
    showArticle(nil)
  end
end

local function setTopButton(category)
  if selectedTopButton then
    selectedTopButton:setChecked(false)
  end

  selectedTopButton = nil

  for _, categoryInfo in ipairs(CATEGORIES) do
    local button = getChild(categoryInfo.button)
    if button and categoryInfo.key == category then
      selectedTopButton = button
      selectedTopButton:setChecked(true)
      return
    end
  end
end

local function normalizeTitle(title)
  return tostring(title or ""):lower():trim()
end

local function findEntryByTitle(title)
  local normalizedTitle = normalizeTitle(title)
  if normalizedTitle == "" then
    return nil
  end

  if not next(compendiumEntries) and not loadCompendium() then
    return nil
  end

  for _, entries in pairs(compendiumEntries) do
    for _, entry in ipairs(entries) do
      if normalizeTitle(entry.headline) == normalizedTitle then
        return entry
      end
    end
  end

  for _, entries in pairs(compendiumEntries) do
    for _, entry in ipairs(entries) do
      if normalizeTitle(entry.headline):find(normalizedTitle, 1, true) then
        return entry
      end
    end
  end

  return nil
end

local function selectEntry(entry)
  local categoriesPanel = getChild("categories")
  if not entry or not categoriesPanel then
    return false
  end

  for _, tree in pairs(categoriesPanel:getChildren()) do
    if tree.entry then
      if tree.entry.id == entry.id and tree.mainButton then
        tree.mainButton.onClick()
        return true
      end

      if tree.entry.id == entry.groupheaderid and tree.mainButton then
        tree.mainButton.onClick()

        local panel = tree:getChildById("panel")
        local articleButton = panel and panel:getChildById("article" .. tostring(entry.id))
        if articleButton then
          articleButton.onClick()
          return true
        end
      end
    end
  end

  return false
end

function selectCategory(category)
  if not compendiumWindow then
    return
  end

  loadSeenEntries()
  currentCategory = category
  setTopButton(category)
  buildMenu(category)
end

function init()
  compendiumWindow = g_ui.displayUI("compendium")
  loadCompendium()
  selectCategory("PLAYER GUIDE")
  hide()
  syncSideButtonHighlight()
end

function terminate()
  g_client.setInputLockWidget(nil)

  if compendiumWindow then
    compendiumWindow:destroy()
    compendiumWindow = nil
  end
end

function hide()
  if compendiumWindow then
    compendiumWindow:hide()
  end

  seenTrackingEnabled = false
  g_client.setInputLockWidget(nil)
end

function show()
  if not compendiumWindow then
    return
  end

  loadSeenEntries()
  if not currentCategory then
    selectCategory("PLAYER GUIDE")
  else
    refreshMenuFlags()
  end

  compendiumWindow:show(true)
  compendiumWindow:focus()
  seenTrackingEnabled = true
  if currentArticle then
    renderArticleContent(currentArticle.message)
    markSeen(currentArticle)
  end
  syncSideButtonHighlight()
  g_client.setInputLockWidget(compendiumWindow)
end

function hasUnseenContent()
  return hasUnseenContentImpl and hasUnseenContentImpl() or false
end

function refreshSideButtonHighlight()
  syncSideButtonHighlight()
end

function openArticleByTitle(title)
  if not compendiumWindow then
    return false
  end

  local entry = findEntryByTitle(title)
  if not entry then
    show()
    return false
  end

  show()
  if currentCategory ~= entry.category then
    selectCategory(entry.category)
  end

  selectEntry(entry)
  return true
end
