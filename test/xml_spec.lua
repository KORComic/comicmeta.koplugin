local XmlObject = require("lib.comicxml")

describe("xml object", function()
    describe("parse sample", function()
        local xml = [[
    <root>
      <item okay="yes">Hello</item>
      <item okay="no">World</item>
    </root>
    ]]

        local parser = XmlObject:new()
        local root = parser:parse(xml)
        local obj = parser:toTable(root)

        it("should have 2 items", function()
            -- NOTE: this is a hack to pretty print the table :sob:
            -- assert.are.equal(obj, nil)
            assert.are.equal(#obj.item, 2)
        end)
        it("should have text HelloWorld", function()
            assert.are.equal(obj.item[1].text .. obj.item[2].text, "HelloWorld")
        end)
        it("should have attributes okay=yes/no", function()
            assert.are.equal(obj.item[1].okay, "yes")
            assert.are.equal(obj.item[2].okay, "no")
        end)
    end)
end)

describe("xml object with array", function()
    describe("parse sample", function()
        local xml = [[
    <root>
      <items>
        <item okay="yes">Hello</item>
        <item okay="no">World</item>
      </items>
    </root>
    ]]

        local parser = XmlObject:new()
        local root = parser:parse(xml)
        local obj = parser:toTable(root)

        it("should have 2 items", function()
            -- NOTE: this is a hack to pretty print the table :sob:
            -- assert.are.equal(obj, nil)
            assert.is_not_nil(obj.items)
            assert.are.equal(#obj.items.item, 2)
        end)
        it("should have text HelloWorld", function()
            assert.are.equal(obj.items.item[1].text .. obj.items.item[2].text, "HelloWorld")
        end)
        it("should have attributes okay=yes/no", function()
            assert.are.equal(obj.items.item[1].okay, "yes")
            assert.are.equal(obj.items.item[2].okay, "no")
        end)
    end)
end)
