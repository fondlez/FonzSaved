local A = FonzSaved
local L = A.locale

-- [Optional] Addon dependency: GUI

local _, module_name = A.module 'savedinstances'

local util = A.requires(
  'util.table',
  'util.string'
)

local GetNumSavedInstances = GetNumSavedInstances
local GetSavedInstanceInfo = GetSavedInstanceInfo
local GetTime = GetTime
local GetLocale = GetLocale

local tinsert = table.insert

local profile_defaults = {
  player = {},
  raid_info = {},
  instance_info = {},
}

A.registerProfileDefaults(module_name, profile_defaults)

function M.getSavedInfo()
  local n = GetNumSavedInstances()
  if not n or n < 1 then
    return
  end
  
  local thetime = time()
  local instances = {}
  for i=1,n do
    local name, id, duration = GetSavedInstanceInfo(i)
    instances[name] = { id = id, duration = duration, 
      reset = (thetime + tonumber(duration)) }
  end
  
  return instances, n, thetime
end

do
  local strlen = strlen
  
  local uniqueKeySearch = util.uniqueKeySearch
  
  local function mergeAcrossLocales(name)
    if A.locale_info.code == GetLocale() then return L[name] end
    
    -- If current locale is not the same as client locale, merge key-value pairs 
    -- for the same catalog entry name across all catalogs into a big table.
    -- This works because identical keys have identical values across catalogs,
    -- e.g. raid index for exact name "Karazhan" is 7 across all catalogs.
    local t = {}
    for code, catalog in pairs(A.locale_info.catalogs) do
      local entry = catalog[name]
      for key, value in pairs(entry) do
        t[key] = value
      end
    end
    
    return t
  end
  
  local function search(entry_name, search_name, exact)
    if not search_name or strlen(search_name) < 1 then return end
    
    local t = mergeAcrossLocales(entry_name)
    if exact then
      return t[search_name]
    else
      local name = uniqueKeySearch(t, search_name, util.leq)
      return name and t[name]
    end
  end
  
  function M.findRaidIdByName(search_name, exact)
    return search("RAID_NAMES", search_name, exact)
  end
  
  function M.findHeroicByName(search_name, exact)
    return search("HEROIC_NAMES", search_name, exact)
  end
end

do
  local current_locale
  local ids = {}
  
  local saveIds = {
    ["raid"] = function()
      ids["raid"] = {}
      for name, raid_id in pairs(L["RAID_NAMES"]) do
        ids["raid"][tostring(raid_id)] = name
      end
    end,
    ["heroic"] = function()
      ids["heroic"] = {}
      for name, heroic in pairs(L["HEROIC_NAMES"]) do
        ids["heroic"][tostring(heroic.heroic_id)] = {
          heroic_id = heroic.heroic_id,
          code = heroic.code,
          short = heroic.short,
          name = name,
        }
      end
    end,
  }
  
  -- Query mapping from instance id to current locale's instance name.
  -- Create cache of mappings if empty or if locale code changes.
  local function search(saved_type, query_id)
    local locale_code = A.locale_info.code
    
    if not ids[saved_type] 
        or (ids[saved_type] and current_locale ~= locale_code) then
      current_locale = locale_code
      saveIds[saved_type]()
    end
    if not query_id then return end
    
    return ids[saved_type][tostring(query_id)]
  end
  
  function M.findRaidNameById(query_id)
    return search("raid", query_id)
  end
  
  function M.findHeroicById(query_id)
    return search("heroic", query_id)
  end
end

do
  -- Time in seconds
  local DELAYS = {
    GetSavedInstanceInfo = 300,
    RequestRaidInfo = 30,
  }
  local last_times = {}
  
  function resetSeen(tag)
    last_times[tag] = nil
  end
  
  -- No point spamming the server too often. Create throttle function
  function seen(tag)
    local last_time = last_times[tag]
    
    if not last_time or (GetTime() - last_time > DELAYS[tag]) then
      A.debug("[module: %s] %s %s", module_name, tag, "cache miss")
      last_times[tag] = GetTime()
      return false
    end
    
    return true
  end
end

function M.updateSaved()
  if seen("GetSavedInstanceInfo") then return end
  
  local saved, _, thetime = getSavedInfo()
  
  local db = A.getProfile(module_name)
  db.player.name = A.player.name
  db.player.class = A.player.class
  db.query_time = thetime
  
  local raid_info = db.raid_info
  local instance_info = db.instance_info
  
  -- Nothing saved
  if not saved then
    raid_info.n = 0
    raid_info.raids = nil
    
    instance_info.n = 0
    instance_info.instances = nil
    return
  end
  
  A.trace("updateSaved: instances found")
  
  raid_info.raids = {}
  instance_info.instances = {}
  for name, detail in pairs(saved) do
    -- Exact name search for raids
    local raid_id = findRaidIdByName(name, true)
    if raid_id then
      A.debug("updateSaved: added raid %s", name)
      tinsert(raid_info.raids, { 
        name = name, raid_id = raid_id, id = detail.id, 
        duration = detail.duration, reset = detail.reset
        })
    -- Collect other instances that do not match
    else
      A.debug("updateSaved: added instance %s", name)
      -- Exact name search for heroics
      local heroic = findHeroicByName(name, true)
      tinsert(instance_info.instances, { 
        name = name, id = detail.id, duration = detail.duration, 
        reset = detail.reset, heroic_id = heroic and heroic.heroic_id
        })
    end
  end

  local raids_n = getn(raid_info.raids) or 0
  raid_info.n = raids_n
  if raids_n == 0 then
     raid_info.raids = nil
     A.trace("updateSaved: - but no raids found")
  end
  
  local instances_n = getn(instance_info.instances) or 0
  instance_info.n = instances_n
  if instances_n == 0 then
    instance_info.instances = nil
    A.trace("updateSaved: - but no instances found")
  end
  
  -- Confirm pending saves in lockouts
  local lockout = A.require 'lockout'
  lockout.canSaveLockout(saved)
  
  -- Update GUI, if available
  -- Risky due to loading.
  --[[
  if FonzSavedFu then
    FonzSavedFu:UpdateFuBarPlugin()
  end
  --]]
end

do  
  local function expired(instances)
    if not instances then return true end
    
    local found = false
    
    for i, instance in ipairs(instances) do
      -- Look for at least one raid that has not reset
      if instance.reset and tonumber(instance.reset) > time() then
        found = true
      end
    end
    
    return not found
  end

  local DURATION_MAX_RESET = {
    instances = 24*60*60, --24 hours
    raids = 7*24*60*60, --7 days
  }
  
  local info_types = {
    instances = "instance_info",
    raids = "raid_info",
  }
  
  function M.getAccountSaved(saved_type)
    local chars = A.getProfileRealmChars()
    
    local saved_infos = {}
    for name, profile in pairs(chars) do
      local this_module = profile[module_name]
      local query_time = this_module.query_time
      -- Early staleness check
      if query_time 
          and (time() - tonumber(query_time) < DURATION_MAX_RESET[saved_type]) then
        local saved_info = this_module and this_module[info_types[saved_type]]
        local n = saved_info and saved_info.n
        
        if n and n > 0 and not expired(saved_info[saved_type]) then
          saved_infos[name] = saved_info
        end
      end
    end
    
    return getn(util.keys(saved_infos)) > 0 and saved_infos
  end
end

function M.filterRaids(raids, query_raid_id, eager)
  if not query_raid_id then
    return raids
  else
    local t = {}
    for i, record in pairs(raids) do
      if record.raid_id == query_raid_id then
        tinsert(t, record)
        if eager then return t end
      end
    end
    -- Return late so that case of empty but filtered result is distinguishable
    return t
  end
end

function M.filterSelfRaids(query_raid_id)
  local db = A.getProfile(module_name)
  local raid_info = db.raid_info
  
  -- If no raid count, then this is the first time for raid data.
  -- All other updates are from events.
  if not raid_info.n then
    updateSaved()
  end
  
  if raid_info.n < 1 then return end
  
  -- Filter for query (eager result return)
  return filterRaids(raid_info.raids, query_raid_id, true)
end

function M.getSelfHeroics()
  local db = A.getProfile(module_name)
  local instance_info = db.instance_info
  
  -- If no instance count, then ensure saved instance information called once.
  if not instance_info.n then
    updateSaved()
  end
  
  return instance_info.n > 0 and instance_info.instances
end

do
  local strlower = strlower
  
  local keyslower = util.keyslower
  
  function M.filterAccountRaids(name, query_raid_id)
    local raid_infos = getAccountSaved("raids")
    if not raid_infos or not name then return end
    
    local l_raid_infos = keyslower(raid_infos)
    local raid_info = l_raid_infos[strlower(name)]
    if not raid_info then return end
    
    -- Filter for query (late result return)
    return filterRaids(raid_info.raids, query_raid_id, false)
  end
end

-- EVENTS --

local frame = CreateFrame("Frame")
M.event_frame = frame

do  
  -- Update raid info from saved instances
  function frame:UPDATE_INSTANCE_INFO()
    updateSaved()
  end
  
  -- Ensure that up-to-date raid information is available on saved instances 
  -- change
  ---[[
  function frame:RAID_INSTANCE_WELCOME()    
    RequestRaidInfo()
    
    -- Reset delay for saved instances server query
    resetSeen("GetSavedInstanceInfo")
    A.trace("Instances refreshed - RAID_INSTANCE_WELCOME!")
  end

  function frame:CHAT_MSG_SYSTEM(msg)
    if not msg then return end
    -- Blizzard's GlobalStrings.lua:
    -- INSTANCE_SAVED = "You are now saved to this instance";
    if tostring(msg) == INSTANCE_SAVED then      
      RequestRaidInfo()
      
      -- Save to current lockout  
      local lockout = A.require 'lockout'
      lockout.pendingSaved()
      
      -- Reset delay for saved instances server query
      resetSeen("GetSavedInstanceInfo")
      A.trace("New instance saved - CHAT_MSG_SYSTEM!")
    end
  end
  --]]
end

-- Fires when information about instances to which the player is saved changes 
-- or becomes available
frame:RegisterEvent("UPDATE_INSTANCE_INFO")

-- Fired when you enter a instaces that saves u when a boss is killed. 
frame:RegisterEvent("RAID_INSTANCE_WELCOME")

-- Fires when a system message is received
frame:RegisterEvent("CHAT_MSG_SYSTEM")

frame:SetScript("OnEvent", function()
  local event_method = frame[event]
  if event_method then
    event_method(this, arg1)
  end
end)