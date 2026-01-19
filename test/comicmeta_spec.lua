require("test/mocks")

describe("ComicMeta utility functions", function()
    local test_root = "/tmp/comicmeta_test"
    local subdir = test_root .. "/sub"
    local cbz_file = test_root .. "/test.cbz"
    local sub_cbz_file = subdir .. "/subtest.cbz"
    local cbr_file = test_root .. "/test.cbr"
    local sub_cbr_file = subdir .. "/subtest.cbr"
    local ComicMeta = require("main")

    before_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))

        lfs.mkdir(test_root)
        lfs.mkdir(subdir)

        -- Create dummy .cbz files
        local f = io.open(cbz_file, "w")
        f:write("dummy")
        f:close()

        local f2 = io.open(sub_cbz_file, "w")
        f2:write("dummy")
        f2:close()

        -- Create dummy .cbr files
        local f3 = io.open(cbr_file, "w")
        f3:write("dummy")
        f3:close()

        local f4 = io.open(sub_cbr_file, "w")
        f4:write("dummy")
        f4:close()
    end)

    after_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
    end)

    it("scanForComicFiles finds comic files", function()
        local files = ComicMeta:scanForComicFiles(test_root, true)
        local localFiles = ComicMeta:scanForComicFiles(test_root, false)

        assert.equals(4, #files)
        assert.equals(2, #localFiles)
    end)

    it("scanForComicFiles returns empty for folder with no comic files", function()
        os.remove(cbz_file)
        os.remove(sub_cbz_file)
        os.remove(cbr_file)
        os.remove(sub_cbr_file)

        local files = ComicMeta:scanForComicFiles(test_root, true)
        local localFiles = ComicMeta:scanForComicFiles(test_root, false)

        assert.equals(0, #files)
        assert.equals(0, #localFiles)
    end)

    it("hasSubdirectories detects subdirectories", function()
        assert.is_true(ComicMeta:hasSubdirectories(test_root))
        assert.is_false(ComicMeta:hasSubdirectories(subdir))
    end)
end)

describe("ComicMeta._getSortDisplayLabel", function()
    local ComicMeta = require("main")

    it("returns correct label for name ascending", function()
        assert.equals("Name ↑", ComicMeta:_getSortDisplayLabel("name", "asc"))
    end)

    it("returns correct label for name descending", function()
        assert.equals("Name ↓", ComicMeta:_getSortDisplayLabel("name", "desc"))
    end)

    it("returns correct label for date ascending", function()
        assert.equals("Date ↑", ComicMeta:_getSortDisplayLabel("date", "asc"))
    end)

    it("returns correct label for date descending", function()
        assert.equals("Date ↓", ComicMeta:_getSortDisplayLabel("date", "desc"))
    end)

    it("returns correct label for size ascending", function()
        assert.equals("Size ↑", ComicMeta:_getSortDisplayLabel("size", "asc"))
    end)

    it("returns correct label for size descending", function()
        assert.equals("Size ↓", ComicMeta:_getSortDisplayLabel("size", "desc"))
    end)

    it("returns default label for unknown sort type", function()
        assert.equals("Name ↑", ComicMeta:_getSortDisplayLabel("unknown", "asc"))
    end)
end)

describe("ComicMeta._getFileDisplayText", function()
    local ComicMeta = require("main")

    it("returns filename only when not recursive", function()
        local result = ComicMeta:_getFileDisplayText("/base/folder/comic.cbz", "/base/folder", false)
        assert.equals("comic.cbz", result)
    end)

    it("returns relative path when recursive", function()
        local result = ComicMeta:_getFileDisplayText("/base/folder/subdir/comic.cbz", "/base/folder", true)
        assert.equals("subdir/comic.cbz", result)
    end)

    it("returns filename for file in base folder when recursive", function()
        local result = ComicMeta:_getFileDisplayText("/base/folder/comic.cbz", "/base/folder", true)
        assert.equals("comic.cbz", result)
    end)
end)

describe("ComicMeta._compareFilesForSort", function()
    local ComicMeta = require("main")
    local base_folder = "/comics"
    local metadata_map

    before_each(function()
        metadata_map = {
            ["/comics/a.cbz"] = { modification = 1000, size = 100 },
            ["/comics/b.cbz"] = { modification = 2000, size = 200 },
            ["/comics/c.cbz"] = { modification = 1000, size = 100 },
            ["/comics/sub/d.cbz"] = { modification = 3000, size = 300 },
        }
    end)

    it("places main folder files before subdirectory files", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/sub/d.cbz",
            base_folder, metadata_map, "name", "asc"
        )
        assert.is_true(result)
    end)

    it("places subdirectory files after main folder files", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/sub/d.cbz", "/comics/a.cbz",
            base_folder, metadata_map, "name", "asc"
        )
        assert.is_false(result)
    end)

    it("sorts alphabetically ascending by name", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "name", "asc"
        )
        assert.is_true(result)
    end)

    it("sorts alphabetically descending by name", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "name", "desc"
        )
        assert.is_false(result)
    end)

    it("sorts by modification time ascending", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "date", "asc"
        )
        assert.is_true(result)
    end)

    it("sorts by modification time descending", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "date", "desc"
        )
        assert.is_false(result)
    end)

    it("uses filename as tiebreaker when dates are equal", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/c.cbz",
            base_folder, metadata_map, "date", "asc"
        )
        assert.is_true(result)
    end)

    it("sorts by file size ascending", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "size", "asc"
        )
        assert.is_true(result)
    end)

    it("sorts by file size descending", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/a.cbz", "/comics/b.cbz",
            base_folder, metadata_map, "size", "desc"
        )
        assert.is_false(result)
    end)

    it("handles missing metadata gracefully", function()
        local result = ComicMeta:_compareFilesForSort(
            "/comics/unknown.cbz", "/comics/a.cbz",
            base_folder, metadata_map, "size", "asc"
        )
        assert.is_true(result)
    end)
end)

describe("ComicMeta._sortComicFiles", function()
    local ComicMeta = require("main")
    local base_folder = "/comics"
    local metadata_map

    before_each(function()
        metadata_map = {
            ["/comics/c.cbz"] = { modification = 3000, size = 300 },
            ["/comics/a.cbz"] = { modification = 1000, size = 100 },
            ["/comics/b.cbz"] = { modification = 2000, size = 200 },
            ["/comics/sub/d.cbz"] = { modification = 500, size = 50 },
        }
    end)

    it("sorts files by name ascending", function()
        local files = { "/comics/c.cbz", "/comics/a.cbz", "/comics/b.cbz", "/comics/sub/d.cbz" }
        ComicMeta:_sortComicFiles(files, base_folder, metadata_map, "name", "asc")
        assert.same({
            "/comics/a.cbz",
            "/comics/b.cbz",
            "/comics/c.cbz",
            "/comics/sub/d.cbz",
        }, files)
    end)

    it("sorts files by name descending", function()
        local files = { "/comics/c.cbz", "/comics/a.cbz", "/comics/b.cbz", "/comics/sub/d.cbz" }
        ComicMeta:_sortComicFiles(files, base_folder, metadata_map, "name", "desc")
        assert.same({
            "/comics/c.cbz",
            "/comics/b.cbz",
            "/comics/a.cbz",
            "/comics/sub/d.cbz",
        }, files)
    end)

    it("keeps main folder files before subdirectory files", function()
        local files = { "/comics/sub/d.cbz", "/comics/a.cbz" }
        ComicMeta:_sortComicFiles(files, base_folder, metadata_map, "name", "asc")
        assert.equals("/comics/a.cbz", files[1])
        assert.equals("/comics/sub/d.cbz", files[2])
    end)
end)

describe("ComicMeta._buildFileSelectorItems", function()
    local ComicMeta = require("main")

    it("builds menu items with sort button and separator", function()
        local files = { "/comics/a.cbz", "/comics/b.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", false, "name", "asc")

        assert.equals(4, #items)
        assert.is_true(items[1].is_sort_button)
        assert.is_true(items[2].is_separator)
    end)

    it("includes file index in menu items", function()
        local files = { "/comics/a.cbz", "/comics/b.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", false, "name", "asc")

        assert.equals(1, items[3].index)
        assert.equals(2, items[4].index)
    end)

    it("uses filename as display text when not recursive", function()
        local files = { "/comics/a.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", false, "name", "asc")

        assert.equals("a.cbz", items[3].text)
    end)

    it("uses relative path as display text when recursive", function()
        local files = { "/comics/sub/a.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", true, "name", "asc")

        assert.equals("sub/a.cbz", items[3].text)
    end)

    it("initializes items as not selected", function()
        local files = { "/comics/a.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", false, "name", "asc")

        assert.is_false(items[3].selected)
    end)

    it("includes file path in menu items", function()
        local files = { "/comics/a.cbz" }
        local items = ComicMeta:_buildFileSelectorItems(files, "/comics", false, "name", "asc")

        assert.equals("/comics/a.cbz", items[3].path)
    end)
end)

describe("ComicMeta._getSelectedFilePaths", function()
    local ComicMeta = require("main")

    it("returns empty table when no files selected", function()
        local menu_items = {
            { is_sort_button = true },
            { is_separator = true },
            { selected = false, index = 1 },
            { selected = false, index = 2 },
        }
        local files = { "/comics/a.cbz", "/comics/b.cbz" }

        local result = ComicMeta:_getSelectedFilePaths(menu_items, files)
        assert.same({}, result)
    end)

    it("returns selected file paths", function()
        local menu_items = {
            { is_sort_button = true },
            { is_separator = true },
            { selected = true, index = 1 },
            { selected = false, index = 2 },
            { selected = true, index = 3 },
        }
        local files = { "/comics/a.cbz", "/comics/b.cbz", "/comics/c.cbz" }

        local result = ComicMeta:_getSelectedFilePaths(menu_items, files)
        assert.same({ "/comics/a.cbz", "/comics/c.cbz" }, result)
    end)
end)

describe("ComicMeta._toggleFileSelection", function()
    local ComicMeta = require("main")

    it("toggles selection from false to true", function()
        local item = { selected = false, path = "/comics/a.cbz", text = "a.cbz" }
        ComicMeta:_toggleFileSelection(item, "/comics", false)

        assert.is_true(item.selected)
        assert.equals("✓ a.cbz", item.text)
    end)

    it("toggles selection from true to false", function()
        local item = { selected = true, path = "/comics/a.cbz", text = "✓ a.cbz" }
        ComicMeta:_toggleFileSelection(item, "/comics", false)

        assert.is_false(item.selected)
        assert.equals("a.cbz", item.text)
    end)

    it("uses relative path when recursive", function()
        local item = { selected = false, path = "/comics/sub/a.cbz", text = "sub/a.cbz" }
        ComicMeta:_toggleFileSelection(item, "/comics", true)

        assert.is_true(item.selected)
        assert.equals("✓ sub/a.cbz", item.text)
    end)
end)

describe("ComicMeta._buildFileMetadataMap", function()
    local ComicMeta = require("main")
    local test_root = "/tmp/comicmeta_metadata_test"
    local test_file = test_root .. "/test.cbz"

    before_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
        lfs.mkdir(test_root)
        local f = io.open(test_file, "w")
        f:write("dummy content")
        f:close()
    end)

    after_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
    end)

    it("builds metadata map with modification and size", function()
        local files = { test_file }
        local metadata = ComicMeta:_buildFileMetadataMap(files)

        assert.is_table(metadata[test_file])
        assert.is_number(metadata[test_file].modification)
        assert.is_number(metadata[test_file].size)
        assert.equals(13, metadata[test_file].size)
    end)

    it("returns zero values for non-existent files", function()
        local files = { "/nonexistent/file.cbz" }
        local metadata = ComicMeta:_buildFileMetadataMap(files)

        assert.is_table(metadata["/nonexistent/file.cbz"])
        assert.equals(0, metadata["/nonexistent/file.cbz"].modification)
        assert.equals(0, metadata["/nonexistent/file.cbz"].size)
    end)
end)

describe("ComicMeta.writeCustomToC", function()
    local ComicMeta = require("main")

    it("saves correct ToC settings from pages data", function()
        -- Mock doc_settings
        local saved = {}
        local doc_settings = {
            saveSetting = function(_, key, value)
                saved[key] = value
            end,
        }

        -- Example pages_data as parsed from ComicInfo.xml
        local pages_data = {
            Page = {
                { Image = "0", Type = "FrontCover", Bookmark = "Capa" },
                { Image = "1", Type = "Story", Bookmark = "Capítulo 1: Paraíso" },
                { Image = "71", Type = "Story", Bookmark = "Capítulo 2: Pseudo-criaturas" },
                { Image = "112", Type = "Story", Bookmark = "Capítulo 3: Hospedeiros" },
                { Image = "159", Type = "Story", Bookmark = "Capítulo 4: Purgatório" },
            },
        }

        ComicMeta:writeCustomToC(doc_settings, pages_data)

        assert.is_true(saved.handmade_toc_enabled)
        assert.is_false(saved.handmade_toc_edit_enabled)
        assert.is_table(saved.handmade_toc)
        assert.equals(5, #saved.handmade_toc)
        assert.same({ depth = 1, page = 1, title = "Capa" }, saved.handmade_toc[1])
        assert.same({ depth = 1, page = 2, title = "Capítulo 1: Paraíso" }, saved.handmade_toc[2])
        assert.same({ depth = 1, page = 72, title = "Capítulo 2: Pseudo-criaturas" }, saved.handmade_toc[3])
        assert.same({ depth = 1, page = 113, title = "Capítulo 3: Hospedeiros" }, saved.handmade_toc[4])
        assert.same({ depth = 1, page = 160, title = "Capítulo 4: Purgatório" }, saved.handmade_toc[5])
    end)
end)
