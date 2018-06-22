--[[ Kniggel ]]

--TODO:
--minimap button to show/hide, right click menu
--highlight own column
--when receiving an accept, wait for iTP:IDLE() to send one broadcast with all accepting players
--save game state (/reload)
--host: repeat last state broadcast (on button click or something)
--don't force caps
--sound notification
--TCP for WoW

--DONE, needs testing:
---

local iTP = LibStub:GetLibrary("iTransferProtocol-1.0")
if not iTP then return end
local iTPCallback = iTP:RegisterPrefix("KNiGGEL")

local DefaultO = {
  ["framePoint"] = "CENTER";
  ["frameRelativeTo"] = "UIParent";
  ["frameRelativePoint"] = "CENTER";
  ["frameOffsetX"] = 0;
  ["frameOffsetY"] = 0;
  ["framePointPopup"] = "CENTER";
  ["frameRelativeToPopup"] = "UIParent";
  ["frameRelativePointPopup"] = "CENTER";
  ["frameOffsetXPopup"] = 0;
  ["frameOffsetYPopup"] = 0;
  ["showFrame"] = 1;
  ["invitelist"] = "";
  ["fixed"] = 0;
  ["debug"] = 0;
  ["stats"] = {
    ["Classic"] = {};
    ["DancingDice"] = {};
  };
  ["shoutGuild"] = 0;
  ["COMchannel"] = "GUILD";
  ["scaleFrame"] = 1;
  ["gameMode"] = "Classic";
  ["clickToDiscard"] = 0;
};
local O

local frame = CreateFrame("Frame", "KniggelFrame", UIParent)
local popupFrame = CreateFrame("Frame", "KniggelPopupFrame", UIParent)
local frameEvents = {};
local PLAYER_WIDTH = 100
local PLAYER_HEIGHT = 12
local TOP_BUTTON_HEIGHT = 12
local DICE_WIDTH = 20
local ROLL_WIDTH = 40
local ROW_COUNT = 20
local COL_SPACING = 5
local BLUE_TEXT_COLOR = {0.6, 0.6, 0.8, 1}
local LIGHTBLUE_TEXT_COLOR = {0.5, 0.5, 1, 1}
local WHITE_TEXT_COLOR = {1, 1, 1, 1}
local GREEN_TEXT_COLOR = {0.67, 1, 0.67, 1}
local GREY_TEXT_COLOR = {0.5, 0.5, 0.5, 1}
local RED_TEXT_COLOR = {1, 0.67, 0.67, 1}
local BLUE_PRINT_COLOR = "|cffaaaaff"
local CHANNEL_LIST = {"PARTY", "RAID", "GUILD", "OFFICER", "BATTLEGROUND"};
local GAMEMODE_LIST = {
  "Classic",
  "DancingDice",
};
local isdebug = 0
local function logdebug(...)
  if isdebug == 1 then
    print(...)
  end
end
local isInEncounter = false
local playerTables = {};
local playerFinishedBonus = {};
local diceLock = {
  {1, 0},
  {1, 0},
  {1, 0},
  {1, 0},
  {1, 0},
};
--KNIGGELDICELOCK = diceLock
local tempSortedDice = {0, 0, 0, 0, 0};
local myState = -1
local waitingForNextStateBroadcast = false
local nextTurnPlayer = 0
local turnPlayerId = ""
local winPlayers = nil
local myGames = {};
local myGameId = ""

local invitedBy, invitedByGameId, invitedByGameMode, invitedByChannel = "", "", "", ""
local myPlayerId

--forward function declarations
local updatePlayerColumnContent, mysplit2, updateGameState, updateNextTurnPlayerColor

local function scaleFrames(scale)
  frame:SetScale(scale)
  popupFrame:SetScale(scale)
  O.scaleFrame = scale
end

local function setCOMChannel(channel, silent)
  O.COMchannel = channel
  frame.COMchannel = channel
  frame.channelDropDown:updateSelection()
  if not silent then
    print(BLUE_PRINT_COLOR.."Kniggel |rCOM channel changed to:", channel)
  end
end
local function setGameMode(mode, silent)
  O.gameMode = mode
  frame.gameMode = mode
  frame.gameModeDropDown:updateSelection()
  if not silent then
    print(BLUE_PRINT_COLOR.."Kniggel |rgame mode changed to:", mode)
  end
end

local function returnValidGameModeOrFalse(mode)
  for i = 1, #GAMEMODE_LIST do
    if mode == GAMEMODE_LIST[i] then
      return mode
    end
  end
  return false
end

local function isValidChannel(channel)
  for i = 1, #CHANNEL_LIST do
    if channel == CHANNEL_LIST[i] then
      return true
    end
  end
  return false
end

local function isSelfGameHost(gameId)
  return myGames[gameId].invitedBy == myPlayerId
end

local function addPlayerToGameResponded(gameId, playerId)
  logdebug("!addPlayerToGameResponded", gameId, playerId)
  if not myGames[gameId] then
    return
  end
  
  for _, v in ipairs(myGames[gameId].respondedlist) do
    if v == playerId then
      return
    end
  end
  table.insert(myGames[gameId].respondedlist, playerId)
  
  logdebug("respondedlist:", table.concat(myGames[gameId].respondedlist, ", "))
end

local function checkAllPlayersPresent(gameId)
  if not myGames[gameId] then
    return
  end
  
  if #(myGames[gameId].respondedlist) ~= #(myGames[gameId].playerlist) then
    return false
  end
  
  frame.stateDisplay:SetText("All players present")
end

local function addPlayerToGame(gameId, playerId)
  if not myGames[gameId] then
    return
  end
  
  for i, v in ipairs(myGames[gameId].playerlist) do
    if v == playerId then
      return
    end
  end
  table.insert(myGames[gameId].playerlist, playerId)
end

local function removePlayerFromGame(gameId, playerId)
  if not myGames[gameId] then
    return
  end
  
  for i, v in ipairs(myGames[gameId].playerlist) do
    if v == playerId then
      table.remove(myGames[gameId].playerlist, i)
      return
    end
  end
end

local function isPlayerInvited(gameId, playerId)
  if not myGames[gameId] then
    return false
  end
  
  logdebug("?isPlayerInvited", gameId, playerId)
  local text = ""
  for _, v in ipairs(myGames[gameId].playerlist) do
    text = text..v..", "
  end
  logdebug("playerlist:", text)
  
  for _, v in ipairs(myGames[gameId].playerlist) do
    if v == playerId then
      return true
    end
  end
  return false
end

local function splitPlayerId(playerId)
  local i = playerId:find("-")
  if not i then
    return playerId
  end
  return playerId:sub(1, i - 1), playerId:sub(i + 1)
end

local function getNewPlayerTable(playerId)
  local playername, realmname = splitPlayerId(playerId)
  return {
    ["id"] = format("%s-%s", playername, realmname);
    ["nameshort"] = playername;
    ["field"] = {
      [1] = -1;
      [2] = -1;
      [3] = -1;
      [4] = -1;
      [5] = -1;
      [6] = -1;
      [7] = -1; --3 of a kind                             (sum)
      [8] = -1; --4 of a kind                             (sum)
      [9] = -1; --full house (3 of a kind + 2 of a kind)  25
      [10] = -1; --small street (sequence of 4)           30
      [11] = -1; --large street (sequence of 5)           40
      [12] = -1; --5 of a kind                            50
      [13] = -1; --chance                                 (sum)
    };
    ["collink"] = nil; --link to column table
  };
end

local function getPlayerTableById(playerId)
  for i, t in ipairs(playerTables) do
    if t.id == playerId then
      return i, t
    end
  end
  return 0, nil
end

local function addPlayerTable(playerId)
  local i = getPlayerTableById(playerId)
  if i > 0 then
    return
  end
  
  local t = getNewPlayerTable(playerId)
  table.insert(playerTables, t)
  
  frame:addPlayerColumn(t)
  frame:alignPlayerColumns()
  updatePlayerColumnContent(t)
  
  return t
end

local function removePlayerTableById(playerId)
  local i, t = getPlayerTableById(playerId)
  if i == 0 then
    return
  end
  
  frame:removePlayerColumn(t)
  playerTables[i] = nil
end

local function resetPlayer(playerTable)
  for i = 1, 13 do
    playerTable["field"][i] = -1
  end
end

local function removeAllPlayerTables()
  for i = #playerTables, 1, -1 do
    removePlayerTableById(playerTables[i].id)
  end
end

local function resetKniggel()
  removeAllPlayerTables()
  for k in pairs(myGames) do
    myGames[k] = nil
  end
  scratchFieldnumber = -1
  frame.stateDisplay:HideButton()
  myState = -1
  myGameId = ""
  updateGameState()
  iTP:ClearPendingMessages(frame.COMprefix)
  print(BLUE_PRINT_COLOR.."Kniggel |rstate reset")
end

local function addGame(gameId, invitedBy)
  local game = {
    ["invitedBy"] = invitedBy;
    ["playerlist"] = {};
    ["respondedlist"] = {};
    ["state"] = 0;
  };
  myGames[gameId] = game
  return game
end

local function isCommaSeparatedPlayerIdList(text)
  local list = mysplit2(text, ",")
  for _, v in ipairs(list) do
    if not v:find("^[^%s]+\-[^%s]+$") then
      return false
    end
  end
  return true
end

--playerIdList = "player1-realm,player2-realm,..."
local function inviteNewGame(playerIdList)
  if not playerIdList then
    return
  end
  
  if not isCommaSeparatedPlayerIdList(playerIdList) then
    print(BLUE_PRINT_COLOR.."Kniggel: |rInvite list needs to be like:\n".."Alice-Realmname,Bob-Realmname,...")
    return
  end
  
  myGameId = frame:getNewGameId()
  removeAllPlayerTables()
  addPlayerTable(myPlayerId)
  local game = addGame(myGameId, myPlayerId)
  game.playerlist = mysplit2(playerIdList, ",")
  frame:sendBroadcastInvite(myGameId)
  addPlayerToGame(myGameId, myPlayerId) --don't need an invite, so add now
  addPlayerToGameResponded(myGameId, myPlayerId) --i responded to my own game
  
  myState = 0
  updateGameState()
end

local function buildGameField(gameId)
  removeAllPlayerTables()
  local game = myGames[gameId]
  for i, v in ipairs(game.playerlist) do
    addPlayerTable(v)
  end
end

local function prepareState(state, isFirstTime)
  if state == 1 then
    if frame.gameMode == "Classic" then
      --choose next player
      nextTurnPlayer = nextTurnPlayer + 1
      if nextTurnPlayer > #(myGames[myGameId].playerlist) then
        nextTurnPlayer = 1
      end
      turnPlayerId = myGames[myGameId].playerlist[nextTurnPlayer]
      logdebug("turnPlayerId", turnPlayerId)
      
      frame:sendBroadcastPlayersTurn(myGameId, 1, turnPlayerId)
    elseif frame.gameMode == "DancingDice" then
      if isFirstTime then
        frame:sendBroadcastAllPlayersFirstTurn(myGameId, 1)
      else
        frame:sendBroadcastPlayersTurn(myGameId, 1, turnPlayerId)
      end
    end
  elseif state == 2 then
    frame:sendBroadcastPlayersTurn(myGameId, 2, turnPlayerId)
  elseif state == 3 then
    frame:sendBroadcastPlayersTurn(myGameId, 3, turnPlayerId)
  elseif state == 4 then
    frame:sendBroadcastPlayersTurn(myGameId, 4, turnPlayerId)
  elseif state == 5 then
    frame:sendBroadcastPlayersTurn(myGameId, 5, turnPlayerId)
  elseif state == 6 then
    frame:sendBroadcastPlayersTurn(myGameId, 6, turnPlayerId)
  elseif state == 7 then
    frame:sendBroadcastPlayersTurn(myGameId, 7, turnPlayerId)
  elseif state == 8 then
    if frame.gameMode == "Classic" then
      local playerlist = {};
      for _, playerId in ipairs(myGames[myGameId].playerlist) do
        local _, t = getPlayerTableById(playerId)
        local points = updatePlayerColumnContent(t)
        table.insert(playerlist, {playerId, points})
      end
      table.sort(playerlist, function(a,b)return a[2]>b[2] end)
      
      if #playerlist >= 3 then
        frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2], playerlist[2][1], playerlist[2][2], playerlist[3][1], playerlist[3][2])
      elseif #playerlist >= 2 then
        frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2], playerlist[2][1], playerlist[2][2])
      else
        frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2])
      end
    elseif frame.gameMode == "DancingDice" then
      --called every time a player broadcasts his state 7
      if isSelfGameHost(myGameId) then
        local allPlayersFinished = true
        for k, v in pairs(playerFinishedBonus) do
          if v == -1 then
            allPlayersFinished = false
            break
          end
        end
        if allPlayersFinished then
          local playerlist = {};
          for _, playerId in ipairs(myGames[myGameId].playerlist) do
            local _, t = getPlayerTableById(playerId)
            local points = updatePlayerColumnContent(t)
            table.insert(playerlist, {playerId, points})
          end
          table.sort(playerlist, function(a,b)return a[2]>b[2] end)
          
          if #playerlist >= 3 then
            frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2], playerlist[2][1], playerlist[2][2], playerlist[3][1], playerlist[3][2])
          elseif #playerlist >= 2 then
            frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2], playerlist[2][1], playerlist[2][2])
          else
            frame:sendBroadcastPlayerWins(myGameId, 8, playerlist[1][1], playerlist[1][2])
          end
        end
      end
    end
  end
end

local function rollDice()
  for i = 1, 5 do
    if diceLock[i][2] == 0 then
      diceLock[i][1] = random(1, 6)
    end
  end
  --if clicking to discard dice, lock all dice after rolling
  if O.clickToDiscard == 1 then
    for i = 1, 5 do
      diceLock[i][2] = 1
    end
  end
  frame:sendMyDiceStatus(myGameId)
  frame:updateDiceDisplay()
  waitingForNextStateBroadcast = true
end

--call lockDice([01], [01], [01], [01], [01])
local function lockDice(...)
  for i = 1, 5 do
    if select(i, ...) == 1 then
      diceLock[i][2] = 1
    else
      diceLock[i][2] = 0
    end
  end
  frame:updateDiceDisplay()
  frame:sendMyDiceStatus(myGameId)
  waitingForNextStateBroadcast = true
end

local function sumDice()
  local n = 0
  for i = 1, 5 do
    n = n + diceLock[i][1]
  end
  return n
end

local function isDice_Kniggel(sortedDice)
  local foundKniggel = true
  local v = sortedDice[1]
  for i = 2, 5 do
    if sortedDice[i] ~= v then
      foundKniggel = false
      break
    end
  end
  if foundKniggel then
    return true
  else
    return false
  end
end

local function getChooseFieldAmount(fieldnumber)
  for i = 1, 5 do
    tempSortedDice[i] = diceLock[i][1]
  end
  table.sort(tempSortedDice, function(a,b)return a<b end)
  
  if fieldnumber >= 1 and fieldnumber <= 6 then
    local n = 0
    for i = 1, 5 do
      if tempSortedDice[i] == fieldnumber then
        n = n + fieldnumber
      end
    end
    return n
  elseif fieldnumber == 7 or fieldnumber == 8 then
    local sameAmount = fieldnumber == 7 and 3 or 4
    local foundSame = false
    local n
    for v = 1, 6 do
      n = 0
      for i = 1, 5 do
        if tempSortedDice[i] == v then
          n = n + 1
        end
      end
      if n >= sameAmount then
        foundSame = true
        break
      end
    end
    if foundSame then
      return sumDice()
    else
      return 0
    end
  elseif fieldnumber == 9 then --Full House
    if tempSortedDice[1] == tempSortedDice[2] and tempSortedDice[4] == tempSortedDice[5]
          and (tempSortedDice[2] == tempSortedDice[3] or tempSortedDice[3] == tempSortedDice[4])
          and not isDice_Kniggel(tempSortedDice) then
      --1==2 && 4==5 && (2==3 || 3==4)
      return 25
    else
      return 0
    end
  elseif fieldnumber == 10 or fieldnumber == 11 then --Small or Large Street
    local streetLength
    if fieldnumber == 10 then
      streetLength = 4
    else
      streetLength = 5
    end
    local foundStreet = false
    for i = 1, 6-streetLength do
      local v = tempSortedDice[i]
      local n = 1
      for v2 = v + 1, v + streetLength - 1 do
        for j = i + 1, 5 do
          if tempSortedDice[j] == v2 then
            n = n + 1
            break
          end
        end
      end
      if n >= streetLength then
        foundStreet = true
        break
      end
    end
    if foundStreet then
      return fieldnumber == 10 and 30 or 40
    else
      return 0
    end
  elseif fieldnumber == 12 then --Kniggel
    if isDice_Kniggel(tempSortedDice) then
      return 50
    else
      return 0
    end
  elseif fieldnumber == 13 then --Chance
    return sumDice()
  else
    return -1
  end
end

local function confirmScratch()
  if scratchFieldnumber ~= -1 then
    local _, t = getPlayerTableById(myPlayerId)
    t.field[scratchFieldnumber] = 0
    frame:sendMyPlayerTable(myGameId, scratchFieldnumber)
    scratchFieldnumber = -1
    frame.stateDisplay:HideButton()
    waitingForNextStateBroadcast = true
  end
end

--call chooseField(1..13)
local function chooseField(fieldnumber)
  local _, t = getPlayerTableById(myPlayerId)
  
  if t.field[fieldnumber] ~= -1 then return false end
  
  local amount = getChooseFieldAmount(fieldnumber)
  
  if amount > 0 then
    scratchFieldnumber = -1
    frame.stateDisplay:HideButton()
    t.field[fieldnumber] = amount
    frame:sendMyPlayerTable(myGameId, fieldnumber)
    waitingForNextStateBroadcast = true
    return true
  else
    scratchFieldnumber = fieldnumber
    frame.stateDisplay:SetText("Confirm scratch?")
    frame.stateDisplay:ShowButton()
    return true
  end
end

local function isChooseAllowed()
  return turnPlayerId == myPlayerId and waitingForNextStateBroadcast == false and (myState == 2 or myState == 4 or myState == 6)
end
local function isLockAllowed()
  return turnPlayerId == myPlayerId and waitingForNextStateBroadcast == false and (myState == 2 or myState == 4)
end
local function isRollAllowed()
  return turnPlayerId == myPlayerId and waitingForNextStateBroadcast == false and (myState == 1 or myState == 3 or myState == 5)
end

local function addStats(playercount, score)
  local isWin = winPlayers[1][1] == myPlayerId
  if not O.stats[O.gameMode] then
    O.stats[O.gameMode] = {};
  end
  local t = O.stats[O.gameMode][playercount]
  if not t then
    t = {
      ["games"] = 0;
      ["wins"] = 0;
      ["high"] = 0;
      ["totalscore"] = 0;
    };
    O.stats[O.gameMode][playercount] = t
  end
  
  local overallHigh, overallHighPlayers = 0, 0
  for i, t2 in pairs(O.stats[O.gameMode]) do
    if t2.high > overallHigh then
      overallHigh = t2.high
      overallHighPlayers = i
    end
  end
  
  local oldGames, oldWins, oldHigh = t.games, t.wins, t.high
  
  t.games = t.games + 1
  if isWin then 
    t.wins = t.wins + 1
  end
  if score > t.high then
    t.high = score
  end
  t.totalscore = t.totalscore + score
  
  if isWin then
    print(BLUE_PRINT_COLOR.."Kniggel: |rYou win!")
    if O.shoutGuild == 1 then
      if #winPlayers >= 3 then
        local playername2 = splitPlayerId(winPlayers[2][1])
        local playername3 = splitPlayerId(winPlayers[3][1])
        --SendChatMessage(format("I just won a game of Kniggel (%s) with %s points! 2nd: %s, %d points; 3rd: %s, %d points", O.gameMode, score, playername2, winPlayers[2][2], playername3, winPlayers[3][2]), "GUILD")
        SendChatMessage(format("I just won a game of Kniggel (%s) with %s points! 2nd: %s, %d points; 3rd: %s, %d points", O.gameMode, score, playername2, winPlayers[2][2], playername3, winPlayers[3][2]), O.COMchannel)
      elseif #winPlayers >= 2 then
        local playername2 = splitPlayerId(winPlayers[2][1])
        --SendChatMessage(format("I just won a game of Kniggel (%s) with %s points! 2nd: %s, %d points", O.gameMode, score, playername2, winPlayers[2][2]), "GUILD")
        SendChatMessage(format("I just won a game of Kniggel (%s) with %s points! 2nd: %s, %d points", O.gameMode, score, playername2, winPlayers[2][2]), O.COMchannel)
      else
        --SendChatMessage(format("I just won a game of Kniggel (%s) with %s points!", O.gameMode, score), "GUILD")
        SendChatMessage(format("I just won a game of Kniggel (%s) with %s points!", O.gameMode, score), O.COMchannel)
      end
    end
  end
  
  print(format(BLUE_PRINT_COLOR.."Kniggel (%s): |rTotal wins with %d players: %d", O.gameMode, playercount, t.wins))
  print(format("  Average score with %d players: %d, %d%% wins", playercount, t.totalscore/t.games, t.wins/t.games*100))
  if score > oldHigh and oldHigh > 0 then
    print(format("  New high score with %d players: %d!", playercount, score))
  end
  if score > overallHigh and overallHigh > 0 then
    print(format("  New overall high score! (last was %d with %d players)", overallHigh, overallHighPlayers))
  end
end

local function resetStats()
  for _, v in pairs(O.stats) do
    for i, _ in pairs(v) do
      v[i] = nil
    end
  end
end

function updateGameState()
  logdebug("updateGameState", myState)
  
  waitingForNextStateBroadcast = false
  
  if myState == 0 then
    frame.stateDisplay:SetText("Waiting for players...")
  elseif myState == 1 then
    for i = 1, 5 do
      diceLock[i][1] = 0 --face ?
      diceLock[i][2] = 0 --not locked
    end
    frame:updateDiceDisplay(true)
    
    if frame.gameMode == "Classic" then
      if turnPlayerId == myPlayerId then
        print(BLUE_PRINT_COLOR.."Kniggel: |rYour turn!")
      end
    --[[
    --do not announce every turn
    elseif frame.gameMode == "DancingDice" then
      print(BLUE_PRINT_COLOR.."Kniggel: |rYour turn!")
    --]]
    end
    frame.stateDisplay:SetText("First roll")
  elseif myState == 2 then
    frame.stateDisplay:SetText("First lock or choose")
  elseif myState == 3 then
    frame.stateDisplay:SetText("Second roll")
    frame:updateDiceDisplay(true)
  elseif myState == 4 then
    frame.stateDisplay:SetText("Second lock or choose")
  elseif myState == 5 then
    frame.stateDisplay:SetText("Third roll")
    frame:updateDiceDisplay(true)
  elseif myState == 6 then
    frame.stateDisplay:SetText("Choose now")
  elseif myState == 7 then
    if frame.gameMode == "Classic" then
      if isSelfGameHost(myGameId) then
        local allPlayersFinished = true
        for _, playerId in ipairs(myGames[myGameId].playerlist) do
          local _, t = getPlayerTableById(playerId)
          for i = 1, 13 do
            if t.field[i] == -1 then
              allPlayersFinished = false
              break
            end
          end
        end
        if allPlayersFinished then
          prepareState(8)
        else
          prepareState(1)
        end
      end
      frame.stateDisplay:SetText("Next player's turn...")
    elseif frame.gameMode == "DancingDice" then
      local isFinished = true
      local _, t = getPlayerTableById(myPlayerId)
      for i = 1, 13 do
        if t.field[i] == -1 then
          isFinished = false
          break
        end
      end
      if isFinished then
        frame.stateDisplay:SetText("You finished!")
        prepareState(8)
      else
        frame.stateDisplay:SetText("Next turn...")
        prepareState(1)
      end
    end
  elseif myState == 8 then
    local _, playerTable = getPlayerTableById(myPlayerId)
    local score = updatePlayerColumnContent(playerTable)
    addStats(#(myGames[myGameId].playerlist), score)
    myState = -1
    updateGameState()
  end
  
  if isRollAllowed() then
    frame.rollDisplay:SetTextColor(unpack(GREEN_TEXT_COLOR))
  else
    frame.rollDisplay:SetTextColor(unpack(GREY_TEXT_COLOR))
  end
  if isLockAllowed() then
    frame.diceDisplay[6]:SetTextColor(unpack(GREEN_TEXT_COLOR))
  else
    frame.diceDisplay[6]:SetTextColor(unpack(GREY_TEXT_COLOR))
  end
  
  if myState == -1 or myState == 8 then
    frame.inviteTextbox:Show()
    frame.inviteDisplay:ShowAll()
  else
    frame.inviteTextbox:Hide()
    frame.inviteDisplay:HideAll()
  end
  
  if myState == -1 then
    frame.channelDropDown:Show()
    frame.gameModeDropDown:Show()
  else
    frame.channelDropDown:Hide()
    frame.gameModeDropDown:Hide()
  end
  
  if myState == 0 and isSelfGameHost(myGameId) then
    frame.startGameDisplay:ShowAll()
  else
    frame.startGameDisplay:HideAll()
  end
  
  if myState == -1 or myState == 8 then
    frame.stateDisplay:Hide()
  else
    frame.stateDisplay:Show()
    if turnPlayerId == myPlayerId then
      frame.stateDisplay:SetTextColor(unpack(GREEN_TEXT_COLOR))
    else
      frame.stateDisplay:SetTextColor(unpack(GREY_TEXT_COLOR))
    end
  end
  
  updateNextTurnPlayerColor()
end

local function startGame()
  myState = 0
  
  --remove players who did not respond
  myGames[myGameId].playerlist = {};
  for i, v in ipairs(myGames[myGameId].respondedlist) do
    table.insert(myGames[myGameId].playerlist, v)
    logdebug("Player", v)
  end
  
  nextTurnPlayer = 0
  prepareState(1, true)
end

function updateNextTurnPlayerColor()
  if myGameId and myGames[myGameId] then
    for _, v in ipairs(myGames[myGameId].playerlist) do
      local _, playerTable = getPlayerTableById(v)
      if playerTable then
        if v == turnPlayerId then
          playerTable.collink[1]:SetTextColor(unpack(GREEN_TEXT_COLOR))
        else
          playerTable.collink[1]:SetTextColor(unpack(BLUE_TEXT_COLOR))
        end
      end
    end
  end
end

function updatePlayerColumnContent(playerTable, fieldnumber)
  playerTable.collink[1]:SetText(playerTable.nameshort)

  local p, sum, topSum, bottomSum = 0, 0, 0, 0
  local f = playerTable.field
  
  for i = 1, 6 do
    p = f[i]
    if fieldnumber and fieldnumber == i then
      playerTable.collink[i+1]:SetText(format("[%s]", p == -1 and "-" or p))
    else
      playerTable.collink[i+1]:SetText(p == -1 and "-" or p)
    end
    p = p == -1 and 0 or p
    topSum = topSum + p
  end
  
  playerTable.collink[8]:SetText(topSum)
  if topSum >= 63 then
    topSum = topSum + 35
    playerTable.collink[9]:SetText("35")
  else
    playerTable.collink[9]:SetText("0")
  end
  playerTable.collink[10]:SetText(topSum)
  
  for i = 7, 13 do
    p = f[i]
    if fieldnumber and fieldnumber == i then
      playerTable.collink[i+4]:SetText(format("[%s]", p == -1 and "-" or p))
    else
      playerTable.collink[i+4]:SetText(p == -1 and "-" or p)
    end
    p = p == -1 and 0 or p
    bottomSum = bottomSum + p
  end
  playerTable.collink[18]:SetText(bottomSum)
  playerTable.collink[19]:SetText(topSum)
  
  sum = topSum + bottomSum
  
  if frame.gameMode == "Classic" then
    playerTable.collink[20]:SetText(sum)
  elseif frame.gameMode == "DancingDice" then
    if playerFinishedBonus[playerTable.id] and playerFinishedBonus[playerTable.id] > 0 then
      playerTable.collink[20]:SetText(format("%d (+%d)", sum, playerFinishedBonus[playerTable.id]))
      sum = sum + playerFinishedBonus[playerTable.id]
    else
      playerTable.collink[20]:SetText(sum)
    end
  end
  
  return sum
end

local function getNewClickableRowFrame(frameself, tag, tag2)
  local ret = CreateFrame("Frame", nil, frameself)
  ret:SetFrameStrata("LOW")
  ret:SetSize(PLAYER_WIDTH, PLAYER_HEIGHT)
  
  ret.tag = tag
  ret.tag2 = tag2
  
  --HIGHLIGHT
  ret.highlighttexture = ret:CreateTexture(nil, "HIGHLIGHT")
  ret.highlighttexture:SetAllPoints(ret)
  ret.highlighttexture:SetColorTexture(1, 1, 1, 0.2)
  
  ret.frameRef = frameself
  ret:EnableMouse(true)
  ret:SetScript("OnMouseUp", function(self, button)
    if GetMouseFocus() == self then --OnMouseUp fires when the button is released while the cursor is not above the frame
      self.frameRef:handleMouseUp(self.tag, self.tag2, button)
    end
  end)
  
  return ret
end

local function getNewClickableFontString(frameself, width, height, anchorself, parent, anchorparent, dx, dy, clickTag1, clickTag2)
  local ret = frameself:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ret:SetPoint(anchorself, parent, anchorparent, dx, dy)
  ret:SetJustifyH("CENTER")
  ret:SetJustifyV("MIDDLE")
  if width and height then
    ret:SetSize(width, height)
  end
  ret:SetTextColor(unpack(WHITE_TEXT_COLOR))
  
  local froll = getNewClickableRowFrame(frameself, clickTag1, clickTag2)
  froll:SetAllPoints(ret)
  ret.clickFrame = froll
  
  ret.ShowButton = function(self)
    self.clickFrame:Show()
  end
  ret.HideButton = function(self)
    self.clickFrame:Hide()
  end
  ret.ShowAll = function(self)
    self:Show()
    self.clickFrame:Show()
  end
  ret.HideAll = function(self)
    self.clickFrame:Hide()
    self:Hide()
  end
  ret.setClickTag1 = function(self, tag)
    self.clickFrame.tag = tag
  end
  
  return ret
end

local function getNewClickableTexture(frameself, width, height, anchorself, parent, anchorparent, dx, dy, clickTag1, clickTag2)
  local ret = CreateFrame("Frame", nil, frameself)
  ret:SetFrameStrata("LOW")
  ret:SetSize(width, height)
  ret:SetPoint(anchorself, parent, anchorparent, dx, dy)
  
  ret.tag = clickTag1
  ret.tag2 = clickTag2
  
  --HIGHLIGHT
  ret.highlighttexture = ret:CreateTexture(nil, "HIGHLIGHT")
  ret.highlighttexture:SetAllPoints(ret)
  ret.highlighttexture:SetColorTexture(1, 1, 1, 0.2)
  
  ret.frameRef = frameself
  ret:EnableMouse(true)
  ret:SetScript("OnMouseUp", function(self, button)
    if GetMouseFocus() == self then --OnMouseUp fires when the button is released while the cursor is not above the frame
      self.frameRef:handleMouseUp(self.tag, self.tag2, button)
    end
  end)
  
  ret.tex = ret:CreateTexture(nil, "OVERLAY")
  ret.tex:SetAllPoints(ret)
  
  return ret
end

local function initFrame()
  frame:SetPoint(O["framePoint"], O["frameRelativeTo"], O["frameRelativePoint"], O["frameOffsetX"], O["frameOffsetY"])
  frame:SetFrameStrata("LOW")
  frame:SetSize((PLAYER_WIDTH + COL_SPACING) * 2, 330)
  
  frame.bgtexture = frame:CreateTexture(nil, "OVERLAY")
  frame.bgtexture:SetAllPoints(frame)
  frame.bgtexture:SetColorTexture(0, 0, 0, 1)
  
  frame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    O["framePoint"] = point or "CENTER"
    O["frameRelativeTo"] = relativeTo or "UIParent"
    O["frameRelativePoint"] = relativePoint or "CENTER"
    O["frameOffsetX"] = xOfs
    O["frameOffsetY"] = yOfs
  end);
  
  frame.toggleFrame = function(self, b)
    if b == 1 then
      self:Show()
    else
      self:Hide()
    end
    O.showFrame = b
  end
  
  frame:EnableMouse(true)
  
  frame.tslU = 0
  frame.timerInterval = 2
  frame.timerIntervalB = 1
  
  --------------------
  -- Player table displays
  --------------------
  
  frame.unusedPlayerColumns = {};
  frame.playerColumns = {};
  frame.getNewColumn = function(self)
    local colTable
    if #(self.unusedPlayerColumns) > 0 then
      colTable = table.remove(self.unusedPlayerColumns) --pop last element
      for i, v in ipairs(colTable) do
        v:Show()
      end
    else
      colTable = {};
      local lastRow = nil
      for i = 1, ROW_COUNT do
        local row = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        if lastRow then
          row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, 0)
        else
          row:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
        end
        lastRow = row
        row:SetSize(PLAYER_WIDTH, PLAYER_HEIGHT)
        row:SetText("0")
        row:SetJustifyH("LEFT")
        if i >= 2 and i <= 7 or i >= 11 and i <= 17 then
          row:SetTextColor(unpack(WHITE_TEXT_COLOR))
        else
          row:SetTextColor(unpack(BLUE_TEXT_COLOR))
        end
        colTable[i] = row
      end
    end
    
    table.insert(self.playerColumns, colTable)
    return colTable
  end
  frame.handleMouseUp = function(self, tag, tag2, button)
    if button == "LeftButton" then
      if tag2 == 1 and not isInEncounter then --choose
        if isChooseAllowed() then
          chooseField(tag)
        end
      elseif tag2 == 2 and not isInEncounter then
        if isLockAllowed() then
          if tag <= 5 then --lock/unlock
            diceLock[tag][2] = diceLock[tag][2] == 1 and 0 or 1
            self:updateDiceDisplay()
          else --confirm lock
            lockDice(diceLock[1][2], diceLock[2][2], diceLock[3][2], diceLock[4][2], diceLock[5][2])
          end
        end
      elseif tag2 == 3 and not isInEncounter then --roll
        if isRollAllowed() then
          rollDice()
        end
      elseif tag2 == 4 and not isInEncounter then --single invite
        inviteNewGame(O.invitelist)
      elseif tag2 == 5 and not isInEncounter then --start game
        startGame()
      elseif tag2 == 6 then --hide frame
        self:toggleFrame(0)
      elseif tag2 == 7 and not isInEncounter then --confirm scratch
        if tag == 1 then
          if isChooseAllowed() then
            confirmScratch()
          end
        end
      elseif tag2 == 9 then --reset
        if tag == 1 and IsControlKeyDown() and IsShiftKeyDown() and IsAltKeyDown() then
          resetKniggel()
        end
      elseif tag2 == 10 then --lock/unlock frame
        if O.fixed == 0 then
          O.fixed = 1
          self:SetMovable(false)
          self:RegisterForDrag("")
        else
          O.fixed = 0
          self:SetMovable(true)
          self:RegisterForDrag("LeftButton")
        end
        self:updateLockButtonTex()
      end
    end
  end
  
  frame.addFirstColumn = function(self)
    local colTable = self:getNewColumn()
    
    colTable[1].id = "first"
    
    colTable[1]:SetText("Name:")
    colTable[2]:SetText("1:")
    colTable[3]:SetText("2:")
    colTable[4]:SetText("3:")
    colTable[5]:SetText("4:")
    colTable[6]:SetText("5:")
    colTable[7]:SetText("6:")
    colTable[8]:SetText("SUM:")
    colTable[9]:SetText("Bonus (>= 63):")
    colTable[10]:SetText("Upper Total:")
    colTable[11]:SetText("3 of a kind:")
    colTable[12]:SetText("4 of a kind:")
    colTable[13]:SetText("Full House:")
    colTable[14]:SetText("Small Street:")
    colTable[15]:SetText("Large Street:")
    colTable[16]:SetText("Kniggel:")
    colTable[17]:SetText("Chance:")
    colTable[18]:SetText("SUM:")
    colTable[19]:SetText("Upper Total:")
    colTable[20]:SetText("TOTAL:")
    
    for i = 1, ROW_COUNT do
      colTable[i]:SetJustifyH("RIGHT")
    end
    
    self.firstColumn = colTable
    
    for i = 1, 6 do
      local f = getNewClickableRowFrame(frame, i, 1)
      f:SetPoint("TOPLEFT", colTable[i + 1], "TOPLEFT")
      colTable[i + 1].clickFrame = f
    end
    for i = 7, 13 do
      local f = getNewClickableRowFrame(frame, i, 1)
      f:SetPoint("TOPLEFT", colTable[i + 4], "TOPLEFT")
      colTable[i + 4].clickFrame = f
    end
  end
  frame.addPlayerColumn = function(self, playerTable)
    local colTable = self:getNewColumn()
    
    colTable[1].id = playerTable.id
    
    playerTable.collink = colTable
  end
  frame.removePlayerColumn = function(self, playerTable)
    for i, colTable in ipairs(self.playerColumns) do
      if colTable[1].id == playerTable.id then
        local colTable2 = table.remove(self.playerColumns, i) --pop element
        for _, row in ipairs(colTable2) do
          row:Hide()
        end
        playerTable.collink = nil
        table.insert(self.unusedPlayerColumns, colTable2)
        return
      end
    end
  end
  
  frame.alignPlayerColumns = function(self)
    for i, colTable in ipairs(self.playerColumns) do
      colTable[1]:SetPoint("TOPLEFT", self, "TOPLEFT", (i-1)*(PLAYER_WIDTH+COL_SPACING), 0)
    end
    self:SetWidth((PLAYER_WIDTH + COL_SPACING) * (#(self.playerColumns)))
    
    for i = 1, 6 do
      self.firstColumn[i + 1].clickFrame:SetWidth(self:GetWidth())
    end
    for i = 7, 13 do
      self.firstColumn[i + 4].clickFrame:SetWidth(self:GetWidth())
    end
  end
  
  frame.OnUpdate = function(self, elapsed)
    self.tslU = self.tslU + elapsed
    if (self.tslU >= self.timerInterval) then
      self.tslU = 0
    end
  end
  frame:SetScript("OnUpdate", function(self, elapsed)
    self.OnUpdate(self, elapsed)
  end);
  
  frame:addFirstColumn()
  
  --------------------
  -- Dice display
  --------------------
  
  frame.diceDisplay = {};
  local lastDice = nil
  for i = 1, 5 do
    if lastDice then
      frame.diceDisplay[i] = getNewClickableFontString(frame, DICE_WIDTH, DICE_WIDTH, "BOTTOMLEFT", lastDice, "BOTTOMRIGHT", 0, 0, i, 2)
    else
      frame.diceDisplay[i] = getNewClickableFontString(frame, DICE_WIDTH, DICE_WIDTH, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0, i, 2)
    end
    lastDice = frame.diceDisplay[i]
    
    frame.diceDisplay[i]:SetText("d"..i)
  end
  frame.diceDisplay[6] = getNewClickableFontString(frame, DICE_WIDTH, DICE_WIDTH, "BOTTOMLEFT", lastDice, "BOTTOMRIGHT", 5, 0, 6, 2)
  lastDice = frame.diceDisplay[6]
  frame.diceDisplay[6]:SetText("OK")
  
  frame.updateDiceDisplay = function(self, showQuestionMarks)
    for i = 1, 5 do
      local text
      if O.clickToDiscard == 1 then
        if diceLock[i][2] == 1 then
          text = diceLock[i][1]
          frame.diceDisplay[i]:SetTextColor(unpack(WHITE_TEXT_COLOR))
        else
          text = showQuestionMarks and "?" or diceLock[i][1]
          frame.diceDisplay[i]:SetTextColor(unpack(GREY_TEXT_COLOR))
        end
        frame.diceDisplay[i]:SetText(text)
      else
        if diceLock[i][2] == 1 then
          text = "["..diceLock[i][1].."]"
        else
          text = showQuestionMarks and "?" or diceLock[i][1]
        end
        frame.diceDisplay[i]:SetTextColor(unpack(WHITE_TEXT_COLOR))
        frame.diceDisplay[i]:SetText(text)
      end
    end
  end
  
  --------------------
  -- Close button
  --------------------
  
  frame.CloseButton = getNewClickableFontString(frame, TOP_BUTTON_HEIGHT, TOP_BUTTON_HEIGHT, "TOPLEFT", frame, "TOPLEFT", 0, 0, 1, 6)
  frame.CloseButton:SetText("X")
  frame.CloseButton:SetTextColor(unpack(RED_TEXT_COLOR))
  
  --------------------
  -- Lock button
  --------------------
  
  frame.lockButton = getNewClickableTexture(frame, TOP_BUTTON_HEIGHT, TOP_BUTTON_HEIGHT, "TOPLEFT", frame, "TOPLEFT", TOP_BUTTON_HEIGHT, 0, 1, 10)
  frame.lockButton.texFileLocked = "Interface\\Addons\\Kniggel\\Graphics\\lockclosed"
  frame.lockButton.texFileUnlocked = "Interface\\Addons\\Kniggel\\Graphics\\lockopen"
  frame.updateLockButtonTex = function(self)
    if O.fixed == 1 then
      self.lockButton.tex:SetTexture(self.lockButton.texFileLocked)
    else
      self.lockButton.tex:SetTexture(self.lockButton.texFileUnlocked)
    end
  end
  frame:updateLockButtonTex()
  
  --------------------
  -- Reset button
  --------------------
  
  frame.resetButton = getNewClickableTexture(frame, TOP_BUTTON_HEIGHT, TOP_BUTTON_HEIGHT, "TOPLEFT", frame, "TOPLEFT", TOP_BUTTON_HEIGHT * 2, 0, 1, 9)
  frame.resetButton.tex:SetTexture("Interface\\Addons\\Kniggel\\Graphics\\reset")
  
  --------------------
  -- Roll display
  --------------------
  
  frame.rollDisplay = getNewClickableFontString(frame, ROLL_WIDTH, DICE_WIDTH, "BOTTOMLEFT", lastDice, "BOTTOMRIGHT", 10, 0, 1, 3)
  frame.rollDisplay:SetText("ROLL")
  
  --------------------
  -- State display
  --------------------
  
  frame.stateDisplay = getNewClickableFontString(frame, nil, nil, "BOTTOMLEFT", frame, "BOTTOMLEFT", 10, DICE_WIDTH + 4, 1, 7)
  frame.stateDisplay:SetFont("Fonts\\FRIZQT__.TTF", 14)
  frame.stateDisplay:SetTextColor(unpack(WHITE_TEXT_COLOR))
  frame.stateDisplay:SetText("State display")
  frame.stateDisplay:HideAll()
  
  --------------------
  -- Invite display
  --------------------
  
  local invtextbox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.inviteTextbox = invtextbox
  invtextbox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, DICE_WIDTH)
  invtextbox:SetAutoFocus(false)
  invtextbox:SetWidth(PLAYER_WIDTH)
  invtextbox:SetHeight(DICE_WIDTH)
  invtextbox:SetTextInsets(0,0,3,3)
  invtextbox:SetText(O.invitelist)
  invtextbox:SetCursorPosition(0)
  invtextbox:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    O.invitelist = self:GetText()
  end);
  invtextbox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    self:SetText(O.invitelist)
  end);
  
  frame.inviteDisplay = getNewClickableFontString(frame, ROLL_WIDTH, DICE_WIDTH, "BOTTOMLEFT", frame, "BOTTOMLEFT", (10 + PLAYER_WIDTH) + 10, DICE_WIDTH, 1, 4)
  frame.inviteDisplay:SetText("Invite")
  
  frame.startGameDisplay = getNewClickableFontString(frame, ROLL_WIDTH, DICE_WIDTH, "BOTTOMLEFT", frame, "BOTTOMLEFT", (10 + PLAYER_WIDTH) + (10 + ROLL_WIDTH) + 10, DICE_WIDTH, 1, 5)
  frame.startGameDisplay:SetText("Start")
  
  --------------------
  -- channel display
  --------------------
  
  frame.channelDropDown = CreateFrame("Button", "$parentChannelDropDown", frame, "UIDropDownMenuTemplate")
  frame.channelDropDown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -14, DICE_WIDTH + 20)
  frame.channelDropDown.OnClick = function(self)
    if O.COMchannel ~= CHANNEL_LIST[self:GetID()] then
      setCOMChannel(CHANNEL_LIST[self:GetID()])
    end
  end
  frame.channelDropDown.initialize = function(self, level)
    local info
    for _, v in ipairs(CHANNEL_LIST) do
      info = UIDropDownMenu_CreateInfo()
      info.text = v
      info.value = v
      info.func = self.OnClick
      UIDropDownMenu_AddButton(info, level)
    end
  end
  frame.channelDropDown.updateSelection = function(self)
    local dropDownIndex = 3 --GUILD
    for i, v in ipairs(CHANNEL_LIST) do
      if v == O.COMchannel then
        dropDownIndex = i
        break
      end
    end
    UIDropDownMenu_SetSelectedID(self, dropDownIndex)
  end
  UIDropDownMenu_Initialize(frame.channelDropDown, frame.channelDropDown.initialize)
  UIDropDownMenu_SetWidth(frame.channelDropDown, 100, 0)
  UIDropDownMenu_SetButtonWidth(frame.channelDropDown, 124)
  frame.channelDropDown:updateSelection()
  UIDropDownMenu_JustifyText(frame.channelDropDown, "LEFT")
  
  --------------------
  -- game mode display
  --------------------
  
  frame.gameModeDropDown = CreateFrame("Button", "$parentGameModeDropDown", frame, "UIDropDownMenuTemplate")
  frame.gameModeDropDown:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 110, DICE_WIDTH + 20)
  frame.gameModeDropDown.OnClick = function(self)
    if O.gameMode ~= GAMEMODE_LIST[self:GetID()] then
      setGameMode(GAMEMODE_LIST[self:GetID()])
    end
  end
  frame.gameModeDropDown.initialize = function(self, level)
    local info
    for _, v in ipairs(GAMEMODE_LIST) do
      info = UIDropDownMenu_CreateInfo()
      info.text = v
      info.value = v
      info.func = self.OnClick
      UIDropDownMenu_AddButton(info, level)
    end
  end
  frame.gameModeDropDown.updateSelection = function(self)
    local dropDownIndex = 1 --Classic
    for i, v in ipairs(GAMEMODE_LIST) do
      if v == O.gameMode then
        dropDownIndex = i
        break
      end
    end
    UIDropDownMenu_SetSelectedID(self, dropDownIndex)
  end
  UIDropDownMenu_Initialize(frame.gameModeDropDown, frame.gameModeDropDown.initialize)
  UIDropDownMenu_SetWidth(frame.gameModeDropDown, 100, 0)
  UIDropDownMenu_SetButtonWidth(frame.gameModeDropDown, 124)
  frame.gameModeDropDown:updateSelection()
  UIDropDownMenu_JustifyText(frame.gameModeDropDown, "LEFT")
  frame.gameMode = O.gameMode
  
  --------------------
  -- COM stuff
  --------------------
  frame.COMprefix = "KNiGGEL"
  frame.COMchannel = O.COMchannel
  logdebug("COMchannel =", frame.COMchannel)
  frame.COMPlayerName = UnitName("player")
  frame.COMRealmName = GetRealmName("player"):gsub("%s","")
  myPlayerId = frame.COMPlayerName.."-"..frame.COMRealmName
  logdebug("myPlayerId =", myPlayerId)
  frame.COMMsgPrefixes = {
    sendOwnPlayerTable = "PTA";
    sendOwnDiceStatus = "PDS";
    sendBroadcastInvite = "IBA";
    sendPersonalInvite = "IVB";
    sendInviteAccept = "IVA";
    sendInviteDecline = "IVD";
    sendBroadcastNewPlayerJoined = "PNW";
    sendBroadcastPlayersTurn = "STA";
    sendBroadcastAllPlayersFirstTurn = "ALL";
    sendBroadcastPlayerWins = "END";
    sendBroadcastGameBackup = "BKP";
    reqVersionNumber = "VER";
    sendVersionNumber = "VRR";
  };
  
  frame.getNewGameId = function(self)
    return myPlayerId..time()
  end
  frame.sendMyPlayerTable = function(self, gameId, fieldnumber)
    local _, t = getPlayerTableById(myPlayerId)
    if t then
      local msg = self.COMMsgPrefixes.sendOwnPlayerTable
      msg = msg..gameId
      for i = 1, 13 do
        msg = msg.." "..t["field"][i]
      end
      msg = msg.." "..fieldnumber
      --msgcontent = "Playername-Realmname1118722038 <field1 value>[...] <field13 value> <fieldnumber>"
      iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
    end
  end
  frame.sendMyDiceStatus = function(self, gameId)
    local msg = self.COMMsgPrefixes.sendOwnDiceStatus
    msg = msg..gameId
    for i = 1, 5 do
      msg = msg.." "..diceLock[i][1].." "..diceLock[i][2] --dice value, dice lock status
    end
    --msgcontent = "Playername-Realmname1118722038 <dice1 value> <dice1 locked>[...] <dice5 value> <dice5 locked>"
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendBroadcastInvite = function(self, gameId)
    local msg = self.COMMsgPrefixes.sendBroadcastInvite
    msg = msg..gameId
    msg = msg.." "..self.gameMode
    msg = msg.." "..table.concat(myGames[gameId].playerlist, " ")
    --msgcontent = "Playername-Realmname1118722038 Classic Playername1-Realm1 Playername2-Realm2..."
    print(BLUE_PRINT_COLOR.."Kniggel: |rinviting players...")
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendPersonalInvite = function(self, gameId, playerId)
    local msg = self.COMMsgPrefixes.sendPersonalInvite
    msg = msg..gameId
    msg = msg.." "..frame.COMchannel
    logdebug("personal invite", gameId, playerId)
    --msgcontent = "Playername-Realmname1118722038 GUILD"
    print(BLUE_PRINT_COLOR.."Kniggel: |rinviting", playerId)
    iTP:SendAddonMessage(self.COMprefix, msg, "WHISPER", playerId)
  end
  frame.sendInviteAccept = function(self, gameId, playerId)
    local msg = self.COMMsgPrefixes.sendInviteAccept
    msg = msg..gameId
    --msgcontent = "Playername-Realmname1118722038"
    local msgid = iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
    logdebug("sendInviteAccept: msgid =", msgid)
    logdebug(" ", iTPCallback.prefix, iTPCallback.nextmsgid, iTPCallback.messagesOut and #iTPCallback.messagesOut, iTPCallback.messagesIn and #iTPCallback.messagesIn)
  end
  frame.sendInviteDecline = function(self, gameId, playerId, reason, tempChannel)
    local msg = self.COMMsgPrefixes.sendInviteDecline
    msg = msg..gameId
    if reason then
      msg = msg.." "..reason
    end
    --msgcontent = "Playername-Realmname1118722038[ <reason>]"
    iTP:SendAddonMessage(self.COMprefix, msg, tempChannel or self.COMchannel)
  end
  frame.sendBroadcastNewPlayerJoined = function(self, gameId, playerId)
    local msg = self.COMMsgPrefixes.sendBroadcastNewPlayerJoined
    msg = msg..gameId.." "..playerId
    --msgcontent = "Playername-Realmname1118722038 NewPlayername-Realmname"
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendBroadcastPlayersTurn = function(self, gameId, state, ...)
    local msg = self.COMMsgPrefixes.sendBroadcastPlayersTurn
    msg = msg..gameId.." "..state.." "..table.concat({...}, " ")
    --msgcontent = "Playername-Realmname1118722038 1 Playername-Realmname"
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendBroadcastAllPlayersFirstTurn = function(self, gameId, state)
    local msg = self.COMMsgPrefixes.sendBroadcastAllPlayersFirstTurn
    msg = msg..gameId.." "..state
    --msgcontent = "Playername-Realmname1118722038 1"
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendBroadcastPlayerWins = function(self, gameId, state, ...)
    local msg = self.COMMsgPrefixes.sendBroadcastPlayerWins
    msg = msg..gameId.." "..state.." "..table.concat({...}, " ")
    --msgcontent = "Playername-Realmname1118722038 8 Playername-Realmname 123 ..."
    iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
  end
  frame.sendBroadcastGameBackup = function(self, gameId, state, playerIdTurn, dice)
    local msg = self.COMMsgPrefixes.sendBroadcastGameBackup
    --TODO
    --need to send:
    --gameId
    --state
    --playerIdTurn
    --dice lock
    --for each player:
    --  playerId
    --  field
    msg = msg..gameId.." "..state.." "..playerIdTurn
    --msg = msg..table.concat({...}, " ")
    --msgcontent = "Playername-Realmname1118722038 8 Playername-Realmname 123 ..."
    --msgid = iTP:SendAddonMessage(self.COMprefix, msg, self.COMchannel)
    
    --iTP:SendAddonMessage(self.COMprefix, "BKPKniggelplayerFrames getSetFieldFunc "..playerId.." \""..field.."\"", self.COMchannel)
  end
  frame.sendVersion = function(self, playerId)
    local msg = self.COMMsgPrefixes.sendVersionNumber
    msg = msg..(GetAddOnMetadata("Kniggel", "Version") or "?")
    iTP:SendAddonMessage(self.COMprefix, msg, "WHISPER", playerId)
  end
  
  --------------------
  -- Popup frame
  --------------------
  
  popupFrame:SetPoint(O.framePointPopup, O.frameRelativeToPopup, O.frameRelativePointPopup, O.frameOffsetXPopup, O.frameOffsetYPopup)
  popupFrame:SetFrameStrata("DIALOG")
  popupFrame:SetSize(166, 70)
  
  popupFrame.bgtexture = popupFrame:CreateTexture(nil, "OVERLAY")
  popupFrame.bgtexture:SetAllPoints(popupFrame)
  popupFrame.bgtexture:SetColorTexture(0, 0, 0, 1)
  
  popupFrame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
  popupFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    O["framePointPopup"] = point or "CENTER"
    O["frameRelativeToPopup"] = relativeTo or "UIParent"
    O["frameRelativePointPopup"] = relativePoint or "CENTER"
    O["frameOffsetXPopup"] = xOfs
    O["frameOffsetYPopup"] = yOfs
  end);
  
  popupFrame:EnableMouse(true)
  popupFrame:SetMovable(true)
  popupFrame:RegisterForDrag("LeftButton")
  
  local qstring = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qstring:SetPoint("TOP", popupFrame, "TOP", 0, -2)
  qstring:SetTextColor(unpack(WHITE_TEXT_COLOR))
  qstring:SetText("Accept invite from:")
  popupFrame.qstring = qstring
  
  local qstring2 = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qstring2:SetPoint("TOP", qstring, "BOTTOM", 0, -2)
  qstring2:SetTextColor(unpack(LIGHTBLUE_TEXT_COLOR))
  qstring2:SetText("Playername-Realmname")
  popupFrame.qstring2 = qstring2
  
  local qstring3 = popupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qstring3:SetPoint("TOP", qstring2, "BOTTOM", 0, -2)
  qstring3:SetTextColor(unpack(WHITE_TEXT_COLOR))
  qstring3:SetText("Classic (GUILD)")
  popupFrame.qstring3 = qstring3
  
  popupFrame.acceptButton = getNewClickableFontString(popupFrame, 80, 20, "BOTTOMRIGHT", popupFrame, "BOTTOM", -1, 0, 1, 1)
  popupFrame.acceptButton.clickFrame:SetFrameStrata("DIALOG")
  popupFrame.acceptButton:SetText("Accept")
  popupFrame.declineButton = getNewClickableFontString(popupFrame, 80, 20, "BOTTOMLEFT", popupFrame, "BOTTOM", 1, 0, 1, 2)
  popupFrame.declineButton.clickFrame:SetFrameStrata("DIALOG")
  popupFrame.declineButton:SetText("Decline")
  
  popupFrame.frameRef = frame
  
  popupFrame.handleMouseUp = function(self, tag, tag2, button)
    if button == "LeftButton" then
      if tag2 == 1 then --accept
        --change COM channel
        if invitedByChannel and self.frameRef.COMchannel ~= invitedByChannel then
          setCOMChannel(invitedByChannel)
        end
        
        if invitedByGameMode and self.frameRef.gameMode ~= invitedByGameMode then
          setGameMode(invitedByGameMode)
        end
        
        self.frameRef:sendInviteAccept(invitedByGameId, invitedBy)
        self.frameRef:toggleFrame(1)
        
        myGameId = invitedByGameId
        addPlayerToGame(myGameId, myPlayerId)
        buildGameField(myGameId)
        self:Hide()
        
        myState = 0
        updateGameState()
      elseif tag2 == 2 then --decline
        self.frameRef:sendInviteDecline(invitedByGameId, invitedBy, "MANUAL", invitedByChannel)
        self:Hide()
      end
    end
  end
  
  popupFrame:Hide()
  popupFrame.showInvite = function(self, from)
    popupFrame.qstring2:SetText(from)
    popupFrame.qstring3:SetText(format("%s (%s)", invitedByGameMode or "Unknown", invitedByChannel or "Unknown"))
    popupFrame:Show()
  end
end

function frameEvents:PLAYER_ENTERING_WORLD(...)
  frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  
  --------------------
  -- get all options/upgrade option table
  --------------------
  if not KniggelOptions then
    KniggelOptions = DefaultO
  end
  O = KniggelOptions
  
  local oldVersion = O.addonVersion or 0
  O.addonVersion = GetAddOnMetadata("Kniggel", "Version")
  
  O.showFrame = type(O.showFrame) == "number" and O.showFrame or DefaultO.showFrame --type checking because in v0.6 "O.showFrame" would be set to "frame"
  O.invitelist = O.invitelist or DefaultO.invitelist
  O.fixed = O.fixed or DefaultO.fixed
  O.debug = O.debug or DefaultO.debug
  O.shoutGuild = O.shoutGuild or DefaultO.shoutGuild
  O.COMchannel = O.COMchannel or DefaultO.COMchannel
  O.scaleFrame = O.scaleFrame or DefaultO.scaleFrame
  O.gameMode = O.gameMode or DefaultO.gameMode
  O.clickToDiscard = O.clickToDiscard or DefaultO.clickToDiscard
  isdebug = O.debug
  iTP:toggledebug(isdebug, isdebug == 0)
  
  O.framePointPopup = O.framePointPopup or DefaultO.framePointPopup
  O.frameRelativeToPopup = O.frameRelativeToPopup or DefaultO.frameRelativeToPopup
  O.frameRelativePointPopup = O.frameRelativePointPopup or DefaultO.frameRelativePointPopup
  O.frameOffsetXPopup = O.frameOffsetXPopup or DefaultO.frameOffsetXPopup
  O.frameOffsetYPopup = O.frameOffsetYPopup or DefaultO.frameOffsetYPopup
  
  O.stats = O.stats or DefaultO.stats
  if not O.stats["Classic"] then
    --upgrade from v0.14 or earlier
    O.stats = {
      ["Classic"] = O.stats;
      ["DancingDice"] = {};
    };
  end
  
  --------------------
  -- init frame and frame's functions
  --------------------
  initFrame()
  
  scaleFrames(O.scaleFrame)
  
  frame:toggleFrame(O.showFrame)
  if O.fixed == 0 then
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
  end
  
  updateGameState()
  
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("ENCOUNTER_END")
  frame:RegisterEvent("ENCOUNTER_START")
end

function iTPCallback:CHAT_MSG_ADDON(prefix, msg, channel, from, sendermsgid)
  if prefix == frame.COMprefix then
    logdebug(prefix, ";", msg, ";", channel, ";", from, "myState =", myState)
    local MSGPrefix = msg:sub(1, 3)
    if MSGPrefix == frame.COMMsgPrefixes.sendPersonalInvite and channel == "WHISPER" then
      local msgTable = mysplit2(msg:sub(4))
      if myState == -1 then
        print(BLUE_PRINT_COLOR.."Kniggel |rinvite from:", from)
        invitedBy = from
        invitedByGameId = msgTable[1]
        invitedByChannel = msgTable[2]
        addGame(invitedByGameId, invitedBy)
        addPlayerToGame(invitedByGameId, invitedBy)
        popupFrame:showInvite(from)
      else
        --i already joined a game (waiting to start)
        print(BLUE_PRINT_COLOR.."Kniggel |rinvite from:", from, "(auto declined)")
        frame:sendInviteDecline(msgTable[1], from, "INGAME", channel)
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastInvite then
      local msgTable = mysplit2(msg:sub(4))
      for i = 2, #msgTable do
        if msgTable[i] == myPlayerId then
          if myState == -1 then
            print(BLUE_PRINT_COLOR.."Kniggel |rinvite from:", from)
            invitedBy = from
            invitedByGameId = msgTable[1]
            invitedByGameMode = returnValidGameModeOrFalse(msgTable[2]) or "Classic"
            invitedByChannel = channel
            addGame(invitedByGameId, invitedBy)
            addPlayerToGame(invitedByGameId, invitedBy)
            popupFrame:showInvite(from)
          else
            --i already joined a game (waiting to start)
            print(BLUE_PRINT_COLOR.."Kniggel |rinvite from:", from, "(auto declined)")
            frame:sendInviteDecline(msgTable[1], from, "INGAME", channel)
          end
          break
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendInviteAccept and msg:sub(4) == myGameId then
      if myState == 0 and isSelfGameHost(myGameId) then
        if isPlayerInvited(myGameId, from) then
          addPlayerTable(from)
          addPlayerToGameResponded(myGameId, from)
          frame:sendBroadcastNewPlayerJoined(myGameId, from)
          checkAllPlayersPresent(myGameId)
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendInviteDecline then
      if myState == 0 and isSelfGameHost(myGameId) then
        local msgTable = mysplit2(msg:sub(4))
        if msgTable[1] == myGameId then
          if isPlayerInvited(myGameId, from) then
            if msgTable[2] == "MANUAL" then
              print(format(BLUE_PRINT_COLOR.."Kniggel: |r%s declined the game invite.", from))
            elseif msgTable[2] == "INGAME" then
              print(format(BLUE_PRINT_COLOR.."Kniggel: |r%s is already playing.", from))
            else
              print(format(BLUE_PRINT_COLOR.."Kniggel: |r%s declined the game invite.", from))
            end
            removePlayerFromGame(myGameId, from)
            checkAllPlayersPresent(myGameId)
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastNewPlayerJoined then
      if myState == -1 or myState == 0 then
        local gameId, playerId = unpack(mysplit2(msg:sub(4)))
        
        if gameId and playerId then
          addPlayerToGame(gameId, playerId)
          if gameId == myGameId then
            addPlayerTable(playerId)
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastPlayersTurn then
      local gameId, state, playerId = unpack(mysplit2(msg:sub(4)))
      if gameId and state and playerId then
        if gameId == myGameId then
          if frame.gameMode == "Classic" then
            myState = tonumber(state)
            turnPlayerId = playerId
            updateGameState()
          elseif frame.gameMode == "DancingDice" then
            if from == myPlayerId then
              myState = tonumber(state)
              turnPlayerId = myPlayerId
              updateGameState()
            end
            --has this player finished?
            if tonumber(state) == 7 then
              local finishedPlayerCount = 0
              for k, v in pairs(playerFinishedBonus) do
                if v >= 0 then
                  finishedPlayerCount = finishedPlayerCount + 1
                end
              end
              local playerFinished = true
              local _, playerTable = getPlayerTableById(from)
              for i = 1, 13 do
                if playerTable.field[i] == -1 then
                  playerFinished = false
                  break
                end
              end
              if playerFinished and playerFinishedBonus[from] == -1 then
                if finishedPlayerCount == 0 then
                  playerFinishedBonus[from] = 10
                else
                  playerFinishedBonus[from] = 0
                end
                updatePlayerColumnContent(playerTable)
              end
              --have all players finished?
              if isSelfGameHost(myGameId) then
                prepareState(8)
              end
            end
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastAllPlayersFirstTurn then
      local msgTable = mysplit2(msg:sub(4))
      if msgTable[1] and msgTable[2] then
        if msgTable[1] == myGameId then
          if frame.gameMode == "DancingDice" then
            --init finished table
            playerFinishedBonus = {};
            for _, v in ipairs(myGames[myGameId].playerlist) do
              playerFinishedBonus[v] = -1
            end
            
            myState = tonumber(msgTable[2])
            turnPlayerId = myPlayerId --it's always everyone's turn
            updateGameState()
            print(BLUE_PRINT_COLOR.."Kniggel (DancingDice): |rGo!")
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendOwnPlayerTable then
      if isPlayerInvited(myGameId, from) then
        local playerTableFields = mysplit2(msg:sub(4))
        if (not playerTableFields) or (#playerTableFields ~= 15) then --15: gameId,field(13),fieldnumber
          error(frame.COMMsgPrefixes.sendOwnPlayerTable.." corrupted data received")
        end
        if playerTableFields[1] == myGameId then
          local _, v = getPlayerTableById(from)
          for i = 1, 13 do
            v.field[i] = tonumber(playerTableFields[i + 1])
          end
          updatePlayerColumnContent(v, tonumber(playerTableFields[15]))
          if frame.gameMode == "Classic" then
            if isSelfGameHost(myGameId) then
              if myState == 2 then
                prepareState(7)
              elseif myState == 4 then
                prepareState(7)
              elseif myState == 6 then
                prepareState(7)
              end
            end
          elseif frame.gameMode == "DancingDice" then
            --update my state
            if from == myPlayerId then
              if myState == 2 then
                prepareState(7)
              elseif myState == 4 then
                prepareState(7)
              elseif myState == 6 then
                prepareState(7)
              end
            end
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendOwnDiceStatus then
      if isPlayerInvited(myGameId, from) then
        local diceTable = mysplit2(msg:sub(4))
        if (not diceTable) or (#diceTable ~= 11) then
          error(frame.COMMsgPrefixes.sendOwnDiceStatus.." corrupted data received")
        end
        if diceTable[1] == myGameId then
          logdebug("Got the dice from player", from)
          if frame.gameMode == "Classic" then
            for i = 1, 5 do
              diceLock[i][1] = tonumber(diceTable[i * 2]) --value
              diceLock[i][2] = tonumber(diceTable[i * 2 + 1]) --locked status
            end
            frame:updateDiceDisplay()
            if isSelfGameHost(myGameId) then
              if myState == 1 then --player rolled
                prepareState(2)
              elseif myState == 2 then --player locked
                prepareState(3)
              elseif myState == 3 then --player rolled
                prepareState(4)
              elseif myState == 4 then --player locked
                prepareState(5)
              elseif myState == 5 then --player rolled
                prepareState(6)
              end
            end
          elseif frame.gameMode == "DancingDice" then
            --do not change my dice
            if from == myPlayerId then
              frame:updateDiceDisplay()
              if myState == 1 then --player rolled
                prepareState(2)
              elseif myState == 2 then --player locked
                prepareState(3)
              elseif myState == 3 then --player rolled
                prepareState(4)
              elseif myState == 4 then --player locked
                prepareState(5)
              elseif myState == 5 then --player rolled
                prepareState(6)
              end
            end
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastPlayerWins then
      local argTable = mysplit2(msg:sub(4))
      if (argTable[1] and argTable[1] == myGameId) and argTable[2] then
        myState = tonumber(argTable[2])
        winPlayers = {};
        for i = 3, #argTable, 2 do
          table.insert(winPlayers, {argTable[i], argTable[i + 1]})
        end
        updateGameState()
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.sendBroadcastGameBackup then
      --KniggelplayerFrames getSetFieldFunc playerId "field1 ... fieldn"
      --KniggelplayerFrames getSetDiceFunc playerId "d1 ... dn"
      --KniggelglobalFrame getSetDiceFunc "" "d1 ... dn"
      local argTable = mysplit2(msg:sub(4))
      --protect against exposing "_G" table to user input
      local protectedTables = {["_G"]=1};
      if not protectedTables[argTable[1]] then
        --get correct frame
        local framesT = _G[argTable[1]]
        if framesT then
          --get frame's setter func
          local framesTSetF = framesT[argTable[2]]
          if framesTSetF then
            --get playerId transfer func
            local f = framesTSetF(argTable[3])
            if f then
              --transfer data to correct table
              f(argTable[4])
            end
          end
        end
      end
    elseif MSGPrefix == frame.COMMsgPrefixes.reqVersionNumber then
      if from ~= myPlayerId then
        frame:sendVersion(from)
      end
    end
  end
end

function frameEvents:PLAYER_REGEN_ENABLED()
end
function frameEvents:PLAYER_REGEN_DISABLED()
end
function frameEvents:ENCOUNTER_END()
  isInEncounter = false
  if O.showFrame == 1 then
    self:toggleFrame(1)
  end
end
function frameEvents:ENCOUNTER_START()
  isInEncounter = true
  if self:IsShown() then
    self:Hide() --don't override showFrame state
  end
end

frame:SetScript("OnEvent", function(self, event, ...)
  frameEvents[event](self, ...)
end);
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

function iTPCallback:OnSendAddonMessageBegin(msgid, partcount)
  logdebug("OnSendAddonMessageBegin", msgid, partcount)
end
function iTPCallback:OnSendAddonMessageProgress(msgid, partcount, partnumber)
  logdebug("OnSendAddonMessageProgress", msgid, partcount, partnumber)
end
function iTPCallback:OnSendAddonMessageEnd(msgid, partcount)
  logdebug("OnSendAddonMessageEnd", msgid, partcount)
end
function iTPCallback:IDLE()
  logdebug("iTP:IDLE")
end

--split string containing quoted and non quoted arguments
--input pattern: (\S+|".+")?(\s+(\S+|".+"))*
--example input: [[arg1 "arg2part1 arg2part2" arg3]]
--example output: {"arg1", "arg2part1 arg2part2", "arg3"}
function mysplit2(inputstr, separator)
  local i, i1, i2, l, ret, retI = 1, 0, 0, inputstr:len(), {}, 1
  if not separator then
    separator = "%s"
  end
  --remove leading spaces
  i1, i2 = inputstr:find("^"..separator.."+")
  if i1 then
    i = i2 + 1
  end
  
  while i <= l do
    --find end of current arg
    if (inputstr:sub(i, i)) == "\"" then
      --quoted arg, find end quote
      i1, i2 = inputstr:find("\""..separator.."+", i + 1)
      if i1 then
        --spaces after end quote, more args to follow
        ret[retI] = inputstr:sub(i + 1, i1 - 1)
        retI = retI + 1
        i = i2 + 1
      else
        i1, i2 = inputstr:find("\"$", i + 1)
        if i1 then
          --end of msg
          ret[retI] = inputstr:sub(i + 1, i1 - 1)
          return ret
        else
          -- no end quote found, or end quote followed by no-space-charater found, disregard last arg
          return ret
        end
      end
    else
      --not quoted arg, find next space (if any)
      i1, i2 = inputstr:find(separator.."+", i + 1)
      if i1 then
        --spaces after arg, more args to follow
        ret[retI] = inputstr:sub(i, i1 - 1)
        retI = retI + 1
        i = i2 + 1
      else
        --end of msg
        ret[retI] = inputstr:sub(i)
        return ret
      end
    end
  end
  
  return ret
end

SLASH_KNIGGEL1 = "/kniggel"
SlashCmdList["KNIGGEL"] = function(msg, editbox)
  local args = mysplit2(msg or "")
  local arg1 = string.lower(args[1] or "")
  if arg1 == "move" then
    if O.fixed == 0 then
      O.fixed = 1
      frame:SetMovable(false)
      frame:RegisterForDrag("")
    else
      O.fixed = 0
      frame:SetMovable(true)
      frame:RegisterForDrag("LeftButton")
    end
    frame:updateLockButtonTex()
    print(BLUE_PRINT_COLOR.."Kniggel |rmove "..BLUE_PRINT_COLOR.."is now "..(O.fixed == 0 and "|cffaaffaamoving" or "|cffff8888fixed"))
  elseif arg1 == "hide" then
    frame:toggleFrame(0)
  elseif arg1 == "show" then
    frame:toggleFrame(1)
  elseif arg1 == "resetposition" then
    O["framePoint"] = DefaultO["framePoint"]
    O["frameRelativeTo"] = DefaultO["frameRelativeTo"]
    O["frameRelativePoint"] = DefaultO["frameRelativePoint"]
    O["frameOffsetX"] = DefaultO["frameOffsetX"]
    O["frameOffsetY"] = DefaultO["frameOffsetY"]
    
    frame:ClearAllPoints()
    frame:SetPoint(O["framePoint"], O["frameRelativeTo"], O["frameRelativePoint"], O["frameOffsetX"], O["frameOffsetY"])
    
    print(BLUE_PRINT_COLOR.."Kniggel |rposition reset")
  elseif arg1 == "shout" then
    O.shoutGuild = O.shoutGuild == 1 and 0 or 1
    print(BLUE_PRINT_COLOR.."Kniggel |rshout "..BLUE_PRINT_COLOR.."to guild is now "..(O.shoutGuild == 0 and "|cffff8888off" or "|cffaaffaaon"))
  --[[
  elseif arg1 == "testsenddice" then
    frame:sendMyDiceStatus(myGameId)
  elseif arg1 == "testbroadcastinvite" then
    frame:sendBroadcastInvite()
  --]]
  elseif arg1 == "testrepeat" then
    print(iTP:RepeatLastMessage(frame.COMprefix))
  elseif arg1 == "testaddsingleinvite" then
    if myState == 0 and isSelfGameHost(myGameId) then
      table.insert(myGames[myGameId].playerlist, args[2])
      frame:sendPersonalInvite(myGameId, args[2])
    end
  elseif arg1 == "testinviteaccept" then
    frame:sendInviteAccept(invitedByGameId, invitedBy)
    myGameId = invitedByGameId
    buildGameField(myGameId)
  elseif arg1 == "teststartgame" then
    startGame()
  elseif arg1 == "testroll" then
    if isRollAllowed() then
      rollDice()
    end
  elseif arg1 == "testlock" then
    if isLockAllowed() then
      lockDice(tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6]))
    end
  elseif arg1 == "testchoose" then
    if isChooseAllowed() then
      chooseField(tonumber(args[2]))
    end
  elseif arg1 == "channel" then
    if args[2] then
      if isValidChannel(args[2]) then
        setCOMChannel(args[2])
      else
        print(BLUE_PRINT_COLOR.."Kniggel |rvalid COM channels:", table.concat(CHANNEL_LIST, ", "))
      end
    else
      print(BLUE_PRINT_COLOR.."Kniggel |rCOM channel:", frame.COMchannel)
    end
  elseif arg1 == "scale" then
    if args[2] then
      scaleFrames(tonumber(args[2]) or O.scaleFrame)
    else
      scaleFrames(O.scaleFrame)
    end
    print(BLUE_PRINT_COLOR.."Kniggel |rscale:", O.scaleFrame)
  elseif arg1 == "clicktodiscard" then
    O.clickToDiscard = O.clickToDiscard == 0 and 1 or 0
    frame:updateDiceDisplay()
    print(BLUE_PRINT_COLOR.."Kniggel |rclicktodiscard:", O.clickToDiscard)
  elseif arg1 == "debug" then
    if args[2] then
      local level = tonumber(args[2])
      if level == 0 then
        isdebug = 0
        O.debug = isdebug
        iTP:toggledebug(0)
      elseif level == 1 then
        isdebug = 1
        O.debug = isdebug
        iTP:toggledebug(1)
      elseif level == 2 then
        isdebug = 1
        O.debug = isdebug
        iTP:toggledebug(2)
      end
    else
      isdebug = isdebug == 1 and 0 or 1
      O.debug = isdebug
      iTP:toggledebug(isdebug)
    end
    print("isdebug", isdebug)
  elseif arg1 == "debugpending" then
    print("pending:", iTPCallback.prefix, "nextmsgid", iTPCallback.nextmsgid, "out", iTPCallback.messagesOut and #iTPCallback.messagesOut, "in", iTPCallback.messagesIn and #iTPCallback.messagesIn)
    if iTPCallback.messagesOut and #iTPCallback.messagesOut > 0 then
      for i, messageOut in ipairs(iTPCallback.messagesOut) do
        print("msgout", i, messageOut.msgid, messageOut.channel, messageOut.whispertarget, messageOut.partcount, messageOut.nextpartnumber)
        for k, part in pairs(messageOut.parts) do
          print(" ", k, ":", part)
        end
      end
    end
  elseif arg1 == "resetstats" then
    resetStats()
    print(BLUE_PRINT_COLOR.."Kniggel |rstats reset")
  elseif arg1 == "stats" then
    print(BLUE_PRINT_COLOR.."Kniggel |rstats:")
    for gameMode, gameModeTable in pairs(O.stats) do
      print(format("  %s:", gameMode))
      for i, v in pairs(gameModeTable) do
        print(format("    %d players: %d games, %d wins (%d%%), high %d (avg %d)", i, v.games, v.wins, v.wins/v.games*100, v.high, v.totalscore/v.games))
      end
    end
  elseif arg1 == "reset" then
    resetKniggel()
  else
    print(BLUE_PRINT_COLOR.."Kniggel |r"..(GetAddOnMetadata("Kniggel", "Version") or "").." "..BLUE_PRINT_COLOR.."(use |r/kniggel <option> "..BLUE_PRINT_COLOR.."for these options)")
    print("  move "..BLUE_PRINT_COLOR.."toggle moving the frame ("..(O.fixed == 0 and "|cffaaffaamoving" or "|cffff8888fixed")..BLUE_PRINT_COLOR..")")
    print("  resetposition "..BLUE_PRINT_COLOR.."reset the frame's position")
    print("  show/hide "..BLUE_PRINT_COLOR.."show/hide the frame ("..(O.showFrame == 1 and "|cffaaffaashown" or "|cffff8888hidden")..BLUE_PRINT_COLOR..")")
  end
end
