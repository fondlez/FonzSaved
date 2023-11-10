FonzSavedFu = Rock:NewAddon("FonzSavedFu", "LibRockDB-1.0", "LibRockConfig-1.0", 
  "LibFuBarPlugin-3.0")
local A = FonzSavedFu

-- Import local data
local LI = FonzSavedFu_LocaleInfo
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
A.path = function(subpath)
  local addonPath = [[Interface\AddOns\]] .. A.name
  if not subpath then return addonPath end
  
  return format("%s%s", addonPath, subpath)
end

-- Saved variables registered
A:SetDatabase("FonzSavedFuDB")