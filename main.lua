--[[--
Plugin for KOReader to extract metadata from comic (.cbz and .cbr) files as Custom Metadata

@module koplugin.ComicMeta
--]]

-- Get the absolute path of this plugin directory
local function getPluginDir()
    local source = debug.getinfo(1, "S").source
    -- Remove @ and file: prefix if present
    source = source:gsub("^@", ""):gsub("^file:", "")
    -- Extract directory
    return source:match("^(.*[/\\])")
end

local plugin_dir = getPluginDir()
package.path = package.path .. ";" .. plugin_dir .. "lib/comiclib/?.lua"
package.path = package.path .. ";" .. plugin_dir .. "lib/comiclib/lib/?.lua"
package.path = package.path .. ";" .. plugin_dir .. "lib/comiclib/third_party/?/?.lua"

local ComicLib = require("comiclib")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local T = ffiUtil.template
local _ = require("gettext")

-- ... reste du code inchangé

local ComicMeta = WidgetContainer:extend({
    name = "comicmeta",
    is_doc_only = false,
})

--- Register our plugin setting
function ComicMeta:onDispatcherRegisterActions()
    Dispatcher:registerAction(
        "comicmeta_action",
        { category = "none", event = "ComicMeta", title = _("Extract Comic Meta"), general = true }
    )
end

--- Initiate our plugin
function ComicMeta:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

--- Add a main menu entry to the UI
function ComicMeta:addToMainMenu(menu_items)
    menu_items.comic_meta = {
        text = _("Extract Comic Meta"),
        -- in which menu this should be appended
        sorting_hint = "more_tools",
        -- a callback when tapping
        callback = function()
            self:onComicMeta()
        end,
    }
end

--- Extract metadata from a comic archive
---
-- @param comic_file string: full path to the comic file
-- @return boolean: true on success, false on failure
function ComicMeta:processFile(comic_file)
    local comicInfo, ok = ComicLib.ComicInfo:new(comic_file)
    if not ok or comicInfo == nil then
        logger.dbg(_("Failed to open comic file"), comic_file)
        return false
    end

    logger.dbg("ComicMeta -> processFile comicInfo.metadata", comicInfo.metadata)

    -- Parse the XML content and create a metadata table
    local metadata = {
        title = comicInfo.metadata.Title,
        authors = comicInfo.metadata.Writer,
        series = comicInfo.metadata.Series,
        series_index = comicInfo.metadata.Number,
        description = comicInfo.metadata.Summary,
        keywords = comicInfo.metadata.Tags,
        language = comicInfo.metadata.LanguageISO,
    }

    logger.dbg("ComicMeta -> processFile metadata", metadata)

    -- Fixup metadata
    for key, value in pairs(metadata) do
        if key == "keywords" then
            local out = ""
            local values = util.splitToArray(value, ",", false)
            for __, val in ipairs(values) do
                if #out > 0 then
                    out = out .. "\n"
                end
                out = out .. util.htmlEntitiesToUtf8(util.trim(val))
            end

            metadata[key] = out
        else
            metadata[key] = util.htmlEntitiesToUtf8(value)
        end
    end

    -- Retrieve current metadata
    local custom_doc_settings = DocSettings.openSettingsFile(comic_file)
    local doc_settings = DocSettings:open(comic_file)
    if not custom_doc_settings or not doc_settings then
        logger.dbg(T(_("Failed to open DocSettings for file: %1"), comic_file))
        return false
    end

    -- Read the existing doc_props property
    local doc_props = custom_doc_settings:readSetting("doc_props") or {}
    local original_doc_props = {}
    for key, __ in pairs(metadata) do
        original_doc_props[key] = doc_props[key] or ""
    end
    custom_doc_settings:saveSetting("doc_props", original_doc_props)

    -- Update the custom properties with the new metadata
    for key, value in pairs(metadata) do
        doc_props[key] = value
    end

    -- Write the updated doc_props property back to the DocSettings
    custom_doc_settings:saveSetting("custom_props", doc_props)

    local has_toc = self:writeCustomToC(doc_settings, comicInfo.metadata.Pages)

    -- Save the updated metadata back to the metadata file
    custom_doc_settings:flushCustomMetadata(comic_file)
    if has_toc then
        doc_settings:flush()
    end

    return true
end

--- Scans a folder and returns a list of all comic files found.
---
-- @param folder string: The folder to scan.
-- @param recursive boolean: Whether or not to scan recursively.
-- @return table: List of comic file paths.
function ComicMeta:scanForComicFiles(folder, recursive)
    logger.dbg("ComicMeta -> scanForComicFiles scanning folder", folder, "recursive:", recursive)

    local comic_files = {}

    for entry in lfs.dir(folder) do
        if entry == "." or entry == ".." then
            goto continue
        end

        local full_path = folder .. "/" .. entry
        local attr = lfs.attributes(full_path)

        if not attr or (attr.mode ~= "directory" and attr.mode ~= "file") then
            goto continue -- Skip if it's not a file or directory
        end

        if attr.mode == "directory" and recursive then
            if entry:lower():match("%.sdr$") then -- Skip sidecar folders
                goto continue
            end

            logger.dbg("ComicMeta -> scanForComicFiles entering subdirectory", full_path)

            local sub_comic_files = self:scanForComicFiles(full_path, recursive)

            for _, f in ipairs(sub_comic_files) do
                table.insert(comic_files, f)
            end
        elseif attr.mode == "file" and (entry:lower():match("%.cbz$") or entry:lower():match("%.cbr$")) then
            logger.dbg("ComicMeta -> scanForComicFiles found comic file", full_path)

            table.insert(comic_files, full_path)
        end
        ::continue::
    end

    if #comic_files == 0 then
        logger.dbg("ComicMeta -> scanForComicFiles no comic files found")
    end

    return comic_files
end

--- Checks if a folder contains any subdirectories.
---
-- @param folder string: The folder to check.
-- @return boolean: True if subdirectories exist, false otherwise.
function ComicMeta:hasSubdirectories(folder)
    logger.dbg("ComicMeta -> hasSubdirectories checking folder", folder)

    for entry in lfs.dir(folder) do
        if entry == "." or entry == ".." then
            goto continue
        end

        local attr = lfs.attributes(folder .. "/" .. entry)

        if attr and attr.mode == "directory" and not entry:lower():match("%.sdr$") then
            logger.dbg("ComicMeta -> hasSubdirectories found subdirectory", entry)
            return true
        end
        ::continue::
    end

    logger.dbg("ComicMeta -> hasSubdirectories no subdirectories found")

    return false
end

--- Processes all comic files in a folder, optionally recursively.
---
-- @param folder string: The folder to process.
-- @param recursive boolean: Whether to process subfolders recursively.
function ComicMeta:processDirectory(folder, recursive)
    logger.dbg("ComicMeta -> processDirectory processing folder", folder, "recursive:", recursive)

    Trapper:setPausedText(_("Do you want to abort extraction?"), _("Abort"), _("Don't abort"))

    local doNotAbort = Trapper:info(_("Scanning for comics..."))
    if not doNotAbort then
        Trapper:clear()
        return
    end
    ffiUtil.sleep(2) -- Pause so that the user can see it

    local comic_files = self:scanForComicFiles(folder, recursive)
    self:processFiles(comic_files)

end

function ComicMeta:processFiles(comic_files)
    if #comic_files == 0 then
        logger.dbg("ComicMeta -> processDirectory no comic files found")
        Trapper:info(_("No comics found."))
        return
    end

    logger.dbg("ComicMeta -> processDirectory found", #comic_files, "comic files to process")
    local successes = 0

    for idx, file_path in ipairs(comic_files) do
        local real_path = ffiUtil.realpath(file_path)

        logger.dbg("ComicMeta -> processFiles processing file", real_path)
        local doNotAbort = Trapper:info(  -- Ajout de 'local' ici
            T(
                _([[
Extracting metadata...
%1 / %2]]),
                idx,
                #comic_files
            ),
            true
        )
        if not doNotAbort then
            Trapper:clear()
            return
        end

        local complete, success = Trapper:dismissableRunInSubprocess(function()
            return self:processFile(real_path)
        end)
        if complete and success then
            successes = successes + 1

            -- Update the book info in the file manager
            UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", real_path))
            UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
        end
    end

    Trapper:clear()
    UIManager:show(InfoMessage:new({
        text = T(
            _([[
Comic metadata extraction complete.
Successfully extracted %1 / %2]]),
            successes,
            #comic_files
        ),
    }))
end

--- Writes a custom Table of Contents based on the Pages data from ComicInfo.xml
--- Example xml:
---<Pages>
--   <Page Image="0" Type="FrontCover" Bookmark="Capa" />
--   <Page Image="1" Type="Story" Bookmark="Capítulo 1: Paraíso" />
--   <Page Image="71" Type="Story" Bookmark="Capítulo 2: Pseudo-criaturas" />
--   <Page Image="112" Type="Story" Bookmark="Capítulo 3: Hospedeiros" />
--   <Page Image="159" Type="Story" Bookmark="Capítulo 4: Purgatório" />
-- </Pages>
--
-- So to access these fields:
-- pages_data.Page[1].Image, pages_data.Page[1].Bookmark, etc.
--
-- For the structure of the ToC entries, see:
-- https://github.com/koreader/koreader/blob/7e63f91c8e74af64089cefa187a17d664e261b35/frontend/apps/reader/modules/readerhandmade.lua#L23
--
-- @param doc_settings: The DocSettings object for the file, this must be DocSettings:open(file)
-- @param pages_data: The Pages data from the parsed ComicInfo.xml
-- @return boolean: true if ToC was written, false if not
function ComicMeta:writeCustomToC(doc_settings, pages_data)
    if not pages_data or not pages_data.Page then
        logger.dbg("ComicMeta -> writeCustomToC: No pages data found")

        return false
    end

    logger.dbg("ComicMeta -> writeCustomToC writing ToC from pages", #pages_data.Page)

    local toc = {}
    local pages = pages_data.Page

    for _, page in ipairs(pages) do
        if page.Bookmark and page.Bookmark ~= "" then
            -- Convert Image attribute to page number (add 1 since it's 0-based)
            local page_num = tonumber(page.Image)

            if page_num then
                table.insert(toc, {
                    depth = 1,
                    page = page_num + 1, -- Convert from 0-based to 1-based
                    title = page.Bookmark,
                })
            else
                logger.err("ComicMeta -> writeCustomToC: Invalid Image value for page", page.Image)
            end
        end
    end

    if #toc == 0 then
        logger.dbg("ComicMeta -> writeCustomToC: No bookmarked pages found")
        return false
    end

    logger.dbg("ComicMeta -> writeCustomToC: Created ToC with", #toc, "entries")

    doc_settings:saveSetting("handmade_toc", toc)
    doc_settings:saveSetting("handmade_toc_enabled", true)
    doc_settings:saveSetting("handmade_toc_edit_enabled", false)
end

--- This is basically the plugin's main()
function ComicMeta:onComicMeta()
    if not FileManager.instance then
        return
    end

    local current_folder = FileManager.instance.file_chooser.path

    Trapper:wrap(function()
        local has_subdirs = self:hasSubdirectories(current_folder)
        local recursive = false

        local go_on = Trapper:confirm(
            _([[
This will extract comic metadata from comics in the current directory.
Once extraction has started, you can abort at any moment by tapping on the screen.

Standby will be prevented during extraction and may take time.
It's recommended to keep your device plugged in, as this can use some battery power.]]),
            _("Cancel"),
            _("Continue")
        )
        if not go_on then
            return
        end

        -- First ask about subdirectories if they exist
        if has_subdirs then
            recursive = Trapper:confirm(
                _([[
Subfolders detected.
Also extract comic metadata from comics in subdirectories?]]),
                -- @translators Extract comic metadata only for comics in this directory.
                _("Here only"),
                -- @translators Extract comic metadata for comics in this directory as well as in subdirectories.
                _("Here and under")
            )
        end

        -- Then ask about full directory or selection
        local full_directory = Trapper:confirm(
            _([[
Do you want to process the full directory or only a selection of files?]]),
            _("Select files"),
            _("Full directory")
        )

        Trapper:clear()

        if full_directory then
            -- Process entire directory
            self:processDirectory(current_folder, recursive)
        else
            -- Show file selector with files from current and subdirectories if recursive
            self:showFileSelector(current_folder, recursive)
        end
    end)
end

--- Build a map of file paths to their metadata (size and modification time).
---
--- @param comic_files table Array of file paths
--- @return table Map of file_path -> {modification, size}
function ComicMeta:_buildFileMetadataMap(comic_files)
    local metadata_map = {}
    for _, file_path in ipairs(comic_files) do
        local attributes = lfs.attributes(file_path)
        metadata_map[file_path] = {
            modification = (attributes and attributes.modification) or 0,
            size = (attributes and attributes.size) or 0,
        }
    end
    return metadata_map
end

--- Get display label for a sort type and order combination.
---
--- @param sort_type string One of "name", "date", "size"
--- @param sort_order string One of "asc", "desc"
--- @return string Display label with arrow indicator
function ComicMeta:_getSortDisplayLabel(sort_type, sort_order)
    local labels = {
        name_asc = "Name ↑",
        name_desc = "Name ↓",
        date_asc = "Date ↑",
        date_desc = "Date ↓",
        size_asc = "Size ↑",
        size_desc = "Size ↓",
    }
    return labels[sort_type .. "_" .. sort_order] or "Name ↑"
end

--- Compare two files for sorting, with main folder files appearing before subdirectory files.
--- Uses filename as tiebreaker when primary sort values are equal.
---
--- @param file_path_a string First file path
--- @param file_path_b string Second file path
--- @param base_folder string The base folder being scanned
--- @param metadata_map table Map of file paths to their metadata
--- @param sort_type string One of "name", "date", "size"
--- @param sort_order string One of "asc", "desc"
--- @return boolean True if file_a should come before file_b
function ComicMeta:_compareFilesForSort(file_path_a, file_path_b, base_folder, metadata_map, sort_type, sort_order)
    local file_a_in_main_folder = not file_path_a:match("^" .. base_folder .. "/[^/]+/")
    local file_b_in_main_folder = not file_path_b:match("^" .. base_folder .. "/[^/]+/")

    if file_a_in_main_folder and not file_b_in_main_folder then
        return true
    elseif not file_a_in_main_folder and file_b_in_main_folder then
        return false
    end

    local metadata_a = metadata_map[file_path_a] or { modification = 0, size = 0 }
    local metadata_b = metadata_map[file_path_b] or { modification = 0, size = 0 }

    local filename_a = file_path_a:match("([^/]+)$") or ""
    local filename_b = file_path_b:match("([^/]+)$") or ""

    local comparison_result = filename_a:lower() < filename_b:lower()
    local values_are_equal = false

    if sort_type == "date" then
        local modification_time_a = tonumber(metadata_a.modification) or 0
        local modification_time_b = tonumber(metadata_b.modification) or 0

        if modification_time_a == modification_time_b then
            values_are_equal = true
            comparison_result = filename_a:lower() < filename_b:lower()
        else
            comparison_result = modification_time_a < modification_time_b
        end
    elseif sort_type == "size" then
        local file_size_a = tonumber(metadata_a.size) or 0
        local file_size_b = tonumber(metadata_b.size) or 0

        if file_size_a == file_size_b then
            values_are_equal = true
            comparison_result = filename_a:lower() < filename_b:lower()
        else
            comparison_result = file_size_a < file_size_b
        end
    end

    if sort_order == "desc" and not values_are_equal then
        return not comparison_result
    else
        return comparison_result
    end
end

--- Sort comic files in place using the specified sort type and order.
---
--- @param comic_files table Array of file paths to sort (modified in place)
--- @param base_folder string The base folder being scanned
--- @param metadata_map table Map of file paths to their metadata
--- @param sort_type string One of "name", "date", "size"
--- @param sort_order string One of "asc", "desc"
function ComicMeta:_sortComicFiles(comic_files, base_folder, metadata_map, sort_type, sort_order)
    local self_ref = self
    table.sort(comic_files, function(file_a, file_b)
        if file_a == file_b then
            return false
        end
        local success, result = pcall(function()
            return self_ref:_compareFilesForSort(file_a, file_b, base_folder, metadata_map, sort_type, sort_order)
        end)

        if not success or result == nil then
            logger.warn("ComicMeta: Sort comparison failed:", result)
            return file_a < file_b
        end

        return result
    end)
end

--- Build the menu items array for the file selector.
---
--- @param comic_files table Array of file paths
--- @param base_folder string The base folder being scanned
--- @param is_recursive boolean Whether subdirectories are included
--- @param sort_type string Current sort type
--- @param sort_order string Current sort order
--- @return table Array of menu items
function ComicMeta:_buildFileSelectorItems(comic_files, base_folder, is_recursive, sort_type, sort_order)
    local menu_items = {}

    table.insert(menu_items, {
        text = "⚙ Sort: " .. self:_getSortDisplayLabel(sort_type, sort_order),
        is_sort_button = true,
    })

    table.insert(menu_items, {
        text = "────────────────────────",
        is_separator = true,
    })

    for file_index, file_path in ipairs(comic_files) do
        local filename = file_path:match("([^/]+)$")
        local display_text = filename
        if is_recursive then
            local relative_path = file_path:gsub("^" .. base_folder .. "/", "")
            display_text = relative_path
        end

        table.insert(menu_items, {
            text = display_text,
            path = file_path,
            selected = false,
            index = file_index,
        })
    end

    return menu_items
end

--- Extract selected file paths from menu items.
---
--- @param menu_items table Array of menu items
--- @param comic_files table Array of all comic file paths
--- @return table Array of selected file paths
function ComicMeta:_getSelectedFilePaths(menu_items, comic_files)
    local selected_paths = {}
    for _, menu_item in ipairs(menu_items) do
        if menu_item.selected then
            table.insert(selected_paths, comic_files[menu_item.index])
        end
    end
    return selected_paths
end

--- Get display text for a file item, using relative or absolute path as appropriate.
---
--- @param file_path string Full path to the file
--- @param base_folder string The base folder being scanned
--- @param is_recursive boolean Whether subdirectories are included
--- @return string Display text for the file
function ComicMeta:_getFileDisplayText(file_path, base_folder, is_recursive)
    if is_recursive then
        return file_path:gsub("^" .. base_folder .. "/", "")
    else
        return file_path:match("([^/]+)$")
    end
end

--- Toggle selection state for a file item and update its display text.
---
--- @param item table The menu item to toggle
--- @param base_folder string The base folder being scanned
--- @param is_recursive boolean Whether subdirectories are included
function ComicMeta:_toggleFileSelection(item, base_folder, is_recursive)
    item.selected = not item.selected
    local display_text = self:_getFileDisplayText(item.path, base_folder, is_recursive)

    if item.selected then
        item.text = "✓ " .. display_text
    else
        item.text = display_text
    end
end

--- Create the sort dialog with all sort options.
---
--- @param on_sort_selected function Callback receiving (sort_type, sort_order)
--- @return table ButtonDialog widget
function ComicMeta:_createSortDialog(on_sort_selected)
    local ButtonDialog = require("ui/widget/buttondialog")

    local function makeSortCallback(sort_type, sort_order)
        return function()
            on_sort_selected(sort_type, sort_order)
        end
    end

    return ButtonDialog:new{
        title = _("Sort by"),
        buttons = {
            {
                { text = _("Name ↑"), callback = makeSortCallback("name", "asc") },
                { text = _("Name ↓"), callback = makeSortCallback("name", "desc") },
            },
            {
                { text = _("Date ↑"), callback = makeSortCallback("date", "asc") },
                { text = _("Date ↓"), callback = makeSortCallback("date", "desc") },
            },
            {
                { text = _("Size ↑"), callback = makeSortCallback("size", "asc") },
                { text = _("Size ↓"), callback = makeSortCallback("size", "desc") },
            },
        },
    }
end

--- Display the file selector menu for choosing comic files to process.
---
--- @param folder string The folder to scan for comic files
--- @param recursive boolean Whether to include subdirectories
function ComicMeta:showFileSelector(folder, recursive)
    local comic_files = self:scanForComicFiles(folder, recursive)

    if #comic_files == 0 then
        UIManager:show(InfoMessage:new({
            text = _("No comic files (.cbr/.cbz) found"),
        }))
        return
    end

    local metadata_map = self:_buildFileMetadataMap(comic_files)
    local current_sort_type = "name"
    local current_sort_order = "asc"

    self:_sortComicFiles(comic_files, folder, metadata_map, current_sort_type, current_sort_order)
    local file_items = self:_buildFileSelectorItems(comic_files, folder, recursive, current_sort_type, current_sort_order)

    local file_menu
    local self_ref = self

    local function refreshMenuAfterSort()
        file_items = self_ref:_buildFileSelectorItems(comic_files, folder, recursive, current_sort_type, current_sort_order)
        file_menu:switchItemTable(nil, file_items)
    end

    file_menu = Menu:new{
        title = _("Select files"),
        item_table = file_items,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        single_line = true,
        show_path = false,
        title_bar_left_icon = "check",

        onLeftButtonTap = function()
            UIManager:close(file_menu)

            local selected_files = self_ref:_getSelectedFilePaths(file_items, comic_files)

            if #selected_files == 0 then
                UIManager:show(InfoMessage:new({
                    text = _("No file selected"),
                }))
                return
            end

            Trapper:wrap(function()
                Trapper:setPausedText(_("Do you want to abort extraction?"), _("Abort"), _("Don't abort"))
                self_ref:processFiles(selected_files)
            end)
        end,

        onMenuSelect = function(menu, item)
            if item.is_sort_button then
                local sort_dialog
                sort_dialog = self_ref:_createSortDialog(function(sort_type, sort_order)
                    current_sort_type = sort_type
                    current_sort_order = sort_order
                    self_ref:_sortComicFiles(comic_files, folder, metadata_map, current_sort_type, current_sort_order)
                    refreshMenuAfterSort()
                    UIManager:close(sort_dialog)
                end)
                UIManager:show(sort_dialog)
                return
            end

            if item.is_separator then
                return
            end

            self_ref:_toggleFileSelection(item, folder, recursive)
            menu:updateItems()
        end,
    }

    UIManager:show(file_menu)
end
return ComicMeta
