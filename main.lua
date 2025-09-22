--[[--
Plugin for KOReader to extract metadata from .cbz files as Custom Metadata

@module koplugin.ComicMeta
--]]
--
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/?.lua"
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/lib/?.lua"
package.path = package.path .. ";plugins/comicmeta.koplugin/lib/comiclib/third_party/?/?.lua"

local ComicLib = require("comiclib")
local ConfirmBox = require("ui/widget/confirmbox")
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

function ComicMeta:onDispatcherRegisterActions()
    Dispatcher:registerAction(
        "comicmeta_action",
        { category = "none", event = "ComicMeta", title = _("Get Comic Meta"), general = true }
    )
end

function ComicMeta:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

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

function ComicMeta:processFile(cbz_file)
    local comicInfo, ok = ComicLib.ComicInfo:new(cbz_file)
    if not ok or comicInfo == nil then
        UIManager:show(InfoMessage:new({
            text = T(_("Failed to open CBZ file: {file}"), { file = cbz_file }),
        }))

        return
    end

    logger.dbg("ComicMeta -> processFile comic_metadata", comicInfo.metadata)

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
    local custom_doc_settings = DocSettings.openSettingsFile(cbz_file)
    local doc_settings = DocSettings:open(cbz_file)
    if not custom_doc_settings or not doc_settings then
        UIManager:show(InfoMessage:new({
            text = _("Failed to open DocSettings for file: ") .. cbz_file,
        }))
        return
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
    custom_doc_settings:flushCustomMetadata(cbz_file)
    doc_settings:flush()

    -- Update the book info in the file manager
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", cbz_file))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
end

--- Recursively scans a folder and returns a list of all .cbz files found.
---
-- @param folder string: The folder to scan.
-- @return table: List of .cbz file paths.
function ComicMeta:scanCbzFilesRecursive(folder)
    logger.dbg("ComicMeta -> scanCbzFilesRecursive scanning folder", folder)

    local cbz_files = {}

    for entry in lfs.dir(folder) do
        if entry ~= "." and entry ~= ".." then
            local full_path = folder .. "/" .. entry
            local attr = lfs.attributes(full_path)

            if attr and attr.mode == "directory" and not entry:match("%.sdr$") then
                logger.dbg("ComicMeta -> scanCbzFilesRecursive entering subdirectory", full_path)

                local sub_cbz = self:scanCbzFilesRecursive(full_path)

                for _, f in ipairs(sub_cbz) do
                    table.insert(cbz_files, f)
                end
            elseif attr and attr.mode == "file" and entry:match("%.cbz$") then
                logger.dbg("ComicMeta -> scanCbzFilesRecursive found cbz file", full_path)

                table.insert(cbz_files, full_path)
            end
        end
    end

    if #cbz_files == 0 then
        logger.dbg("ComicMeta -> scanCbzFilesRecursive no cbz files found")
    end

    return cbz_files
end

--- Checks if a folder contains any subdirectories.
---
-- @param folder string: The folder to check.
-- @return boolean: True if subdirectories exist, false otherwise.
function ComicMeta:hasSubdirectories(folder)
    logger.dbg("ComicMeta -> hasSubdirectories checking folder", folder)

    for entry in lfs.dir(folder) do
        if entry ~= "." and entry ~= ".." then
            local attr = lfs.attributes(folder .. "/" .. entry)

            if attr and attr.mode == "directory" and not entry:match("%.sdr$") then
                logger.dbg("ComicMeta -> hasSubdirectories found subdirectory", entry)
                return true
            end
        end
    end

    logger.dbg("ComicMeta -> hasSubdirectories no subdirectories found")

    return false
end

--- Processes all .cbz files in a folder, optionally recursively.
---
-- @param folder string: The folder to process.
-- @param recursive boolean: Whether to process subfolders recursively.
function ComicMeta:processAllCbz(folder, recursive)
    logger.dbg("ComicMeta -> processAllCbz processing folder", folder, "recursive:", recursive)

    local cbz_files = {}

    if recursive then
        cbz_files = self:scanCbzFilesRecursive(folder)
    else
        for file in lfs.dir(folder) do
            if file ~= "." and file ~= ".." then
                local attr = lfs.attributes(folder .. "/" .. file)

                if attr and attr.mode == "file" and file:match("%.cbz$") then
                    logger.dbg("ComicMeta -> processAllCbz found cbz file", file)

                    table.insert(cbz_files, folder .. "/" .. file)
                end
            end
        end
    end

    if #cbz_files == 0 then
        logger.dbg("ComicMeta -> processAllCbz no cbz files found")

        return
    end

    logger.dbg("ComicMeta -> processAllCbz found", #cbz_files, ".cbz files to process")

    for __, file_path in ipairs(cbz_files) do
        local real_path = ffiUtil.realpath(file_path)

        logger.dbg("ComicMeta -> processAllCbz processing file", real_path)

        self:processFile(real_path)
    end
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

function ComicMeta:onComicMeta()
    if not FileManager.instance then
        return
    end

    local current_folder = FileManager.instance.file_chooser.path
    local has_subdirs = self:hasSubdirectories(current_folder)

    if not has_subdirs then
        self:processAllCbz(current_folder, false)

        return
    end

    UIManager:show(ConfirmBox:new({
        text = _("Subfolders detected. Process all .cbz files recursively?"),
        cancel_text = _("No"),
        cancel_callback = function()
            self:processAllCbz(current_folder, false)
        end,
        ok_text = _("Yes"),
        ok_callback = function()
            self:processAllCbz(current_folder, true)
        end,
    }))
end

return ComicMeta
