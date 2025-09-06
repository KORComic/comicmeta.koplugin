local SLAXML = require("third_party.slaxml.slaxml")

local XmlObject = {}
XmlObject.__index = XmlObject

function XmlObject:new()
    local o = {
        root = nil,
        stack = {},
    }
    setmetatable(o, self)
    return o
end

-- Parses XML string into Lua table object
function XmlObject:parse(xml)
    local currentNode = {}

    local parser = SLAXML:parser({
        startElement = function(name, nsURI, nsPrefix)
            local node = {
                _name = name,
                _children = {},
                _text = "",
                _attr = {},
            }

            if not self.root then
                self.root = node
            else
                -- Add this node as child of currentNode
                table.insert(currentNode._children, node)
            end

            -- Push current node on stack and update currentNode
            table.insert(self.stack, node)
            currentNode = node
        end,

        attribute = function(name, value, nsURI, nsPrefix)
            if currentNode then
                if currentNode._attr then
                    currentNode._attr[name] = value
                else
                    currentNode._attr = {}
                    currentNode._attr[name] = value
                end
            end
        end,

        text = function(text)
            if currentNode then
                if currentNode._text then
                    currentNode._text = currentNode._text .. text
                else
                    currentNode._text = text
                end
            end
        end,

        closeElement = function(name)
            currentNode = table.remove(self.stack)
            currentNode = self.stack[#self.stack] -- parent node or nil if closed root
        end,
    })

    parser:parse(xml)
    return self.root
end

-- Helper: converts parsed tree to a cleaner table
-- Children with unique names become keys; multiple children same name become arrays
function XmlObject:toTable(node)
    if not node then
        return nil
    end

    local obj = {}

    -- Merge attributes first
    for k, v in pairs(node._attr) do
        obj[k] = v
    end

    -- Process children
    local childrenByName = {}
    for _, child in ipairs(node._children) do
        childrenByName[child._name] = childrenByName[child._name] or {}
        table.insert(childrenByName[child._name], self:toTable(child))
    end

    for name, list in pairs(childrenByName) do
        if #list == 1 then
            obj[name] = list[1]
        else
            obj[name] = list
        end
    end

    -- Add text if present and no children or attributes
    local text = node._text:match("^%s*(.-)%s*$")
    if text ~= "" then
        if next(obj) == nil then
            return text
        else
            obj["text"] = text
        end
    end

    return obj
end

return XmlObject
