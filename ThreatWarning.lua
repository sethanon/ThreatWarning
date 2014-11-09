-----------------------------------------------------------------------------------------------
-- Client Lua Script for ThreatWarning
-- Copyright (c) NCsoft. All rights reserved
-- Author: Sethanon
-----------------------------------------------------------------------------------------------
 
require "Window"
require "Apollo"
require "ApolloTimer"
require "GameLib"
require "GroupLib"

-----------------------------------------------------------------------------------------------
-- ThreatWarning Module Definition
-----------------------------------------------------------------------------------------------
local ThreatWarning = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
local ktTankStances = {
	[47881] = true, -- Engineer provocation mode
	[47022] = true, -- Warrior bulwalk stance
	[46074] = true, -- Stalker suit mode: evasive
}

local function InTankStance()
	local innateSpell = GameLib.GetCurrentClassInnateAbilitySpell()
	return (innateSpell and ktTankStances[innateSpell:GetId()])
end

ThreatWarning.tOptionsDefault = {
	nOptionsVersion = 3,
	bShow = true,
	bShowWarning = true,
	bLock = false,
	nWarningThreshold = 90,
	bHideWhenTanking = true,
	bShowHUD = false,
	tAnchors = {
		0,
		0,
		0,
		0
		},
	tOffsets = {
		0,
		0,
		350,
		250
		},
	tColors = {
      tSelf = { nR = 87, nG = 156, nB = 12, nA = 255 },
      tOthers = { nR = 13, nG = 143, nB = 211, nA = 255 },
      tPet = { nR = 47, nG = 79, nB = 79, nA = 255 },
      [GameLib.CodeEnumClass.Warrior] = { nR = 235, nG = 27, nB = 27, nA = 255 },
      [GameLib.CodeEnumClass.Engineer] = { nR = 225, nG = 140, nB = 32, nA = 255 },
      [GameLib.CodeEnumClass.Esper] = { nR = 13, nG = 143, nB = 211, nA = 255 },
      [GameLib.CodeEnumClass.Medic] = { nR = 233, nG = 192, nB = 36, nA = 255 },
      [GameLib.CodeEnumClass.Spellslinger] = { nR = 87, nG = 156, nB = 12, nA = 255 },
      [GameLib.CodeEnumClass.Stalker] = { nR = 154, nG = 25, nB = 230, nA = 255 }
		}
	}


--ThreatWarning.tOptions = {}

local Utility

-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function ThreatWarning:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    return o
end

function ThreatWarning:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		"ThreatWarning:Utility",
		"GeminiColor"
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies )

end
 
-----------------------------------------------------------------------------------------------
-- ThreatWarning OnLoad
-----------------------------------------------------------------------------------------------
function ThreatWarning:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("ThreatWarning.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	-- Register utility files
	Utility = Apollo.GetPackage("ThreatWarning:Utility").tPackage
	
	-- Pull in GeminiColor for Color Picker forms
	GeminiColor = Apollo.GetPackage("GeminiColor").tPackage
end

-----------------------------------------------------------------------------------------------
-- ThreatWarning OnDocLoaded
-----------------------------------------------------------------------------------------------
function ThreatWarning:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "Threat", nil, self)
		--Set additional Window Variables from document
		self.wndWarn = Apollo.LoadForm(self.xmlDoc, "Warning", nil, self)
		self.wndWarn:Show(false, true)
		self.wndOptions = Apollo.LoadForm(self.xmlDoc, "Options", nil, self)
		self.wndThreatList = self.wndMain:FindChild("ThreatList")
		self.wndOptions:Show(false, true)
		self.wndThreatHUD = Apollo.LoadForm(self.xmlDoc, "ThreatHUD", nil, self)
		self.wndThreatHUD:Show(false,true)
		self.wndMiniThreatList = self.wndThreatHUD:FindChild("MiniBarList")
		
		-- GeminiColor Color Picker
		--self.picker = GeminiColor:CreateColorPicker(self, "ColorPickerCallback", true)
		
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		

		
		-- Threat List
		self.wndThreatList = self.wndMain:FindChild("ThreatList")
	    self.wndMain:Show(false, true)

		-- Slash Commands
		Apollo.RegisterSlashCommand("tw", "OnThreatWarningOn", self)

		-- Create a timer to track combat status. Needed for TPS calculations.
		self.tCombatTimer = ApolloTimer.Create(1, true, "OnCombatTimer", self)
	
		-- Create a timer to update the UI. Not needed all that frequently.
		self.tUpdateTimer = ApolloTimer.Create(0.5, true, "OnUpdateTimer", self)
		
		-- Create Event Handlers
		Apollo.RegisterEventHandler("TargetThreatListUpdated","OnTargetThreatListUpdated",self)
		Apollo.RegisterEventHandler("TargetUnitChanged", "OnTargetUnitChanged", self)
		
		--R egister a series of variables
		self.pTotal = 0
		self.pId = 0 -- GameLib.GetPlayerUnit():GetId()
		self.nValue = 0
		self.nId = 0
		self.oUnit = 0
		self.sName = ""
		self.bPet = 0
		self.tThreatList = {}
		self.tEntry = {}
		self.nTotal = 0
		self.nCombatDuration = 0
		self.nLastCombatAction = 0
		self.tItems = {}
		
		-- Load saved settings
		if self.tOptions ~= nil and self.tOptions.nOptionsVersion == self.tOptionsDefault.nOptionsVersion then
			self:ShowHideMeter(self.tOptions.bShow)
			self.wndMain:SetAnchorOffsets(unpack(self.tOptions.tOffsets))
			self.wndMain:SetAnchorPoints(unpack(self.tOptions.tAnchors))
		else
			self.tOptions = self.tOptionsDefault
			self:ShowHideMeter(self.tOptions.bShow)
			self.wndMain:SetAnchorOffsets(unpack(self.tOptions.tOffsets))
			self.wndMain:SetAnchorPoints(unpack(self.tOptions.tAnchors))
		end	
		self.wndMain:SetStyle("Moveable", not self.tOptions.bLock)
		self.wndMain:SetStyle("Sizable", not self.tOptions.bLock)
		self.wndMain:SetStyle("IgnoreMouse", self.tOptions.bLock)
		self.wndMain:FindChild("Background"):Show(not self.tOptions.bLock,true)
	end
end


-----------------------------------------------------------------------------------------------
-- ThreatWarning Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here
-- Show Window
function ThreatWarning:ShowHideMeter(bShow)
	-- Start timers if we're opening the window, and stop them if it's being closed
	if bShow then
		self.tCombatTimer:Start()
		self.tUpdateTimer:Start()
	else
		self.tCombatTimer:Stop()
		self.tUpdateTimer:Stop()
	end
	self.wndMain:Show(bShow)
end


-- on SlashCommand "/tw"
function ThreatWarning:OnThreatWarningOn(cmd, args)
	if args:lower() == "options" then
		self:OnOptionsOn()
	else
		self:ShowHideMeter(not self.tOptions.bShow)
	end
end

-- Save addon information on clean game exit
function ThreatWarning:OnSave(eLevel)
	if (eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character) then
		return nil
	end
	
	self.tOptions.tAnchors = {self.wndMain:GetAnchorPoints()}
	self.tOptions.tOffsets = {self.wndMain:GetAnchorOffsets()}
	
	local tData = self.tOptions
	
	return tData
end

-- Restore addon settings on load
function ThreatWarning:OnRestore(eLevel, tData)
	if (eLevel ~= GameLib.CodeEnumAddonSaveLevel.Character) then
		return nil
	end
	
	--Set tOptions to the Option values for the addon
	self.tOptions = tData
end



-- Update the Threat List (clear it first) when the target's threat list is updated
function ThreatWarning:OnTargetThreatListUpdated(...)
	self.tThreatList = {}
	self.nPid = GameLib.GetPlayerUnit():GetId()
	self.nPtotal = 0
	self.nTotal = 0
	self.nLastCombatAction = os.time()
	
	
	--Build the Threat List
	for i = 1, select("#",...), 2 do
		local oUnit = select(i,...)
		local nValue = select(i+1,...)
		
		if oUnit ~= nil then
			table.insert(self.tThreatList, {
			nId = oUnit:GetId(),
			sName = oUnit:GetName(),
			eClass = oUnit:GetClassId(),
			bPet = oUnit:GetUnitOwner() ~= nil,
			nValue = nValue
			})
			self.nTotal = self.nTotal + nValue
			if oUnit:GetId() == self.nPid then self.nPtotal = self.nPtotal + nValue end  --Find out if the unit is the player, if so, set the player threat total
		end
	end
	
	-- Sort the Threat List
  	table.sort(self.tThreatList,
		function(oValue1, oValue2)
			return oValue1.nValue > oValue2.nValue
		end
		)

	--Find the lists Top Threat value and send it as well as the player's threat value to the Warning evaluation function
	if self.nPtotal > 0 then			--CHANGE THIS FOR LIVERSION
		self:WarnCheck(self.nPtotal, self.tThreatList[1]["nValue"])
	end
	self.nLastCombatEvent = os.time()
end

function ThreatWarning:OnTargetUnitChanged(unitTarget)
	self.wndMain:FindChild("ThreatList"):DestroyChildren()
	self.wndWarn:Show(false)
end

-----------------------------------------------------------------------------------------------
-- Warning Functions
-----------------------------------------------------------------------------------------------
-- Actually show the warning form
function ThreatWarning:ShowWarn(bShow)
	if self.tOptions.bHideWhenTanking and InTankStance() then
		self.wndWarn:Show(false)
	else
		self.wndWarn:Show(bShow)
		if bShow then Sound.Play(221) end  -- Sound for Warning
	end
end


-- Should we show the warning, and if so, what should it look like
-- Added ThreatHUD Calcs and Changes to this check
function ThreatWarning:WarnCheck(myThreat, topThreat)
	if #self.tThreatList > 0 then	
	local nPercent = 0
	
	if myThreat / topThreat == 1 and #self.tThreatList > 1 then
		nPercent = ((self.tThreatList[2].nValue - myThreat) / myThreat) * 100 
	else
		nPercent = (myThreat / topThreat) * 100
	end
	self.wndThreatHUD:FindChild("Percent"):SetText(string.format("%d%s", nPercent, "%"))

		-- Set Warning Text Color
		if nPercent < 0.9 then
			self.wndWarn:SetTextColor(ApolloColor.new("yellow"))
			self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("yellow"))
		elseif nPercent == 1 then
			self.wndWarn:SetTextColor(ApolloColor.new("magenta"))
					elseif nPercent >= 0.9 then
			self.wndWarn:SetTextColor(ApolloColor.new("red"))
		end
	
		-- Show or hide the ThreatHUD
		if nPercent >= self.tOptions.nWarningThreshold / 100 and self.tOptions.bShowHUD then
			self.wndThreatHUD:FindChild("TopThreat"):SetText("Aggro: "..GameLib.GetUnitById(self.tThreatList[1].nId):GetName())
			self:ShowHUD(true)
			-- Is there something interesting to report in the "Message" window on the ThreatHUD
			
			
		else
			self:ShowHUD(false)
		end
	
		-- Should we show the warning?
		if myThreat >= ((self.tOptions.nWarningThreshold / 100) * topThreat) and self.tOptions.bShowWarning == true then
			if self.wndWarn ~= nil and not self.wndWarn:IsShown() then
				self:ShowWarn(true)
			end
		else
			if self.wndWarn ~= nil and self.wndWarn:IsShown() then
				self.ShowWarn(false)
				self.ShowHUD(false)
			end 
		end
	end
end


-----------------------------------------------------------------------------------------------
-- ThreatList Functions
-----------------------------------------------------------------------------------------------
function ThreatWarning:OnCombatTimer()
	if os.time() >= (self.nLastCombatAction + 5) then
		self.wndMain:FindChild("ThreatList"):DestroyChildren()
		self.wndThreatHUD:FindChild("MiniBarList"):DestroyChildren()
		self.nCombatDuration = 0
		self.wndWarn:Show(false)
		self.wndThreatHUD:Show(false)
	else self.nCombatDuration = self.nCombatDuration + 1
	end
end

-- On Update Timer: Defines the refresh of the UI
function ThreatWarning:OnUpdateTimer()
	if self.wndMain == nil then
		return
	end

	-- Future Option for showing the GUI
	--if not self.tOptions.bShowSolo and #self.tThreatList < 2 then
		--return
	--end
	
	local wndThreatBar = Apollo.LoadForm(self.xmlDoc, "ThreatBar", nil, self)
	local nBars = math.floor(self.wndThreatList:GetHeight() / wndThreatBar:GetHeight())
	wndThreatBar:Destroy()
	

	if self.nTotal >= 0 and #self.tThreatList > 0 then
  		self.wndThreatList:DestroyChildren()
		self.wndMiniThreatList:DestroyChildren()
  		for _, tEntry in ipairs(self.tThreatList) do
    		self:CreateThreatBar(self.wndThreatList, tEntry)
  		end

		self.wndThreatList:ArrangeChildrenVert()--(0, ThreatWarning.SortBars)
		self.wndMiniThreatList:ArrangeChildrenVert()
	end	

	local numChildren = #self.wndThreatList:GetChildren()
	if numChildren > nBars then
  		for i = 1, (numChildren-nBars) do
    		self.wndThreatList:GetChildren()[nBars+1]:Destroy()
  		end
	end
end
 
-- Create the Threat Bars based on the current Threat Table
function ThreatWarning:CreateThreatBar(wndParent, tEntry)
	--Do some maths
	local nTPS = tEntry.nValue / self.nCombatDuration
	local nPercent = 0
	local sValue = self:FormatNumber(tEntry.nValue, 2)

	if #wndParent:GetChildren()> 0 then
		local nTop = wndParent:GetChildren()[1]:FindChild("Threat"):GetData()
		nPercent = (tEntry['nValue'] / nTop) * 100
	else
 		-- This is the topmost bar.
    	nPercent = 100
	end

	
	-- Load the Threat Bar and populate the data
	local wnd = Apollo.LoadForm(self.xmlDoc, "ThreatBar", self.wndThreatList, self)
	wnd:FindChild("Name"):SetText(tEntry['sName'])
	wnd:FindChild("TPS"):SetText(string.format("%.1f", nTPS))
	wnd:FindChild("Threat"):SetText(string.format("%s  %d%s", sValue, nPercent, "%"))
	wnd:FindChild("Threat"):SetData(tEntry['nValue'])
	
	local wndMini = Apollo.LoadForm(self.xmlDoc, "MiniBar", self.wndMiniThreatList, self)
	wndMini:FindChild("Name"):SetText(tEntry['sName'])
	wndMini:FindChild("Percent"):SetText(string.format("%d%s", nPercent, "%"))
	
	
	-- Set the background color for the ThreatBar
	local nR, nG, nB, nA = self:GetColorForThreatBar(tEntry)
	local nLeft, nTop, _, nBottom = wnd:FindChild("Background"):GetAnchorPoints()
	wnd:FindChild("Background"):SetAnchorPoints(nLeft, nTop, nPercent / 100, nBottom)
	wnd:FindChild("Background"):SetBGColor(ApolloColor.new(nR, nG, nB, nA))
	
	-- Set the length and background for the MiniThreatBar
	local nLeftMini, nTopMini, _, nBottomMini = wndMini:FindChild("Background"):GetAnchorPoints()
	wndMini:FindChild("Background"):SetAnchorPoints(nLeftMini, nTopMini, nPercent / 100, nBottomMini)
	wndMini:FindChild("Background"):SetBGColor(ApolloColor.new(nR, nG, nB, nA))
	

end

function ThreatWarning.SortBars(wnd1, wnd2)
	local nValue1 = wnd1:FindChild("Threat"):GetData()
	local nValue2 = wnd2:FindChild("Threat"):GetData()
	return nValue1 >= nValue2
end

function ThreatWarning:GetColorForThreatBar(tEntry)
	local tColor = nil
	local tDefault = { nR = 255, nG = 255, nB = 255, nA = 255 }  -- White

	local oPlayer = GameLib.GetPlayerUnit()
	if oPlayer ~= nil and oPlayer:GetId() == tEntry.nId then
		tColor = self.tOptions.tColors.tSelf or tDefault
	else
		tColor = self.tOptions.tColors.tOthers or tDefault
	end

	--Use Class Colors
	--tColor = self.tOptions.tColors[tEntry.eClass] or tDefault
  
	if tEntry.bPet then
		tColor = self.tOptions.tColors.tPet or tDefault
	end

	return (tColor.nR / 255), (tColor.nG / 255), (tColor.nB  / 255), (tColor.nA / 255)
end

---------------------------------------------------------------------------------------------------
-- ThreatHUD Functions
---------------------------------------------------------------------------------------------------

function ThreatWarning:ShowHUD(bShow)
	if bShow then 
		self.wndThreatHUD:Show(bShow)
	else
		self.wndThreatHUD:Show(bShow)
	end
end

-----------------------------------------------------------------------------------------------
-- Space for Rent
-----------------------------------------------------------------------------------------------
-- BigInt number format utility
function ThreatWarning:FormatNumber(nNumber, nPrecision)
	nPrecision = nPrecision or 0
	if nNumber >= 1000000 then
  		return string.format("%."..nPrecision.."fm", nNumber / 1000000)
	elseif nNumber >= 10000 then
		return string.format("%."..nPrecision.."fk", nNumber / 1000)
	else
		return tostring(nNumber)
	end
end

---------------------------------------------------------------------------------------------------
-- Options Functions
---------------------------------------------------------------------------------------------------

function ThreatWarning:OnOptionsOn()
	-- Set Defaults
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Enable"):SetCheck(self.tOptions.bShow)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Lock"):SetCheck(self.tOptions.bLock)
	self.wndOptions:FindChild("WarningOptions"):FindChild("ShowWarning"):SetCheck(self.tOptions.bShowWarning)
	self.wndOptions:FindChild("WarningOptions"):FindChild("WarningThresholdSlider"):FindChild("Value"):SetText(string.format("%s %s", self.tOptions.nWarningThreshold, "%"))
	self.wndOptions:FindChild("ThreatHudOptions"):FindChild("Enable"):SetCheck(self.tOptions.bShowHUD)
	local tSelf
	for i = 1, #self.tOptions.tColors.tSelf do
		tSelf[i] = self.tOptions.tColors.tSelf[i] / 255
	end
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Self"):FindChild("SelfBGColor"):SetBGColor(tSelf)

	
	if self.wndOptions:IsShown() then self.wndOptions:Show(false) else self.wndOptions:Show(true) end
end

function ThreatWarning:OnOptionsClose( wndHandler, wndControl, eMouseButton )
	self.wndOptions:Show(false)
end

function ThreatWarning:OnEnableBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bShow = wndControl:IsChecked()

	self:ShowHideMeter(self.tOptions.bShow)
end

function ThreatWarning:OnShowWarningBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bWarningShow = wndControl:IsChecked()
end

function ThreatWarning:OnLockBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bLock = wndControl:IsChecked()

	self.wndMain:SetStyle("Moveable", not self.tOptions.bLock)
	self.wndMain:SetStyle("Sizable", not self.tOptions.bLock)
	self.wndMain:SetStyle("IgnoreMouse", self.tOptions.bLock)
	self.wndMain:FindChild("Background"):Show(not self.tOptions.bLock,true)
end

function ThreatWarning:OnWarningThresholdSilder( wndHandler, wndControl, fNewValue, fOldValue )
	self.tOptions.nWarningThreshold = fNewValue
	wndControl:GetParent():FindChild("Value"):SetText(string.format("%s %s", fNewValue, "%"))
end

function ThreatWarning:OnEnableHUDBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bShowHUD = wndControl:IsChecked()
	
	self:ShowHUD(self.tOptions.bShowHUD)
end

function ThreatWarning:OnShowMoveHUDBtn( wndHandler, wndControl, eMouseButton )
	self.wndThreatHUD:Show(true)
end

-- Show Color selector
function ThreatWarning:OnColorClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	if wndHandler ~= wndControl or eMouseButton ~= GameLib.CodeEnumInputMouse.Left then return end
	local strFocus = wndControl:GetParent():GetName()
	local tColor = {}
	if strFocus == "Self" then
		tColor = self.tOptions.tColors.tSelf
	elseif strFocus == "Others" then
		tColor = self.tOptions.tColors.tOthers
	end
	GeminiColor:ShowColorPicker(self, "OnGeminiColor", true, tColor, strFocus)
end

-- Process color choice
function ThreatWarning:OnGeminiColor(strColor, strFocus)
Print(strColor)
Print(strFocus..": "..strColor)
	--self.wndOptions:FindChild(strGroup):FindChild("ThreatMeterOptions"):FindChild(strFocus):FindChild("SelfBGColor"):SetBGColor(strColor)
	if strFocus == "Self" then
		self.tOptions.tColors.tSelf = strColor
	elseif strFocus == "Others" then
		self.tOptions.tColors.tOthers = strColor
	end
end



-----------------------------------------------------------------------------------------------
-- ThreatWarning Instance
-----------------------------------------------------------------------------------------------
local ThreatWarningInst = ThreatWarning:new()
ThreatWarningInst:Init()
