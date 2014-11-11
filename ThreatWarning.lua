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
	nOptionsVersion = 1,
	bShow = true,
	bShowWarning = true,
	bLock = false,
	nWarningThreshold = 90,
	bHideWhenTanking = true,
	bShowHUD = false,
	bUseMiniMeter = false,
	sBarTexture = "ClientSprites:HoverHealthFull",
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
	tAnchorsHUD = {
		0.5,
		0.5,
		0.5,
		0.5
		},
	tOffsetsHUD = {
		-75,
		-250,
		75,
		-180
		},
	tColors = {
      sSelf = "ff8b0000",
      sOthers = "ff20b2aa",
      sPet = "ff2e8b57"
		}
	}

	
ThreatWarning.tTextures = {
	"BasicSprites:WhiteFill",
	"BasicSprites:LineFill",
	"ClientSprites:HoverHealthFull",
	"CRB_NameplateSprites:sprNp_WhiteBarFill",
	"TargetFrameSprites:TargetCastBarFill",
	"CRB_ActionBarIconSprites:sprAS_ButtonPress",
	"CRB_MinimapSprites:WhiteNoise"
	--"CRB_ActionBarFrameSprites:sprResourceBar_AbsorbProgBar",
	--"CRB_ActionBarFrameSprites:sprResourceBar_AbsorbProgBarWithEdge",
	--"CRB_Basekit:kitIProgBar_Breath_Fill",
	--"CRB_InterfaceMenuList:spr_BaseBar_TEMP_HalfPurpleXP",
	--"CRB_NameplateSprites:sprNp_HealthBarGrey",
	--"CRB_Raid:sprRaid_AbsorbProgBar",
	--"CRB_Raid:sprRaid_HealthProgBar_Orange",
	--"CRB_Raid:sprRaidTear_BigHealthProgBar_Orange",
	--"HologramSprites:HoloProgressBar",
	--"HUD_BottomBar:spr_HUD_VerticalGoo",
	--"HUD_TargetFrameFlipped:spr_TargetFrame_HealthFillYellowFlipped"
	}

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
		self.wndThreatHUD:Show(self.tOptions.bShowHUD)
		self.wndMiniMeter = Apollo.LoadForm(self.xmlDoc, "MiniMeter", nil, self)
		self.wndMiniMeter:Show(self.tOptions.bUseMiniMeter)
		self.wndMiniThreatList = self.wndMiniMeter:FindChild("MiniBarList")
		
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
		
		-- Register a series of variables
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
			self.wndThreatHUD:SetAnchorOffsets(unpack(self.tOptions.tOffsetsHUD))
			self.wndThreatHUD:Show(self.tOptions.bShowHUD)
		else
			self.tOptions = self.tOptionsDefault
			self:ShowHideMeter(self.tOptions.bShow)
		end	
		self.wndMain:SetStyle("Moveable", not self.tOptions.bLock)
		self.wndMain:SetStyle("Sizable", not self.tOptions.bLock)
		self.wndMain:SetStyle("IgnoreMouse", self.tOptions.bLock)
		self.wndMain:FindChild("Background"):Show(not self.tOptions.bLock,true)
		self.wndThreatHUD:FindChild("Flash"):Show(false,true)
		self.wndMain:SetAnchorOffsets(unpack(self.tOptions.tOffsets))
		self.wndThreatHUD:SetAnchorOffsets(unpack(self.tOptions.tOffsetsHUD))
		self.wndThreatHUD:Show(self.tOptions.bShowHUD)
		self.wndThreatHUD:FindChild("Percent"):SetText("")
		self.wndThreatHUD:FindChild("TopThreat"):SetText("")

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
		--self.tCombatTimer:Start()
		--self.tUpdateTimer:Start()
	else
		--self.tCombatTimer:Stop()
		--self.tUpdateTimer:Stop()
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
	
	self.tOptions.tAnchorsHUD = {self.wndThreatHUD:GetAnchorPoints()}
	self.tOptions.tOffsetsHUD = {self.wndThreatHUD:GetAnchorOffsets()}
	
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
	

	-- Fires the Warning Check if there is anyone on the threat list
	if #self.tThreatList > 0 then			
		self:WarnCheck(self.nPtotal, self.tThreatList[1]["nValue"])
	end
	self.nLastCombatEvent = os.time()
end

function ThreatWarning:OnTargetUnitChanged(unitTarget)
	self.wndMain:FindChild("ThreatList"):DestroyChildren()
	self.wndWarn:Show(false)
	self.wndThreatHUD:FindChild("MiniBarList"):DestroyChildren()
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
		self.wndThreatHUD:FindChild("Flash"):Show(true)
		if bShow then Sound.Play(221) end  -- Sound for Warning
	end
end


-- Should we show the warning, and if so, what should it look like
-- Added ThreatHUD push to this path
function ThreatWarning:WarnCheck(myThreat, topThreat)
	local nPercent = 0
	-- Set the %threat of the player in relation to the first person on the threatlist.
	if myThreat / topThreat == 1 and #self.tThreatList > 1 then	
		nPercent = (self.tThreatList[2].nValue / myThreat) * 100 
	else
		nPercent = (myThreat / topThreat) * 100
	end
	
	self:UpdateHUD(nPercent)
	
	if #self.tThreatList > 1 then -- Base Check to only change things when there is more than 1 person in the group

		-- Set Warning Text Color
		if nPercent < 90 then
			self.wndWarn:FindChild("Text"):SetText("***High Threat***")
			self.wndWarn:SetTextColor(ApolloColor.new("yellow"))
		elseif nPercent == 100 then
			self.wndWarn:SetTextColor(ApolloColor.new("ff8b0000"))
			self.wndWarn:FindChild("Text"):SetText("***TOP THREAT***")
		elseif nPercent >= 90 then
			self.wndWarn:FindChild("Text"):SetText("***High Threat***")
			self.wndWarn:SetTextColor(ApolloColor.new("red"))
		end
		
		-- Should we show the warning?
		if myThreat >= ((self.tOptions.nWarningThreshold / 100) * topThreat) and self.tOptions.bShowWarning == true then
			if self.wndWarn ~= nil and not self.wndWarn:IsShown() then
				self:ShowWarn(true)
			end
		else
			if self.wndWarn ~= nil and self.wndWarn:IsShown() then
				self.ShowWarn(false)
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
		self.wndMiniMeter:FindChild("MiniBarList"):DestroyChildren()
		self.nCombatDuration = 0
		self.wndWarn:Show(false)
		self.wndThreatHUD:FindChild("Flash"):Show(false)
		self.wndThreatHUD:FindChild("Percent"):SetText("")
		self.wndThreatHUD:FindChild("TopThreat"):SetText("")
		self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("white"))
		self.wndThreatHUD:FindChild("TopThreat"):SetTextColor(ApolloColor.new("white"))
		self.wndThreatHUD:FindChild("Message"):SetText("")
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

		self.wndThreatList:ArrangeChildrenVert()
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
	-- Do some maths
	local nTPS = tEntry.nValue / self.nCombatDuration
	local nPercent = 0
	local sValue = self:FormatNumber(tEntry.nValue, 2)

	if #wndParent:GetChildren()> 0 then
		local nTop = wndParent:GetChildren()[1]:FindChild("Threat"):GetData()
		nPercent = (tEntry['nValue'] / nTop) * 100
	else
    	nPercent = 100
	end

	
	-- Load the Threat Bar and populate the data
	local wnd = Apollo.LoadForm(self.xmlDoc, "ThreatBar", self.wndThreatList, self)
	wnd:FindChild("Name"):SetText(tEntry['sName'])
	wnd:FindChild("TPS"):SetText(string.format("%.1f", nTPS))
	wnd:FindChild("Threat"):SetText(string.format("%s  %d%s", sValue, nPercent, "%"))
	wnd:FindChild("Threat"):SetData(tEntry['nValue'])
	
	-- Load the Mini Bar and populate the data
	local wndMini = Apollo.LoadForm(self.xmlDoc, "MiniBar", self.wndMiniThreatList, self)
	wndMini:FindChild("Name"):SetText(tEntry['sName'])
	wndMini:FindChild("Percent"):SetText(string.format("%d%s", nPercent, "%"))
	
	-- Set the background color for the ThreatBar
	local sColor = self:GetColorForThreatBar(tEntry)
	local nLeft, nTop, _, nBottom = wnd:FindChild("Background"):GetAnchorPoints()
	wnd:FindChild("Background"):SetAnchorPoints(nLeft, nTop, nPercent / 100, nBottom)
	wnd:FindChild("Background"):SetBGColor(ApolloColor.new(sColor))
	wnd:FindChild("Background"):SetSprite(self.tOptions.sBarTexture)
	
	-- Set the length and background for the MiniThreatBar
	local nLeftMini, nTopMini, _, nBottomMini = wndMini:FindChild("Background"):GetAnchorPoints()
	wndMini:FindChild("Background"):SetAnchorPoints(nLeftMini, nTopMini, nPercent / 100, nBottomMini)
	wndMini:FindChild("Background"):SetBGColor(ApolloColor.new(sColor))
	wndMini:FindChild("Background"):SetSprite(self.tOptions.sBarTexture)
	

end

function ThreatWarning:GetColorForThreatBar(tEntry)
	local sColor = nil
	local sDefault = "blue"

	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer ~= nil and unitPlayer:GetId() == tEntry.nId then
		sColor = self.tOptions.tColors.sSelf or sDefault
	else
		sColor = self.tOptions.tColors.sOthers or sDefault
	end

	-- Use Class Colors as a future option?
  
	if tEntry.bPet then
		sColor = self.tOptions.tColors.sPet or sDefault
	end

	return sColor
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

function ThreatWarning:UpdateHUD(nPercent)
	self.wndThreatHUD:FindChild("Message"):SetText("")
	-- Set the ThreatHUD Percent Display
	if nPercent > 0 then
		self.wndThreatHUD:FindChild("Percent"):SetText(string.format("%d%s", nPercent, "%"))
	else 
		self.wndThreatHUD:FindChild("Percent"):SetText(string.format("%s%s", "Low", "%"))
	end
	
	-- Set other HUD text and colors
	if nPercent < 90 then
		self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("yellow"))
		self.wndThreatHUD:FindChild("Flash"):Show(false)
		self.wndThreatHUD:FindChild("TopThreat"):SetTextColor(ApolloColor.new(self.tOptions.tColors.sOthers))
		self.wndThreatHUD:FindChild("TopThreat"):SetText("Aggro: "..GameLib.GetUnitById(self.tThreatList[1].nId):GetName())
	elseif nPercent == 100 then
		self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("red"))
		self.wndThreatHUD:FindChild("TopThreat"):SetTextColor(ApolloColor.new(self.tOptions.tColors.sSelf))
		if #self.tThreatList > 1 then
			if self.tOptions.bHideWhenTanking and InTankStance() then
				self.wndThreatHUD:FindChild("Flash"):Show(false)
			else
				self.wndThreatHUD:FindChild("Flash"):Show(true)
			end
			self.wndThreatHUD:FindChild("TopThreat"):SetText("Second: "..GameLib.GetUnitById(self.tThreatList[2].nId):GetName())
			self.wndThreatHUD:FindChild("Message"):SetText("TOP THREAT!!!")
		else
			self.wndThreatHUD:FindChild("TopThreat"):SetText("Aggro: "..GameLib.GetUnitById(self.tThreatList[1].nId):GetName())
		end
		--self.wndThreatHUD:FindChild("Message"):SetTextColor(ApolloColor.new("ff8b0000"))

	elseif nPercent >= 90 then
		self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("red"))
		self.wndThreatHUD:FindChild("Flash"):Show(false)
	end
	
	-- Message Checks
	
	-- Show or hide the ThreatHUD based on a FUTURE HUD toggle setting
	if nPercent >= self.tOptions.nWarningThreshold / 100 and self.tOptions.bShowHUD then
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
	self.wndOptions:FindChild("WarningOptions"):FindChild("Tanking"):SetCheck(self.tOptions.bHideWhenTanking)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Self"):FindChild("BGColor"):SetBGColor(self.tOptions.tColors.sSelf)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Others"):FindChild("BGColor"):SetBGColor(self.tOptions.tColors.sOthers)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Pet"):FindChild("BGColor"):SetBGColor(self.tOptions.tColors.sPet)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("ShowMiniMeter"):SetCheck(self.tOptions.bUseMiniMeter)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("Popout"):Show(false)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("BarDemo"):SetBGColor(self.tOptions.tColors.sSelf)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("BarDemo"):SetSprite(self.tOptions.sBarTexture)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("MiniBarDemo"):SetBGColor(self.tOptions.tColors.sSelf)
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("MiniBarDemo"):SetSprite(self.tOptions.sBarTexture)
	
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
	self.nLastCombatAction = os.time() + 8
	self.wndThreatHUD:FindChild("Percent"):SetText("50%")
	self.wndThreatHUD:FindChild("TopThreat"):SetText("Aggro: "..GameLib.GetPlayerUnit():GetName())
	self.wndThreatHUD:FindChild("Percent"):SetTextColor(ApolloColor.new("yellow"))
	self.wndThreatHUD:FindChild("TopThreat"):SetTextColor(ApolloColor.new(self.tOptions.tColors.sOthers))
end

-- Show Color selector
function ThreatWarning:OnColorClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	if wndHandler ~= wndControl or eMouseButton ~= GameLib.CodeEnumInputMouse.Left then return end
	local strFocus = wndControl:GetParent():GetName()
	local tColor = ""
	if strFocus == "Self" then
		tColor = self.tOptions.tColors.sSelf
	elseif strFocus == "Others" then
		tColor = self.tOptions.tColors.sOthers
	elseif strFocus == "Pet" then
		tColor = self.tOptions.tColors.sPet
	end
	GeminiColor:ShowColorPicker(self, "OnGeminiColor", true, tColor, strFocus)
end

-- Process color choice
function ThreatWarning:OnGeminiColor(strColor, strFocus)
--Print(strColor)
--Print(strFocus..": "..strColor)
	if strFocus == "Self" then
		self.tOptions.tColors.sSelf = strColor
	elseif strFocus == "Others" then
		self.tOptions.tColors.sOthers = strColor
	elseif strFocus == "Pet" then
		self.tOptions.tColors.sPet = strColor
	end
	self.wndOptions:Show(false)
	self:OnOptionsOn()
end

function ThreatWarning:OnHideWhenTankingBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bHideWhenTanking = wndControl:IsChecked()
end

function ThreatWarning:OnResetOptionsBtn( wndHandler, wndControl, eMouseButton )
	-- Hide the UI
	self.wndOptions:Show(false)
	self.wndMain:Show(false)
	self.wndThreatHUD:Show(false)
	
	-- Reset Default Settings
	self.tOptions = self.tOptionsDefault
	
	--Reload the UI
	self.wndMain:SetAnchorOffsets(unpack(self.tOptions.tOffsets))
	self.wndMain:SetAnchorPoints(unpack(self.tOptions.tAnchors))
	self.wndThreatHUD:Show(self.tOptions.bShowHUD)
	self.wndMain:SetStyle("Moveable", not self.tOptions.bLock)
	self.wndMain:SetStyle("Sizable", not self.tOptions.bLock)
	self.wndMain:SetStyle("IgnoreMouse", self.tOptions.bLock)
	self.wndMain:FindChild("Background"):Show(not self.tOptions.bLock,true)
	self:ShowHideMeter(self.tOptions.bShow)
	self:OnOptionsOn()
end

function ThreatWarning:OnShowTestBarsBtn( wndHandler, wndControl, eMouseButton )
	local tTestBars = {}
	self.nLastCombatAction = os.time() + 8
	self.nCombatDuration = 60
	tTestBars = {
			{
			nId = 0,
			sName = "Main Tank",
			eClass = GameLib.CodeEnumClass.Stalker,
			bPet = false,
			nValue = 500000
			},
			{
			nId = GameLib.GetPlayerUnit():GetId(),
			sName = GameLib.GetPlayerUnit():GetName(),
			eClass = GameLib.GetPlayerUnit():GetClassId(),
			bPet = false,
			nValue = 475000
			},
			{
			nId = 0,
			sName = "Engineer DPS",
			eClass = GameLib.CodeEnumClass.Esper,
			bPet = false,
			nValue = 425000
			},
			{
			nId = 0,
			sName = "Esper DPS",
			eClass = GameLib.CodeEnumClass.Spellslinger,
			bPet = false,
			nValue = 350000
			},
			{
			nId = 0,
			sName = "Pet of Somebody",
			eClass = nil,
			bPet = true,
			nValue = 300000
			}
		}

	self.wndThreatList:DestroyChildren()
	self.wndMiniThreatList:DestroyChildren()
	
  	for _, tEntry in ipairs(tTestBars) do
    	self:CreateThreatBar(self.wndThreatList, tEntry)
  	end

	self.wndThreatList:ArrangeChildrenVert()
	self.wndMiniThreatList:ArrangeChildrenVert()
end

function ThreatWarning:OnMiniMeterShowBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.bUseMiniMeter = wndControl:IsChecked()
	self.wndMiniMeter:Show(self.tOptions.bUseMiniMeter)
end

function ThreatWarning:OnChangeTextureBtn( wndHandler, wndControl, eMouseButton )
	local wndPopout = self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("Popout")
	local wndList = wndPopout:FindChild("TextureList")
	wndList:DestroyChildren()
	
	if wndPopout:IsShown() then
		wndPopout:Show(false)
	else
		wndPopout:Show(true)
		for i = 1, #self.tTextures do
			local wndTexture = Apollo.LoadForm(self.xmlDoc, "TextureButton", wndList, self)
			wndTexture:FindChild("OthersTexture"):SetSprite(self.tTextures[i])
			wndTexture:FindChild("OthersTexture"):SetBGColor(self.tOptions.tColors.sOthers)
			wndTexture:FindChild("SelfTexture"):SetSprite(self.tTextures[i])
			wndTexture:FindChild("SelfTexture"):SetBGColor(self.tOptions.tColors.sSelf)
			wndTexture:SetData(self.tTextures[i])
		end
		
		wndList:ArrangeChildrenVert()
		
	end
end

---------------------------------------------------------------------------------------------------
-- TextureButton Functions
---------------------------------------------------------------------------------------------------

function ThreatWarning:OnTextureBtn( wndHandler, wndControl, eMouseButton )
	self.tOptions.sBarTexture = wndHandler:GetData()
	self.wndOptions:FindChild("ThreatMeterOptions"):FindChild("Texture"):FindChild("Popout"):Show(false)
	self.wndOptions:Show(false)
	self:OnOptionsOn()
end

-----------------------------------------------------------------------------------------------
-- ThreatWarning Instance
-----------------------------------------------------------------------------------------------
local ThreatWarningInst = ThreatWarning:new()
ThreatWarningInst:Init()

