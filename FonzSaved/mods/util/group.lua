local A = FonzSaved

A.module 'util.group'

local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers = GetNumRaidMembers
local GetPartyLeaderIndex = GetPartyLeaderIndex
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRealNumPartyMembers = GetRealNumPartyMembers
local GetRealNumRaidMembers = GetRealNumRaidMembers
local IsInInstance = IsInInstance
local IsRealPartyLeader = IsRealPartyLeader
local IsRealRaidLeader = IsRealRaidLeader
local UnitName = UnitName
local UnitClass = UnitClass

local format = string.format
local strlower = strlower

function M.isInParty()
  return GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0
end

function M.isInRaid()
  return GetNumRaidMembers() > 0
end

function M.isInGroup()
  return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

function M.isPveGroup()
  -- Only interested in group membership outside of PvP (battlegrounds)
  local num_raid = GetRealNumRaidMembers()
  local num_party = GetRealNumPartyMembers()
  return (num_raid > 0 and "RAID") or (num_party > 0 and "PARTY")
end

function M.isPveInstance()
  local is_instance, instance_type = IsInInstance()
  if not is_instance then return end
  if instance_type == "pvp" or instance_type == "arena" then return end
  
  return is_instance, instance_type
end

function M.getPartyLeader()  
  local index = GetPartyLeaderIndex()
  if not index then return end
  
  if index > 0 then
    local unit = format("party%d", index)
    return UnitName(unit), UnitClass(unit)
  else
    if not UnitInParty("player") then return end
    return UnitName("player"), UnitClass("player")
  end
end

do
  local RANK_LEADER = 2
  
  function M.getRaidLeader()
    if GetRealNumRaidMembers() < 2 then return end
    
    for i=1,MAX_RAID_MEMBERS do
      local name, rank, party, level, _, class, zone, online 
        = GetRaidRosterInfo(i)
      if name and rank == RANK_LEADER then
        return name, class, online, level, party, zone
      end
    end
  end
end

do
  local funcs = {
    ["PARTY"] = getPartyLeader,
    ["RAID"] = getRaidLeader,
  }
  
  function M.getPveGroupLeader()
    local group = isPveGroup()
    if group then
      return funcs[group]()
    end
  end
end

function M.isPveGroupLeader(name)
  if not name then
    return IsRealRaidLeader() or IsRealPartyLeader()
  else
    local leader = getPveGroupLeader()
    return leader and strlower(leader) == strlower(name)
  end
end