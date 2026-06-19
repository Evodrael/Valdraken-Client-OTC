function init()
  local files
  local loaded_files = {}
  local layout = g_resources:getLayout()

  files = g_resources.listDirectoryFiles('/data/styles')
  table.sort(files)
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'otui') then
      g_ui.importStyle('/data/styles/' .. file)
    end
  end

  if layout:len() > 0 then
    files = g_resources.listDirectoryFiles('/layouts/' .. layout .. '/styles')
    table.sort(files)
    for _,file in pairs(files) do
      if g_resources.isFileType(file, 'otui') then
        g_ui.importStyle('/layouts/' .. layout .. '/styles/' .. file)
      end
    end
  end

  if layout:len() > 0 then
    files = g_resources.listDirectoryFiles('/layouts/' .. layout .. '/fonts')
    loaded_files = {}
    for _,file in pairs(files) do
      if g_resources.isFileType(file, 'otfont') then
        g_fonts.importFont('/layouts/' .. layout .. '/fonts/' .. file)
        loaded_files[file] = true
      end
    end
  end

  files = g_resources.listDirectoryFiles('/data/fonts')
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'otfont') and not loaded_files[file] then
      g_fonts.importFont('/data/fonts/' .. file)
    end
  end

  g_mouse.loadCursors('/data/cursors/cursors')
  if layout:len() > 0 and g_resources.directoryExists('/layouts/' .. layout .. '/cursors/cursors') then
    g_mouse.loadCursors('/layouts/' .. layout .. '/cursors/cursors')
  end

  g_gameConfig:loadFonts()
end

function terminate()
end
