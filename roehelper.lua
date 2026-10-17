-- roehelper.lua – RoE Helper (Ashita v4), based on commandobill/roe
-- Author: Original by Cair, ported by Commandobill
-- Description: Create and manage RoE profiles with configurable settings

addon.name    = 'roehelper'
addon.version = '1.0.2'
addon.author  = 'Original by Cair, ported by Commandobill; UI by Adamantking'
addon.desc    = 'Create and activate RoE profiles'
addon.link    = 'https://github.com/commandobill/roe'

local config    = require('settings')
local chat      = require('chat')
local struct    = require('struct')
local bit       = require('bit')
local coroutine = coroutine
local roe_mapping = require('roe_mapping')

-- Print error message
local function eprint(msg) print(chat.header('roehelper') .. chat.error(msg)) end

-- Print normal message
local function nprint(msg) print(chat.header('roehelper') .. chat.message(msg)) end

-- Fuzzy string matching function using Ashita v4 string utilities
local function fuzzy_match(search_term, target_string)
    -- Normalize strings: lowercase, remove punctuation, clean whitespace
    search_term = search_term:lower():gsub('[%p]+', ' '):clean()
    target_string = target_string:lower():gsub('[%p]+', ' '):clean()
    
    -- Split into words using Ashita's split function
    local search_words = search_term:split(' ')
    local target_words = target_string:split(' ')
    
    -- Debug: Print detailed matching info for crystal objectives
    if target_string:find('crystal') and search_term:find('crystal') then
        nprint(('Debug fuzzy_match: search="%s" target="%s"'):format(search_term, target_string))
        nprint(('Debug: search_words=%s'):format(table.concat(search_words, ',')))
        nprint(('Debug: target_words=%s'):format(table.concat(target_words, ',')))
    end
    
    -- Check if all search words are found in target using exact word matches
    local matches = 0
    local total_possible_matches = 0
    
    for _, search_word in ipairs(search_words) do
        if search_word:len() > 0 then  -- Skip empty words
            total_possible_matches = total_possible_matches + 1
            for _, target_word in ipairs(target_words) do
                -- Use exact word match instead of contains for better precision
                if target_word == search_word then
                    matches = matches + 1
                    break
                end
            end
        end
    end
    
    -- Calculate final score
    local final_score
    if matches == total_possible_matches then
        -- All search words found - this is a perfect match regardless of extra words
        final_score = 1.0
    else
        -- Partial match - score based on percentage of search words found
        final_score = matches / total_possible_matches
    end
    
    -- Debug: Print score for crystal objectives
    if target_string:find('crystal') and search_term:find('crystal') then
        nprint(('Debug: matches=%d/%d, final_score=%.2f'):format(matches, total_possible_matches, final_score))
    end
    
    return final_score
end

-- Find RoE objectives by name using fuzzy matching
local function find_roe_by_name(search_term, require_all_words)
    local results = {}
    local min_score = require_all_words and 1.0 or 0.5  -- Require 100% match for bulk operations
    
    -- Debug: Print search term and min_score
    nprint(('Debug: Searching for "%s" with min_score %.1f'):format(search_term, min_score))
    
    for id, name in pairs(roe_mapping) do
        local score = fuzzy_match(search_term, name)
        if score >= min_score then
            results[#results + 1] = {
                id = id,
                name = name,
                score = score
            }
            -- Debug: Print when we add a result
            if name:find('Crystal') then
                nprint(('Debug: Added result %d: "%s" (score=%.2f)'):format(id, name, score))
            end
        end
    end
    
    -- Debug: Print number of results found
    nprint(('Debug: Found %d results'):format(#results))
    
    -- Sort by score (highest first)
    table.sort(results, function(a, b) return a.score > b.score end)
    
    return results
end

-- Send RoE packet with a given packet ID and objective ID
local function send_roe_packet(pid, roe_id)
    local pkt = struct.pack('bbbbHbb', pid, 0x04, 0x00, 0x00, roe_id, 0x00, 0x00):totable()
    AshitaCore:GetPacketManager():AddOutgoingPacket(pid, pkt)
end


-- Create a new set object with utility methods
local function _new_set(values)
    local self = {}
    if values then for _, v in pairs(values) do self[v] = true end end
    local mt = {}

    function mt.__index(t, k)
        if     k == 'add'          then return function(_, v) t[v] = true end
        elseif k == 'remove'       then return function(_, v) t[v] = nil end
        elseif k == 'contains'     then return function(_, v) return t[v] end
        elseif k == 'length'       then return function() local c = 0; for _ in pairs(t) do c = c + 1 end; return c end
        elseif k == 'keyset'       then return function() local r = S{}; for v in pairs(t) do r:add(v) end; return r end
        elseif k == 'update'       then return function(_, o) for v in pairs(o) do t[v] = true end end
        elseif k == 'diff'         then return function(_, o) local r = S{}; for v in pairs(t) do if not o[v] then r:add(v) end end; return r end
        elseif k == 'intersection' then return function(_, o) local r = S{}; for v in pairs(t) do if o[v] then r:add(v) end end; return r end
        elseif k == 'union'        then return function(_, o) local r = S{}; r:update(t); r:update(o); return r end
        elseif k == 'it'           then return function() local k; return function() k = next(t, k); return k end end
        end
    end

    return setmetatable(self, mt)
end

-- Global S constructor for sets
S = setmetatable({}, { __call = function(_, iter) return _new_set(iter) end })

-- Convert input into a Set object
local function as_set(value)
    if type(value) == 'string' then
        local arr = {}; for id in value:gmatch('%d+') do arr[#arr+1] = tonumber(id) end
        return S(arr)
    elseif type(value) == 'table' then
        if value.diff then return value end -- Already a Set
        local arr = {}
        for k, v in pairs(value) do
            if type(k) == 'number' and v == true then arr[#arr+1] = k
            elseif type(v) == 'number' then arr[#arr+1] = v end
        end
        return S(arr)
    end
    return S{}
end

-- Default configuration settings
local defaults = T{
    profiles      = { default = S{} },
    blacklist     = T{},
    clear         = true,
    clearprogress = false,
    clearall      = false,
    repeatables   = T{ 15, 117 },
}

-- State management
local roe = T{
    active    = S{},
    complete  = S{},
    max_count = 30,
    settings  = config.load(defaults)
}

-- Register settings update handler
config.register('settings', 'settings_update', function(s)
    if s then roe.settings = s end
    config.save()
end)

-- Cancel a specific RoE objective
local function cancel_roe(id)
    id = tonumber(id)
    if not id or roe.settings.blacklist[id] or not roe.active[id] then return end
    send_roe_packet(0x10D, id)
end

-- Accept a specific RoE objective
local function accept_roe(id)
    id = tonumber(id)
    if not id or roe.complete[id] or roe.active[id] then return end
    if id >= 4008 and id <= 4021 then return end
    send_roe_packet(0x10C, id)
end

-- Save current active RoE objectives as a profile
local function save_profile(name)
    if type(name) ~= 'string' then eprint('save: specify a profile name') return end
    name = name:lower()
    local list, n = {}, 0
    for id in pairs(roe.active) do n = n + 1; list[n] = id end
    roe.settings.profiles[name] = S(list)
    config.save()
    nprint(('saved %d objectives to profile %s'):format(n, name))
end

-- List all saved RoE profiles
local function list_profiles()
    nprint('Profiles: ' .. table.concat((function()
        local out = {}; for k in pairs(roe.settings.profiles) do out[#out+1] = k end
        table.sort(out); return out end)(), ', '))
end

-- Set and apply a saved profile of RoE objectives
local function set_profile(name)
    if type(name) ~= 'string' then eprint('set: specify a profile name') return end
    name = name:lower()
    local prof = as_set(roe.settings.profiles[name])
    if prof:length() == 0 then eprint(('set: profile "%s" does not exist or is empty'):format(name)) return end

    local have   = roe.active:keyset()
    local need   = prof:diff(have)
    local slots  = roe.max_count - roe.active:length()
    local remove = S{}

    if roe.settings.clearall then
        remove:update(have)
    elseif roe.settings.clear then
        for id, prog in pairs(roe.active) do
            if (need:length() - remove:length()) <= slots then break end
            if (prog == 0 or roe.settings.clearprogress) and not roe.settings.blacklist[id] then
                remove:add(id)
            end
        end
    end

    local remaining = need:length() - remove:length()
    if remaining > slots then
        eprint("not enough free ROE slots. Additional slots needed: " .. remaining - slots)
        return
    end

    for id in remove:it() do cancel_roe(id); coroutine.sleep(0.5) end
    for id in need:it()   do accept_roe(id); coroutine.sleep(0.5) end
    nprint(('loaded profile "%s"'):format(name))
end

-- Unset active objectives or those in a given profile
local function unset_profile(name)
    name = name and name:lower()
    if name and roe.settings.profiles[name] then
        local todo = roe.active:keyset():intersection(roe.settings.profiles[name])
        for id in todo:it() do cancel_roe(id); coroutine.sleep(0.5) end
        nprint(('unset profile "%s"'):format(name))
    elseif name then
        eprint(('unset: profile "%s" does not exist'):format(name))
    else
        nprint('clearing ROE objectives...')
        for id, prog in pairs(roe.active) do
            if prog == 0 or roe.settings.clearprogress then cancel_roe(id); coroutine.sleep(0.5) end
        end
        nprint('ROE objectives cleared...')
    end
end

-- Handle incoming RoE packets
ashita.events.register('packet_in','roe_in', function(e)
    if e.id == 0x111 then
        local was_known, old_active = roe.known, roe.active
        roe.active = S{}
        roe.known = true
            for i = 1, roe.max_count do
            local off   = 5 + ((i - 1) * 4)
            local word  = struct.unpack('I', e.data, off)   -- 32-bit LE
            local qid   = bit.band(word, 0xFFF)             -- lower 12 bits
            local prog  = bit.rshift(word, 12)              -- upper 20 bits
            if qid > 0 then
                roe.active[qid] = prog                      -- store progress %
            end
        end
        -- log the number of any RoE you just took yourself (RoEs added by this addon are already in
        -- roe.active, so they are not repeated; the first sync after login/reload is skipped)
        if was_known then
            for id in pairs(roe.active) do
                if old_active[id] == nil then
                    nprint(('RoE taken: #%d  %s   (repeatable: /roehelper repeat add %d)'):format(id, roe_mapping[id] or '?', id))
                end
            end
        end
    elseif e.id == 0x112 then
        local done = S{}
        local offset_val = struct.unpack('H', e.data, 133)
        for i = 0, 1023 do
            local byte = e.data:byte(5 + math.floor(i / 8))
            if bit.band(byte, bit.lshift(1, i % 8)) ~= 0 then
                done:add(i + offset_val * 1024)
            end
        end
        roe.complete:update(done)
    end
end)

local true_strings  = S{'true','t','y','yes','on'}
local false_strings = S{'false','f','n','no','off'}
local bool_strings  = true_strings:union(false_strings)

-- Handle toggle settings command
local function handle_setting(name, val)
    if type(name) ~= 'string' then eprint('settings: specify a setting name'); return end
    name = name:lower()
    if roe.settings[name] == nil then eprint(('settings: "%s" does not exist'):format(name)); return end
    if type(roe.settings[name]) ~= 'boolean' then eprint(('settings: "%s" is not a toggle'):format(name)); return end
    val = val and val:lower()
    if not val or not bool_strings:contains(val) then
        roe.settings[name] = not roe.settings[name]
    elseif true_strings:contains(val) then
        roe.settings[name] = true
    else
        roe.settings[name] = false
    end
    nprint(('setting "%s" is now %s'):format(name, tostring(roe.settings[name])))
    config.save()
end

-- Handle blacklist add/remove command
local function blacklist(action, id)
    action = action and action:lower()
    id = tonumber(id)
    if not (action and id) then eprint('blacklist usage: blacklist [add|remove] <id>'); return end
    if action == 'add' then
        roe.settings.blacklist[id] = true
        nprint(('quest %d added to blacklist'):format(id))
    elseif action == 'remove' then
        if id >= 4008 and id <= 4021 then return end
        roe.settings.blacklist[id] = nil
        nprint(('quest %d removed from blacklist'):format(id))
    else
        eprint('blacklist: first arg must be "add" or "remove"')
    end
    config.save()
end

-- Add a specific RoE objective by ID or name
local function add_roe(input)
    
    -- Try to parse as number first
    local id = tonumber(input)
    
    if id then
        -- Input is a number, treat as ID
        if roe.complete[id] then 
            local name = roe_mapping[id] or "Unknown"
            eprint(('RoE objective %d (%s) is already completed'):format(id, name))
            return 
        end
        if roe.active[id] then 
            local name = roe_mapping[id] or "Unknown"
            eprint(('RoE objective %d (%s) is already active'):format(id, name))
            return 
        end
        if id >= 4008 and id <= 4021 then 
            local name = roe_mapping[id] or "Unknown"
            eprint(('RoE objective %d (%s) cannot be added (auto hourly objectives)'):format(id, name))
            return 
        end
        
        accept_roe(id)
        local name = roe_mapping[id] or "Unknown"
        nprint(('Added RoE objective %d: %s'):format(id, name))
    else
        -- Input is not a number, treat as name search
        local results = find_roe_by_name(input)
        
        if #results == 0 then
            eprint(('No RoE objectives found matching "%s"'):format(input))
            return
        elseif #results == 1 then
            local result = results[1]
            if roe.complete[result.id] then 
                eprint(('RoE objective %d (%s) is already completed'):format(result.id, result.name))
                return 
            end
            if roe.active[result.id] then 
                eprint(('RoE objective %d (%s) is already active'):format(result.id, result.name))
                return 
            end
            if result.id >= 4008 and result.id <= 4021 then 
                eprint(('RoE objective %d (%s) cannot be added (restricted range)'):format(result.id, result.name))
                return 
            end
            
            accept_roe(result.id)
            nprint(('Added RoE objective %d: %s'):format(result.id, result.name))
        else
            -- Multiple matches found - check if there's a 100% match
            local perfect_match = nil
            for _, result in ipairs(results) do
                if result.score == 1.0 then
                    perfect_match = result
                    break
                end
            end
            
            if perfect_match then
                -- Use the perfect match automatically
                if roe.complete[perfect_match.id] then 
                    eprint(('RoE objective %d (%s) is already completed'):format(perfect_match.id, perfect_match.name))
                    return 
                end
                if roe.active[perfect_match.id] then 
                    eprint(('RoE objective %d (%s) is already active'):format(perfect_match.id, perfect_match.name))
                    return 
                end
                if perfect_match.id >= 4008 and perfect_match.id <= 4021 then 
                    eprint(('RoE objective %d (%s) cannot be added (restricted range)'):format(perfect_match.id, perfect_match.name))
                    return 
                end
                
                accept_roe(perfect_match.id)
                nprint(('Added RoE objective %d: %s'):format(perfect_match.id, perfect_match.name))
            else
                -- No perfect match, show multiple results
                eprint(('Multiple RoE objectives found matching "%s":'):format(input))
                for i = 1, math.min(5, #results) do  -- Show top 5 matches
                    local result = results[i]
                    nprint(('  %d: %s (%.0f%% match)'):format(result.id, result.name, result.score * 100))
                end
                if #results > 5 then
                    nprint(('  ... and %d more matches'):format(#results - 5))
                end
                eprint('Please be more specific or use the ID directly.')
            end
        end
    end
end

-- Remove a specific RoE objective by ID or name
local function rem_roe(input)
    -- Check if we have 0 active RoEs (status needs refresh)
    if roe.active:length() == 0 then
        eprint('No active RoE objectives detected. Please add an RoE objective to refresh the status.')
        return
    end
    
    -- Try to parse as number first
    local id = tonumber(input)
    
    if id then
        -- Input is a number, treat as ID
        if not roe.active[id] then 
            local name = roe_mapping[id] or "Unknown"
            eprint(('RoE objective %d (%s) is not currently active'):format(id, name))
            return 
        end
        if roe.settings.blacklist[id] then
            local name = roe_mapping[id] or "Unknown"
            eprint(('RoE objective %d (%s) is blacklisted and cannot be removed'):format(id, name))
            return 
        end
        
        cancel_roe(id)
        local name = roe_mapping[id] or "Unknown"
        nprint(('Removed RoE objective %d: %s'):format(id, name))
    else
        -- Input is not a number, treat as name search
        local results = find_roe_by_name(input)
        
        if #results == 0 then
            eprint(('No RoE objectives found matching "%s"'):format(input))
            return
        elseif #results == 1 then
            local result = results[1]
            if not roe.active[result.id] then 
                eprint(('RoE objective %d (%s) is not currently active'):format(result.id, result.name))
                return 
            end
            if roe.settings.blacklist[result.id] then
                eprint(('RoE objective %d (%s) is blacklisted and cannot be removed'):format(result.id, result.name))
                return 
            end
            
            cancel_roe(result.id)
            nprint(('Removed RoE objective %d: %s'):format(result.id, result.name))
        else
            -- Multiple matches found - check if there's a 100% match
            local perfect_match = nil
            for _, result in ipairs(results) do
                if result.score == 1.0 then
                    perfect_match = result
                    break
                end
            end
            
            if perfect_match then
                -- Use the perfect match automatically
                if not roe.active[perfect_match.id] then 
                    eprint(('RoE objective %d (%s) is not currently active'):format(perfect_match.id, perfect_match.name))
                    return 
                end
                if roe.settings.blacklist[perfect_match.id] then
                    eprint(('RoE objective %d (%s) is blacklisted and cannot be removed'):format(perfect_match.id, perfect_match.name))
                    return 
                end
                
                cancel_roe(perfect_match.id)
                nprint(('Removed RoE objective %d: %s'):format(perfect_match.id, perfect_match.name))
            else
                -- No perfect match, show multiple results
                eprint(('Multiple RoE objectives found matching "%s":'):format(input))
                for i = 1, math.min(5, #results) do  -- Show top 5 matches
                    local result = results[i]
                    local status = ""
                    if not roe.active[result.id] then
                        status = " (not active)"
                    elseif roe.settings.blacklist[result.id] then
                        status = " (blacklisted)"
                    end
                    nprint(('  %d: %s (%.0f%% match)%s'):format(result.id, result.name, result.score * 100, status))
                end
                if #results > 5 then
                    nprint(('  ... and %d more matches'):format(#results - 5))
                end
                eprint('Please be more specific or use the ID directly.')
            end
        end
    end
end

-- Add multiple RoE objectives by name using fuzzy matching
local function addall_roe(input)
    
    -- Only works with name search, not ID
    local id = tonumber(input)
    if id then
        eprint('addall: use "add" command for specific ID numbers')
        return
    end
    
    -- Search for matches (require all words to match for bulk operations)
    local results = find_roe_by_name(input, true)
    
    if #results == 0 then
        eprint(('No RoE objectives found matching "%s"'):format(input))
        return
    elseif #results > 10 then
        eprint(('Too many RoE objectives found matching "%s" (%d matches)'):format(input, #results))
        eprint('Showing first 10 matches:')
        for i = 1, 10 do
            local result = results[i]
            local status = ""
            if roe.complete[result.id] then
                status = " (completed)"
            elseif roe.active[result.id] then
                status = " (active)"
            elseif result.id >= 4008 and result.id <= 4021 then
                status = " (restricted)"
            end
            nprint(('  %d: %s (%.0f%% match)%s'):format(result.id, result.name, result.score * 100, status))
        end
        eprint('Please be more specific or use individual IDs.')
        return
    end
    
    -- Check available slots
    local available_slots = roe.max_count - roe.active:length()
    local objectives_to_add = 0
    
    -- Count how many objectives we can actually add
    for _, result in ipairs(results) do
        if not roe.complete[result.id] and not roe.active[result.id] and not (result.id >= 4008 and result.id <= 4021) then
            objectives_to_add = objectives_to_add + 1
        end
    end
    
    if objectives_to_add > available_slots then
        eprint("not enough free ROE slots. Additional slots needed: " .. (objectives_to_add - available_slots))
        eprint(('Found %d objectives to add, but only %d slots available'):format(objectives_to_add, available_slots))
        return
    end
    
    -- Process all matches
    local added_count = 0
    local skipped_count = 0
    local skipped_reasons = {}
    
    for _, result in ipairs(results) do
        if roe.complete[result.id] then 
            skipped_count = skipped_count + 1
            skipped_reasons[#skipped_reasons + 1] = ('%d (%s) - already completed'):format(result.id, result.name)
        elseif roe.active[result.id] then 
            skipped_count = skipped_count + 1
            skipped_reasons[#skipped_reasons + 1] = ('%d (%s) - already active'):format(result.id, result.name)
        elseif result.id >= 4008 and result.id <= 4021 then 
            skipped_count = skipped_count + 1
            skipped_reasons[#skipped_reasons + 1] = ('%d (%s) - restricted range'):format(result.id, result.name)
        else
            accept_roe(result.id)
            coroutine.sleep(0.5)
            added_count = added_count + 1
        end
    end
    
    -- Report results
    if added_count > 0 then
        nprint(('Added %d RoE objectives matching "%s"'):format(added_count, input))
    end
    
    if skipped_count > 0 then
        eprint(('Skipped %d objectives:'):format(skipped_count))
        for _, reason in ipairs(skipped_reasons) do
            eprint(('  %s'):format(reason))
        end
    end
    
    if added_count == 0 and skipped_count == 0 then
        eprint(('No objectives were processed for "%s"'):format(input))
    end
end

-- Remove multiple RoE objectives by name using fuzzy matching
local function remall_roe(input)
    -- Check if we have 0 active RoEs (status needs refresh)
    if roe.active:length() == 0 then
        eprint('No active RoE objectives detected. Please add an RoE objective to refresh the status.')
        return
    end
    
    -- Only works with name search, not ID
    local id = tonumber(input)
    if id then
        eprint('remall: use "rem" command for specific ID numbers')
        return
    end
    
    -- Search for matches (require all words to match for bulk operations)
    local results = find_roe_by_name(input, true)
    
    if #results == 0 then
        eprint(('No RoE objectives found matching "%s"'):format(input))
        return
    elseif #results > 10 then
        eprint(('Too many RoE objectives found matching "%s" (%d matches)'):format(input, #results))
        eprint('Showing first 10 matches:')
        for i = 1, 10 do
            local result = results[i]
            local status = ""
            if not roe.active[result.id] then
                status = " (not active)"
            elseif roe.settings.blacklist[result.id] then
                status = " (blacklisted)"
            end
            nprint(('  %d: %s (%.0f%% match)%s'):format(result.id, result.name, result.score * 100, status))
        end
        eprint('Please be more specific or use individual IDs.')
        return
    end
    
    -- Process all matches
    local removed_count = 0
    local skipped_count = 0
    local skipped_reasons = {}
    
    for _, result in ipairs(results) do
        if not roe.active[result.id] then 
            skipped_count = skipped_count + 1
            skipped_reasons[#skipped_reasons + 1] = ('%d (%s) - not currently active'):format(result.id, result.name)
        elseif roe.settings.blacklist[result.id] then
            skipped_count = skipped_count + 1
            skipped_reasons[#skipped_reasons + 1] = ('%d (%s) - blacklisted'):format(result.id, result.name)
        else
            cancel_roe(result.id)
            coroutine.sleep(0.5)
            removed_count = removed_count + 1
        end
    end
    
    -- Report results
    if removed_count > 0 then
        nprint(('Removed %d RoE objectives matching "%s"'):format(removed_count, input))
    end
    
    if skipped_count > 0 then
        eprint(('Skipped %d objectives:'):format(skipped_count))
        for _, reason in ipairs(skipped_reasons) do
            eprint(('  %s'):format(reason))
        end
    end
    
    if removed_count == 0 and skipped_count == 0 then
        eprint(('No objectives were processed for "%s"'):format(input))
    end
end

-- Show current RoE status for debugging
local function show_status()
    nprint('Current RoE Status:')
    nprint(('Active objectives: %d/%d'):format(roe.active:length(), roe.max_count))
    
    if roe.active:length() > 0 then
        nprint('Active objectives:')
        for id, progress in pairs(roe.active) do
            local name = roe_mapping[id] or "Unknown"
            nprint(('  %d: %s (%.0f%% progress)'):format(id, name, progress))
        end
    else
        nprint('No active objectives found')
    end
    
    nprint(('Completed objectives: %d'):format(roe.complete:length()))
    nprint(('Blacklisted objectives: %d'):format(table.getn(roe.settings.blacklist)))
    
    -- Note: Status refresh requires adding an RoE objective
    nprint('Note: If status appears incorrect, add an RoE objective to refresh the status.')
end

-- Print help text to chat
local function help()
    nprint([[
ROE - Command List

/roehelper help
    Show this help menu.

/roehelper ui
    Toggle the RoE helper window (zone RoEs, element stones, dailies, repeatables).

/roehelper zone
    Add the combat RoEs and day/weather stones for your current zone.

/roehelper repeat <add|rem|list> [id or name]
    Manage the repeatables list shown in the window.

/roehelper add <id or name>
    Add a specific ROE objective by its ID number or name.
    Examples:
    /roehelper add 77
    /roehelper add "spoils light crystal"
    /roehelper add "vanquish enemy"

/roehelper rem <id or name>
    Remove a specific ROE objective by its ID number or name.
    Examples:
    /roehelper rem 77
    /roehelper rem "spoils light crystal"
    /roehelper rem "vanquish enemy"

/roehelper addall <name>
    Add all ROE objectives matching the name (max 10 matches).
    Examples:
    /roehelper addall "crystal"
    /roehelper addall "vanquish"

/roehelper remall <name>
    Remove all ROE objectives matching the name (max 10 matches).
    Examples:
    /roehelper remall "crystal"
    /roehelper remall "vanquish"

/roehelper save <profile name>
    Save your currently set ROE objectives to a named profile.

/roehelper set <profile name>
    Load and apply a saved profile of ROE objectives.
    - Objectives may be canceled automatically based on settings.
    - By default, only incomplete objectives will be removed if space is needed.

/roehelper unset [<profile name>]
    Remove the currently set ROE objectives.
    - Without a name, it will only remove objectives with no progress.
    - If a profile is specified, it removes only those objectives.

/roehelper list
    List all saved profile names.

/roehelper settings <name> [true|false]
    Toggle a settings value, or set it explicitly.
    * clear         : Remove inactive objectives if needed (default: true)
    * clearprogress : Also remove in-progress objectives (default: false)
    * clearall      : Clear all objectives before loading (default: false)

/roehelper blacklist [add|remove] <id>
    Add or remove a quest from the blacklist.
    - Blacklisted objectives will not be removed automatically.

/roehelper status
    Show current RoE status. If no active objectives are shown, add an RoE objective to refresh the status.
]])
end

-- Command dispatch table
local handlers = {
    save      = save_profile,
    list      = list_profiles,
    set       = set_profile,
    unset     = unset_profile,
    settings  = handle_setting,
    blacklist = blacklist,
    add       = add_roe,
    rem       = rem_roe,
    addall    = addall_roe,
    remall    = remall_roe,
    status    = show_status,
    help      = help,
}

-- Ashita command event
ashita.events.register('command','roe_cmd',function(e)
    local a = e.command:args(); if #a == 0 or a[1]:lower() ~= '/roehelper' then return end
    e.blocked = true
    local sub = a[2] and a[2]:lower() or 'ui'   -- plain /roehelper opens the window; /roehelper help lists commands
    if handlers[sub] then handlers[sub](table.unpack(a, 3))
    else nprint(('unknown roe sub-command: %s'):format(sub)) end
end)



-- Check if world state is ready
local function is_world_ready()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local player_ent = GetPlayerEntity()
    return not (player == nil or player.isZoning or player_ent == nil)
end

-- Initial load event
local _startup = { sent = false }
ashita.events.register('load','roe_load',function()
    for name, prof in pairs(roe.settings.profiles) do
        if type(prof) == 'string' then
            local arr = {}; for id in prof:gmatch('%d+') do arr[#arr+1] = tonumber(id) end
            roe.settings.profiles[name] = S(arr)
        end
    end
    if _startup.sent then return end
    if is_world_ready() then
        nprint('RoE addon loaded. Add an RoE objective to refresh status if needed.')
        _startup.sent = true
    end
end)


--------------------------------------------------------------------------------
-- RoE UI window (combat wide area / region, element stones, dailies, repeatables)
--------------------------------------------------------------------------------
local imgui     = require('imgui')
local theme     = require('theme')
local roe_zones = require('roe_zones')

local ui = {
    visible     = true,
    open        = { true },
    queue       = {},          -- pending { kind = 'add'|'rem', id = n }
    next_send   = 0,
    day_ov      = 'auto',      -- 'auto' or an element name
    weather_ov  = 'auto',      -- 'auto', 'none' or an element name
    weather_id  = nil,         -- from packet 0x057
    clear_arm   = 0,           -- time until which "Remove ALL" is armed
    sel_key     = nil,         -- zone chosen in the conflict dropdown
    rep_buf     = { '' },
    msg         = { text = '', t_end = 0, bad = false },
}

local COL_HEAD = theme.C.gold
local COL_GOOD = theme.C.green
local COL_DIM  = theme.C.muted
local COL_WARN = theme.C.warn
local COL_SEL  = 'primary'      -- btn() markers, not colours
local COL_DEL  = 'danger'

-- Vana'diel day (0 = Firesday) and weather ids ----------------------------------
local DAYS = { [0] = 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark' }

local WEATHER = {
    [0]  = { 'Clear' },                  [1]  = { 'Sunshine' },
    [2]  = { 'Clouds' },                 [3]  = { 'Fog' },
    [4]  = { 'Hot Spell', 'Fire' },      [5]  = { 'Heat Wave', 'Fire' },
    [6]  = { 'Rain', 'Water' },          [7]  = { 'Squall', 'Water' },
    [8]  = { 'Dust Storm', 'Earth' },    [9]  = { 'Sand Storm', 'Earth' },
    [10] = { 'Wind', 'Wind' },           [11] = { 'Gale', 'Wind' },
    [12] = { 'Snow', 'Ice' },            [13] = { 'Blizzard', 'Ice' },
    [14] = { 'Thunder', 'Lightning' },   [15] = { 'Thunderstorm', 'Lightning' },
    [16] = { 'Aurora', 'Light' },        [17] = { 'Stellar Glare', 'Light' },
    [18] = { 'Gloom', 'Dark' },          [19] = { 'Darkness', 'Dark' },
}

local function game_day()
    local vana = (os.time() - 1009810800) * 25       -- Vana'diel seconds since the epoch
    return DAYS[math.floor(vana / 86400) % 8]
end

ashita.events.register('packet_in', 'roe_weather', function(e)
    if e.id == 0x057 then
        local w = struct.unpack('H', e.data, 9)       -- weather id (uint16 at byte offset 8)
        if w and WEATHER[w] then ui.weather_id = w end
    end
end)

-- effective day / weather element (override wins) ---------------------------------
local function day_element()
    if ui.day_ov ~= 'auto' then return ui.day_ov, true end
    return game_day(), false
end

local function weather_info()
    -- returns element-or-nil, display text, overridden?
    if ui.weather_ov == 'none' then return nil, 'None', true end
    if ui.weather_ov ~= 'auto' then return ui.weather_ov, ui.weather_ov, true end
    local w = ui.weather_id and WEATHER[ui.weather_id]
    if not w then return nil, 'Unknown', false end
    return w[2], w[1], false
end

-- zone ----------------------------------------------------------------------------
local function norm(s)
    s = (s or ''):lower()
    s = s:gsub('^the%s+', '')
    s = s:gsub('[%p]', ' ')
    s = s:gsub('%s+', ' ')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    return s
end

local function current_zone()
    local ok, id = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0) end)
    if not ok or not id or id == 0 then return nil, 'Unknown' end
    local ok2, name = pcall(function() return AshitaCore:GetResourceManager():GetString('zones.names', id) end)
    if not ok2 or not name or name == '' then return nil, ('Zone %d'):format(id) end
    return norm(name), name
end

-- index of "Conflict: <zone>" RoEs (all tiers I/II/III...), excluding Unity (UC) ones
local conflict_by_zone = {}
local region_of_zone   = {}
local region_roe_id    = {}
local zone_names       = {}   -- normalized key -> display name
local zone_list        = {}   -- sorted { key =, name = } for the dropdown

local function build_indexes()
    conflict_by_zone, region_of_zone, region_roe_id = {}, {}, {}
    zone_names, zone_list = {}, {}
    local the_set = {}
    for _, n in ipairs(roe_zones.THE_ZONES or {}) do the_set[n] = true end
    for id, name in pairs(roe_mapping) do
        local base = name:match('^Conflict: (.+)$')
        if base and not base:find('%(UC%)') then
            for pat, rep in pairs(roe_zones.ZONE_ALIASES) do base = base:gsub(pat, rep) end
            base = base:gsub('%s+[IVX]+$', '')             -- drop tier suffix
            local key = norm(base)
            conflict_by_zone[key] = conflict_by_zone[key] or {}
            table.insert(conflict_by_zone[key], id)
            if not zone_names[key] then zone_names[key] = the_set[base] and ('The ' .. base) or base end
        end
        local region = name:match('^Region: (.+)$')
        if region then region_roe_id[region] = id end
    end
    for _, list in pairs(conflict_by_zone) do table.sort(list) end
    for key, name in pairs(zone_names) do zone_list[#zone_list + 1] = { key = key, name = name } end
    table.sort(zone_list, function(a, b) return a.key < b.key end)   -- key ignores a leading "The"
    for region, zones in pairs(roe_zones.REGION_ZONES) do
        for _, z in ipairs(zones) do region_of_zone[norm(z)] = region end
    end
end

-- queue ---------------------------------------------------------------------------
local function say(text, bad)
    ui.msg = { text = text, t_end = os.clock() + 8, bad = bad or false }
    if bad then eprint(text) else nprint(text) end
end

local function pending_adds()
    local n = 0
    for _, q in ipairs(ui.queue) do if q.kind == 'add' then n = n + 1 end end
    return n
end

local function queued(kind, id)
    for _, q in ipairs(ui.queue) do
        if q.kind == kind and q.id == id then return true end
    end
    return false
end

-- Queue adds. force = ignore the "already completed" flag (repeatable / daily RoEs);
-- it can be true (all ids) or a table { [id] = true } (only those ids).
-- Returns added count, then list of skip reasons.
local function queue_adds(ids, force)
    local function is_forced(id)
        return force == true or (type(force) == 'table' and force[id] == true)
    end
    local free = roe.max_count - roe.active:length() - pending_adds()
    local added, skipped = 0, {}
    for _, id in ipairs(ids) do
        local name = roe_mapping[id] or ('#' .. id)
        if roe.active[id] or queued('add', id) then
            skipped[#skipped + 1] = name .. ' (already active)'
        elseif roe.complete[id] and not is_forced(id) then
            skipped[#skipped + 1] = name .. ' (completed)'
        elseif id >= 4008 and id <= 4021 then
            skipped[#skipped + 1] = name .. ' (automatic)'
        elseif added >= free then
            skipped[#skipped + 1] = name .. ' (no free slot)'
        else
            ui.queue[#ui.queue + 1] = { kind = 'add', id = id }
            added = added + 1
        end
    end
    return added, skipped
end

local function report(title, added, skipped)
    local msg = ('%s: %d queued'):format(title, added)
    if #skipped > 0 then msg = msg .. (', %d skipped'):format(#skipped) end
    say(msg, false)
    for _, s in ipairs(skipped) do nprint('  skipped: ' .. s) end
end

local function queue_rem(id)
    if roe.active[id] and not roe.settings.blacklist[id] and not queued('rem', id) then
        ui.queue[#ui.queue + 1] = { kind = 'rem', id = id }
        return true
    end
    return false
end

-- Process one queued packet every 0.6 s (same pacing as the command versions)
local function pump_queue(now)
    if #ui.queue == 0 or now < ui.next_send then return end
    local q = table.remove(ui.queue, 1)
    if q.kind == 'add' then
        send_roe_packet(0x10C, q.id)
        roe.active[q.id] = 0                 -- optimistic; the server's 0x111 corrects it
    else
        send_roe_packet(0x10D, q.id)
        roe.active[q.id] = nil
    end
    ui.next_send = now + 0.6
end

-- zone plan: conflict + region + element stones ------------------------------------
local function build_plan(zone_key)
    local plan = {}
    local znorm = zone_key or current_zone()
    if znorm then
        for _, id in ipairs(conflict_by_zone[znorm] or {}) do
            plan[#plan + 1] = { id = id, why = 'Combat (Wide Area)' }
        end
        local region = region_of_zone[znorm]
        if region and region_roe_id[region] then
            plan[#plan + 1] = { id = region_roe_id[region], why = 'Combat (Region)' }
        end
    end
    local day_el = day_element()
    local weather_el = weather_info()
    local seen = {}
    for _, el in ipairs({ day_el, weather_el }) do
        if el and not seen[el] then
            seen[el] = true
            if roe_zones.GEODES[el] then plan[#plan + 1] = { id = roe_zones.GEODES[el], why = el .. ' geode', force = true } end
            if roe_zones.ITES[el]   then plan[#plan + 1] = { id = roe_zones.ITES[el],   why = el .. ' stone', force = true } end
        end
    end
    return plan
end

local function add_zone_roes(zone_key)
    local plan = build_plan(zone_key)
    if #plan == 0 then say('Nothing to add for this zone.', true) return end
    local ids, forced = {}, {}
    for _, p in ipairs(plan) do
        ids[#ids + 1] = p.id
        if p.force then forced[p.id] = true end       -- geodes / -ite stones repeat
    end
    local title = zone_key and ('Zone RoEs (' .. (zone_names[zone_key] or zone_key) .. ')') or 'Zone RoEs'
    local added, skipped = queue_adds(ids, forced)
    report(title, added, skipped)
end

local function add_element_set(tbl, label)
    local ids = {}
    for _, el in ipairs(roe_zones.ELEMENTS) do ids[#ids + 1] = tbl[el] end
    local added, skipped = queue_adds(ids, true)          -- repeatable: never skip as "completed"
    report(label, added, skipped)
end

local function remove_all()
    local n = 0
    for id in pairs(roe.active) do
        if type(id) == 'number' and not (id >= 4008 and id <= 4021) then
            if queue_rem(id) then n = n + 1 end
        end
    end
    say(('Remove all: %d objectives queued for removal'):format(n), false)
end

-- repeatables -----------------------------------------------------------------------
local function repeatables()
    if type(roe.settings.repeatables) ~= 'table' then
        roe.settings.repeatables = T{}
        for _, id in ipairs(roe_zones.DEFAULT_REPEATABLES) do roe.settings.repeatables[#roe.settings.repeatables + 1] = id end
        config.save()
    end
    return roe.settings.repeatables
end

local function repeat_has(id)
    for _, v in ipairs(repeatables()) do if v == id then return true end end
    return false
end

local function repeat_add(input)
    local id = tonumber(input)
    if not id then
        local hits = {}
        for rid, name in pairs(roe_mapping) do
            if fuzzy_match(input, name) >= 1.0 then hits[#hits + 1] = rid end
        end
        table.sort(hits)
        if #hits == 0 then say(('No RoE matches "%s"'):format(input), true) return end
        if #hits > 1 then
            say(('"%s" matches %d RoEs - use an id (/roehelper repeat add <id>):'):format(input, #hits), true)
            for i = 1, math.min(5, #hits) do nprint(('  %d: %s'):format(hits[i], roe_mapping[hits[i]])) end
            return
        end
        id = hits[1]
    end
    if not roe_mapping[id] then say(('Unknown RoE id %d'):format(id), true) return end
    if repeat_has(id) then say(('%s is already in the repeatables list'):format(roe_mapping[id]), true) return end
    local list = repeatables()
    list[#list + 1] = id
    config.save()
    say(('Added to repeatables: %s'):format(roe_mapping[id]))
end

local function repeat_rem(input)
    local id = tonumber(input)
    local list = repeatables()
    for i, v in ipairs(list) do
        if v == id then
            table.remove(list, i)
            config.save()
            say(('Removed from repeatables: %s'):format(roe_mapping[id] or id))
            return
        end
    end
    say('That id is not in the repeatables list', true)
end

local function repeat_toggle(id, want_on)
    if want_on then
        local added = queue_adds({ id }, true)
        if added == 0 then say(('Could not add %s (slot/active)'):format(roe_mapping[id] or id), true) end
    else
        queue_rem(id)
    end
end

-- command: /roehelper ui | /roehelper zone | /roehelper repeat <add|rem|list> ---------------------------
handlers.ui   = function() ui.visible = not ui.visible; ui.open[1] = true end
handlers.zone = function(...)
    local name = table.concat({ ... }, ' ')
    if name == '' then add_zone_roes() return end
    local key = norm(name)
    if not conflict_by_zone[key] then say(('No conflict RoE found for zone "%s"'):format(name), true) return end
    add_zone_roes(key)
end
handlers['repeat'] = function(action, arg)
    action = action and action:lower()
    if action == 'add' and arg then repeat_add(arg)
    elseif (action == 'rem' or action == 'remove') and arg then repeat_rem(arg)
    elseif action == 'list' then
        for _, id in ipairs(repeatables()) do nprint(('  %d: %s'):format(id, roe_mapping[id] or '?')) end
    else
        eprint('usage: /roehelper repeat add <id or name> | rem <id> | list')
    end
end

-- drawing ---------------------------------------------------------------------------
local function btn(label, id, kind)
    if kind == COL_SEL then return theme.accent(label .. '##' .. id, nil, true) end
    if kind == COL_DEL then return theme.danger(label .. '##' .. id) end
    return theme.toggle(label, id, false)
end

local override_cycle = {
    day     = { 'auto', 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark' },
    weather = { 'auto', 'none', 'Fire', 'Earth', 'Water', 'Wind', 'Ice', 'Lightning', 'Light', 'Dark' },
}

local function cycle(kind)
    local list = override_cycle[kind]
    local cur = (kind == 'day') and ui.day_ov or ui.weather_ov
    local idx = 1
    for i, v in ipairs(list) do if v == cur then idx = i break end end
    local nxt = list[(idx % #list) + 1]
    if kind == 'day' then ui.day_ov = nxt else ui.weather_ov = nxt end
end

local function draw_plan(plan)
    if #plan == 0 then
        imgui.TextColored(COL_DIM, '  No combat RoEs found for this zone.')
    end
    for _, p in ipairs(plan) do
        local name = roe_mapping[p.id] or ('#' .. p.id)
        local state, col = '', { 1, 1, 1, 1 }
        if roe.active[p.id] then state, col = '  [active]', COL_GOOD
        elseif roe.complete[p.id] and not p.force then state, col = '  [done]', COL_DIM end
        imgui.TextColored(col, ('  %s  -  %s%s'):format(name, p.why, state))
    end
end

local function draw_window()
    imgui.SetNextWindowPos({ 120, 160 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 470, 640 }, ImGuiCond_FirstUseEver)
    ui.open[1] = true
    if not theme.begin('RoE Helper', ui.open) then imgui.End() return end
    theme.header(ui.open, 'RoE', 'HELPER', 'Records of Eminence')

    -- status ---------------------------------------------------------------------
    imgui.TextColored(COL_HEAD, ('Active RoEs: %d/%d'):format(roe.active:length(), roe.max_count))
    if #ui.queue > 0 then
        imgui.SameLine()
        imgui.TextColored(COL_WARN, ('   working... %d queued'):format(#ui.queue))
    end
    if roe.active:length() == 0 and not roe.known then
        imgui.TextColored(COL_WARN, 'RoE status not received yet - zone or add/remove one RoE to sync.')
    end
    if os.clock() < ui.msg.t_end then
        imgui.TextColored(ui.msg.bad and COL_WARN or COL_GOOD, ui.msg.text)
    end
    imgui.Separator()

    -- zone / day / weather -------------------------------------------------------
    local znorm, zname = current_zone()
    local day_el, day_ov = day_element()
    local w_el, w_text, w_ov = weather_info()
    imgui.Text('Zone:')
    imgui.SameLine()
    imgui.TextColored(COL_HEAD, zname)

    imgui.Text('Day:')
    imgui.SameLine()
    imgui.TextColored(COL_HEAD, day_el .. (day_ov and ' (manual)' or ''))
    imgui.SameLine()
    if btn('change', 'day') then cycle('day') end

    imgui.Text('Weather:')
    imgui.SameLine()
    imgui.TextColored(COL_HEAD, w_text .. (w_el and (' [' .. w_el .. ']') or '') .. (w_ov and ' (manual)' or ''))
    imgui.SameLine()
    if btn('change', 'wx') then cycle('weather') end
    imgui.TextColored(COL_DIM, 'Day/weather are read automatically; "change" cycles a manual override (auto first).')
    imgui.Separator()

    -- zone RoEs --------------------------------------------------------------------
    local plan = build_plan()
    if btn('Add Zone RoEs', 'zone', COL_SEL) then add_zone_roes(nil) end
    imgui.SameLine()
    imgui.TextColored(COL_DIM, '(current zone: combat + day/weather stones; no fishing/harvesting)')
    draw_plan(plan)
    imgui.Separator()

    -- manual conflict zone picker (alphabetical, ignoring "The") ---------------------------
    imgui.TextColored(COL_HEAD, 'Pick a conflict zone manually')
    if imgui.SetNextItemWidth then imgui.SetNextItemWidth(300) end
    local preview = ui.sel_key and zone_names[ui.sel_key] or 'Select a zone...'
    if imgui.BeginCombo('##confzone', preview) then
        for _, z in ipairs(zone_list) do
            if imgui.Selectable(z.name .. '##cz' .. z.key, ui.sel_key == z.key) then ui.sel_key = z.key end
        end
        imgui.EndCombo()
    end
    imgui.SameLine()
    if btn('Add', 'confadd', COL_SEL) then
        if ui.sel_key then add_zone_roes(ui.sel_key) else say('Select a zone first.', true) end
    end
    if ui.sel_key then draw_plan(build_plan(ui.sel_key)) end
    imgui.Separator()

    -- element sets -----------------------------------------------------------------
    imgui.TextColored(COL_HEAD, 'Element RoEs')
    if btn('Add All Crystals', 'crys') then add_element_set(roe_zones.CRYSTALS, 'Crystals') end
    imgui.SameLine()
    if btn('Add All Geodes', 'geo') then add_element_set(roe_zones.GEODES, 'Geodes') end
    imgui.SameLine()
    if btn('Add All -ite Stones', 'ite') then add_element_set(roe_zones.ITES, '-ite stones') end
    imgui.Separator()

    -- dailies ----------------------------------------------------------------------
    imgui.TextColored(COL_HEAD, 'Dailies')
    for i, d in ipairs(roe_zones.DAILIES) do
        local on = roe.active[d.id] ~= nil or queued('add', d.id)
        if i > 1 then imgui.SameLine() end
        if btn(d.label .. (on and '  [on]' or ''), 'daily' .. d.id, on and COL_SEL or nil) then
            if on then queue_rem(d.id) else queue_adds({ d.id }, true) end
        end
    end
    if btn('Add All Dailies', 'dailyall') then
        local ids = {}
        for _, d in ipairs(roe_zones.DAILIES) do ids[#ids + 1] = d.id end
        local added, skipped = queue_adds(ids, true)
        report('Dailies', added, skipped)
    end
    imgui.Separator()

    -- repeatables ------------------------------------------------------------------
    imgui.TextColored(COL_HEAD, 'Repeatables (stay listed - tick to turn on/off)')
    local list = repeatables()
    local remove_idx = nil
    for i, id in ipairs(list) do
        local c = { roe.active[id] ~= nil or queued('add', id) }
        if imgui.Checkbox((roe_mapping[id] or ('#' .. id)) .. '##rep' .. id, c) then
            repeat_toggle(id, c[1])
        end
        imgui.SameLine()
        if imgui.SmallButton('x##reprem' .. id) then remove_idx = id end
    end
    if remove_idx then repeat_rem(remove_idx) end
    if #list == 0 then imgui.TextColored(COL_DIM, '  (none)') end

    if imgui.SetNextItemWidth then imgui.SetNextItemWidth(220) end
    imgui.InputText('##repinput', ui.rep_buf, 64)
    imgui.SameLine()
    if btn('Add to list', 'repadd') and ui.rep_buf[1] ~= '' then
        repeat_add(ui.rep_buf[1])
        ui.rep_buf[1] = ''
    end
    imgui.TextColored(COL_DIM, 'Type an RoE id or name (e.g. "Total Damage I").')
    imgui.Separator()

    -- remove all (two clicks) ----------------------------------------------------------
    local now = os.clock()
    if now < ui.clear_arm then
        if btn('Click again to REMOVE ALL', 'clr2', COL_DEL) then
            ui.clear_arm = 0
            remove_all()
        end
    else
        if btn('Remove All RoEs', 'clr') then ui.clear_arm = now + 3 end
    end

    theme.finish()
    if not ui.open[1] then ui.visible = false end
end

ashita.events.register('d3d_present', 'roe_ui_present', function()
    pump_queue(os.clock())
    if ui.visible then
        local nc, nv = theme.push()
        draw_window()
        theme.pop(nc, nv)
    end
end)

ashita.events.register('load', 'roe_ui_load', function()
    build_indexes()
    repeatables()
end)
