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
