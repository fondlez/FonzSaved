local A = FonzSaved
local L = A.locale

local _, module_name = A.module 'raidleadersaved'

local cmdoptions = A.require 'cmdoptions'
local announce = A.require 'announce'

local util = A.requires(
  'util.table',
  'util.string',
  'util.group'
)

local format = string.format

local defaults = {
  enable = true,
  show_inside = false,
  show_zero = false,
  show_duration = false,
  show_id = false,
  spam_delay = 60, --seconds
  prefix = "default",
}

A.registerCharConfigDefaults(module_name, defaults)

do
  local GetTime = GetTime
  local SendChatMessage = SendChatMessage
  
  local last_time
  
  function M.setThrottle()
    last_time = GetTime()
  end
  
  function M.checkThrottle(delay)
    local db = A.getCharConfig(module_name)
    return not last_time or (GetTime() - last_time > (delay or db.spam_delay))
  end
  
  function M.sendThrottledMessage(msg, delay)
    if checkThrottle(delay) then
      pcall(SendChatMessage, msg, "RAID", nil)
      setThrottle()
    end
  end
end

local frame = CreateFrame("Frame")
M.event_frame = frame

do
  local GetRealNumRaidMembers = GetRealNumRaidMembers
  local IsInInstance = IsInInstance
  local IsRaidLeader, IsPartyLeader = IsRaidLeader, IsPartyLeader
  
  local listSelfRaids = announce.listSelfRaids
  local getRaidLeader = util.getRaidLeader
  
  local num_raiders
  local already_queried_leader = false

  function frame:PLAYER_ENTERING_WORLD()
    if not UnitInRaid("player") then return end
    
    -- Already in a raid so must have already queried raid leader
    already_queried_leader = true
    
    if not (IsRaidLeader() or IsPartyLeader()) then return end
    
    num_raiders = GetRealNumRaidMembers()
    -- Attempt to prevent messages just from logging in
    setThrottle()
  end
  
  function M.queryRaidLeader()
    local name, class, online, level = getRaidLeader()
    if not name then 
      A.warn("[module: %s] %s", module_name, "Unable to find raid leader name.")
      return
    end
    
    -- Minimum level for lowest level raid instance access is 50.
    if level and tonumber(level) < 50 then
      A.info("Raid leader level is too low to have access to raid instances.")
      return
    end
    
    if not online then
      A:print(L["Raid leader is offline. Unable to query saved raids."])
      return
    end
    
    A:print(L["Attempting to query raid leader saved raids."])
    
    local whisper = A.require 'whisper'
    -- Options:
    -- * specific raid id
    -- * suppress confirm
    whisper.queryUnitName(name, nil, true)
  end

  function frame:RAID_ROSTER_UPDATE()
    -- Stop if not or no longer group leader
    if not (IsRaidLeader() or IsPartyLeader()) then 
      -- If not leader, yet in a raid and number of raiders unknown, must be
      -- newly invited or in a converted raid group.
      if not num_raiders then
        if not already_queried_leader then
          queryRaidLeader()
          already_queried_leader = true
        elseif already_queried_leader and GetRealNumRaidMembers() < 2 then
          -- Note. above initial condition is not redundant due to 
          -- short-circuit logical operator.
          
          -- Reset raid leader query if no longer in a raid group
          already_queried_leader = false
        end
        return
      end

      -- Reset if just left group as previous raid leader
      num_raiders = nil
      return
    end
    
    -- Stop if PvP instances or inside an instance without config enabled
    local in_instance, instance_type = IsInInstance()    
    if instance_type == "pvp" or instance_type == "arena" then return end        
    
    local db = A.getCharConfig(module_name)
    if instance_type == "raid" and not db.show_inside then return end

    -- Check status of group
    local latest_num_raiders = GetRealNumRaidMembers() or 0    
    
    if latest_num_raiders == 0 then
      A.info("Not in a raid.")
      -- Reset for future group
      num_raiders = nil
      return 
    elseif latest_num_raiders > 0 and not num_raiders then
      A.info("Party converted to raid.")
      num_raiders = latest_num_raiders
    elseif latest_num_raiders > num_raiders then
      A.info("Raid size increased.")
      num_raiders = latest_num_raiders
    else
      num_raiders = latest_num_raiders            
      return
    end
    
    -- Wait till end of gathering data before stopping, in case options change
    if not db.enable or isQuiet() then return end
    
    -- Potentially expensive check for raid instances, so saved till late.
    local raids_list = listSelfRaids(nil, db.show_id, db.show_duration)
    
    if raids_list then
      local msg = format("%s%s%s.", padPrefix(), L["raid leader saved: "], 
        raids_list)
      sendThrottledMessage(msg)
    elseif not raids_list and db.show_zero then
      local msg = format("%s%s", padPrefix(), 
        L["raid leader has 0 saved raids."])
      sendThrottledMessage(msg)
    else
      return
    end
  end
end

-- Fired when the player enters the world, reloads the UI, enters/leaves an 
-- instance or battleground, or respawns at a graveyard. Also fires any other 
-- time the player sees a loading screen
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Fires on conversion to raid, raid size changes and raid leader changes
frame:RegisterEvent("RAID_ROSTER_UPDATE")

frame:SetScript("OnEvent", function()
  local event_method = frame[event]
  if event_method then
    event_method(this)
  end
end)

-- MODULE OPTIONS --

if not A.options then
  A.options = {
    type = "group",
    args = {},
  }
end

do
  local quiet = false
  
  function M.isQuiet()
    return quiet
  end
  
  function M.toggleQuiet(show_status)
    quiet = not quiet
    
    if not show_status then return end
    
    local msg = cmdoptions.formatToggle(L["Raid Leader Saved - quiet mode"], 
      quiet)
    A:print(msg)
  end
end

do
  local leq = util.leq
  
  function getPrefix()
    local db = A.getCharConfig(module_name)
    return (not db.prefix or db.prefix == "default") and L["{RLS}"]
      or db.prefix
  end

  function setPrefix(msg)
    local db = A.getCharConfig(module_name)
    db.prefix = msg and (leq(msg, DEFAULT) or leq(msg, "default")) and "default"
      or leq(msg, NONE) and ""
      or msg
  end
  
  function padPrefix()
    local prefix = getPrefix()
    return strlen(prefix) > 0 and format("%s ", prefix) or ""
  end
end

A.options.args["rls"] = {
  name = L["RLS"],
  desc = L["Chat options for Raid Leader Saved."],
  type = "group",
  args = {
    Enable = {
      type = "toggle",
      name = L["Enable"],
      desc = L["Enable Raid Leader Saved announcement."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.enable
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.enable = not db.enable
      end,
    },
    Quiet = {
      type = "toggle",
      name = L["Quiet"],
      desc = L["Be silent until next reload or login."],
      get = isQuiet,
      set = toggleQuiet,
    },
    Zero = {
      type = "toggle",
      name = L["Announce Not Saved"],
      desc = L["Announce when saved to 0 raids."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.show_zero
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.show_zero = not db.show_zero
      end,
    },
    Id = {
      type = "toggle",
      name = L["Announce Id"],
      desc = L["Announce instance id."],
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
      name = L["Announce Time"],
      desc = L["Announce time remaining till reset."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.show_duration
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.show_duration = not db.show_duration
      end,
    },
    Inside = {
      type = "toggle",
      name = L["Announce Inside"],
      desc = L["Announce while inside raids zones."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.show_inside
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.show_inside = not db.show_inside
      end,
    },
    Spam = {
      type = "range",
      name = L["Spam Protection"],
      desc = L["Set chat delay for spam protection."],
      get = function() 
        local db = A.getCharConfig(module_name)
        return db.spam_delay
      end,
      set = function(msg)
        local db = A.getCharConfig(module_name)
        db.spam_delay = tonumber(msg)
      end,
      usage = L["<seconds:3-300>"],
      validate = function(msg)
        local n = tonumber(msg)
        return n and n >= 3 and n <= 300
      end,
      min = 3, max = 300, softMin = 2, softMax = 60, step = 2, bigStep = 10,
    },
    Prefix = {
      type = "text",
      name = L["Prefix"],
      desc = L["Set prefix to messages."],
      get = getPrefix,
      set = setPrefix,
      usage = L["DEFAULT | NONE | <string>"],
      validate = function(msg)
        return msg and strlen(msg) > 0
      end,
    },
  },
}
