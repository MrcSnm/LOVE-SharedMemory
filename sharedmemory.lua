local _INTERNAL_SHARED_MEMORY = {}
require "memoryaccess" --Defines SHARED_MEMORY
--This never should be required inside a thread!
if(not love.system.getOS()) then
    error("SHARED_MEMORY: Don't require sharedmemory inside a Thread, it can cause undefined behavior")
end

local registered = {}
local threads = {}

local function checkDefined(varName)
    if(not _INTERNAL_SHARED_MEMORY[varName]) then
        error("SHARED_MEMORY: "..varName.." is not defined yet")
    end
    return _INTERNAL_SHARED_MEMORY[varName]
end

function SHARED_MEMORY.newVar(varName, varType, content)
    if(_INTERNAL_SHARED_MEMORY[varName]) then
        error("SHARED_MEMORY: "..varName.." already exists, use it as another name")
    end
    local ref = love.sound.newSoundData(2800, 44100, 16, 1)

    if(varType == SHARED_MEMORY.AVAILABLE_TYPES.STRING and type(content) ~= "string") then
        error("SHARED_MEMORY: TypeDefined = string, content received type="..type(content))
    elseif varType == SHARED_MEMORY.AVAILABLE_TYPES.NUMBER and type(content) ~= "number" then
        error("SHARED_MEMORY: TypeDefined = number, content received type="..type(content))
    elseif varType == SHARED_MEMORY.AVAILABLE_TYPES.ARRAY and type(content) ~= "table" then
        error("SHARED_MEMORY: TypeDefined = array, content received type="..type(content))
    elseif varType == SHARED_MEMORY.AVAILABLE_TYPES.MAP and type(content) ~= "table" then
        error("SHARED_MEMORY: TypeDefined = map, content received type="..type(content))
    end
    _INTERNAL_SHARED_MEMORY[varName] = {type = varType, content = content, size = 0, ref = ref}
    SHARED_MEMORY.setValueAtPos(ref, 0, varType)
    SHARED_MEMORY.setVarValue(varName, content)
end

--First byte represents the varType
--Override memory access setVarContent, it will use the internal as it won't be connecting variables
function SHARED_MEMORY.setVarValue(varName, value)
    local mvar = checkDefined(varName)
    mvar.content = value

    if(value ~= nil) then
        SHARED_MEMORY.dataSetter[mvar.type](mvar.ref, value)
        love.event.push("_SHARED_MEMORY_UPDATE_MEM", varName)
    end
end

love.handlers["_SHARED_MEMORY_UPDATE_MEM"] = function(variableUpdated)
    local willUpdate = false
    for i, array in ipairs(registered) do
        for _, v in ipairs(array) do
            if(v == variableUpdated) then
                willUpdate = true
                break
            end
        end
        if(willUpdate) then
            love.thread.getChannel("_SHARED_MEMORY_UPDATE_MEM"..tostring(i)):push(variableUpdated)
            willUpdate = false
        end
    end
end

--Override memory access getVarValue, it will use the internal as it won't be connecting variables
function SHARED_MEMORY.getVarValue(varName) 
    local mvar = checkDefined(varName)
    return SHARED_MEMORY.dataGetter[mvar.type](mvar.ref)
end

--Only debug purposes
function SHARED_MEMORY.printVar(varName)
    local mcontent = SHARED_MEMORY.getVarValue(varName)
    if(type(mcontent) == "string" or type(mcontent) == "number") then
        print(mcontent)
    else
        if(#mcontent ~= 0) then
            for i, v in ipairs(mcontent) do
                print("["..i.."]= "..v)
            end
        else
            for k, v in pairs(mcontent) do
                print("["..k.."]= "..v)
            end
        end
    end
end

--Register the variables to listen when updating
--Usually used called internally by newThread, using it without newThread would need to:
--thread = love.thread.newThread([[...]])
--thread:start(SHARED_MEMORY.registerThread(arg1, arg2... argx, "|", sharedVarName1, sharedVarName2, sharedVarName3, sharedVarNameX....))
--If you just wish to send EVERY Shared variable, instead of listing after "|", switch the "|" symbol for "*"
--Inside thread code, call connectThread(...), after that, memory access will be aware of its ID
--Still inside thread code, call connectVariables(...), it will search for userdata and string pairs to create the association
--Define your onUpdate function after those calls with __MEMORY_ACCESS_ON_UPDATE = function(varUpdated), after that, check the varUpdated(it is the name of the var)
--And call get(varUpdated) for deserializing the updpated userdata
--Inside your thread loop, call SHARED_MEMORY._checkUpdates(), it will be aware of the events to update the thread
--Returns the data passed, the variables passed as the varNames and ID
function SHARED_MEMORY.registerThread(...)
    local tb = nil
    if(type(...) == "table") then
        tb = ...
    else
        tb = {...}
    end
    local registerShare = {}
    local userData = {}
    local shared = {}
    for i, v in ipairs(tb) do
        if _INTERNAL_SHARED_MEMORY[v] then
            table.insert(shared, checkDefined(v).ref)
            table.insert(registerShare, v)
        elseif(v == "*") then
            for name, sharedVariableContent in pairs(_INTERNAL_SHARED_MEMORY) do
                table.insert(shared, sharedVariableContent.ref)
                table.insert(registerShare, name)
            end
        elseif(v ~= "|") then
            table.insert(userData, v)
        end
    end
    --Add as a new event receiver
    table.insert(registered, registerShare)
    for i, v in ipairs(shared) do
        table.insert(userData, v)
    end
    table.insert(userData, "_SHARED_MEMORY_UPDATE_MEM"..tostring(#registered))

    return unpack(userData)
end


--Start code modification section

--Part of code modification, shoul not mess with this function
--Will generate the default update function, which will update the variables whenever the event to do it is fired
local function generateUpdateFunc(varNames)
    local ret = "__MEMORY_ACCESS_ON_UPDATE = function(toUpdate)\n\t"
    for i, v in ipairs(varNames) do
        local get = v.." = SHARED_MEMORY.getVarValue(\""..v..'")\n\t'
        if(i == 1) then
            ret = ret.."if toUpdate == \""..v..'" then\n\t\t'
            ret = ret..get
        else
            ret = ret.."elseif toUpdate == \""..v..'" then\n\t\t'
            ret = ret..get 
        end
        if(i== #varNames) then
            ret = ret.."end\n"
        end
    end
    return ret.."end"
end

--Used for creating syntactic sugar for sharedmemory threads, it will append after every = symbol with
--SHARED_MEMORY.setVarValue for updating shared variables
local function replaceEqualAssigns(threadCode, varNames)
    local nThreadCode = threadCode
    for i, name in ipairs(varNames) do
        for line in string.gmatch(threadCode, name.."%s-=%s-[^\n;]+") do
            nThreadCode = nThreadCode:gsub(line, line.."\nSHARED_MEMORY.setVarValue%(\""..name..'", '..name.."%)\n")
        end
    end
    return nThreadCode
end

local function findAndInsertUpdate(threadCode)
    
end

--Used to get only the varnames declared after the "|" symbol, or get every varname if the "*" is used instead
local function getVarNames(tb)
    local varNames = {}
    local startReading = false

    for i, v in ipairs(tb) do
        if(startReading) then
            table.insert(varNames, v)
        elseif(v == "|") then
            startReading = true
        elseif(v == "*") then
            for name, _ in pairs(_INTERNAL_SHARED_MEMORY) do
                table.insert(varNames, name)
            end
            return varNames
        end
    end
    return varNames
end

--Tb is the table generated by the args parameter
--Used to do the initial set of every shared variable
local function getSharedVariables(tb, quantNames)
    local getVar = ""
    local count = 1
    local isFirst = true
    local iterateInternal = false
    for i, v in ipairs(tb) do
        if(not isFirst and v ~= "|" and v ~= "*") then getVar = getVar..", " else isFirst = false end
        if(i > quantNames) then
            if(v ~= "|") then
                getVar = getVar.."_SHARED_MEM_U"..tostring(count)
                count = count + 1
            end
        elseif(v == "*") then
            iterateInternal = true
            break;
        elseif(v ~= "|") then
            getVar = getVar.."_null"..tostring(i)
        end
    end
    if(iterateInternal) then
        for _, __ in pairs(_INTERNAL_SHARED_MEMORY) do
            getVar = getVar..", _SHARED_MEM_U"..tostring(count)
            count = count + 1
        end
    end
    return getVar.." = ..."
end

--Register the variables to do the update
--Connect variables and the thread to the shared memory
--When the first string equals to | is passed, it starts reading the variables
--Code modification assemble, it will use the arguments passed as a reference to the thread code
--After that, it will be able to access variables by simply writing its name, without calling any get function
local function connect(threadCode, ...)
    local varNames = nil
    local isFirst = true
    local count = 1
    local getVar = ""

    local tb = {...}
    --Get the correct shared memory variables passed to the thread
    varNames = getVarNames(tb)

    --Assign the useful variables as the userdata passed to be updated later
    getVar = getSharedVariables(tb, #varNames)
    

    --Get the variable names to register onto the thread
    --Call function with correct arguments
    local connectVar = "SHARED_MEMORY.connectVariables("
    local variables = ""
    isFirst = true
    count = 1
    local updateVarsDef = generateUpdateFunc(varNames)
    for i, v in ipairs(varNames) do
        if(not isFirst) then
            connectVar = connectVar..", "
        else
            isFirst = false
        end
        connectVar = connectVar.."_SHARED_MEM_U"..tostring(count)..", "
        connectVar = connectVar..'"'..v..'"'
        variables = variables..v.." = SHARED_MEMORY.getVarValue(\""..v..'")'.."\n"
        count = count + 1
    end
    connectVar = connectVar..")"
    --Requires, connections and definitions
    local head = string.format("require(\"love.event\")\nrequire(\"love.sound\")\nrequire \"memoryaccess\"\nSHARED_MEMORY.connectThread(...)\n%s\n%s\n%s\n%s\n", getVar, connectVar, variables, updateVarsDef)

    threadCode = replaceEqualAssigns(threadCode, varNames)
    -- print(head)

    --Get the alternated userdata values to add onto the variables connected

    return head..threadCode
end

--End code modification section

--Cant pass arguments in "start" of the thread  
function SHARED_MEMORY.newThread(fileOrCode, ...)
    if fileOrCode:match(".lua") then
        local nFileOrCode = love.filesystem.read(fileOrCode)
        if(not nFileOrCode) then
            error("SHARED_MEMORY: \""..fileOrCode.."\" not found")
        else
            fileOrCode = nFileOrCode
        end
    end
    fileOrCode = connect(fileOrCode, ...)
    print(fileOrCode)
    local thread = love.thread.newThread(fileOrCode)


    threads[thread] = {SHARED_MEMORY.registerThread(...)}
    return thread
end

--Starts the thread
--By calling this function, you won't need to call registerThread for passing the parameters
function SHARED_MEMORY.start(thread)
    if(threads[thread]) then
        thread:start(unpack(threads[thread]))
    else
        error("SHARED_MEMORY: The thread passed wasn't started by SHARED_MEMORY, call SHARED_MEMORY.newThread instead of love.thread.newThread")
    end
end

--Only accessible in the main thread
--Override metamethods and make shared vars easily accessible
_Shared = setmetatable({},
{
    __index = function(tb, k)
        return SHARED_MEMORY.getVarValue(k)
    end,
    __newindex = function(tb, k, v)
        local tp = type(v)
        if(_INTERNAL_SHARED_MEMORY[k]) then
            SHARED_MEMORY.setVarValue(k, v)
            return v
        end
        
        if(tp == "number") then
            SHARED_MEMORY.newVar(k, SHARED_MEMORY.AVAILABLE_TYPES.NUMBER, v)
        elseif(tp == "string") then
            SHARED_MEMORY.newVar(k, SHARED_MEMORY.AVAILABLE_TYPES.STRING, v)
        elseif(tp == "table") then
            if(#tp ~= 0) then
                SHARED_MEMORY.newVar(k, SHARED_MEMORY.AVAILABLE_TYPES.ARRAY, v)
            else
                SHARED_MEMORY.newVar(k, SHARED_MEMORY.AVAILABLE_TYPES.MAP, v)
            end
        else
            error("SHARED_MEMORY: Type "..tp.." not supported for sharing")
        end
        return v
    end
})