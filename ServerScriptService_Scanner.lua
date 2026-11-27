-- Improved by The Fedora Team. Originally created by Alurion.
return function(Api, Status, Results)
    local function SetStatus(Value)
        if Status and type(Status.SetValue) == "function" then
            pcall(Status.SetValue, Status, "Status: " .. tostring(Value))
        end
    end

    local function SetResults(Value)
        if Results and type(Results.SetValue) == "function" then
            pcall(Results.SetValue, Results, tostring(Value or ""))
        end
    end

    local function GetService(ServiceName)
        local Success, Result = pcall(function()
            return Api:GetService(ServiceName)
        end)
        return Success and Result or nil
    end

    local function GetLocalPlayer()
        local Success, Result = pcall(function()
            return Api:GetLocalPlayer()
        end)
        return Success and Result or nil
    end

    local function GetPath(Object)
        local Success, Result = pcall(function()
            return Object:GetFullName()
        end)
        if Success then
            return tostring(Result)
        end
        return tostring(Object and Object.Name or "Unknown")
    end

    local function IsScript(Object)
        local Success, Result = pcall(function()
            return Object:IsA("Script") or Object:IsA("LocalScript") or Object:IsA("ModuleScript")
        end)
        return Success and Result == true
    end

    local function GetText(Object)
        local Success, Result = pcall(function()
            return Object.Source
        end)
        if Success and type(Result) == "string" and Result ~= "" then
            return Result
        end
        return nil
    end

    local function GetClientSource(Object)
        local Source = GetText(Object)
        if Source then
            return Source
        end
        local Decompiler = decompile
        if type(Decompiler) == "function" then
            local Success, Result = pcall(Decompiler, Object)
            if Success and type(Result) == "string" and Result ~= "" then
                return Result
            end
        end
        return nil
    end

    local function AddPath(Path, Origin, Found, ServiceName)
        Path = tostring(Path or ""):gsub("^%.", ""):gsub("%.$", "")
        if Path == "" or #Found.List >= 200 then
            return
        end
        local FullPath = ServiceName .. "." .. Path
        if Found.Seen[FullPath] then
            return
        end
        Found.Seen[FullPath] = true
        Found.List[#Found.List + 1] = {
            Path = FullPath,
            Origin = Origin
        }
    end

    local function ScanReferences(Found)
        local LocalPlayer = GetLocalPlayer()
        local ReplicatedStorage = GetService("ReplicatedStorage")
        local Roots = {}
        if ReplicatedStorage then
            Roots[#Roots + 1] = ReplicatedStorage
        end
        if LocalPlayer then
            local PlayerScripts
            local PlayerGui
            pcall(function()
                PlayerScripts = LocalPlayer:FindFirstChildOfClass("PlayerScripts") or LocalPlayer:FindFirstChild("PlayerScripts")
                PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:FindFirstChild("PlayerGui")
            end)
            if PlayerScripts then
                Roots[#Roots + 1] = PlayerScripts
            end
            if PlayerGui then
                Roots[#Roots + 1] = PlayerGui
            end
        end
        local Scanned = 0
        local SeenObjects = {}
        for _, Root in ipairs(Roots) do
            local Success, Descendants = pcall(function()
                return Root:GetDescendants()
            end)
            if Success and type(Descendants) == "table" then
                for _, Object in ipairs(Descendants) do
                    if Scanned >= 250 then
                        return Scanned
                    end
                    if IsScript(Object) then
                        local ClassSuccess, IsClientScript = pcall(function()
                            return Object:IsA("LocalScript") or Object:IsA("ModuleScript")
                        end)
                        if ClassSuccess and IsClientScript and not SeenObjects[Object] then
                            SeenObjects[Object] = true
                            Scanned = Scanned + 1
                            local Source = GetClientSource(Object)
                            if Source then
                                Source = Source:sub(1, 250000)
                                local Origin = GetPath(Object)
                                for Path in Source:gmatch("ServerScriptService%.([%w_%.]+)") do
                                    AddPath(Path, Origin, Found, "ServerScriptService")
                                end
                                for Path in Source:gmatch("ServerStorage%.([%w_%.]+)") do
                                    AddPath(Path, Origin, Found, "ServerStorage")
                                end
                                for VarName, Quote, ServiceName in Source:gmatch("local%s+([%w_]+)%s*=%s*game:GetService%((['\"])([%w_]+)%2%)") do
                                    if ServiceName == "ServerScriptService" or ServiceName == "ServerStorage" then
                                        for Path in Source:gmatch(VarName .. "%.([%w_%.]+)") do
                                            AddPath(Path, Origin, Found, ServiceName)
                                        end
                                    end
                                end
                            end
                            if Scanned % 10 == 0 then
                                task.wait()
                            end
                        end
                    end
                end
            end
        end
        return Scanned
    end

    local function ScanExposedServerScripts()
        local ServerScriptService = GetService("ServerScriptService")
        local Exposed = {}
        if not ServerScriptService then
            return Exposed, false
        end
        local Success, Descendants = pcall(function()
            return ServerScriptService:GetDescendants()
        end)
        if not Success or type(Descendants) ~= "table" then
            return Exposed, false
        end
        for Index, Object in ipairs(Descendants) do
            if #Exposed >= 50 then
                break
            end
            if IsScript(Object) then
                local ClassSuccess, ClassName = pcall(function()
                    return Object.ClassName
                end)
                Exposed[#Exposed + 1] = {
                    Path = GetPath(Object),
                    Class = ClassSuccess and tostring(ClassName) or "Script",
                    Source = GetText(Object)
                }
            end
            if Index % 40 == 0 then
                task.wait()
            end
        end
        return Exposed, true
    end

    SetStatus("Scanning client-visible references...")
    SetResults("Scanning...\n")

    local Success, ErrorMessage = pcall(function()
        local Lines = {
            "VALM DEX / SSS VIEWER",
            "Read-only scan. No scripts are created, moved, or rewritten.",
            ""
        }
        local Found = {
            List = {},
            Seen = {}
        }
        local Exposed, ServiceReadable = ScanExposedServerScripts()
        local ScriptCount = ScanReferences(Found)

        if #Exposed > 0 then
            Lines[#Lines + 1] = "SERVER SCRIPTS EXPOSED TO THIS CLIENT"
            for _, Entry in ipairs(Exposed) do
                Lines[#Lines + 1] = "[" .. Entry.Class .. "] " .. Entry.Path
                if Entry.Source then
                    Lines[#Lines + 1] = "Source: available through ordinary Source property access"
                    Lines[#Lines + 1] = Entry.Source:sub(1, 5000)
                else
                    Lines[#Lines + 1] = "Source: Contents Unavailable"
                end
                Lines[#Lines + 1] = ""
            end
        else
            Lines[#Lines + 1] = "ServerScriptService: Contents Unavailable"
            Lines[#Lines + 1] = ServiceReadable and "No server Script instances are replicated to this client." or "ServerScriptService could not be enumerated from this client."
            Lines[#Lines + 1] = ""
        end

        if #Found.List > 0 then
            Lines[#Lines + 1] = "SERVER PATH REFERENCES FOUND IN CLIENT-READABLE SOURCE"
            for _, Entry in ipairs(Found.List) do
                Lines[#Lines + 1] = Entry.Path
                Lines[#Lines + 1] = "  Found in: " .. Entry.Origin
                Lines[#Lines + 1] = "  Source: reference only; original server source is not available here."
            end
        else
            Lines[#Lines + 1] = "No ServerScriptService or ServerStorage path references were found in the scanned client scripts."
        end

        Lines[#Lines + 1] = ""
        Lines[#Lines + 1] = "Client scripts scanned: " .. tostring(ScriptCount)
        Lines[#Lines + 1] = "Server path references: " .. tostring(#Found.List)
        Lines[#Lines + 1] = "Server scripts exposed: " .. tostring(#Exposed)
        Lines[#Lines + 1] = ""
        Lines[#Lines + 1] = "Note: client-side scanning cannot retrieve server-only source. Use an authorized Studio/server-side tool to inspect scripts that are not replicated."
        SetResults(table.concat(Lines, "\n"))
        SetStatus("Finished · " .. tostring(#Exposed) .. " exposed · " .. tostring(#Found.List) .. " references")
        if type(Api.Notify) == "function" then
            Api:Notify("SSS scan finished", 3)
        end
    end)

    if not Success then
        SetStatus("Scan failed")
        SetResults("SSS scan failed: " .. tostring(ErrorMessage))
        if type(Api.Notify) == "function" then
            Api:Notify("SSS scan failed", 4)
        end
        error(ErrorMessage)
    end
end
