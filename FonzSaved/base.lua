FonzSaved = {}
local A = FonzSaved

local LI = FonzSaved_LocaleInfo
A.locale_info = LI

A.locale = setmetatable({}, { 
  __index = function(tab, key)
              -- Search for catalog by locale code and find key entry
              local catalog = LI.catalogs[LI.code] or LI.catalogs["enUS"]
              local value = catalog[key]
              
              -- Boolean true implies untranslated key. Use string key as value
              if value == true then
                return tostring(key)
              -- Any other truthful value means a non-nil value.
              elseif value then
                return value
              -- Boolean false not allowed as a value.
              elseif value == false then
                A.warn("Invalid locale value ('false'): [%s]", tostring(key))
              end
              
              -- Cache unknown keys as their string value and warn during 
              -- development.
              value = tostring(key)
              rawset(tab, key, value)
              if A.debug then A.debug("Unknown locale item: [%s]", value) end
              
              return value
            end
})

A.name = "FonzSaved"
A.folder_name = A.name
A.version = GetAddOnMetadata(A.folder_name, "Version")
A.addon_path = [[Interface\AddOns\]] .. A.folder_name