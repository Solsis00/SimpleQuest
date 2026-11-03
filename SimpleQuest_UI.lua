-- SimpleQuest_UI: UI frame for addon controls
-- Creates a minimal floating frame with toggle buttons and quest list

local addonName, SS = ...

-- ============================================================================
-- Frame References (set by main module)
-- ============================================================================
SS_CheckboxHideAll = nil
SS_CheckboxAutoTrack = nil
SS_CheckboxAutoAccept = nil
SS_ButtonSortMode = nil
SS_UIFrame = nil

-- ============================================================================
-- Create Main UI Frame
-- ============================================================================
function SS_CreateUI()
    -- Main container frame
    local frame = CreateFrame("Frame", "SimpleQuestFrame", UIParent)
    SS_UIFrame = frame
    
    frame:SetSize(320, 400)
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    
    -- Set initial position (bottom-left area)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", 150, 150)
    
    -- Drag handler
    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        SS_SaveFramePosition(frame)
    end)
    
    -- ========================================================================
    -- Title Bar
    -- ========================================================================
    local titleBG = frame:CreateTexture(nil, "BACKGROUND")
    titleBG:SetColorTexture(0.1, 0.1, 0.15, 1)
    titleBG:SetSize(320, 24)
    titleBG:SetPoint("TOP")
    
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("LEFT", 8, 0)
    titleText:SetText("|cff3fcf7fSimpleQuest|r")
    titleText:SetFontObject("GameFontNormalSmall")
    
    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, 2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- ========================================================================
    -- Settings Section
    -- ========================================================================
    local yOffset = -32
    
    -- "Hide All Tracked" checkbox
    local hideCheckbox = CreateFrame("CheckButton", nil, frame)
    hideCheckbox:SetPoint("LEFT", 12, yOffset)
    hideCheckbox:SetSize(24, 24)
    SS_CheckboxHideAll = hideCheckbox
    
    local hideLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    hideLabel:SetPoint("LEFT", hideCheckbox, "RIGHT", 4, 0)
    hideLabel:SetText("Hide All Tracked")
    hideLabel:SetFontObject("GameFontWhite")
    hideLabel:SetSize(150, 16)
    
    hideCheckbox:SetScript("OnClick", function()
        SS_ToggleHideAllTracked()
    end)
    
    yOffset = yOffset - 28
    
    -- "Auto-Track Zone Quests" checkbox
    local autoCheckbox = CreateFrame("CheckButton", nil, frame)
    autoCheckbox:SetPoint("LEFT", 12, yOffset)
    autoCheckbox:SetSize(24, 24)
    SS_CheckboxAutoTrack = autoCheckbox
    
    local autoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    autoLabel:SetPoint("LEFT", autoCheckbox, "RIGHT", 4, 0)
    autoLabel:SetText("Auto-Track Zone Quests")
    autoLabel:SetFontObject("GameFontWhite")
    autoLabel:SetSize(150, 16)
    
    autoCheckbox:SetScript("OnClick", function()
        SS_ToggleAutoTrackZone()
    end)

    yOffset = yOffset - 28

    -- "Auto-Accept Quests" checkbox
    local acceptCheckbox = CreateFrame("CheckButton", nil, frame)
    acceptCheckbox:SetPoint("LEFT", 12, yOffset)
    acceptCheckbox:SetSize(24, 24)
    SS_CheckboxAutoAccept = acceptCheckbox

    local acceptLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    acceptLabel:SetPoint("LEFT", acceptCheckbox, "RIGHT", 4, 0)
    acceptLabel:SetText("Auto-Accept Quests")
    acceptLabel:SetFontObject("GameFontWhite")
    acceptLabel:SetSize(150, 16)

    acceptCheckbox:SetScript("OnClick", function()
        SS_ToggleAutoAccept()
    end)

    yOffset = yOffset - 28
    
    -- Separator line
    local separator = frame:CreateTexture(nil, "BACKGROUND")
    separator:SetColorTexture(0.3, 0.3, 0.3, 1)
    separator:SetSize(296, 1)
    separator:SetPoint("TOPLEFT", 12, yOffset - 4)
    separator:SetPoint("TOPRIGHT", -12, yOffset - 4)
    yOffset = yOffset - 12
    
    -- ========================================================================
    -- Sort Controls
    -- ========================================================================
    
    -- Sort mode button
    local sortButton = CreateFrame("Button", nil, frame)
    sortButton:SetPoint("LEFT", 12, yOffset)
    sortButton:SetSize(140, 24)
    sortButton:SetNormalFontObject("GameFontNormal")
    SS_ButtonSortMode = sortButton
    
    local sortButtonText = sortButton:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    sortButtonText:SetPoint("CENTER")
    sortButtonText:SetText("Sort: Recent")
    sortButtonText:SetFontObject("GameFontWhite")
    sortButton:SetText("")  -- Clear default text
    
    sortButton:SetScript("OnClick", function()
        SS_ToggleSortMode()
    end)
    
    -- Sort order button
    local sortOrderButton = CreateFrame("Button", nil, frame)
    sortOrderButton:SetPoint("LEFT", sortButton, "RIGHT", 4, 0)
    sortOrderButton:SetSize(140, 24)
    sortOrderButton:SetNormalFontObject("GameFontNormal")
    
    local sortOrderText = sortOrderButton:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    sortOrderText:SetPoint("CENTER")
    sortOrderText:SetText("Order: Newest First")
    sortOrderText:SetFontObject("GameFontWhite")
    sortOrderButton:SetText("")
    
    sortOrderButton:SetScript("OnClick", function()
        SS_ToggleSortOrder()
    end)
    
    yOffset = yOffset - 32
    
    -- ========================================================================
    -- Quest List Frame
    -- ========================================================================
    
    -- Scroll frame background
    local scrollBg = frame:CreateTexture(nil, "BACKGROUND")
    scrollBg:SetColorTexture(0.05, 0.05, 0.08, 1)
    scrollBg:SetPoint("TOPLEFT", 10, yOffset - 4)
    scrollBg:SetPoint("BOTTOMRIGHT", -10, 10)
    scrollBg:SetGradient("VERTICAL", 
        {r=0.05, g=0.05, b=0.08, a=1},
        {r=0.08, g=0.08, b=0.12, a=1}
    )
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, yOffset - 4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 12)
    
    -- Quest list container
    local questList = CreateFrame("Frame", nil, scrollFrame)
    questList:SetSize(280, 350)
    scrollFrame:SetScrollChild(questList)
    SS_QuestListFrame = questList
    
    -- ========================================================================
    -- Store references for UI updates
    -- ========================================================================
    frame.questList = questList
    frame.scrollFrame = scrollFrame
    
    -- ========================================================================
    -- Minimap Button
    -- ========================================================================
    local mmButton = CreateFrame("Button", "SimpleQuestMMButton", Minimap)
    mmButton:SetSize(32, 32)
    mmButton:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)
    
    local mmButtonTexture = mmButton:CreateTexture(nil, "BACKGROUND")
    mmButtonTexture:SetTexture("Interface\\MINIMAP\\TRACKING")
    mmButtonTexture:SetSize(20, 20)
    mmButtonTexture:SetPoint("CENTER")
    mmButtonTexture:SetVertexColor(0.3, 0.8, 0.5)
    mmButtonTexture:SetBlendMode("ADD")
    
    local mmButtonGlow = mmButton:CreateTexture(nil, "HIGHLIGHT")
    mmButtonGlow:SetTexture("Interface\\Minimap\\MinimapButtonHighlight")
    mmButtonGlow:SetSize(46, 46)
    mmButtonGlow:SetPoint("CENTER")
    mmButtonGlow:SetVertexColor(1, 1, 1, 0.4)
    
    mmButton:SetScript("OnClick", function()
        if SS_UIFrame:IsVisible() then
            SS_UIFrame:Hide()
        else
            SS_UIFrame:Show()
        end
    end)
    
    mmButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("|cff3fcf7fSimpleQuest|r", 0.3, 0.8, 0.5)
        GameTooltip:AddLine("Click to toggle quest panel", 1, 1, 1, 0.7)
        GameTooltip:Show()
    end)
    
    mmButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Store frame position
    SS.SaveFramePosition = function(savedFrame)
        local points = {}
        local numPoints = savedFrame:GetNumPoints()
        for i = 1, numPoints do
            local point, relativeTo, relativePoint, x, y = savedFrame:GetPoint(i)
            points[i] = {point, relativeTo and relativePoint, x, y}
        end
        -- Store in settings for persistence across reloads
        SS.Settings.FramePosition = points
    end
    
    -- Restore frame position from saved settings
    SS.RestoreFramePosition = function(savedFrame)
        if SS.Settings and SS.Settings.FramePosition then
            for _, p in ipairs(SS.Settings.FramePosition) do
                savedFrame:SetPoint(p[1], p[2], p[1], p[3], p[4])
            end
        end
    end
    
    -- Apply saved position
    SS.RestoreFramePosition(frame)
    
    -- Set initial checkbox states
    hideCheckbox:SetChecked(SS.Settings.hideAllTracked)
    autoCheckbox:SetChecked(SS.Settings.autoTrackZone)
    SS_CheckboxAutoAccept:SetChecked(SS.Settings.autoAccept)
    
    -- Update button text based on current sort mode
    if SS.Settings.sortMode == "recent" then
        sortButtonText:SetText("Sort: Recent")
    else
        sortButtonText:SetText("Sort: Distance")
    end
    
    if SS.Settings.sortOrder == "desc" then
        sortOrderText:SetText("Order: Newest First")
    else
        sortOrderText:SetText("Order: Oldest First")
    end
    
    return frame
end

-- ============================================================================
-- Update Quest List Display
-- ============================================================================
function SS_UpdateQuestList()
    if not SS_UIFrame or not SS_QuestListFrame then return end
    
    local questList = SS_QuestListFrame
    local sortedQuests = SS_GetSortedQuests(true)
    
    -- Clear existing quest buttons
    local numButtons = #questList.questButtons or 0
    for i = 1, numButtons do
        local btn = questList.questButtons[i]
        if btn then
            btn:Hide()
        end
    end
    
    -- Create or update quest buttons
    local yOffset = 0
    local maxVisible = 12  -- Max quests visible without scrolling
    
    for i = 1, #sortedQuests do
        local quest = sortedQuests[i]
        
        -- Get or create button
        local btn = questList.questButtons and questList.questButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, questList)
            btn:SetSize(260, 52)
            btn:SetPoint("TOPLEFT", 8, yOffset)
            questList.questButtons = questList.questButtons or {}
            questList.questButtons[i] = btn
            
            -- Quest title
            local title = btn:CreateFontString(nil, "OVERLAY", "GameFontWhite")
            title:SetPoint("TOPLEFT", 4, -2)
            title:SetPoint("TOPRIGHT", -4, -2)
            title:SetFontObject("GameFontWhite")
            title:SetSize(250, 14)
            title:SetJustifyH("LEFT")
            btn.titleText = title
            
            -- Quest objective
            local objective = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            objective:SetPoint("TOPLEFT", 4, -18)
            objective:SetPoint("TOPRIGHT", -4, -18)
            objective:SetFontObject("GameFontNormalSmall")
            objective:SetSize(250, 14)
            objective:SetJustifyH("LEFT")
            objective:SetTextColor(0.7, 0.7, 0.7, 1)
            btn.objectiveText = objective
            
            -- Quest info (distance or time)
            local info = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            info:SetPoint("BOTTOMLEFT", 4, 2)
            info:SetFontObject("GameFontHighlightSmall")
            info:SetSize(120, 12)
            info:SetJustifyH("LEFT")
            btn.infoText = info
            
            -- Track button
            local trackBtn = CreateFrame("Button", nil, btn)
            trackBtn:SetPoint("TOPRIGHT", -4, -2)
            trackBtn:SetPoint("BOTTOMRIGHT", -4, 2)
            trackBtn:SetSize(40, 48)
            trackBtn:SetNormalFontObject("GameFontNormalSmall")
            
            local trackText = trackBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            trackText:SetPoint("CENTER")
            trackText:SetText("Track")
            trackText:SetFontObject("GameFontNormalSmall")
            trackText:SetTextColor(0.3, 0.8, 0.5, 1)
            trackBtn.trackText = trackText
            
            trackBtn:SetScript("OnClick", function()
                SS_TrackQuest(quest.questId)
                SS_UpdateQuestList()
            end)
            btn.trackButton = trackBtn
            
            -- Untrack button (visible when tracked)
            local untrackBtn = CreateFrame("Button", nil, btn)
            untrackBtn:SetPoint("TOPRIGHT", -4, -2)
            untrackBtn:SetPoint("BOTTOMRIGHT", -4, 2)
            untrackBtn:SetSize(40, 48)
            untrackBtn:SetNormalFontObject("GameFontNormalSmall")
            untrackBtn:Hide()
            
            local untrackText = untrackBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            untrackText:SetPoint("CENTER")
            untrackText:SetText("X")
            untrackText:SetFontObject("GameFontNormalSmall")
            untrackText:SetTextColor(1, 0.3, 0.3, 1)
            untrackBtn.untrackText = untrackText
            
            untrackBtn:SetScript("OnClick", function()
                SS_UntrackQuest(quest.questId)
                SS_UpdateQuestList()
            end)
            btn.untrackButton = untrackBtn
            
            -- Hover highlight
            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetColorTexture(0.2, 0.2, 0.3, 0.5)
            highlight:SetPoint("TOPLEFT", -2, 2)
            highlight:SetPoint("BOTTOMRIGHT", 2, -2)
            btn.highlight = highlight
        end
        
        -- Update button content
        btn:Show()
        
        -- Set title with quality color
        local formattedTitle = SS_FormatQuestTitle(quest)
        btn.titleText:SetText(formattedTitle)
        
        -- Set objective text
        local objectiveText = SS_GetQuestObjectiveText(quest)
        if objectiveText and string.len(objectiveText) > 0 then
            -- Truncate long objective text
            if string.len(objectiveText) > 60 then
                objectiveText = string.sub(objectiveText, 1, 57) .. "..."
            end
            btn.objectiveText:SetText(objectiveText)
            btn.objectiveText:Show()
        else
            btn.objectiveText:SetText("")
            btn.objectiveText:Hide()
        end
        
        -- Set info text (distance or time)
        if SS.Settings.sortMode == "distance" then
            local distText = SS_FormatDistance(quest.distance)
            btn.infoText:SetText(distText)
        else
            -- Note: timeCompleted is normalized from the quest log data
            if quest.timeCompleted and quest.timeCompleted > 0 then
                local timeStr = SS_FormatTime(quest.timeCompleted)
                btn.infoText:SetText(timeStr)
            else
                btn.infoText:SetText("")
            end
        end
        
        -- Show/hide track/untrack buttons
        if quest.isTracked then
            btn.trackButton:Hide()
            btn.untrackButton:Show()
        else
            btn.trackButton:Show()
            btn.untrackButton:Hide()
        end
        
        -- Update position
        yOffset = yOffset - 54
        
        -- Only show max visible quests (scrolling handles the rest)
        if i > maxVisible then
            btn:Hide()
        end
    end
    
    -- Hide unused buttons beyond visible count
    for i = maxVisible + 1, (questList.questButtons and #questList.questButtons or 0) do
        local btn = questList.questButtons[i]
        if btn then
            btn:Hide()
        end
    end
    
    -- Update scroll frame size
    local actualHeight = math.min(#sortedQuests * 54, 350)
    questList:SetSize(280, actualHeight)
    
    -- Update scroll frame
    if SS_UIFrame.scrollFrame then
        SS_UIFrame.scrollFrame:SetScrollChild(questList)
    end
end

-- ============================================================================
-- Initialize UI
-- ============================================================================
function SS_InitializeUI()
    SS_CreateUI()
    
    -- Initialize quest button table
    if SS_QuestListFrame then
        SS_QuestListFrame.questButtons = {}
    end
    
    -- Initial update
    SS_UpdateQuestList()
    
    -- Schedule periodic updates
    SS_UpdateTimer = SS_UpdateTimer or CreateFrame("Frame")
    SS_UpdateTimer:SetScript("OnUpdate", function(self)
        if SS_UIFrame and SS_UIFrame:IsVisible() then
            SS_UpdateQuestList()
        end
    end)
    SS_UpdateTimer:Hide()
    
    -- Show update timer when UI is shown
    local origShow = SS_UIFrame.Show
    function SS_UIFrame:Show()
        SS_UpdateTimer:Show()
        SS_UpdateQuestList()
        origShow(SS_UIFrame)
    end
    
    local origHide = SS_UIFrame.Hide
    function SS_UIFrame:Hide()
        SS_UpdateTimer:Hide()
        origHide(SS_UIFrame)
    end
end

-- ============================================================================
-- Deferred Initialization (runs after all modules have loaded)
-- ============================================================================

-- Initialize UI and do initial zone scan
SS_InitializeUI()
SS_OnZoneChanged()
