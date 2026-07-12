require("test/mocks")

describe("ComicMeta automatic extraction", function()
    local test_root = "/tmp/comicmeta_auto_test"
    local comic_file = test_root .. "/comic.cbz"
    local ComicMeta = require("main")
    local ExtractionRegistry = require("extractionregistry")
    local lfs = require("libs/libkoreader-lfs")
    local original_processFiles = ComicMeta.processFiles
    local registry_counter = 0
    local processed_files

    local function writeFile(path, content)
        local f = io.open(path, "w")
        f:write(content)
        f:close()
    end

    local function recordProcessedFiles(_, files)
        processed_files = files
    end

    before_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
        lfs.mkdir(test_root)
        writeFile(comic_file, "auto comic content")

        registry_counter = registry_counter + 1
        ComicMeta.extraction_registry = ExtractionRegistry:new(test_root .. "/registry_" .. registry_counter)
        ComicMeta.auto_extraction_running = nil
        G_reader_settings:makeFalse("comicmeta_auto_extraction")

        processed_files = nil
        ComicMeta.processFiles = recordProcessedFiles
    end)

    after_each(function()
        ComicMeta.processFiles = original_processFiles
    end)

    it("does nothing when auto extraction is disabled", function()
        ComicMeta:onPathChanged(test_root)

        assert.is_nil(processed_files)
    end)

    it("processes new comics when entering a folder", function()
        G_reader_settings:makeTrue("comicmeta_auto_extraction")

        ComicMeta:onPathChanged(test_root)

        assert.are.same({ comic_file }, processed_files)
    end)

    it("skips comics already extracted", function()
        G_reader_settings:makeTrue("comicmeta_auto_extraction")
        ComicMeta.extraction_registry:markExtracted(comic_file)

        ComicMeta:onPathChanged(test_root)

        assert.is_nil(processed_files)
    end)

    it("does nothing while an automatic extraction is running", function()
        G_reader_settings:makeTrue("comicmeta_auto_extraction")
        ComicMeta.auto_extraction_running = true

        ComicMeta:onPathChanged(test_root)

        assert.is_nil(processed_files)
    end)

    it("processes only new files when a directory scan skips extracted ones", function()
        local new_file = test_root .. "/new.cbz"
        writeFile(new_file, "new comic content")
        ComicMeta.extraction_registry:markExtracted(comic_file)

        ComicMeta:processDirectory(test_root, false, true)

        assert.are.same({ new_file }, processed_files)
    end)

    it("processes every file when a directory scan rescans all", function()
        local new_file = test_root .. "/new.cbz"
        writeFile(new_file, "new comic content")
        ComicMeta.extraction_registry:markExtracted(comic_file)

        ComicMeta:processDirectory(test_root, false, false)

        assert.are.same({ comic_file, new_file }, processed_files)
    end)

    it("marks files as extracted after processing them", function()
        ComicMeta.processFiles = original_processFiles

        ComicMeta:processFiles({ comic_file })

        assert.is_true(ComicMeta.extraction_registry:isAlreadyExtracted(comic_file))
    end)
end)
