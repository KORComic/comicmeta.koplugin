--[[--
Plugin for KOReader to extract metadata from .cbz files as Custom Metadata

@module koplugin.ComicMeta
--]]
--

local Dispatcher = require("dispatcher") -- luacheck:ignore
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local XmlObject = require("lib.xml")
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

local ZIP_LIST = 'unzip -qql "%1"'
local ZIP_EXTRACT_CONTENT = 'unzip -qqp "%1" "%2"'
local ZIP_EXTRACT_FILE = 'unzip -qqo "%1" "%2" -d "%3"' -- overwrite

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
        callback = self.onComicMeta,
    }
end

function ComicMeta:onComicMeta()
    if not FileManager.instance then
        return
    end

    -- Scan current folder for .cbz files
    local current_folder = FileManager.instance.file_chooser.path
    local cbz_files = {}

    -- Build a list of .cbz files in the current folder
    for file in lfs.dir(current_folder) do
        if file:match("%.cbz$") then
            table.insert(cbz_files, file)
        end
    end

    if #cbz_files > 0 then
        -- For each found .cbz file, extract its metadata from ComicInfo.xml
        for __, file in ipairs(cbz_files) do
            local file_path = ffiUtil.realpath(current_folder .. "/" .. file)
            -- Extract ComicInfo.xml from the .cbz file
            local handle = io.popen(T(ZIP_EXTRACT_CONTENT, file_path, "ComicInfo.xml"))
            local xml_content = nil
            if handle then
                xml_content = handle:read("*a")
                handle:close()
            end

            if xml_content and #xml_content > 0 then
                local parser = XmlObject:new()
                local root = parser:parse(xml_content)
                local comic_metadata = parser:toTable(root)

                logger.dbg("ComicMeta:onComicMeta comic_metadata", comic_metadata)

                -- Parse the XML content and create a metadata table
                local metadata = {
                    title = comic_metadata.Title,
                    authors = comic_metadata.Writer,
                    series = comic_metadata.Series,
                    series_index = comic_metadata.Number,
                    description = comic_metadata.Summary,
                    keywords = comic_metadata.Tags,
                    language = comic_metadata.LanguageISO,
                }

                logger.dbg("ComicMeta:onComicMeta metadata", metadata)

                -- Fixup metadata
                for key, value in pairs(metadata) do
                    if key == "title" then
                        metadata[key] = util.htmlEntitiesToUtf8(value)
                    elseif key == "authors" then
                        metadata[key] = util.htmlEntitiesToUtf8(value)
                    elseif key == "series" then
                        metadata[key] = util.htmlEntitiesToUtf8(value)
                    elseif key == "series_index" then
                        metadata[key] = util.htmlEntitiesToUtf8(value)
                    elseif key == "description" then
                        metadata[key] = util.htmlEntitiesToUtf8(value)
                    elseif key == "keywords" then
                        local out = ""
                        local values = util.splitToArray(value, ',', false)
                        for __, val in ipairs(values) do
                            if #out > 0 then
                                out = out .. "\n"
                            end
                            out = out .. util.htmlEntitiesToUtf8(util.trim(val))
                        end

                        metadata[key] = out
                    end
                end

                -- Retrieve current metadata
                local doc_settings = DocSettings.openSettingsFile(file_path)
                if not doc_settings then
                    UIManager:show(InfoMessage:new({
                        text = _("Failed to open DocSettings for file: ") .. file,
                    }))
                    return
                end

                -- Read the existing doc_props property
                local doc_props = doc_settings:readSetting("doc_props") or {}
                local original_doc_props = {}
                for key, __ in pairs(metadata) do
                    original_doc_props[key] = doc_props[key] or ""
                end
                doc_settings:saveSetting("doc_props", original_doc_props)

                -- Update the custom properties with the new metadata
                for key, value in pairs(metadata) do
                    doc_props[key] = value
                end

                -- Write the updated doc_props property back to the DocSettings
                doc_settings:saveSetting("custom_props", doc_props)

                -- Save the updated metadata back to the metadata file
                doc_settings:flushCustomMetadata(file_path)

                -- Update the book info in the file manager
                UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file_path))
                UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
            end
        end
    end
end

return ComicMeta
