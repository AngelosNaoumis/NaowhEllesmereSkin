local ADDON, NS = ...

NS.ADDON = ADDON
NS.NAOWH = "NaowhForever"
NS.NAOWH_COMBAT = "NaowhForever_Combat"
NS.PREFIX = "|cff0cd29fNaowh EUI Skin|r: "
NS.Modules = NS.Modules or {}

function NS:RegisterModule(name, module)
    assert(type(name) == "string" and type(module) == "table", "invalid module registration")
    assert(not self.Modules[name], "duplicate module: " .. name)
    self.Modules[name] = module
end

function NS:Print(text)
    DEFAULT_CHAT_FRAME:AddMessage(self.PREFIX .. tostring(text))
end

function NS:Report(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end
