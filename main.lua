--[[--
Plugin for KOReader to extract metadata from comic (.cbz and .cbr) files as Custom Metadata

@module koplugin.ComicMeta
--]]
--
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/?.lua"
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/lib/?.lua"
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/third_party/?/?.lua"

local ComicLib = require("comiclib")
local Trapper = require("ui/trapper")
local Dispatcher = require("dispatcher") -- luacheck:ignore
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local T = ffiUtil.template
local _ = require("gettext")

local ComicMeta = WidgetContainer:extend({
    name = "comicmeta",
    is_doc_only = false,
})

--- Register our plugin setting
function ComicMeta:onDispatcherRegisterActions()
    Dispatcher:registerAction(
        "comicmeta_action",
        { category = "none", event = "ComicMeta", title = _("Get Comic Meta"), general = true }
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
        text = _("Get Comic Meta"),
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

    self:writeCustomToC(doc_settings, comicInfo.metadata.Pages)

    -- Save the updated metadata back to the metadata file
    custom_doc_settings:flushCustomMetadata(comic_file)
    doc_settings:flush()

    -- Update the book info in the file manager
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", comic_file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))

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
            if entry:match("%.sdr$") then -- Skip sidecar folders
                goto continue
            end

            logger.dbg("ComicMeta -> scanForComicFiles entering subdirectory", full_path)

            local sub_comic_files = self:scanForComicFiles(full_path, recursive)

            for _, f in ipairs(sub_comic_files) do
                table.insert(comic_files, f)
            end
        elseif attr.mode == "file" and (entry:match("%.cbz$") or entry:match("%.cbr$")) then
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

        if attr and attr.mode == "directory" and not entry:match("%.sdr$") then
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
function ComicMeta:processAllComics(folder, recursive)
    logger.dbg("ComicMeta -> processAllComics processing folder", folder, "recursive:", recursive)

    Trapper:setPausedText(_("Do you want to abort extraction?"), _("Abort"), _("Don't abort"))

    local doNotAbort = Trapper:info(_("Scanning for comics..."))
    if not doNotAbort then
        Trapper:clear()
        return
    end
    ffiUtil.sleep(2) -- Pause so that the user can see it

    local comic_files = self:scanForComicFiles(folder, recursive)

    if #comic_files == 0 then
        logger.dbg("ComicMeta -> processAllComics no comic files found")
        Trapper:info(_("No comics found."))
        return
    end

    logger.dbg("ComicMeta -> processAllComics found", #comic_files, "comic files to process")

    local successes = 0

    for idx, file_path in ipairs(comic_files) do
        local real_path = ffiUtil.realpath(file_path)

        logger.dbg("ComicMeta -> processAllComics processing file", real_path)
        doNotAbort = Trapper:info(T(_([[
Extracting metadata...
%1 / %2]]), idx, #comic_files), true)
        if not doNotAbort then
            Trapper:clear()
            return
        end

        local complete, success = Trapper:dismissableRunInSubprocess(function()
            return self:processFile(real_path)
        end)
        if complete and success then
            successes = successes + 1
        end
    end

    Trapper:clear()
    UIManager:show(InfoMessage:new{ text =  T(_([[
Comic metadata extraction complete.
Successfully extracted %1 / %2]]), successes, #comic_files) })
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
function ComicMeta:writeCustomToC(doc_settings, pages_data)
    if not pages_data or not pages_data.Page then
        logger.dbg("ComicMeta -> writeCustomToC: No pages data found")

        return
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
        return
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

    Trapper:wrap(function ()
        local has_subdirs = self:hasSubdirectories(current_folder)
        local recursive = false

        local go_on = Trapper:confirm(_([[
This will extract comic metadata from comics in the current directory.
Once extraction has started, you can abort at any moment by tapping on the screen.

This extraction may take time and use some battery power: you may wish to keep your device plugged in.]]
        ), _("Cancel"), _("Continue"))
        if not go_on then
            return
        end

        if has_subdirs then
            recursive = Trapper:confirm(_([[
Subfolders detected.
Also extract comic metadata from comics in subdirectories?]]
        ),
            -- @translators Extract comic metadata only for comics in this directory.
            _("Here only"),
            -- @translators Extract comic metadata for comics in this directory as well as in subdirectories.
            _("Here and under"))
        end

        Trapper:clear()

        self:processAllComics(current_folder, recursive)
    end)
end

return ComicMeta
