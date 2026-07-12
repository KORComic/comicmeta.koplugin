--[[--
Persistent registry of comic files whose metadata has already been extracted.

Stores two maps in a LuaSettings file, following the approach proposed in
upstream issue #39: one map keyed by absolute file path holding size and
modification time for cheap change detection, and one map keyed by partial
MD5 hash so files that were moved or renamed are still recognized.

@module koplugin.ComicMeta.extractionregistry
--]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local REGISTRY_FILENAME = "comicmeta_extraction_registry.lua"

local ExtractionRegistry = {}

--- Create a registry backed by a LuaSettings file.
---
--- @param settings_file_path string Optional path override, defaults to KOReader's settings directory
--- @return table A new ExtractionRegistry instance
function ExtractionRegistry:new(settings_file_path)
    local registry = setmetatable({}, self)
    self.__index = self

    local file_path = settings_file_path or (DataStorage:getSettingsDir() .. "/" .. REGISTRY_FILENAME)
    registry.settings = LuaSettings:open(file_path)
    registry.entries_by_path = registry.settings:readSetting("entries_by_path") or {}
    registry.seen_hashes = registry.settings:readSetting("seen_hashes") or {}

    return registry
end

--- Check whether a file's metadata has already been extracted.
--- A file is considered extracted when its path entry matches size and
--- modification time, or when its content hash was seen before (which
--- covers files that were moved or renamed since extraction).
---
--- @param file_path string Absolute path to the file
--- @return boolean True if the file was already extracted
function ExtractionRegistry:isAlreadyExtracted(file_path)
    local attributes = lfs.attributes(file_path)
    if not attributes then
        return false
    end

    local entry = self.entries_by_path[file_path]
    if entry and entry.size == attributes.size and entry.modification == attributes.modification then
        return true
    end

    local hash = util.partialMD5(file_path)
    if hash and self.seen_hashes[hash] then
        self:_recordEntry(file_path, attributes, hash)
        return true
    end

    return false
end

--- Record a file as extracted and persist the registry.
---
--- @param file_path string Absolute path to the file
function ExtractionRegistry:markExtracted(file_path)
    local attributes = lfs.attributes(file_path)
    if not attributes then
        return
    end

    self:_recordEntry(file_path, attributes, util.partialMD5(file_path))
    self:flush()
end

--- Keep only the files that have not been extracted yet.
---
--- @param file_paths table Array of absolute file paths
--- @return table Array of file paths needing extraction
function ExtractionRegistry:filterNotExtracted(file_paths)
    local files_to_extract = {}
    for _, file_path in ipairs(file_paths) do
        if not self:isAlreadyExtracted(file_path) then
            table.insert(files_to_extract, file_path)
        end
    end
    return files_to_extract
end

--- Persist the registry to its settings file.
function ExtractionRegistry:flush()
    self.settings:saveSetting("entries_by_path", self.entries_by_path)
    self.settings:saveSetting("seen_hashes", self.seen_hashes)
    self.settings:flush()
end

--- Store the path and hash entries for a file.
---
--- @param file_path string Absolute path to the file
--- @param attributes table lfs attributes of the file
--- @param hash string Partial MD5 hash of the file, may be nil
function ExtractionRegistry:_recordEntry(file_path, attributes, hash)
    self.entries_by_path[file_path] = {
        size = attributes.size,
        modification = attributes.modification,
    }
    if hash then
        self.seen_hashes[hash] = true
    end
end

return ExtractionRegistry
