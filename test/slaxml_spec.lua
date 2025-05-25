local SLAXML = require("third_party.slaxml.slaxml")

describe("slaxml XML Parsing", function()
    local itemContents

    before_each(function()
        itemContents = {}
        local currentElement = nil
        local currentAttributes = {}

        local parser = SLAXML:parser({
            startElement = function(name, nsURI, nsPrefix)
                currentElement = name
            end,

            attribute = function(name, value, nsURI, nsPrefix)
                currentAttributes[name] = value
            end,

            closeElement = function(name)
                currentElement = nil
                currentAttributes = {}
            end,

            text = function(text)
                text = text:match("^%s*(.-)%s*$")
                if currentElement == "item" and text ~= "" then
                    table.insert(itemContents, {
                        text = text,
                        attrs = currentAttributes,
                    })
                end
            end,
        })

        local xml = [[
    <root>
      <item okay="yes">Hello</item>
      <item okay="no">World</item>
    </root>
    ]]
        parser:parse(xml)
    end)

    it("parses two <item> elements", function()
        assert.are.equal(2, #itemContents)
    end)

    it("parses correct text content", function()
        assert.are.equal("Hello", itemContents[1].text)
        assert.are.equal("World", itemContents[2].text)
    end)

    it("parses attributes correctly", function()
        -- NOTE: this is a hack to pretty print the table :sob:
        -- assert.are.same(itemContents, nil)
        assert.are.equal("yes", itemContents[1].attrs.okay)
        assert.are.equal("no", itemContents[2].attrs.okay)
    end)
end)
