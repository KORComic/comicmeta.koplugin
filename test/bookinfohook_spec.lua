require("test/mocks")

describe("ComicMeta book info hook", function()
    local test_root = "/tmp/comicmeta_hook_test"
    local comic_file = test_root .. "/comic.cbz"
    local BookInfoManager = require("bookinfomanager")
    local ComicMeta = require("main")
    local lfs = require("libs/libkoreader-lfs")
    local original_processFile = ComicMeta.processFile
    local processed_file

    local function writeFile(path, content)
        local f = io.open(path, "w")
        f:write(content)
        f:close()
    end

    before_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
        lfs.mkdir(test_root)
        writeFile(comic_file, "hook comic content")

        G_reader_settings:makeTrue("comicmeta_auto_extraction")
        BookInfoManager.extract_calls = {}

        processed_file = nil
        ComicMeta.processFile = function(_, filepath)
            processed_file = filepath
            return true
        end
    end)

    after_each(function()
        ComicMeta.processFile = original_processFile
    end)

    describe("prepareComicMetadata", function()
        it("extracts metadata for a comic without custom metadata", function()
            ComicMeta:prepareComicMetadata(comic_file)

            assert.are.equal(comic_file, processed_file)
        end)

        it("does nothing when automatic extraction is disabled", function()
            G_reader_settings:makeFalse("comicmeta_auto_extraction")

            ComicMeta:prepareComicMetadata(comic_file)

            assert.is_nil(processed_file)
        end)

        it("ignores files that are not comics", function()
            ComicMeta:prepareComicMetadata(test_root .. "/book.epub")

            assert.is_nil(processed_file)
        end)

        it("skips comics that already have custom metadata", function()
            writeFile(comic_file .. ".custom_metadata", "existing")

            ComicMeta:prepareComicMetadata(comic_file)

            assert.is_nil(processed_file)
        end)
    end)

    describe("hookBookInfoManager", function()
        it("prepares metadata before delegating to the original extraction", function()
            ComicMeta:hookBookInfoManager()

            BookInfoManager:extractBookInfo(comic_file)

            assert.are.equal(comic_file, processed_file)
            assert.are.same({ comic_file }, BookInfoManager.extract_calls)
        end)

        it("does not wrap the original extraction twice", function()
            ComicMeta:hookBookInfoManager()
            ComicMeta:hookBookInfoManager()

            BookInfoManager:extractBookInfo(comic_file)

            assert.are.same({ comic_file }, BookInfoManager.extract_calls)
        end)
    end)
end)
