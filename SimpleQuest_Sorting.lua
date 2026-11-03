-- SimpleQuest_Sorting: Quest sorting module
-- Handles sorting quests by recent progress changes and distance

local addonName, SS = ...

-- ============================================================================
-- Sorting State
-- ============================================================================
SS.SortState = {
    lastRefresh = 0,
    refreshInterval = 2,  -- seconds between distance recalculations
    cachedSort = {},
}

-- ============================================================================
-- Build Sorted Quest List: Recent Progress Changes
-- ============================================================================
function SS_BuildRecentSort()
    local sorted = {}
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            -- Get the most recent timestamp for this quest
            local recentTime = 0
            
            -- Check completion times (timeCompleted may be set by the API)
            if entry.timeCompleted then recentTime = math.max(recentTime, entry.timeCompleted) end
            if entry.timeCompletedForLog then recentTime = math.max(recentTime, entry.timeCompletedForLog) end
            
            -- Quests with recent objective updates get a boost
            -- We use the quest ID as a tiebreaker (lower = older quest in log)
            table.insert(sorted, {
                questId = entry.questId,
                title = entry.title,
                quality = entry.quality or 0,
                isTracked = entry.isTracked,
                isComplete = entry.isComplete,
                recentTime = recentTime,
                sortOrder = entry.sortOrder or i,
                index = i,
            })
        end
    end
    
    -- Sort by most recent first (or oldest first based on setting)
    table.sort(sorted, function(a, b)
        -- Complete quests go to bottom
        if a.isComplete ~= b.isComplete then
            return not a.isComplete
        end
        
        -- By recent time
        if SS.Settings.sortOrder == "desc" then
            return a.recentTime > b.recentTime
        else
            return a.recentTime < b.recentTime
        end
    end)
    
    SS.SortState.cachedSort = sorted
    SS.SortState.lastRefresh = GetTime()
    
    return sorted
end

-- ============================================================================
-- Build Sorted Quest List: Distance to Objective
-- ============================================================================
function SS_BuildDistanceSort()
    local sorted = {}
    local mapID = C_Map.GetBestMapForUnit("player")
    
    if not mapID then
        SS.SortState.cachedSort = {}
        return {}
    end
    
    local numQuests = SS_GetNumQuestLogEntries()
    
    for i = 1, numQuests do
        local entry = SS_GetQuestLogEntryByIndex(i)
        if entry and entry.questId then
            local distance = SS_GetQuestDistance(entry.questId)
            
            table.insert(sorted, {
                questId = entry.questId,
                title = entry.title,
                quality = entry.quality or 0,
                isTracked = entry.isTracked,
                isComplete = entry.isComplete,
                distance = distance,
                index = i,
            })
        end
    end
    
    -- Sort by distance
    table.sort(sorted, function(a, b)
        -- Complete quests go to bottom
        if a.isComplete ~= b.isComplete then
            return not a.isComplete
        end
        
        -- Handle unknown distances (-1) - put them at the end
        if a.distance < 0 and b.distance >= 0 then return false end
        if a.distance >= 0 and b.distance < 0 then return true end
        if a.distance < 0 and b.distance < 0 then return a.questId < b.questId end
        
        -- Sort by distance
        if SS.Settings.sortOrder == "desc" then
            return a.distance > b.distance
        else
            return a.distance < b.distance
        end
    end)
    
    SS.SortState.cachedSort = sorted
    SS.SortState.lastRefresh = GetTime()
    
    return sorted
end

-- ============================================================================
-- Get Current Sorted List (cached or fresh)
-- ============================================================================
function SS_GetSortedQuests(forceRefresh)
    -- Return cache if valid and not forcing refresh
    if not forceRefresh and #SS.SortState.cachedSort > 0 then
        local elapsed = GetTime() - SS.SortState.lastRefresh
        
        -- For distance sort, refresh periodically as player moves
        if SS.Settings.sortMode == "distance" and elapsed < SS.SortState.refreshInterval then
            return SS.SortState.cachedSort
        end
        
        -- For recent sort, cache is stable until quest log changes
        if SS.Settings.sortMode == "recent" and elapsed < 1 then
            return SS.SortState.cachedSort
        end
    end
    
    -- Build fresh sorted list
    if SS.Settings.sortMode == "recent" then
        return SS_BuildRecentSort()
    else
        return SS_BuildDistanceSort()
    end
end

-- ============================================================================
-- Get Quest Quality Color
-- ============================================================================
function SS_GetQualityColor(quality)
    quality = quality or 0
    
    local colors = {
        [0] = "|cff9d9d9d",  -- Poor - gray
        [1] = "|cffFFFFFF",  -- Uncommon - white (some quests)
        [2] = "|cff1eff00",  -- Rare - green
        [3] = "|cff0070ff",  -- Epic - blue
        [4] = "|cffa335ee",  -- Legendary - orange
        [5] = "|cffe6cc80",  -- Heirloom
        [6] = "|ff808080",  -- Artifact
    }
    
    return colors[quality] or "|cff9d9d9d"
end

-- ============================================================================
-- Format Distance for Display
-- ============================================================================
function SS_FormatDistance(distance)
    if distance < 0 then return "??" end
    
    -- Map distance is 0-1, convert to approximate yards
    -- This is an approximation since map scale varies
    local yards = distance * 1000  -- rough conversion
    
    if yards < 10 then
        return " nearby"
    elseif yards < 100 then
        return string.format("%.0fy", yards)
    elseif yards < 1000 then
        return string.format("%.0fy", yards)
    else
        local yards2 = yards / 1000
        return string.format("%.1fy", yards2)
    end
end

-- ============================================================================
-- Format Time for Display
-- ============================================================================
function SS_FormatTime(timestamp)
    if not timestamp or timestamp == 0 then return "" end
    
    local now = time()
    local diff = now - timestamp
    
    if diff < 60 then
        return string.format("%ds", diff)
    elseif diff < 3600 then
        return string.format("%dm", diff / 60)
    elseif diff < 86400 then
        return string.format("%dh", diff / 3600)
    else
        return string.format("%dd", diff / 86400)
    end
end

-- ============================================================================
-- Get Quest Quality Index for Color
-- ============================================================================
function SS_GetQuestColor(quality)
    -- Quest quality constants
    local qualityColors = {
        [0] = {0.62, 0.62, 0.62},  -- Poor
        [1] = {1.0, 1.0, 1.0},     -- Uncommon
        [2] = {0.0, 1.0, 0.0},     -- Rare
        [3] = {0.0, 0.45, 1.0},    -- Epic
        [4] = {1.0, 0.5, 0.0},     -- Legendary
        [5] = {1.0, 0.5, 0.5},     -- Artifact
    }
    
    local color = qualityColors[quality] or qualityColors[0]
    return color[1], color[2], color[3]
end

-- ============================================================================
-- Format Quest Title with Quality Color
-- ============================================================================
function SS_FormatQuestTitle(quest)
    local title = quest and quest.title or "Unknown Quest"
    local quality = quest and (quest.quality or 0) or 0
    
    local r, g, b = SS_GetQuestColor(quality)
    local colorString = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    
    return colorString .. title .. "|r"
end

-- ============================================================================
-- Check if Quest Has Active Objectives
-- ============================================================================
function SS_QuestHasObjectives(quest)
    if not quest or not quest.questId then return false end
    
    local success, objectives = pcall(C_QuestLog.GetQuestObjectives, quest.questId)
    if not success or not objectives then return false end
    
    -- GetQuestObjectives returns a table of strings in new API
    for _, objText in ipairs(objectives) do
        if objText and string.len(objText) > 0 then
            return true
        end
    end
    
    return false
end

-- ============================================================================
-- Get Quest Objective Text
-- ============================================================================
function SS_GetQuestObjectiveText(quest)
    if not quest or not quest.questId then return "" end
    
    local success, objectives = pcall(C_QuestLog.GetQuestObjectives, quest.questId)
    if not success or not objectives then return "" end
    
    local lines = {}
    for _, obj in ipairs(objectives) do
        if obj and obj.text and obj.text ~= "" then
            -- Gray/Green for completed, standard light gray/white for incomplete
            local colorCode = obj.finished and "|cff808080" or "|cffffffff"
            lines[#lines + 1] = string.format("%s- %s|r", colorCode, obj.text)
        end
    end
    
    return table.concat(lines, "\n")
end
--[[ function SS_GetQuestObjectiveText(quest)
    if not quest or not quest.questId then return "" end
    
    local success, objectives = pcall(C_QuestLog.GetQuestObjectives, quest.questId)
    if not success or not objectives then return "" end
    
    -- Join objective strings with newlines
    local text = ""
    for i, objText in ipairs(objectives) do
        if i > 1 then text = text .. "\n" end
        text = text .. (objText or "")
    end
    return text
end
 ]]

-- ============================================================================
-- Get Quest Progress Text
-- ============================================================================
function SS_GetQuestProgressText(quest)
    if not quest or not quest.questId then return "" end
    
    -- No direct equivalent in new API; return empty for now
    return ""
end
