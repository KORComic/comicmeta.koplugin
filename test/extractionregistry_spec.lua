require("test/mocks")

describe("ExtractionRegistry", function()
    local test_root = "/tmp/comicmeta_registry_test"
    local registry_file = test_root .. "/registry.lua"
    local comic_file = test_root .. "/comic.cbz"
    local ExtractionRegistry = require("extractionregistry")
    local lfs = require("libs/libkoreader-lfs")

    local function writeFile(path, content)
        local f = io.open(path, "w")
        f:write(content)
        f:close()
    end

    before_each(function()
        os.execute("rm -rf " .. string.format("%q", test_root))
        lfs.mkdir(test_root)
        writeFile(comic_file, "comic content A")
    end)

    it("reports a never-seen file as not extracted", function()
        local registry = ExtractionRegistry:new(registry_file)

        assert.is_false(registry:isAlreadyExtracted(comic_file))
    end)

    it("reports a missing file as not extracted", function()
        local registry = ExtractionRegistry:new(registry_file)

        assert.is_false(registry:isAlreadyExtracted(test_root .. "/missing.cbz"))
    end)

    it("reports a file as extracted after marking it", function()
        local registry = ExtractionRegistry:new(registry_file)

        registry:markExtracted(comic_file)

        assert.is_true(registry:isAlreadyExtracted(comic_file))
    end)

    it("recognizes a moved file through its content hash", function()
        local registry = ExtractionRegistry:new(registry_file)
        registry:markExtracted(comic_file)

        local moved_file = test_root .. "/renamed.cbz"
        os.rename(comic_file, moved_file)

        assert.is_true(registry:isAlreadyExtracted(moved_file))
    end)

    it("reports a modified file as not extracted", function()
        local registry = ExtractionRegistry:new(registry_file)
        registry:markExtracted(comic_file)

        writeFile(comic_file, "comic content B, now with different size")

        assert.is_false(registry:isAlreadyExtracted(comic_file))
    end)

    it("persists extractions across registry instances", function()
        local first_registry = ExtractionRegistry:new(registry_file)
        first_registry:markExtracted(comic_file)

        local second_registry = ExtractionRegistry:new(registry_file)

        assert.is_true(second_registry:isAlreadyExtracted(comic_file))
    end)

    it("keeps only files needing extraction when filtering", function()
        local registry = ExtractionRegistry:new(registry_file)
        local new_file = test_root .. "/new.cbz"
        writeFile(new_file, "comic content C")
        registry:markExtracted(comic_file)

        local files_to_extract = registry:filterNotExtracted({ comic_file, new_file })

        assert.are.same({ new_file }, files_to_extract)
    end)
end)
