require("test/mocks")

describe("ComicMeta utility functions", function()
    local test_root = "/tmp/comicmeta_test"
    local subdir = test_root .. "/sub"
    local cbz_file = test_root .. "/test.cbz"
    local sub_cbz_file = subdir .. "/subtest.cbz"
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
    end)

    after_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
    end)

    it("scanCbzFilesRecursive finds .cbz files recursively", function()
        local files = ComicMeta:scanCbzFilesRecursive(test_root)

        assert.equals(2, #files)
    end)

    it("scanCbzFilesRecursive returns empty for folder with no .cbz files", function()
        os.remove(cbz_file)
        os.remove(sub_cbz_file)

        local files = ComicMeta:scanCbzFilesRecursive(test_root)

        assert.equals(0, #files)
    end)

    it("hasSubdirectories detects subdirectories", function()
        assert.is_true(ComicMeta:hasSubdirectories(test_root))
        assert.is_false(ComicMeta:hasSubdirectories(subdir))
    end)
end)
