local A = FonzSaved
local L = A.locale

local _, module_name = A.module 'whisper'

local savedinstances = A.require 'savedinstances'
local announce = A.require 'announce'

local util = A.requires(
  'util.string'
)

local UnitPlayerControlled = UnitPlayerControlled
local UnitFactionGroup = UnitFactionGroup
local SendAddonMessage = SendAddonMessage

local format = string.format
local strlower = strlower
local strlen = strlen

local defaults = {
  enable = true,
  show_id = false,
  show_duration = false,
  quiet = false,
  cache_duration = 60, --seconds
}

A.registerCharConfigDefaults(module_name, defaults)

function canWhisper(be_quiet)
  local db = A.getCharConfig(module_name)
  if not db.enable then 
    if not be_quiet then
      A:print(
        format(L["Query mode is not enabled. Type '%s' to enable."],
          L["SLASHCMD_SHORT"]))
    end
    return false
  end
  return true
end

function confirmQuery(target)
  local db = A.getCharConfig(module_name)
  if db.quiet then return end
  
  A:print(format(L["Query sent to %s."], target))
end

do
  local cache = {
    query_send = {},
    reply_send = {},
    reply_receive = {},
  }

  function updateCache(tag, name, data)
    cache[tag][name] = { last_time = GetTime(), data = data }
  end
  
  function getCache(tag, name)
    local entry = cache[tag][name]
    local last_time = entry and entry.last_time
    
    local db = A.getCharConfig(module_name)
    local cache_duration = db.cache_duration > 1 and db.cache_duration 
      or defaults.cache_duration
    
    if not last_time or (GetTime() - last_time > cache_duration) then 
      A.debug("[module: %s] %s %s %s", module_name, tag, name, "cache miss")
      return
    end
    
    return entry
  end
end

do
  local strsplit = strsplit or util.strsplit
  local tinsert, tconcat = table.insert, table.concat
  
  local filterRaids = savedinstances.filterRaids
  local filterSelfRaids = savedinstances.filterSelfRaids
  local formatRaids = announce.formatRaids
  local findRaidNameById = savedinstances.findRaidNameById
  
  --[[
  EBNF syntax for Whisper Reply:
  
  whisper reply = empty reply | reply ;
  empty reply = reply code, [ block delimiter ] ;
  reply = reply code, block delimiter, instance info, 
    { block delimiter, instance info } ;
  instance info = raid id, 
    [ field delimiter, instance id, [ field delimiter, duration ] ] ;
  raid id = number ;
  instance id = non-negative number ;
  duration = non-negative number ;
  number = [ "-" ], non-negative number ;
  non-negative number = digit, { digit } ;
  reply code = 'r' ;
  block delimiter = ';' ;
  field delimiter = ':' ;
  digit = '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' ;
  --]]
  
  local function parseQuery(msgtable)
    return tonumber(msgtable[2])
  end
  
  local function validateInfo(info)
    -- Validate numbers instead of only non-negative numbers
    local raid_id = info.raid_id and tonumber(info.raid_id)
    local id = info.id and tonumber(info.id)
    local duration = info.duration and tonumber(info.duration)
    
    return raid_id and tostring(raid_id), 
      id and tostring(id) or "", 
      duration and tostring(duration) or ""
  end
  
  local function formatReply(query_raid_id)
    local raids = filterSelfRaids(query_raid_id)
    if not raids then return "r" end
    
    local infos = {}
    for i, info in ipairs(raids) do
      local raid_id, id, duration = validateInfo(info)
      if raid_id then
        tinsert(infos, format("%s:%s:%s", raid_id, id, duration))
      end
    end
    
    return format("r;%s", tconcat(infos, ";"))
  end
  
  local function validateMessage(msg)
    if strlen(msg) < 1 then return end
    
    -- Split by field delimiter within a block
    local raid_id, id, duration = strsplit(":", msg)
    
    -- Validate numbers instead of only non-negative numbers
    return strlen(raid_id) > 0 and tonumber(raid_id) and raid_id, 
      id and strlen(id) > 0 and tonumber(id) and id, 
      duration and strlen(duration) > 0 and tonumber(duration) and duration
  end
  
  local function parseReply(msgtable)
    local n = msgtable and getn(msgtable)
    if not n or n < 2 then return end
    
    -- All raid data starts after the message type, so from block 2
    local raids = {}
    for i=2,n do
      local raid_id, id, duration = validateMessage(msgtable[i])
      local name = findRaidNameById(raid_id)
      if name then
        tinsert(raids, { name = name, raid_id = raid_id, id = id, 
          duration = duration })
      end
    end
    
    return raids
  end
  
  function showReply(raids, raid_id, name, is_self)
    local db = A.getCharConfig(module_name)
    local n = raids and getn(raids) or 0
    
    local show_id = not is_self and db.show_id or true
    local show_duration = not is_self and db.show_duration or true
    
    -- General user response if data available
    if n > 0 and not raid_id then
      A:print(format(L["%s has %d saved raid(s): %s."], name, n,
        formatRaids(raids, show_id, show_duration)))
    -- Query-specific user response if data available
    elseif n > 0 and raid_id then
      A:print(format(L["%s is saved to %s."], name, 
        formatRaids(raids, show_id, show_duration, raid_id)))
    -- General user response if no data available
    elseif n == 0 and not raid_id then
      A:print(format(L["%s has 0 saved raids."], name))
    -- Query-specific user response if no data available
    elseif n == 0 and raid_id then
      A:print(format(L["%s is NOT saved to %s."], name,
        findRaidNameById(raid_id)))
    -- No reply seen
    else
      A.trace("[module: %s] %s %s", module_name, "showReply", 
        "Bad path")
    end
  end

  local frame = CreateFrame("Frame")
  M.event_frame = frame
  
  function frame.processQuery(msgtable, sender)
    if not canWhisper(true) then return end
    
    local l_sender = strlower(sender)
    
    -- Check not already sent this sender a message recently
    local seen = getCache("reply_send", l_sender)
    if seen then 
      A.trace("[module: %s] %s", module_name, "processQuery")
      return
    end
    
    local raid_id = parseQuery(msgtable)
    local reply = formatReply(raid_id)
    
    A.debug("[module: %s] %s %s", module_name, reply, sender)
    local ok = pcall(SendAddonMessage, A.name, reply, "WHISPER", sender)
    if not ok then
      A:print(format(L["Unable to contact player: %s."], sender))
    end  
    
    updateCache("reply_send", l_sender, raid_id)
  end
  
  function frame.processReply(msgtable, sender)    
    local l_sender = strlower(sender)
    
    local query_seen = getCache("query_send", l_sender)
    
    -- Find out if we've already received data from this sender.
    -- Ensure a (boolean) value is stored, and not a reference.
    local reply_seen = not not getCache("reply_receive", l_sender)
    
    if getn(msgtable) < 2 or strlen(msgtable[2]) < 1 then
      A.trace("[module: %s] %s", module_name, "processReply - empty data")
      -- No data
      updateCache("reply_receive", l_sender, nil)
      -- Not allowed to go beyond collecting data
      if not canWhisper(true) then return end
      -- No spam allowed from the same sender, even if it appears as empty data
      if reply_seen then return end
      showReply(nil, query_seen and query_seen.data, sender)
      return
    end
    
    local raids = parseReply(msgtable)
    
    updateCache("reply_receive", l_sender, raids)
    -- Not allowed to go beyond collecting data
    if not canWhisper(true) then return end
    -- No spam allowed from the same sender, even if it appears as real data
    if reply_seen then return end
    
    -- Since all saved raids is returned in replies, filter raids on reply
    local raid_id = query_seen and query_seen.data
    local filtered_raids = filterRaids(raids, raid_id)
    
    showReply(filtered_raids, raid_id, sender)
  end
  
  frame.dispatch = {
    ["q"] = frame.processQuery,
    ["r"] = frame.processReply,
  }
  
  -- Fires when an addon communication message is received
  -- args: prefix, text, channel, sender
  frame:RegisterEvent("CHAT_MSG_ADDON")

  frame:SetScript("OnEvent", function()
    if arg1 ~= A.name then return end
    if arg3 ~= "WHISPER" then return end
    if not arg2 or strlen(arg2) < 1 then 
      A.warn("[module: %s] %s", module_name, "Empty message.")
      return
    end
   
    -- Split message by block delimiter
    local msgtable = { strsplit(";", arg2) }
    local sender = arg4 or L["Unknown"]
    local msgtype = msgtable[1]
    
    local processMsg = frame.dispatch[msgtype]
    if processMsg then 
      processMsg(msgtable, sender) 
    else
      A.warn("[module: %s] %s %s", module_name, "Unknown message type:", 
        msgtype)
      return
    end
  end)
end

do
  local filterRaids = savedinstances.filterRaids
  local findRaidIdByName = savedinstances.findRaidIdByName
  local filterAccountRaids = savedinstances.filterAccountRaids
  
  --[[
  EBNF syntax for Whisper Query:
  
  whisper query = empty query | query ;
  empty query = query code, [ block delimiter ] ;
  query = query code, block delimiter, raid id ;
  raid id = number ;
  number = [ "-" ], non-negative number ;
  non-negative number = digit, { digit } ;
  query code = 'q' ;
  block delimiter = ';' ;
  digit = '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' ;
  --]]
  local function formatQuery(raid_id)
    -- Since caching is being used, discard (sending) specific instance queries.
    -- This allows user to change queries without further data exchange in 
    -- the caching period.
    raid_id = nil
    
    return not raid_id and "q" or format("%s;%d", "q", raid_id)
  end
  
  local function querySelf(name, raid_id)
    local raids = filterAccountRaids(name, raid_id)
    if not raids then return end
    -- Reply as self (show all details)
    showReply(raids, raid_id, name, true)
    return true
  end

  function M.queryUnitName(name, raid_name)
    if not canWhisper() then return end
    
    local raid_id = findRaidIdByName(raid_name)
    
    -- Check if this query applies to own characters first
    if querySelf(name, raid_id) then return end
    
    local l_name = strlower(name)
    local seen = getCache("query_send", l_name)
    
    -- Check not already sent message to this name recently
    if not seen then
      confirmQuery(name)
      
      local ok = pcall(SendAddonMessage, A.name, formatQuery(raid_id), 
        "WHISPER", name)
      if not ok then
        A:print(format(L["Unable to contact player: %s."], name or "Unknown"))
      end
      
      updateCache("query_send", l_name, raid_id)
    else
      -- Check if already received a reply from this name and cached it
      local reply_seen = getCache("reply_receive", l_name)
      local raids = reply_seen and reply_seen.data
      
      if reply_seen then
        -- Since all saved raids is returned in replies, filter raids on reply
        local filtered_raids = filterRaids(raids, raid_id)
        showReply(filtered_raids, raid_id, name)
      else
        A:print(format(L["%s has not responded."], name))
      end
    end
  end
end

function M.queryUnit(unit)  
  if not canWhisper() then return end
  
  A.debug("Unit: %s", tostring(unit))
  unit = unit and strlower(unit) or "target"
  
  -- Unit ids can be checked directly in the API for their attributes.
  -- Check unit is not an NPC and from the same faction as self ("player").
  local friend = UnitIsPlayer(unit) and UnitIsFriend("player", unit)
  
  if not friend then
    A:print(L["Invalid target."])
    return
  end
  
  local name = UnitName(unit)
  queryUnitName(name)
end

-- MODULE OPTIONS --

if not A.options then
  A.options = {
    type = "group",
    args = {},
  }
end

A.options.args["query"] = {
  name = L["Query"],
  desc = format(L["%s chat options to query others saved raids."], 
    L["SLASHCMD_SAVED"]),
  type = "group",
  args = {
    Enable = {
      type = "toggle",
      name = L["Enable"],
      desc = L["Enable querying and showing other players saved raids."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.enable
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.enable = not db.enable
      end,
    },
    Id = {
      type = "toggle",
      name = L["Show Id"],
      desc = L["Show instance id."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.show_id
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.show_id = not db.show_id
      end,
    },
    Time = {
      type = "toggle",
      name = L["Show Time"],
      desc = L["Show time remaining till reset."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.show_duration
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.show_duration = not db.show_duration
      end,
    },
    Quiet = {
      type = "toggle",
      name = L["Quiet"],
      desc = L["No message when sending a query."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.quiet
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.quiet = not db.quiet
      end,
    },
  },
}

-- Debug-only options
if A.logging("DEBUG") then
  A.options.args["query"].args.Cache = {
    type = "range",
    name = "Cache Duration",
    desc = "Set duration of whisper cache (seconds).",
    get = function() 
      local db = A.getCharConfig(module_name)
      return db.cache_duration
    end,
    set = function(msg) 
      local db = A.getCharConfig(module_name)
      db.cache_duration = tonumber(msg)
    end,
    usage = "<seconds: greater than 1>",
    validate = function(msg)
      local n = msg and strlen(msg) > 0 and tonumber(msg)
      return n and n > 1
    end,
    min = 2, max = 600, softMin = 2, softMax = 60, step = 2, bigStep = 10,
  }
end