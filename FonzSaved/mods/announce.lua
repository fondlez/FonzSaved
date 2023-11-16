local A = FonzSaved
local L = A.locale

local _, module_name = A.module 'announce'

local savedinstances = A.require 'savedinstances'
local palette = A.require 'palette'
local util = A.requires(
  'util.table',
  'util.string',
  'util.time',
  'util.group'
)

local GetChannelName = GetChannelName
local SendChatMessage = SendChatMessage

local format = string.format
local strlen = strlen
local tinsert, tconcat = table.insert, table.concat

local sortRecords = util.sortRecords1
local formatDuration = util.formatDurationFull

local HEROICS_FORMATS = {
  ["code"] = true,
  ["short"] = true,
  ["name"] = true,
}

local HEROICS_SORTS = {
  ["index"] = "heroic_id",
  ["code"] = true,
  ["short"] = true,
  ["name"] = true,    
}

local defaults = {
  prefix = "default",
  zero = true,
  show_id = false,
  show_duration = false,
  
  self_heroics_show = true,
  self_heroics_format = "code",
  self_heroics_sort = "index",
}

A.registerCharConfigDefaults(module_name, defaults)

do
  local color_name = palette.color.green

  local function formatRaid(name, id, reset)
    local strid = id and format(" #%s", tostring(id)) or ""
    local duration = reset and (tonumber(reset) - time())
    -- Colorize and hide seconds
    local strduration = duration and 
      format(" (%s)", 
        formatDuration(duration, true, true, A.locale_info.code))
      or ""
    
    return format("%s%s%s", color_name(name), strid, strduration)
  end
  
  function M.formatRaids(raids, show_id, show_duration, query_raid_id)
    if not raids then return end
    
    local n = getn(raids)
    if n == 1 then
      local raid = raids[1]
      
      return formatRaid(raid.name, show_id and raid.id, 
        show_duration and raid.reset), n
    elseif n > 1 then
      sortRecords(raids, "raid_id", true)
      
      local sorted = {}
      if not query_raid_id then
        for i, raid in ipairs(raids) do
          tinsert(sorted, formatRaid(raid.name, show_id and raid.id, 
            show_duration and raid.reset))
        end
      else
        for i, raid in ipairs(raids) do
          if query_raid_id == raid.raid_id then
            tinsert(sorted, formatRaid(raid.name, show_id and raid.id, 
              show_duration and raid.reset))
          end
        end
      end
      
      return tconcat(sorted, ", "), n
    end  
  end
end

do
  local HEROICS_COUNT = 16
  
  local color_count = palette.color.white_text
  local color_text = palette.color.lightyellow_text

  local filterSelfRaids = savedinstances.filterSelfRaids
  local getSelfHeroics = savedinstances.getSelfHeroics
  local findHeroicById = savedinstances.findHeroicById
  
  function M.listSelfRaids(query_raid_id, show_id, show_duration)
    local raids = filterSelfRaids(query_raid_id)
    return formatRaids(raids, show_id, show_duration)
  end
  
  local function color_paren(text, color)
    return format("%s%s%s", color("("), text or '', color(")"))
  end

  function M.listSelfHeroics()
    local heroics = getSelfHeroics()
    if not heroics then return end
    
    local count = format("%s/%s", 
      color_count(getn(heroics)),
      color_count(HEROICS_COUNT))
    local duration = tonumber(heroics[1].reset) - time()
    local time_left = format("%s%s",
      color_text("- "),
      color_text(formatDuration(duration, true, true, A.locale_info.code))
    )
    local msg = format("%s %s %s%s", 
      color_text(L["Heroics"]),
      color_paren(count, color_text), 
      time_left,
      color_text(": "))
    
    local named_heroics = {}
    for i, saved in ipairs(heroics) do
      local heroic_id = saved.heroic_id
      
      -- Find current locale heroic data based on heroic_id, if available
      local lc_heroic = findHeroicById(heroic_id)
      
      -- If no locale heroic data, fall back to saved name
      if lc_heroic then
        tinsert(named_heroics, {
            name = lc_heroic.name,
            code = lc_heroic.code,
            short = lc_heroic.short,
            heroic_id = heroic_id,
        })
      else
        local name = saved.name
        tinsert(named_heroics, {
          name = name,
          code = name,
          short = name,
          heroic_id = name,
        })
      end
    end
    
    local db = A.getCharConfig(module_name)      
    local sorting = HEROICS_SORTS[db.self_heroics_sort] == true 
      and db.self_heroics_sort or HEROICS_SORTS[db.self_heroics_sort]
    
    sortRecords(named_heroics, sorting)

    local formatting = db.self_heroics_format
    local t = {}
    for i, heroic in ipairs(named_heroics) do
      tinsert(t, color_text(heroic[formatting]))
    end
    
    return format("%s%s%s", msg, 
      formatting == "code" and '' or "\n",
      tconcat(t, color_text(formatting == "code" and ", " or "\n")))
  end
end

do
  local color_highlight = palette.color.gold_text
  
  function M.announceSelf()
    local msg
    
    local db = A.getCharConfig(module_name)      
    if db.self_heroics_show then
      msg = listSelfHeroics()
      if msg then A:print(msg) end
    end
    
    msg = listSelfRaids(nil, true, true)
    if msg then
      A:print(format("%s %s", color_highlight(L["Raids:"]), msg))
    else
      A:print(color_highlight(L["You have 0 saved raids."]))
    end
  end
end

do
  local function announceHaveRaids(raids_list, n)
    local msg = format(L["I have %d saved raid(s): %s."], n, raids_list)
    return format("%s%s", padPrefix(), msg)
  end

  local function announceHaveZeroRaids()
    local msg = L["I have 0 saved raids."]
    return format("%s%s", padPrefix(), msg)
  end

  function M.announceToChat(chat_type)
    A.debug(chat_type)
    local db = A.getCharConfig(module_name)
    local raids_list, n = listSelfRaids(nil, db.show_id,
      db.show_duration)
      
    if raids_list then
      pcall(SendChatMessage, announceHaveRaids(raids_list, n), chat_type, nil)
    elseif not raids_list and db.zero then
      pcall(SendChatMessage, announceHaveZeroRaids(), chat_type, nil)
    else
      return
    end
  end

  function M.announceByChannelNum(channel_num)
    channel_num = tonumber(channel_num) or 0
    A.debug("channel num: %d", channel_num)
    
    local id = GetChannelName(channel_num)
    if not id or id == 0 then
      A:print(format(L["Invalid channel number: %d."], channel_num))
      return
    end
    
    local db = A.getCharConfig(module_name)
    local raids_list = listSelfRaids(nil, db.show_id,
      db.show_duration)
      
    if raids_list then
      pcall(SendChatMessage, announceHaveRaids(raids_list, n), "CHANNEL", nil, 
        channel_num)
    elseif not raids_list and db.zero then
      pcall(SendChatMessage, announceHaveZeroRaids(), "CHANNEL", nil, 
        channel_num)
    else
      return
    end
  end

  function M.announceByChannelName(channel_name)
    A.debug("channel name: %s", channel_name)
    local id = GetChannelName(channel_name)
    if not id or id == 0 then 
      A:print(format(L["Invalid channel name: %s."], channel_name))
      return
    end
    
    local db = A.getCharConfig(module_name)
    local raids_list = listSelfRaids(nil, db.show_id,
      db.show_duration)
      
    if raids_list then
      pcall(SendChatMessage, announceHaveRaids(raids_list, n), "CHANNEL", nil, 
        id)
    elseif not raids_list and db.zero then
      pcall(SendChatMessage, announceHaveZeroRaids(), "CHANNEL", nil, id)
    else
      return
    end
  end
end

function M.announceMessage(message, channel, target)
  if not channel then
    A.warn("Invalid channel supplied.")
    return
  end
  
  local msg = format("%s%s", padPrefix(), message)

  pcall(SendChatMessage, msg, channel, nil, target)
end

-- MODULE OPTIONS --

if not A.options then
  A.options = {
    type = "group",
    args = {},
  }
end

do
  local leq = util.leq
  
  function getPrefix()
    local db = A.getCharConfig(module_name)
    return (not db.prefix or db.prefix == "default") and A.prefix()
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

A.options.args["chat"] = {
  name = L["Chat"],
  desc = format(L["%s chat options for announcing."], L["SLASHCMD_SAVED"]),
  type = "group",
  args = {
    Zero = {
      type = "toggle",
      name = L["Announce Not Saved"],
      desc = L["Announce when saved to 0 raids."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.zero
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.zero = not db.zero
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

A.options.args["self"] = {
  name = L["Self"],
  desc = format(L["%s chat options for own instances."], L["SLASHCMD_SAVED"]),
  type = "group",
  args = {
    Heroics = {
      type = "toggle",
      name = L["Show Heroics"],
      desc = L["Print list of saved heroics."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.self_heroics_show
      end,
      set = function()
        local db = A.getCharConfig(module_name)      
        db.self_heroics_show = not db.self_heroics_show
      end,
    },
    Format = {
      type = "choice",
      name = L["Heroics Format"],
      desc = L["Select type of formatting for heroics list."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.self_heroics_format
      end,
      set = function(msg)
        if not msg or not HEROICS_FORMATS[msg] then return end
        local db = A.getCharConfig(module_name)
        db.self_heroics_format = msg
      end,
      usage = "{ code | short | name }",
      validate = function(msg)
        return msg and HEROICS_FORMATS[msg]
      end,
      choices = {
        ["code"] = L["Code"],
        ["short"] = L["Short name"],
        ["name"] = L["Long name"],
      },
      choiceType = "dict",
      choiceOrder = { 
        "code", "short", "name",
      },
    },
    Sort = {
      type = "choice",
      name = L["Heroics Sorting"],
      desc = L["Select sorting for heroics list."],
      get = function() 
        local db = A.getCharConfig(module_name)      
        return db.self_heroics_sort
      end,
      set = function(msg)
        if not msg or not HEROICS_SORTS[msg] then return end
        local db = A.getCharConfig(module_name)
        db.self_heroics_sort = msg
      end,
      usage = "{ index | code | short | name }",
      validate = function(msg)
        return msg and HEROICS_SORTS[msg]
      end,
      choices = {
        ["index"] = L["Index"], --index == heroic_id
        ["code"] = L["Code"],
        ["short"] = L["Short name"],
        ["name"] = L["Long name"],
      },
      choiceType = "dict",
      choiceOrder = { 
        "index", "code", "short", "name",
      },
    },
  },
}