local _, NS = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("ADDON_LOADED")
        NS.Runtime:OnPlayerLogin()
        return
    end
    NS.Runtime:OnAddonLoaded(name)
end)
