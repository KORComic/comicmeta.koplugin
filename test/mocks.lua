-- Mocks for KOReader modules
package.preload["libs/libkoreader-lfs"] = function()
    return {
        dir = function(path)
            -- Returns an iterator over files and directories in the path
            local files = {}
            local handle = io.popen(string.format("ls -A %q", path))
            if handle then
                for entry in handle:lines() do
                    table.insert(files, entry)
                end
                handle:close()
            end
            local i = 0
            return function()
                i = i + 1
                return files[i]
            end
        end,
        attributes = function(path)
            local function modificationTime()
                local stat = io.popen(string.format("stat -c %%Y %q 2>/dev/null || stat -f %%m %q", path, path))
                if not stat then
                    return os.time()
                end
                local mtime = tonumber(stat:read("*l"))
                stat:close()
                return mtime or os.time()
            end
            local handle =
                io.popen(string.format('test -d %q && echo "directory" || test -f %q && echo "file"', path, path))
            if handle then
                local result = handle:read("*l")
                handle:close()
                if result == "directory" then
                    return { mode = "directory", modification = modificationTime(), size = 0 }
                elseif result == "file" then
                    local f = io.open(path, "rb")
                    local size = 0
                    if f then
                        size = f:seek("end") or 0
                        f:close()
                    end
                    return { mode = "file", modification = modificationTime(), size = size }
                end
            end
            return nil
        end,
        mkdir = function(path)
            os.execute(string.format("mkdir -p %q", path))
            return true
        end,
    }
end
package.preload["ui/trapper"] = function()
    return {
        info = function()
            return {}
        end,
        confirm = function()
            return {}
        end,
        clear = function()
            return {}
        end,
        wrap = function(_, func)
            return func()
        end,
        dismissableRunInSubprocess = function()
            return true
        end,
        setPausedText = function() end,
    }
end
package.preload["dispatcher"] = function()
    return { registerAction = function() end }
end
package.preload["docsettings"] = function()
    return {
        openSettingsFile = function()
            return {
                readSetting = function()
                    return {}
                end,
                saveSetting = function() end,
                flushCustomMetadata = function() end,
            }
        end,
    }
end
package.preload["ui/event"] = function()
    return {
        new = function()
            return {}
        end,
    }
end
package.preload["apps/filemanager/filemanager"] = function()
    return {
        instance = {
            file_chooser = { path = "/tmp/comicmeta_test" },
        },
    }
end
package.preload["ui/widget/infomessage"] = function()
    return {
        new = function()
            return {}
        end,
    }
end
package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        broadcastEvent = function() end,
    }
end
package.preload["ui/widget/container/widgetcontainer"] = function()
    local mt = {}
    mt.__index = mt
    function mt:extend(tbl)
        setmetatable(tbl, self)
        return tbl
    end
    return setmetatable({}, mt)
end
package.preload["ffi/util"] = function()
    return {
        template = function(str, ...)
            return str
        end,
        realpath = function(path)
            return path
        end,
    }
end
package.preload["logger"] = function()
    return {
        dbg = function(...) end,
        warn = function(...) end,
        err = function(...) end,
    }
end
package.preload["util"] = function()
    return {
        splitToArray = function(str, sep, _)
            return {}
        end,
        htmlEntitiesToUtf8 = function(str)
            return str
        end,
        trim = function(str)
            return str
        end,
        partialMD5 = function(filepath)
            if not filepath then
                return nil
            end
            local file = io.open(filepath, "rb")
            if not file then
                return nil
            end
            local content = file:read("*a")
            file:close()
            return "fakemd5:" .. content
        end,
    }
end
package.preload["luasettings"] = function()
    local stores = {}
    return {
        open = function(_, file_path)
            stores[file_path] = stores[file_path] or {}
            local data = stores[file_path]
            return {
                readSetting = function(_, key)
                    return data[key]
                end,
                saveSetting = function(_, key, value)
                    data[key] = value
                end,
                flush = function() end,
            }
        end,
    }
end
package.preload["datastorage"] = function()
    return {
        getSettingsDir = function()
            return "/tmp/comicmeta_test_settings"
        end,
    }
end
package.preload["gettext"] = function()
    return function(str)
        return str
    end
end
G_reader_settings = {
    data = {},
    isTrue = function(self, key)
        return self.data[key] == true
    end,
    toggle = function(self, key)
        self.data[key] = not self.data[key]
    end,
    makeTrue = function(self, key)
        self.data[key] = true
    end,
    makeFalse = function(self, key)
        self.data[key] = false
    end,
}
package.preload["ffi/archiver"] = function() end
package.preload["ui/widget/menu"] = function()
    return {
        new = function(self, args)
            return args
        end,
    }
end
package.preload["device"] = function()
    return {
        screen = {
            getWidth = function()
                return 800
            end,
            getHeight = function()
                return 600
            end,
        },
    }
end
package.preload["ui/widget/buttondialog"] = function()
    return {
        new = function(self, args)
            return args
        end,
    }
end
