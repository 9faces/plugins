-- Improved by Valm and The Fedora Team.
return function(Api, Status, Results)
    local MaxScripts = 1500
    local MaxReferences = 500
    local MaxExposedScripts = 100
    local MaxSourceLength = 300000
    local MaxReportSourceLength = 12000

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

    local function Notify(Value, Duration)
        if Api and type(Api.Notify) == "function" then
            pcall(Api.Notify, Api, tostring(Value), Duration or 3)
        end
    end

    local function GetService(ServiceName)
        local Success, Result = pcall(function()
            return Api:GetService(ServiceName)
        end)
        if Success then
            return Result
        end
        return nil
    end

    local function GetLocalPlayer()
        local Success, Result = pcall(function()
            return Api:GetLocalPlayer()
        end)
        if Success then
            return Result
        end
        return nil
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

    local function GetDecompiler()
        local Decompiler = decompile
        if type(Decompiler) == "function" then
            return Decompiler
        end
        if type(getgenv) == "function" then
            local Success, Environment = pcall(getgenv)
            if Success and type(Environment) == "table" and type(Environment.decompile) == "function" then
                return Environment.decompile
            end
        end
        return nil
    end

    local function GetBytecodeGetter()
        local Getter = getscriptbytecode
        if type(Getter) == "function" then
            return Getter
        end
        if type(getgenv) == "function" then
            local Success, Environment = pcall(getgenv)
            if Success and type(Environment) == "table" and type(Environment.getscriptbytecode) == "function" then
                return Environment.getscriptbytecode
            end
        end
        return nil
    end

    local Decompiler = GetDecompiler()
    local BytecodeGetter = GetBytecodeGetter()

    local function GetSource(Object)
        local SourceSuccess, Source = pcall(function()
            return Object.Source
        end)
        if SourceSuccess and type(Source) == "string" and Source ~= "" then
            return Source:sub(1, MaxSourceLength), "Source property"
        end
        if Decompiler then
            local DecompileSuccess, DecompiledSource = pcall(Decompiler, Object)
            if DecompileSuccess and type(DecompiledSource) == "string" and DecompiledSource ~= "" then
                return DecompiledSource:sub(1, MaxSourceLength), "Decompiler"
            end
        end
        return nil, nil
    end

    local function HasBytecode(Object)
        if not BytecodeGetter then
            return false
        end
        local Success, Bytecode = pcall(BytecodeGetter, Object)
        return Success and type(Bytecode) == "string" and #Bytecode > 0
    end

    local function GetDescendants(Object)
        local Success, Descendants = pcall(function()
            return Object:GetDescendants()
        end)
        if Success and type(Descendants) == "table" then
            return Descendants
        end
        return nil
    end

    local function CollectScripts()
        local Scripts = {}
        local Seen = {}
        local function AddObject(Object)
            if Object and not Seen[Object] and IsScript(Object) then
                Seen[Object] = true
                Scripts[#Scripts + 1] = Object
            end
        end
        local GameSuccess, GameDescendants = pcall(function()
            return game:GetDescendants()
        end)
        if GameSuccess and type(GameDescendants) == "table" then
            for _, Object in ipairs(GameDescendants) do
                AddObject(Object)
                if #Scripts >= MaxScripts then
                    break
                end
            end
        end
        if #Scripts < MaxScripts then
            local ChildrenSuccess, Children = pcall(function()
                return game:GetChildren()
            end)
            if ChildrenSuccess and type(Children) == "table" then
                for _, Root in ipairs(Children) do
                    AddObject(Root)
                    local Descendants = GetDescendants(Root)
                    if Descendants then
                        for _, Object in ipairs(Descendants) do
                            AddObject(Object)
                            if #Scripts >= MaxScripts then
                                break
                            end
                        end
                    end
                    if #Scripts >= MaxScripts then
                        break
                    end
                end
            end
        end
        local LocalPlayer = GetLocalPlayer()
        if LocalPlayer and #Scripts < MaxScripts then
            local Descendants = GetDescendants(LocalPlayer)
            if Descendants then
                for _, Object in ipairs(Descendants) do
                    AddObject(Object)
                    if #Scripts >= MaxScripts then
                        break
                    end
                end
            end
        end
        return Scripts
    end

    local function AddReference(Path, Origin, ServiceName, Found)
        Path = tostring(Path or ""):gsub("^%s+", ""):gsub("%s+$", "")
        Path = Path:gsub("^%.+", ""):gsub("%.+$", "")
        if Path == "" or #Found.List >= MaxReferences then
            return
        end
        local FullPath = ServiceName .. "." .. Path
        if Found.Seen[FullPath] then
            return
        end
        Found.Seen[FullPath] = true
        Found.List[#Found.List + 1] = {
            Path = FullPath,
            Service = ServiceName,
            Origin = Origin
        }
    end

    local function ExtractChains(Source, Token, ServiceName, Origin, Found)
        local SearchPosition = 1
        while true do
            local StartPosition, EndPosition = Source:find(Token, SearchPosition, true)
            if not StartPosition then
                break
            end
            local Cursor = EndPosition + 1
            local Parts = {}
            while true do
                local Remaining = Source:sub(Cursor)
                local PropertyStart, PropertyEnd, PropertyName = Remaining:find("^%s*%.%s*([%w_]+)")
                if PropertyName then
                    Parts[#Parts + 1] = PropertyName
                    Cursor = Cursor + PropertyEnd
                else
                    local MethodStart, MethodEnd, ChildName = Remaining:find("^%s*:%s*[%w_]+%s*%(%s*['\"]([^'\"]+)['\"]%s*%)")
                    if ChildName then
                        Parts[#Parts + 1] = ChildName
                        Cursor = Cursor + MethodEnd
                    else
                        local IndexStart, IndexEnd, IndexName = Remaining:find("^%s*%[%s*['\"]([^'\"]+)['\"]%s*%]")
                        if IndexName then
                            Parts[#Parts + 1] = IndexName
                            Cursor = Cursor + IndexEnd
                        else
                            break
                        end
                    end
                end
            end
            if #Parts > 0 then
                AddReference(table.concat(Parts, "."), Origin, ServiceName, Found)
            end
            SearchPosition = EndPosition + 1
        end
    end

    local function ScanSource(Source, Origin, Found)
        for _, ServiceName in ipairs({"ServerScriptService", "ServerStorage"}) do
            ExtractChains(Source, ServiceName, ServiceName, Origin, Found)
            local VariablePattern = "local%s+([%a_][%w_]*)%s*=%s*game%s*:%s*GetService%s*%(%s*['\"]" .. ServiceName .. "['\"]%s*%)"
            for VariableName in Source:gmatch(VariablePattern) do
                ExtractChains(Source, VariableName, ServiceName, Origin, Found)
            end
            local PropertyVariablePattern = "local%s+([%a_][%w_]*)%s*=%s*game%s*%.%s*" .. ServiceName
            for VariableName in Source:gmatch(PropertyVariablePattern) do
                ExtractChains(Source, VariableName, ServiceName, Origin, Found)
            end
            local InlineMethodPattern = ServiceName .. "[^\n]-:%s*[%w_]+%s*%(%s*['\"]([^'\"]+)['\"]%s*%)"
            for ChildName in Source:gmatch(InlineMethodPattern) do
                AddReference(ChildName, Origin, ServiceName, Found)
            end
        end
    end

    local function ScanExposedServerScripts()
        local Exposed = {}
        local ServiceStates = {}
        for _, ServiceName in ipairs({"ServerScriptService", "ServerStorage"}) do
            local Service = GetService(ServiceName)
            local Descendants = Service and GetDescendants(Service) or nil
            ServiceStates[ServiceName] = Service ~= nil and Descendants ~= nil
            if Descendants then
                for _, Object in ipairs(Descendants) do
                    if IsScript(Object) then
                        local Source, SourceMethod = GetSource(Object)
                        Exposed[#Exposed + 1] = {
                            Path = GetPath(Object),
                            Class = tostring(Object.ClassName),
                            Source = Source,
                            SourceMethod = SourceMethod,
                            Service = ServiceName
                        }
                        if #Exposed >= MaxExposedScripts then
                            return Exposed, ServiceStates
                        end
                    end
                end
            end
        end
        return Exposed, ServiceStates
    end

    local function BuildReferenceTree(Found)
        local Roots = {}
        for _, Entry in ipairs(Found.List) do
            local Root = Roots[Entry.Service]
            if not Root then
                Root = {Children = {}, Order = {}}
                Roots[Entry.Service] = Root
            end
            local Current = Root
            for Part in Entry.Path:sub(#Entry.Service + 2):gmatch("[^%.]+") do
                if not Current.Children[Part] then
                    Current.Children[Part] = {Children = {}, Order = {}}
                    Current.Order[#Current.Order + 1] = Part
                end
                Current = Current.Children[Part]
            end
        end
        local Lines = {}
        local function RenderNode(Node, Prefix)
            for Index, Name in ipairs(Node.Order) do
                local Last = Index == #Node.Order
                Lines[#Lines + 1] = Prefix .. (Last and "└─ " or "├─ ") .. Name
                RenderNode(Node.Children[Name], Prefix .. (Last and "   " or "│  "))
            end
        end
        for _, ServiceName in ipairs({"ServerScriptService", "ServerStorage"}) do
            local Root = Roots[ServiceName]
            if Root then
                Lines[#Lines + 1] = ServiceName
                RenderNode(Root, "")
            end
        end
        return Lines
    end

    SetStatus("Scanning all client-visible script instances...")
    SetResults("Scanning accessible script instances and bytecode...\n")

    local Success, ErrorMessage = pcall(function()
        local Lines = {
            "VALM DEX / SCRIPT BYTECODE CONSTRUCTER",
            "Read-only scan. No Instances are created and no script Source is written.",
            ""
        }
        local Found = {
            List = {},
            Seen = {}
        }
        local Scripts = CollectScripts()
        local DecodedCount = 0
        local BytecodeCount = 0
        local ServerSourceCount = 0
        local SourceFailures = 0
        local ServerRoots = {
            ServerScriptService = true,
            ServerStorage = true
        }
        local Exposed, ServiceStates = ScanExposedServerScripts()
        local ExposedByPath = {}
        for _, Entry in ipairs(Exposed) do
            ExposedByPath[Entry.Path] = Entry
            if Entry.Source then
                ServerSourceCount = ServerSourceCount + 1
            end
        end
        for Index, Object in ipairs(Scripts) do
            local Source, SourceMethod = GetSource(Object)
            if Source then
                DecodedCount = DecodedCount + 1
                local Origin = GetPath(Object)
                ScanSource(Source, Origin, Found)
                local IsServerObject = false
                for ServiceName in pairs(ServerRoots) do
                    local Service = GetService(ServiceName)
                    if Service then
                        local IsDescendantSuccess, IsDescendant = pcall(function()
                            return Object:IsDescendantOf(Service)
                        end)
                        if IsDescendantSuccess and IsDescendant then
                            IsServerObject = true
                            break
                        end
                    end
                end
                if IsServerObject and not ExposedByPath[Origin] then
                    ExposedByPath[Origin] = {
                        Path = Origin,
                        Class = tostring(Object.ClassName),
                        Source = Source,
                        SourceMethod = SourceMethod
                    }
                    ServerSourceCount = ServerSourceCount + 1
                end
            else
                SourceFailures = SourceFailures + 1
                if HasBytecode(Object) then
                    BytecodeCount = BytecodeCount + 1
                end
            end
            if Index % 12 == 0 then
                SetStatus("Scanning script " .. tostring(Index) .. " of " .. tostring(#Scripts) .. "...")
                task.wait()
            end
        end
        local ExposedList = {}
        for _, Entry in pairs(ExposedByPath) do
            ExposedList[#ExposedList + 1] = Entry
        end
        table.sort(ExposedList, function(Left, Right)
            return Left.Path < Right.Path
        end)
        if #ExposedList > 0 then
            Lines[#Lines + 1] = "SERVER-SERVICE SCRIPT INSTANCES ACCESSIBLE TO THIS CLIENT"
            for _, Entry in ipairs(ExposedList) do
                Lines[#Lines + 1] = "[" .. Entry.Class .. "] " .. Entry.Path
                if Entry.Source then
                    Lines[#Lines + 1] = "Decoded source via " .. tostring(Entry.SourceMethod or "available source") .. ":"
                    Lines[#Lines + 1] = Entry.Source:sub(1, MaxReportSourceLength)
                    if #Entry.Source > MaxReportSourceLength then
                        Lines[#Lines + 1] = "[Source output shortened to fit the results panel]"
                    end
                else
                    Lines[#Lines + 1] = "Source: unavailable; no source was fabricated."
                end
                Lines[#Lines + 1] = ""
            end
        else
            Lines[#Lines + 1] = "ServerScriptService / ServerStorage: No script instances are accessible to this client."
            Lines[#Lines + 1] = ServiceStates.ServerScriptService and "ServerScriptService was enumerable, but no script descendants were exposed." or "ServerScriptService could not be enumerated in this client context."
            Lines[#Lines + 1] = ServiceStates.ServerStorage and "ServerStorage was enumerable, but no script descendants were exposed." or "ServerStorage could not be enumerated in this client context."
            Lines[#Lines + 1] = ""
        end
        if #Found.List > 0 then
            Lines[#Lines + 1] = "INFERRED SERVER PATH TREE"
            Lines[#Lines + 1] = "Paths below were found in decompiled/readable script text; they are references, not recovered server files."
            for _, TreeLine in ipairs(BuildReferenceTree(Found)) do
                Lines[#Lines + 1] = TreeLine
            end
            Lines[#Lines + 1] = ""
            Lines[#Lines + 1] = "REFERENCE DETAILS"
            for _, Entry in ipairs(Found.List) do
                Lines[#Lines + 1] = Entry.Path
                Lines[#Lines + 1] = "  Referenced by: " .. Entry.Origin
            end
        else
            Lines[#Lines + 1] = "No ServerScriptService or ServerStorage paths were found in the accessible script source."
        end
        Lines[#Lines + 1] = ""
        Lines[#Lines + 1] = "Script instances scanned: " .. tostring(#Scripts)
        Lines[#Lines + 1] = "Sources decoded/read: " .. tostring(DecodedCount)
        Lines[#Lines + 1] = "Raw bytecode only: " .. tostring(BytecodeCount)
        Lines[#Lines + 1] = "Source reads failed: " .. tostring(SourceFailures)
        Lines[#Lines + 1] = "Server-service script instances exposed: " .. tostring(#ExposedList)
        Lines[#Lines + 1] = "Server source texts available: " .. tostring(ServerSourceCount)
        Lines[#Lines + 1] = "Server path references: " .. tostring(#Found.List)
        Lines[#Lines + 1] = ""
        Lines[#Lines + 1] = "The constructed tree is inferred from references. Only exposed script instances with readable or decompiled source are shown as decoded source. Hidden server-only scripts cannot be reconstructed from a client."
        SetResults(table.concat(Lines, "\n"))
        SetStatus("Finished · " .. tostring(#Scripts) .. " scanned · " .. tostring(#ExposedList) .. " server scripts exposed")
        Notify("Script Bytecode Constructer scan finished", 4)
    end)

    if not Success then
        SetStatus("Scan failed")
        SetResults("Script Bytecode Constructer failed: " .. tostring(ErrorMessage))
        Notify("Script Bytecode Constructer scan failed", 4)
        error(ErrorMessage)
    end
end
