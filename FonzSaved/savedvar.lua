local A = FonzSaved

-- Namespaces are tables in the character saved variable.
A.namespaces = {}

-- Profiles are tables in the account saved variable with a realm-character 
-- structure.
A.profiles = {}

-- Charless contains tables in the account saved variable within a realm but
-- not belonging to a specific character.
A.charless = {}

--------------------------------------------------------------------------------
-- Character Configuration
--------------------------------------------------------------------------------

function A.registerCharConfigDefaults(name, defaults)
  A.namespaces[name] = A.namespaces[name] or {}
  local module = A.namespaces[name]
  
  if not defaults or type(defaults) ~= "table" then 
    A.warn("Table data expected for character variable config defaults.")
  end
  
  module["defaults"] = defaults or {}
end

function A.getCharConfigDefaults(name)
  if not A.namespaces[name] then return end
  return A.namespaces[name]["defaults"]
end

function A.setCharConfigDefaults()
  -- Get character saved variable
  local _G = getfenv(0)
  local svar_name = A.name .. "CDB"
  if not _G[svar_name] then
    _G[svar_name] = {}
  end
  local saved_variable = _G[svar_name]
  
  -- Ensure a toplevel subtable exists
  saved_variable["namespaces"] = saved_variable["namespaces"] or {}
  local namespaces = saved_variable["namespaces"]
  
  -- Update namespaces with any missing defaults
  local found = false
  for name, module in pairs(A.namespaces) do
    namespaces[name] = namespaces[name] or {}
    local namespace = namespaces[name]
    
    local defaults = module["defaults"]
    for k, v in pairs(defaults) do
      if not namespace[k] then
        namespace[k] = v
        found = true
      end
    end
  end
  if found then
    A.info("Saved character variable: defaults set.")
  end
end

function A.getCharConfig(name)
  -- Locate variable access attempts before addon name is resolved.
  -- This typically may happen with dropdown menu initialization function 
  -- calls.
  if not A.is_loaded then
    A.error("Addon has not loaded: %s.", debugstack(2))
    return
  end
  
  -- Get character saved variable
  local _G = getfenv(0)
  local saved_variable = _G[A.name .. "CDB"]
  if not saved_variable then 
    A.error("No addon character saved variable found: %s.",
      debugstack(2))
    return
  end
  
  -- Get namespace data
  local namespaces = saved_variable["namespaces"]
  if not namespaces or not namespaces[name] then 
    A.error("No namespace data for addon character saved variable found: %s.",
      debugstack(2))
    return
  end
  
  return namespaces[name]
end

--------------------------------------------------------------------------------
-- Account Configuration
--------------------------------------------------------------------------------

do
  local REALM = GetRealmName()
  local PLAYER = GetUnitName("player")

  function A.registerProfileDefaults(name, defaults)
    A.profiles[name] = A.profiles[name] or {}
    local module = A.profiles[name]
    
    if not defaults or type(defaults) ~= "table" then 
      A.warn("Table data expected for profile config defaults.")
    end
    
    module["defaults"] = defaults or {}
  end

  function A.getProfileDefaults(name)
    if not A.profiles[name] then return end
    return A.profiles[name]["defaults"]
  end

  function A.setProfileDefaults()
    -- Get account saved variable
    local _G = getfenv(0)
    local svar_name = A.name .. "DB"
    _G[svar_name] = _G[svar_name] or {}
    local saved_variable = _G[svar_name]
    
    -- Ensure profile data structure as realm-character exists and for
    -- the current logged-in character.
    saved_variable["profiles"] = saved_variable["profiles"] or {}

    local profiles = saved_variable["profiles"]
    profiles["_realms"] = profiles["_realms"] or {}
    
    local realms = profiles["_realms"]
    realms[REALM] = realms[REALM] or {}
    realms[REALM]["_chars"] = realms[REALM]["_chars"] or {}
    
    local chars = realms[REALM]["_chars"]
    chars[PLAYER] = chars[PLAYER] or {}
    
    local profile = chars[PLAYER]
    
    -- Update profile namespaces with any missing defaults
    local found = false
    for name, module in pairs(A.profiles) do
      profile[name] = profile[name] or {}
      local namespace = profile[name]
      
      local defaults = module["defaults"]
      for k, v in pairs(defaults) do
        if not namespace[k] then
          namespace[k] = v
          found = true
        end
      end
    end
    if found then
      A.info("Saved account variable: profile defaults set.")
    end
  end
  
  function A.registerRealmDefaults(name, defaults)
    A.charless[name] = A.charless[name] or {}
    local module = A.charless[name]
    
    if not defaults or type(defaults) ~= "table" then 
      A.warn("Table data expected for realm config defaults.")
    end
    
    module["defaults"] = defaults or {}
  end
  
  function A.getRealmDefaults(name)
    if not A.charless[name] then return end
    return A.charless[name]["defaults"]
  end
  
  function A.setRealmDefaults()
    -- Get account saved variable
    local _G = getfenv(0)
    local svar_name = A.name .. "DB"
    _G[svar_name] = _G[svar_name] or {}
    local saved_variable = _G[svar_name]
    
    -- Ensure data structure for realms exists and for the current
    -- realm. Re-use toplevel profiles table
    saved_variable["profiles"] = saved_variable["profiles"] or {}

    local profiles = saved_variable["profiles"]
    profiles["_realms"] = profiles["_realms"] or {}
    
    local realms = profiles["_realms"]
    realms[REALM] = realms[REALM] or {}
    
    local realm = realms[REALM]
    
    -- Update profile namespaces with any missing defaults
    local found = false
    for name, module in pairs(A.charless) do
      realm[name] = realm[name] or {}
      local namespace = realm[name]
      
      local defaults = module["defaults"]
      for k, v in pairs(defaults) do
        if not namespace[k] then
          namespace[k] = v
          found = true
        end
      end
    end
    if found then
      A.info("Saved account variable: realm defaults set.")
    end
  end

  function A.getProfile(name)
    -- Locate variable access attempts before addon name is resolved.
    -- This typically may happen with dropdown menu initialization function 
    -- calls.
    if not A.is_loaded then
      A.error("Addon has not loaded: %s.", debugstack(2))
      return
    end
    
    -- Get account saved variable
    local _G = getfenv(0)
    local saved_variable = _G[A.name .. "DB"]
    if not saved_variable then 
      A.error("No addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    -- Get realm-character data
    local profiles = saved_variable["profiles"]
    local realms = profiles and profiles["_realms"]
    local realm = realms and realms[REALM]
    local chars = realm and realm["_chars"]
    local profile = chars and chars[PLAYER]
    
    if not profile or not profile[name] then 
      A.error("No profile data for addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    return profile[name]
  end
  
  function A.getProfileRealmChars(search_realm)
    -- Locate variable access attempts before addon name is resolved.
    -- This typically may happen with dropdown menu initialization function 
    -- calls.
    if not A.is_loaded then
      A.error("Addon has not loaded: %s.", debugstack(2))
      return
    end
    
    -- Get account saved variable
    local _G = getfenv(0)
    local saved_variable = _G[A.name .. "DB"]
    if not saved_variable then 
      A.error("No addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    -- Get realm-character data
    local profiles = saved_variable["profiles"]
    local realms = profiles and profiles["_realms"]
    local realm = realms and realms[search_realm or REALM]
    local chars = realm and realm["_chars"]
    
    if not chars then 
      A.error(
        "No realm-character data for addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    return chars
  end
  
  function A.getProfileRealm(name, search_realm)
    -- Locate variable access attempts before addon name is resolved.
    -- This typically may happen with dropdown menu initialization function 
    -- calls.
    if not A.is_loaded then
      A.error("Addon has not loaded: %s.", debugstack(2))
      return
    end
    
    -- Get account saved variable
    local _G = getfenv(0)
    local saved_variable = _G[A.name .. "DB"]
    if not saved_variable then 
      A.error("No addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    -- Get realm-character data
    local profiles = saved_variable["profiles"]
    local realms = profiles and profiles["_realms"]
    local realm = realms and realms[search_realm or REALM]
    
    if not realm or not realm[name] then
      A.error("No realm data for addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    return realm[name]
  end

  function A.getProfileRealms()
    -- Locate variable access attempts before addon name is resolved.
    -- This typically may happen with dropdown menu initialization function 
    -- calls.
    if not A.is_loaded then
      A.error("Addon has not loaded: %s.", debugstack(2))
      return
    end
    
    -- Get account saved variable
    local _G = getfenv(0)
    local saved_variable = _G[A.name .. "DB"]
    if not saved_variable then 
      A.error("No addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    -- Get realm-character data
    local profiles = saved_variable["profiles"]
    local realms = profiles and profiles["_realms"]
    
    if not realms then 
      A.error("No realms data for addon account saved variable found: %s.",
        debugstack(2))
      return
    end
    
    return realms
  end
end