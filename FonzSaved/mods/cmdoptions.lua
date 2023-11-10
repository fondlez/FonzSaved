local A = FonzSaved
local L = A.locale

A.module 'cmdoptions'

local util = A.requires(
  'util.table',
  'util.string'
)

local palette = A.require 'palette'

local color_heading = palette.color.yellow
local color_group = palette.color.blue1
local color_normal = palette.color.white
local color_true = palette.color.green
local color_false = palette.color.red

local format, join, split, match, tolower, strlen = string.format, strjoin, 
  strsplit or util.strsplit, strmatch or util.strmatch, strlower, strlen

do
  local strvarg = util.strvarg
  
  -- General print without an addon name prefix
  function A:rawPrint(...)
    DEFAULT_CHAT_FRAME:AddMessage(join(", ", strvarg(...)))
  end
  
  -- General print with an addon name prefix
  function A:print(...)
    DEFAULT_CHAT_FRAME:AddMessage(format("%s: %s", color_heading(A.name), 
      join(", ", strvarg(...))))
  end
end

do  
  local isempty = util.isempty
  local isNotSpaceOrEmpty = util.isNotSpaceOrEmpty
  local leq = util.leq
  local keyslower = util.keyslower
  local sortedKeys = util.sortedKeys
  local sortedPairs = util.sortedPairs
  
  local lowercase_table_cache = setmetatable({}, {
    __index = function(t, k)
      if type(k) == "table" then
        local l = keyslower(k)
        rawset(t, k, l)
        return l
      end
    end
  })
  
  local function getLowercaseKeyTable(t)
    return lowercase_table_cache[t]
  end
  
  local function color_bracket(text, color)
    color = color or color_heading
    return format("%s%s%s", color("["), text or '', color("]"))
  end
  
  local option_formatter = {
    ["text"] = function(name, text)
      return format("%s %s %s", 
        color_heading(name), 
        color_normal(L["is currently set to"]), 
        color_bracket(text))
    end,
    ["toggle"] = function(name, toggle)
      return format("%s %s %s", 
        color_heading(name), 
        color_normal(L["is now set to"]), 
        color_bracket(toggle and color_true(L["On"]) or color_false(L["Off"])))
    end,
    ["group"] = {
      ["text"] = function(name, description, text)
        return format("- %s %s %s", 
          color_heading(format("%s:", name)), 
          color_bracket(text),
          color_normal(description))
      end,
      ["toggle"] = function(name, description, toggle)
        return format("- %s %s %s", 
          color_heading(format("%s:", name)), 
          color_bracket(toggle and color_true(L["On"]) 
            or color_false(L["Off"])),
          color_normal(description))
      end,
      ["group"] = function(name, description, unused)
        return format("- %s %s", 
          color_group(format("%s:", name)),
          color_normal(description))
      end,
      ["execute"] = function(name, description, unused)
        return format("- %s %s", 
          color_heading(format("%s:", name)),
          color_normal(description))
      end,
    },
  }
  option_formatter["range"] = option_formatter["text"]
  option_formatter["group"]["range"] = option_formatter["group"]["text"]
  option_formatter["select"] = option_formatter["text"]
  option_formatter["group"]["select"] = option_formatter["group"]["text"]
  option_formatter["choice"] = option_formatter["text"]
  option_formatter["group"]["choice"] = option_formatter["group"]["text"]
  
  local text_options = {
    text = true,
    range = true,
    select = true,
    choice = true,
  }
  
  function M.formatText(name, description, text)
    local formatter = option_formatter["text"]
    return formatter(name, description, text)
  end
  
  function M.formatToggle(name, toggle)
    local formatter = option_formatter["toggle"]
    return formatter(name, toggle)
  end
  
  local function formatUsage(prefix, usage, command)
    local prefix_string = not isempty(prefix) and (' ' .. prefix) or ''
    return format("%s %s%s %s", color_heading("Usage:"), command,
      color_normal(prefix_string), usage or '')
  end
  
  local function formatGroupUsage(group, prefix, command)
    local args = getLowercaseKeyTable(group.args)
    local list = join(" \124 ", unpack(sortedKeys(args)))
    return formatUsage(prefix, format("{%s}", list), command)
  end
  
  local function formatHeader(options)
    return options.help or GetAddOnMetadata(A.name, "Notes")
  end

  function processSubcommand(options, cmd, option, msg, prefix)
    local toplevel_command = options.command
    
    -- No valid option found, so list top level options header
    if not option then
      local header = formatHeader(options)
      A:print(color_normal(header or ""))
      A:rawPrint(formatGroupUsage(options, nil, toplevel_command))
      
      -- List top level option status
      local group_formatter = option_formatter["group"]
      local args = getLowercaseKeyTable(options.args)
      for k, v in sortedPairs(args) do
        local formatter = group_formatter[v.type]
        A:rawPrint(formatter(tolower(k), v.desc, v.get and v.get()))
      end     
      return
    end
    
    if text_options[strlower(option.type)] then
      local validate = msg and option.validate
      local set_check = validate and validate(msg) or 
        not option.validate and isNotSpaceOrEmpty(msg)
      local get = option.get
      local formatter = option_formatter["text"]
      
      if not set_check then
        A:print(formatUsage(prefix, option.usage, toplevel_command))
        A:rawPrint(formatter(option.name, get and get() or ''))
      else
        local set = option.set
        if set then set(msg) end
        if get then
          A:print(formatter(option.name, get()))
        end
      end
    elseif leq(option.type, "toggle") then
      local formatter = option_formatter["toggle"]
      local get, set = option.get, option.set
      if set then set() end
      if get then 
        A:print(formatter(option.name, get()))
      end
    elseif leq(option.type, "execute") then
      local func = option.func
      if func then func() end
    elseif leq(option.type, "group") then
      local subcommand, rest
      if isNotSpaceOrEmpty(msg) then
        subcommand, rest = match(msg, "^(%S+)%s*(.*)$")
      end
      
      local args = getLowercaseKeyTable(option.args)
      local lc_subcommand = subcommand and tolower(subcommand)
      local child_option = lc_subcommand and args[lc_subcommand]
      
      -- No valid option found, so list group header and status
      if not child_option then
        A:print(formatGroupUsage(option, prefix, toplevel_command))
        local group_formatter = option_formatter["group"]
        for k, v in sortedPairs(args) do
          local formatter = group_formatter[v.type]
          A:rawPrint(formatter(k, v.desc, v.get and v.get()))
        end
        return
      else
        -- Tail call (return must be present)
        return processSubcommand(options, subcommand, child_option, rest,
          subcommand and join(" ", prefix, subcommand) or prefix)
      end
    else
      A.error("Unknown option type: %s.", tostring(option.type))
      return
    end
  end
  
  function M.processCommand(msg, options, command)    
    if not options then
      A.error("Command option processing requires an options table object.")
      return
    elseif not options.type or options.type ~= "group" then
      A.error("The toplevel option has to contain a type='group' entry.")
      return
    elseif not options.args then
      A.error("Every type='group' option has to contain an args=<table> entry.")
      return
    end
    
    if not command or strlen(command) < 1 then
      A.error("The command associated with toplevel options is required.")
      return
    end
    
    -- Inject toplevel command into toplevel options if not present
    if not options.command then options.command = command end
    
    local subcommand, rest
    if isNotSpaceOrEmpty(msg) then
      subcommand, rest = match(msg, "^(%S+)%s*(.*)$")
    end
    
    local args = getLowercaseKeyTable(options.args)
    local lc_subcommand = subcommand and tolower(subcommand)
    local suboption = lc_subcommand and args[lc_subcommand]
    
    return processSubcommand(options, subcommand, suboption, rest, subcommand)
  end
end
