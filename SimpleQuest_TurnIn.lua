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

local addonName, SS = ...

SS.TurnInFrame = CreateFrame("Frame")
SS.TurnInFrame:RegisterEvent("GOSSIP_SHOW")
SS.TurnInFrame:RegisterEvent("QUEST_GREETING")
SS.TurnInFrame:RegisterEvent("QUEST_PROGRESS")
SS.TurnInFrame:RegisterEvent("QUEST_COMPLETE")

-- ============================================================================
-- Guards
-- ============================================================================
local function SS_ShouldAutoTurnIn()
    if not SS.Settings or not SS.Settings.autoTurnIn then return false end
    if IsShiftKeyDown() then return false end
    return true
end

-- ============================================================================
-- Step 1a: Gossip NPCs (modern dialogue frame)
-- ============================================================================
local function SS_TurnIn_OnGossipShow()
    print("|cff3fcf7fSimpleQuest|r: [DEBUG] GOSSIP_SHOW event fired.")

    -- 1. Handle completed quests (turn-in)
    local activeQuests = C_GossipInfo.GetActiveQuests()
    if activeQuests then
        print("|cff3fcf7fSimpleQuest|r: [DEBUG] Checking active quests...")
        for _, info in ipairs(activeQuests) do
            if info.isComplete and info.questID then
                print(string.format("|cff3fcf7fSimpleQuest|r: [DEBUG] Found complete quest ID: %s. Selecting...", tostring(info.questID)))
                C_GossipInfo.SelectActiveQuest(info.questID)
                return
            end
        end
    end

    -- 2. Handle offered quests (final acceptance stage)
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    if availableQuests and #availableQuests > 0 then
        print(string.format("|cff3fcf7fSimpleQuest|r: [DEBUG] Found %d available quests. Selecting first...", #availableQuests))
        C_GossipInfo.SelectAvailableQuest(1)
        return
    end

    -- 3. Handle dialogue/quest progression (e.g., "(Quest) <Stay awhile and listen.>")
    local options = C_GossipInfo.GetOptions()
    if options then
        print(string.format("|cff3fcf7fSimpleQuest|r: [DEBUG] Checking %d gossip options...", #options))
        
        -- Case A: Only one option exists. It's almost certainly the quest dialogue.
        if #options == 1 then
            print("|cff3fcf7fSimpleQuest|r: [DEBUG] Single option detected. Selecting...")
            C_GossipInfo.SelectOption(options[1].gossipOptionID)
            return
        end

        -- Case B: Multiple options. Look for the one with a 'rewards' table or 'quest' text.
        for _, option in ipairs(options) do
            local optionText = option.text or option.name or ""
            if (option.rewards and type(option.rewards) == "table") or string.find(optionText:lower(), "quest") then
                print(string.format("|cff3fcf7fSimpleQuest|r: [DEBUG] Found quest option! Selecting ID: %s", tostring(option.gossipOptionID)))
                C_GossipInfo.SelectOption(option.gossipOptionID)
                return
            end
        end
    else
        print("|cff3fcf7fSimpleQuest|r: [DEBUG] No options found via C_GossipInfo.GetOptions().")
    end
end

-- ============================================================================
-- Step 1b: Legacy quest greeting NPCs (QuestFrameGreetingPanel)
-- ============================================================================
local function SS_TurnIn_OnQuestGreeting()
    local numActive = GetNumActiveQuests() or 0

    for i = 1, numActive do
        local _, isComplete = GetActiveTitle(i)

        -- Fall back to the quest log state if the greeting didn't report it
        if not isComplete then
            local questId = GetActiveQuestID and GetActiveQuestID(i)
            if questId and questId > 0 then
                isComplete = C_QuestLog.IsComplete(questId)
            end
        end

        if isComplete then
            SelectActiveQuest(i)
            return
        end
    end
end

-- =================================n============================================
-- Step 2: Progress panel ("Continue" button)
-- ============================================================================
local function SS_TurnIn_OnQuestProgress()
    -- Only advance if the quest's requirements are actually met
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

-- ============================================================================
-- Step 3: Reward panel ("Complete Quest" button)
-- ============================================================================
local function SS_TurnIn_OnQuestComplete()
    local numChoices = GetNumQuestChoices() or 0

    if numChoices > 1 then
        -- Player needs to pick a reward; leave the panel open
        SS_PrintChat("|cff3fcf7fSimpleQuest|r: Choose a reward to complete the quest.")
        return
    end

    -- 0 choices -> index 0 (no choice); 1 choice -> it's the only option.
    -- Mirrors what Blizzard's QuestInfoFrame.itemChoice would hold.
    GetQuestReward(numChoices)
end

-- ============================================================================
-- Event Dispatch
-- ============================================================================
SS.TurnInFrame:SetScript("OnEvent", function(self, event)
    if not SS_ShouldAutoTurnIn() then return end

    if event == "GOSSIP_SHOW" then
        SS_TurnIn_OnGossipShow()
    elseif event == "QUEST_GREETING" then
        SS_TurnIn_OnQuestGreeting()
    elseif event == "QUEST_PROGRESS" then
        SS_TurnIn_OnQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        SS_TurnIn_OnQuestComplete()
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
