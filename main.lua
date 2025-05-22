--[[--
Plugin for KOReader to extract metadata from .cbz files as Custom Metadata

@module koplugin.ComicMeta
--]]--

local Event = require("ui/event")
local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local FileManager = require("apps/filemanager/filemanager")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local ComicMeta = WidgetContainer:extend{
    name = "comicmeta",
    is_doc_only = false,
}

local ZIP_LIST            = "unzip -qql \"%1\""
local ZIP_EXTRACT_CONTENT = "unzip -qqp \"%1\" \"%2\""
local ZIP_EXTRACT_FILE    = "unzip -qqo \"%1\" \"%2\" -d \"%3\"" -- overwrite



function ComicMeta:onDispatcherRegisterActions()
    Dispatcher:registerAction("comicmeta_action", {category="none", event="ComicMeta", title=_("Get Comic Meta"), general=true,})
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
        for dummy, file in ipairs(cbz_files) do
            local file_path = ffiUtil.realpath(current_folder .. "/" .. file)
            -- Make sure we have a sidecar file (Lua has no continue.. so we get another nested if, yay -_-)
            if DocSettings:hasSidecarFile(file_path) then
                -- Extract ComicInfo.xml from the .cbz file
                local handle = io.popen(T(ZIP_EXTRACT_CONTENT, file_path, "ComicInfo.xml"))
                local xml_content = nil
                if handle then
                    xml_content = handle:read("*a")
                    handle:close()
                end

                if xml_content and #xml_content > 0 then
                    -- Parse the XML content and create a metadata table
                    local metadata = {
                        title = xml_content:match("<Title>(.-)</Title>"),
                        authors = xml_content:match("<Writer>(.-)</Writer>"),
                        series = xml_content:match("<Series>(.-)</Series>"),
                        series_index = xml_content:match("<Number>(.-)</Number>"),
                        description = xml_content:match("<Summary>(.-)</Summary>"),
                    }

                    -- Fixup metadata
                    for key, value in pairs(metadata) do
                        if key == "title" then
                            metadata[key] = util.htmlEntitiesToUtf8(value)
                        elseif key == "authors" then
                                metadata[key] = util.htmlEntitiesToUtf8(value)
                        elseif key == "series" then
                            metadata[key] = util.htmlEntitiesToUtf8(value)
                        elseif key == "series_index" then
                            metadata[key] = tonumber(util.htmlEntitiesToUtf8(value))
                        elseif key == "description" then
                            -- Description may (often in EPUB, but not always) or may not (rarely in PDF) be HTML
                            metadata[key] = util.htmlToPlainTextIfHtml(util.htmlEntitiesToUtf8(value))
                        end
                    end

                    -- Retrieve current metadata
                    local doc_settings = DocSettings:openSettingsFile(file_path)
                    if not doc_settings then
                        UIManager:show(InfoMessage:new{
                            text = _("Failed to open DocSettings for file: ") .. file,
                        })
                        return
                    end

                    -- Read the existing doc_props property
                    local doc_props = doc_settings:readSetting("doc_props") or {}
                    doc_settings:saveSetting("doc_props", {
                        title = doc_props.title or "",
                        authors = doc_props.authors or "",
                        series = doc_props.series or "",
                        series_index = doc_props.series_index or "",
                        description = doc_props.description or "",
                    })

                    -- Update the custom properties with the new metadata
                    for key, value in pairs(metadata) do
                        doc_props[key] = value
                    end

                    -- Write the updated doc_props property back to the DocSettings
                    doc_settings:saveSetting("custom_props", doc_props)

                    -- Save the updated metadata back to the metadata file
                    doc_settings:flushCustomMetadata(file_path)
                    doc_settings:close()

                    -- Update the book info in the file manager
                    UIManager:broadcastEvent(Event:new("BookInfoChanged", file_path))
                    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", file_path))
                    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
                end
            end
        end
    end
end

return ComicMeta
