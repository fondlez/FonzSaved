local A = FonzSaved

A.module 'util.network'

local util = A.requires(
  'util.table',
  'util.string'
)

local SendAddonMessage = SendAddonMessage

local format = format
local strlen = strlen
local tinsert, tconcact = table.insert, table.concat

local strsplit = util.strsplit

--[[
EBNF syntax for serialization:

msg = command block, [ block delimiter, payload block ] ;
command block = command, [ field delimiter, instruction ] ;
payload block = entry block, { block delimiter, entry block } ;
entry block = subentry, { field delimiter, subentry } ;
--]]

local default_delim = {
  block = "@", -- EBNF block delimiter (default)
  field = "=", -- EBNF field delimiter (default)
}

function M.serialize(command, instruction, payload, block_delim, field_delim)
  if not command then return end
  
  block_delim = block_delim or default_delim.block
  field_delim = field_delim or default_delim.field
  
  local msg = command
  
  local str = instruction and tostring(instruction)
  if str then
    msg = format("%s%s%s", msg, field_delim, str)
  end
  
  if not payload then return msg end
  
  if type(payload) == "table" then
    local num_payload = getn(payload)
    
    for i,entry in ipairs(payload) do
      -- First entry needs block delimiter from previous block (command)
      if i == 1 then
        msg = format("%s%s", msg, block_delim)
      end
      
      if type(entry) == "table" then
        local num_entry = getn(entry)
        
        for j,subentry in ipairs(entry) do
          msg = format("%s%s", msg, tostring(subentry))
          
          if j < num_entry then
            msg = format("%s%s", msg, field_delim)
          end
        end
      else
        msg = format("%s%s", msg, tostring(entry))
      end
      
      -- Add block delimiter if not last entry
      if i < num_payload then
        msg = format("%s%s", msg, block_delim)
      end
    end
  else
    msg = format("%s%s%s", msg, block_delim, tostring(payload))
  end
  
  return msg, block_delim, field_delim
end

function M.deserialize(msg, block_delim, field_delim)
  if not msg or strlen(msg) < 1 then return end
  
  block_delim = block_delim or default_delim.block
  field_delim = field_delim or default_delim.field
  
  local blocktable = { strsplit(block_delim, msg) }
  local num_blocks = getn(blocktable)

  -- First block: command block
  local fieldtable = { strsplit(field_delim, blocktable[1]) }
  local num_fields = getn(fieldtable)
  
  local command = fieldtable[1]
  local instruction = num_fields > 1 and fieldtable[2]
  
  -- Only command block table present, so return early
  if num_blocks == 1 then
    return command, instruction
  end
  
  -- Payload block present. Reconstruct payload
  local payload = {}
  for i=2,num_blocks do
    tinsert(payload, { strsplit(field_delim, blocktable[i]) })
  end
  
  return command, instruction, payload, block_delim, field_delim
end

function M.send(msg, channel, target)
  return pcall(SendAddonMessage, A.name, msg, channel, target)
end