-- SimpleQuest_TurnIn: Auto turn-in module
-- Walks the NPC quest dialogue chain and completes finished quests:
--
--   GOSSIP_SHOW / QUEST_GREETING  ->  pick a completed active quest
--   QUEST_PROGRESS                ->  "Continue" (CompleteQuest)
--   QUEST_COMPLETE                ->  "Complete Quest" (GetQuestReward)
--
-- Each step fires its own event, so every stage of a multi-step dialogue is
-- handled independently (QuestFrame's OnShow only fires once per interaction,
-- which is why a frame hook alone can't drive the whole chain).
--
-- The chain stops at QUEST_COMPLETE when the quest offers more than one reward
-- choice, leaving the reward panel open for the player to pick. Holding Shift
-- while interacting suppresses auto turn-in, matching auto-accept behavior.
--
-- Every action is deferred by a short delay and only the most recent one is
-- kept. Acting synchronously inside the event races the server/UI during
-- dialogue transitions (e.g. turn-in -> NPC re-offers a new quest), which can
-- leave the NPC interaction stuck until the player re-targets.

local addonName, SS = ...

SS.TurnInFrame = CreateFrame("Frame")
SS.TurnInFrame:RegisterEvent("GOSSIP_SHOW")
SS.TurnInFrame:RegisterEvent("GOSSIP_CLOSED")
SS.TurnInFrame:RegisterEvent("QUEST_GREETING")
SS.TurnInFrame:RegisterEvent("QUEST_DETAIL")
SS.TurnInFrame:RegisterEvent("QUEST_PROGRESS")
SS.TurnInFrame:RegisterEvent("QUEST_COMPLETE")
SS.TurnInFrame:RegisterEvent("QUEST_TURNED_IN")
SS.TurnInFrame:RegisterEvent("QUEST_FINISHED")

-- ============================================================================
-- State & Debug Helper
-- ============================================================================
local lastCompletedQuestID = nil
local lastTurnInTime = 0
local selectedOptionIDs = {}
local npcIsQuestRelated = false

local function SS_Debug(msg)
    if SS.Settings and SS.Settings.debugTurnIn then
        print("|cff3fcf7fSimpleQuest|r: [DEBUG] " .. tostring(msg))
    end
end

-- ============================================================================
-- Guards
-- ============================================================================
local function SS_ShouldAutoTurnIn()
    if not SS.Settings or not SS.Settings.autoTurnIn then return false end
    if IsShiftKeyDown() then return false end
    return true
end

local function SS_ShouldAutoAccept()
    if not SS.Settings or not SS.Settings.autoAccept then return false end
    if IsShiftKeyDown() then return false end
    return true
end

-- Dialogue-reported completion flags aren't always reliable (e.g. quests with
-- no objectives, or "talk to"/"report to" quests). Cross-check the quest log,
-- while ignoring a quest that was just turned in (whose log state may lag).
local function SS_IsQuestReadyForTurnIn(questID, reportedComplete)
    if questID and questID == lastCompletedQuestID then
        return false
    end
    if reportedComplete then return true end
    if not questID or questID <= 0 then return false end
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID) then return true end
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) then return true end
    return false
end

-- Only select gossip options that are explicitly marked as quest options by
-- the game (e.g. "(Quest)" flag/label or attached quest rewards), leaving all
-- regular NPC gossip options (vendors, flight masters, lore, etc.) untouched.
local function SS_IsQuestGossipOption(option)
    if not option then return false end

    -- 1. Blizzard's official "(Quest)" label flag (Enum.GossipOptionRecFlags.QuestLabelPrepend = 1)
    if option.flags then
        if FlagsUtil and FlagsUtil.IsSet and Enum and Enum.GossipOptionRecFlags and Enum.GossipOptionRecFlags.QuestLabelPrepend then
            if FlagsUtil.IsSet(option.flags, Enum.GossipOptionRecFlags.QuestLabelPrepend) then
                return true
            end
        elseif bit and bit.band then
            if bit.band(option.flags, 1) ~= 0 then
                return true
            end
        elseif option.flags == 1 then
            return true
        end
    end

    -- 2. Explicit "(Quest)" prefix/tag in the option text
    local optionText = (option.name or option.text or ""):lower()
    if string.find(optionText, "%(quest%)") then
        return true
    end

    -- 3. Explicit quest rewards attached to the gossip option
    if type(option.rewards) == "table" and #option.rewards > 0 then
        return true
    end

    return false
end

-- Returns true if the gossip option uses a standard dialogue/speech-bubble or
-- quest icon rather than a service icon (vendor, flight master, banker, etc.).
-- FileDataID 132053 = GossipGossipIcon (speech bubble).
local function SS_IsDialogueGossipIcon(option)
    if not option then return false end
    local icon = option.overrideIconID or option.icon
    if not icon then return true end
    return icon == 132053 or icon == 132048 or icon == 132049 or icon == 3595324
end

-- Determines whether the currently interacted NPC is part of an active quest
-- in the player's quest log (even when its gossip option lacks the "(Quest)" flag).
local function SS_IsNpcRelatedToActiveQuest()
    -- 1. NPC has an active quest listed in the gossip window itself
    local activeGossipQuests = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests()
    if activeGossipQuests then
        for _, info in ipairs(activeGossipQuests) do
            if info.questID and info.questID ~= lastCompletedQuestID then
                SS_Debug("  NPC quest relation: has active quest in gossip (ID " .. tostring(info.questID) .. ")")
                return true
            end
        end
    end

    local unit = (UnitExists and UnitExists("npc") and "npc")
        or (UnitExists and UnitExists("target") and "target")
        or nil
    if not unit then return false end

    -- 2. Built-in WoW API: unit is directly linked to an active quest
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit) then
        SS_Debug("  NPC quest relation: C_QuestLog.UnitIsRelatedToActiveQuest(" .. unit .. ") = true")
        return true
    end
    if UnitIsQuestBoss and UnitIsQuestBoss(unit) then
        SS_Debug("  NPC quest relation: UnitIsQuestBoss(" .. unit .. ") = true")
        return true
    end

    -- 3. Tooltip inspection: check if the game tooltip for this NPC contains quest lines
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local tooltipData = C_TooltipInfo.GetUnit(unit)
        if tooltipData and tooltipData.lines then
            local questTitleType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle or 17
            local questObjType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective or 8
            local questPlayerType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer or 18
            for _, line in ipairs(tooltipData.lines) do
                if line.type == questTitleType or line.type == questObjType or line.type == questPlayerType then
                    SS_Debug("  NPC quest relation: tooltip has quest line (" .. tostring(line.leftText) .. ")")
                    return true
                end
            end
        end
    end

    -- 4. Fallback: check if the NPC's name is mentioned in any active quest title or incomplete objective
    local npcName = UnitName and UnitName(unit)
    if npcName and npcName ~= "" and C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local npcNameLower = npcName:lower()
        local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID and info.questID ~= lastCompletedQuestID then
                if info.title and string.find(info.title:lower(), npcNameLower, 1, true) then
                    SS_Debug("  NPC quest relation: NPC name in quest title '" .. tostring(info.title) .. "'")
                    return true
                end
                local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID)
                if objectives then
                    for _, obj in ipairs(objectives) do
                        if not obj.finished and obj.text and string.find(obj.text:lower(), npcNameLower, 1, true) then
                            SS_Debug("  NPC quest relation: NPC name in objective '" .. tostring(obj.text) .. "'")
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- Deferred action queue
-- ============================================================================
-- Only one action may be pending. Queuing a new one supersedes the old one.
-- We intentionally do NOT cancel on QUEST_FINISHED or GOSSIP_CLOSED because
-- those events fire as intermediate transitions when handing off from a
-- completed quest to a follow-up quest on the same NPC. Instead, each handler
-- verifies that its specific panel is still shown when the timer fires.
local SS_ACTION_DELAY = 0.5
local pendingToken = 0

local function SS_QueueAction(label, guard, action)
    pendingToken = pendingToken + 1
    local token = pendingToken

    SS_Debug(string.format("Queued %s (delay %.2fs, token %d)", label, SS_ACTION_DELAY, token))

    C_Timer.After(SS_ACTION_DELAY, function()
        if token ~= pendingToken then
            SS_Debug(string.format("Skipped superseded %s (token %d)", label, token))
            return
        end
        if not guard() then
            SS_Debug(string.format("Guard blocked %s", label))
            return
        end
        SS_Debug(string.format("Running %s", label))
        action()
    end)
end

-- ============================================================================
-- Step 1a: Gossip NPCs (modern dialogue frame)
-- ============================================================================
local function SS_TurnIn_OnGossipShow()
    if GossipFrame and not GossipFrame:IsShown() then
        SS_Debug("GOSSIP_SHOW handler skipped: GossipFrame not shown.")
        return
    end

    -- 1. Handle completed quests (turn-in)
    if SS_ShouldAutoTurnIn() then
        local activeQuests = C_GossipInfo.GetActiveQuests()
        if activeQuests then
            SS_Debug(string.format("GOSSIP_SHOW: %d active quest(s).", #activeQuests))
            for _, info in ipairs(activeQuests) do
                SS_Debug(string.format("  Active '%s' (ID %s) isComplete=%s",
                    tostring(info.title), tostring(info.questID), tostring(info.isComplete)))
                if info.questID and SS_IsQuestReadyForTurnIn(info.questID, info.isComplete) then
                    SS_Debug("  -> Selecting active quest ID " .. tostring(info.questID))
                    C_GossipInfo.SelectActiveQuest(info.questID)
                    return
                end
            end
        end
    end

    -- 2. Handle offered quests (pick up new/follow-up quest)
    if SS_ShouldAutoAccept() then
        local availableQuests = C_GossipInfo.GetAvailableQuests()
        if availableQuests and #availableQuests > 0 then
            local firstQuest = availableQuests[1]
            SS_Debug(string.format("GOSSIP_SHOW: %d available quest(s). Selecting '%s' (ID %s)",
                #availableQuests, tostring(firstQuest.title), tostring(firstQuest.questID)))
            if firstQuest.questID then
                C_GossipInfo.SelectAvailableQuest(firstQuest.questID)
                return
            end
        end
    end

    -- 3. Handle quest gossip progression
    if not SS_ShouldAutoTurnIn() then return end

    local options = C_GossipInfo.GetOptions()
    if options and #options > 0 then
        SS_Debug(string.format("GOSSIP_SHOW: %d gossip option(s).", #options))

        -- Pass 1: Explicitly flagged "(Quest)" options (works on any NPC)
        for _, option in ipairs(options) do
            local optID = option.gossipOptionID
            if SS_IsQuestGossipOption(option) and optID and not selectedOptionIDs[optID] then
                SS_Debug("  -> Selecting quest-flagged option ID " .. tostring(optID))
                selectedOptionIDs[optID] = true
                C_GossipInfo.SelectOption(optID)
                return
            end
        end

        -- Pass 2: Unflagged dialogue option on an NPC confirmed to be part of an
        -- active quest objective (skipped right after turning in a quest).
        local recentlyTurnedIn = (GetTime() - lastTurnInTime) < 2.0
        if not recentlyTurnedIn and (npcIsQuestRelated or SS_IsNpcRelatedToActiveQuest()) then
            npcIsQuestRelated = true

            local dialogueOptions = {}
            for _, option in ipairs(options) do
                if SS_IsDialogueGossipIcon(option) then
                    table.insert(dialogueOptions, option)
                end
            end

            if #dialogueOptions == 1 then
                local opt = dialogueOptions[1]
                local optID = opt.gossipOptionID
                if optID and not selectedOptionIDs[optID] then
                    SS_Debug("  -> Quest NPC has 1 dialogue option; selecting ID " .. tostring(optID))
                    selectedOptionIDs[optID] = true
                    C_GossipInfo.SelectOption(optID)
                    return
                end
            end
        end
    end
end

-- ============================================================================
-- Step 1b: Legacy quest greeting NPCs (QuestFrameGreetingPanel)
-- ============================================================================
local function SS_TurnIn_OnQuestGreeting()
    if QuestFrameGreetingPanel and not QuestFrameGreetingPanel:IsShown() then
        SS_Debug("QUEST_GREETING handler skipped: GreetingPanel not shown.")
        return
    end

    if SS_ShouldAutoTurnIn() then
        local numActive = GetNumActiveQuests() or 0
        SS_Debug(string.format("QUEST_GREETING: %d active quest(s).", numActive))

        for i = 1, numActive do
            local title, isComplete = GetActiveTitle(i)
            local questId = GetActiveQuestID and GetActiveQuestID(i)
            SS_Debug(string.format("  Active #%d '%s' (ID %s) isComplete=%s",
                i, tostring(title), tostring(questId), tostring(isComplete)))

            -- Fall back to the quest log state if the greeting didn't report it
            if SS_IsQuestReadyForTurnIn(questId, isComplete) then
                SS_Debug("  -> Selecting active quest #" .. tostring(i))
                SelectActiveQuest(i)
                return
            end
        end
    end

    if SS_ShouldAutoAccept() then
        local numAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
        if numAvailable > 0 then
            SS_Debug(string.format("QUEST_GREETING: %d available quest(s). Selecting #1.", numAvailable))
            SelectAvailableQuest(1)
            return
        end
    end
end

-- ============================================================================
-- Step 2: Progress panel ("Continue" button)
-- ============================================================================
local function SS_TurnIn_OnQuestProgress()
    if QuestFrameProgressPanel and not QuestFrameProgressPanel:IsShown() then
        SS_Debug("QUEST_PROGRESS handler skipped: ProgressPanel not shown.")
        return
    end

    -- Only advance if the quest's requirements are actually met
    SS_Debug("QUEST_PROGRESS: completable=" .. tostring(IsQuestCompletable()))
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

-- ============================================================================
-- Step 3: Reward panel ("Complete Quest" button)
-- ============================================================================
local function SS_TurnIn_OnQuestComplete()
    if QuestFrameRewardPanel and not QuestFrameRewardPanel:IsShown() then
        SS_Debug("QUEST_COMPLETE handler skipped: RewardPanel not shown.")
        return
    end

    local numChoices = GetNumQuestChoices() or 0
    SS_Debug("QUEST_COMPLETE: numChoices=" .. tostring(numChoices))

    if numChoices > 1 then
        -- Player needs to pick a reward; leave the panel open
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Choose a reward to complete the quest.")
        return
    end

    local questID = GetQuestID and GetQuestID()
    if questID and questID > 0 then
        lastCompletedQuestID = questID
    end
    lastTurnInTime = GetTime()
    npcIsQuestRelated = false

    -- 0 choices -> index 0 (no choice); 1 choice -> it's the only option.
    -- Mirrors what Blizzard's QuestInfoFrame.itemChoice would hold.
    GetQuestReward(numChoices)
end

-- ============================================================================
-- Event Dispatch
-- ============================================================================
SS.TurnInFrame:SetScript("OnEvent", function(self, event, arg1)
    SS_Debug(string.format("Event %s (arg1=%s, autoTurnIn=%s, autoAccept=%s, shift=%s)",
        event, tostring(arg1),
        tostring(SS.Settings and SS.Settings.autoTurnIn),
        tostring(SS.Settings and SS.Settings.autoAccept),
        tostring(IsShiftKeyDown())))

    if event == "GOSSIP_CLOSED" then
        selectedOptionIDs = {}
        npcIsQuestRelated = false
        return
    elseif event == "QUEST_TURNED_IN" then
        if arg1 and arg1 > 0 then
            lastCompletedQuestID = arg1
        end
        lastTurnInTime = GetTime()
        npcIsQuestRelated = false
        return
    elseif event == "QUEST_FINISHED" then
        return
    end

    -- Offered quest (detail panel) -> auto-accept, governed by its own setting
    if event == "QUEST_DETAIL" then
        if SS_ShouldAutoAccept() and SS_AutoAcceptQuest then
            SS_QueueAction("QUEST_DETAIL", SS_ShouldAutoAccept, SS_AutoAcceptQuest)
        end
        return
    end

    if event == "GOSSIP_SHOW" then
        if SS_ShouldAutoTurnIn() or SS_ShouldAutoAccept() then
            SS_QueueAction("GOSSIP_SHOW", function()
                return SS_ShouldAutoTurnIn() or SS_ShouldAutoAccept()
            end, SS_TurnIn_OnGossipShow)
        end
    elseif event == "QUEST_GREETING" then
        if SS_ShouldAutoTurnIn() or SS_ShouldAutoAccept() then
            SS_QueueAction("QUEST_GREETING", function()
                return SS_ShouldAutoTurnIn() or SS_ShouldAutoAccept()
            end, SS_TurnIn_OnQuestGreeting)
        end
    elseif event == "QUEST_PROGRESS" then
        if SS_ShouldAutoTurnIn() then
            SS_QueueAction("QUEST_PROGRESS", SS_ShouldAutoTurnIn, SS_TurnIn_OnQuestProgress)
        end
    elseif event == "QUEST_COMPLETE" then
        if SS_ShouldAutoTurnIn() then
            SS_QueueAction("QUEST_COMPLETE", SS_ShouldAutoTurnIn, SS_TurnIn_OnQuestComplete)
        end
    end
end)

-- ============================================================================
-- Toggle (called by UI / slash command)
-- ============================================================================
function SS_ToggleAutoTurnIn()
    SS.Settings.autoTurnIn = not SS.Settings.autoTurnIn

    if SS.Settings.autoTurnIn then
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto turn-in quests ENABLED (Hold Shift to disable).")
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Auto turn-in quests DISABLED.")
    end

    if SS_CheckboxAutoTurnIn then
        SS_CheckboxAutoTurnIn:SetChecked(SS.Settings.autoTurnIn)
    end
end

function SS_ToggleDebugTurnIn()
    SS.Settings.debugTurnIn = not SS.Settings.debugTurnIn
    if SS.Settings.debugTurnIn then
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Turn-in debug logging ENABLED.")
    else
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Turn-in debug logging DISABLED.")
    end
end
