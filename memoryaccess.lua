SHARED_MEMORY = {}
SHARED_MEMORY.AVAILABLE_TYPES =
{
    NUMBER = 1,
    ARRAY = 2,
    STRING = 3,
    MAP = 4
}
--Number used to divide and multiply the value for converting it between character and number
local maxByteSize = 512
--Used only inside threads, it will be overridden inside sharedmemory
--It will store SoundData's
local registeredVars = {}
--This function is defined once per thread
__MEMORY_ACCESS_ON_UPDATE = function (varUpdated)
    -- update(registeredVars[varUpdated])
end

local mId = nil

local function checkRegistered(varName)
    if(not registeredVars[varName]) then
        error("SHARED_MEMORY(MEMORY_ACCESS): "..varName.." is not registered")
    end
    return registeredVars[varName]
end

local function clampDecimal(val, numDecimalPlaces)
    local mult = 10^numDecimalPlaces
    return math.floor(val*mult + 0.5)/mult
end
local function round(num)
    if(num > 0) then return math.floor(num+.5)
    else return math.ceil(num-.5)end
end

--Receives the shared variable and set its value, storing in its sample
--Globally available for setting its type inside sharedmemory
function SHARED_MEMORY.setValueAtPos(sharedVar, pos, value)
    local mByte = clampDecimal(value / maxByteSize, 7)
    sharedVar:setSample(pos, mByte)
end
function SHARED_MEMORY.getValueAtPos(sharedVar, pos)
    return round(sharedVar:getSample(pos) * maxByteSize)
end

local setValueAtPos = SHARED_MEMORY.setValueAtPos
local getValueAtPos = SHARED_MEMORY.getValueAtPos
SHARED_MEMORY.dataSetter =
{
    --Terminated at -1
    [SHARED_MEMORY.AVAILABLE_TYPES.ARRAY] = function (c, value)
        setValueAtPos(c, 1, #value)
        value = table.concat(value, "&").."&"
        for i = 1, #value do
            setValueAtPos(c, i, value:byte(i))
        end
        setValueAtPos(c, #value+1, -1)
    end,
    --Terminated at -1
    [SHARED_MEMORY.AVAILABLE_TYPES.STRING] = function (c, value)
        for i = 1, #value do
            setValueAtPos(c, i, value:byte(i))
        end
        setValueAtPos(c, #value+1, -1)
    end,
    --Represented as a string
    [SHARED_MEMORY.AVAILABLE_TYPES.NUMBER] = function (c, value)
        value = tostring(value)
        for i = 1, #value do
            setValueAtPos(c, i, value:byte(i))
        end
        setValueAtPos(c, #value+1, -1)
    end,
    --Defined as array with: key&value&key&value
    --Terminated at -1
    [SHARED_MEMORY.AVAILABLE_TYPES.MAP] = function (c, value)

        local count = 1
        for k, v in pairs(value) do
            for i = 1, #k do
                setValueAtPos(c, count, k:byte(i))
                count = count + 1
            end
            setValueAtPos(c, count, string.byte("&"))
            count = count+1
            for i = 1, #v do
                setValueAtPos(c, count, v:byte(i))
                count = count + 1
            end
            setValueAtPos(c, count, string.byte("&"))
            count = count+1
        end
        setValueAtPos(c, count+1, -1)
    end
}

SHARED_MEMORY.dataGetter = 
{
    --Second byte represents its size
    --& is reserved! Not gonna update myself
    [SHARED_MEMORY.AVAILABLE_TYPES.ARRAY] = function (c)
        local ret = {}
        local nValue = ""
        local value = getValueAtPos(c, 1)
        local char
        local i = 1
        while(value ~= -1) do
            char = string.char(value)
            local numValue = tonumber(nValue)
            if(char == "&") then
                table.insert(ret, (numValue and numValue or nValue))
                nValue = ""
            else
                nValue = nValue..char
            end
            i = i+1
            value = getValueAtPos(c, i)
        end
        return ret
    end,
    --Terminated at -1
    --Value is a string
    [SHARED_MEMORY.AVAILABLE_TYPES.STRING] = function (c)
        local ret = ""
        local i = 1
        local value = getValueAtPos(c, 1)
        while(value ~= -1) do
            ret = ret..string.char(value)
            i = i + 1
            value = getValueAtPos(c, i)
        end
        return ret
    end,
    --Terminated at -1
    [SHARED_MEMORY.AVAILABLE_TYPES.NUMBER] = function (c)
        local ret = ""
        local i = 1
        local value = getValueAtPos(c, 1)
        --    While in range of 0 to 9      or       "-"   or          "."
        while((value >= 48 and value <= 57) or value == 45 or value == 46)do
            ret = ret..string.char(value)
            i = i + 1
            value = getValueAtPos(c, i)
        end
        return tonumber(ret)
    end,
    --Defined as array with: key, value, key, value
    [SHARED_MEMORY.AVAILABLE_TYPES.MAP] = function (c)
        local ret = {}
        local keyValue = ""
        local isKey = true
        local nValue = ""
        local value = getValueAtPos(c, 1)
        local char
        local i = 1
        while(value ~= -1) do
            char = string.char(value)
            if(char == "&") then
                local numValue = tonumber(nValue)
                if(isKey) then keyValue = (numValue and numValue or nValue)
                else ret[keyValue] = (numValue and numValue or nValue) keyValue = "" end
                isKey = not isKey
                nValue = ""
            else
                nValue = nValue..char
            end
            i = i+1
            value = getValueAtPos(c, i)
        end
        return ret
    end 
}

--Overridden inside sharedmemory for having a main controller
function SHARED_MEMORY.setVarValue(varName, value)
    local mvar = checkRegistered(varName)
    --Notify the set event
    local varType = getValueAtPos(mvar, 0)
    if(value ~= nil) then
        SHARED_MEMORY.dataSetter[varType](mvar, value)
        love.event.push("_SHARED_MEMORY_UPDATE_MEM", varName)
    end
end

--In the 0 bit(sample) is stored its type
function SHARED_MEMORY.getVarValue(varName) 
    local mvar = checkRegistered(varName)
    local varType = getValueAtPos(mvar, 0)
    return SHARED_MEMORY.dataGetter[varType](mvar)
end


--Can only be called once
--Gets the ID from the params argument, requires SHARED_MEMORY.registerThread to be called
function SHARED_MEMORY.connectThread(...)
    if(mId ~= nil) then error("You must not call connectThread twice")end
    for i, v in ipairs({...}) do
        if(type(v) == "string" and string.match(v, "_SHARED_MEMORY_UPDATE_MEM")) then
            print("Connected")
            mId = v
            return
        end
    end
end

--May be called any amount of times, but for easier usability, call it just once
--Use the userdata as a trigger to start connecting variables
--Called only inside the thread
--Creates an association between the userdata and string
function SHARED_MEMORY.connectVariables(...)
    local isNextName = false
    local ref = nil
    for i, v in ipairs({...}) do
        if(isNextName) then
            if(type(v) ~= "string") then
                error("You must define connectVariables as userdata, string, userdata, string...")
            end
            isNextName = false
            registeredVars[v] = ref
            ref = nil
        elseif (type(v) == "userdata") then
            isNextName = true
            ref = v
        end
    end
end


local cache = {}
function SHARED_MEMORY._checkUpdates()
    local toUpdate = love.thread.getChannel(mId):pop()
    while(toUpdate) do
        cache[toUpdate] = true
        toUpdate = love.thread.getChannel(mId):pop()
    end
    for name, willUpdate in pairs(cache) do
        if(willUpdate) then
            __MEMORY_ACCESS_ON_UPDATE(name)
            cache[name] = false
        end
    end
end