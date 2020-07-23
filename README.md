# LOVE-SharedMemory
Sharing variables between threads

# Why
In Love2D, child thread variables are separated from the main thread, the main way to connect those variables are between
Channels, where you need to push to your thread and pop inside it, while it does the work, sometimes you just don't want
to keep pushing and popping those variables, and it becomes even worser if you have multiple threads doing the same work

# What it does
Create variables that are accessible in any thread, and every update on the shared variable will be available on every
thread

# How it works
It creates a SoundData(because their data are inherently shared by the Love framework) object for your threads, 
that will be pushed in every thread, those SoundData are populated with some ASCII values that are divided from
some number to become in the accepted range of the SoundData, then the library makes available some function to convert
the SoundData to the available type (those are defined on SHARED_MEMORY.AVAILABLE_TYPES), the first bit of the sounddata represents
the type, and the bit which represents that has finished data is the -1 number divided by the magic number.

# How to use it
Download sharedmemory.lua and memoryaccess.lua and put it into the root of your project
There are 2 ways to use it, there is the intrusive way and the non-instrusive way, the intrusive way will take care of boilerplate
code, but in the full way, it works like this:

1. Require sharedmemory
2. Define your variables
3. Create and register your thread
4. Inside your thread code make the requires
5. Connect your thread and your variables
6. Define the data update listener function
7. Call a function to read your variables
8. Get the updated variables

## The first two steps
The first two steps shares the same code to be called, and it is very easy to do it:
```lua
require "sharedmemory"
SHARED_MEMORY.newVar("myVariable", SHARED_MEMORY.AVAILABLE_TYPES.STRING, "This is a shared string variable")
```
This function will create your variable called "myVariable" inside your sharedmemory variables, for data awareness, those
sharedmemory variables types are **Immutable**, with that, you won't change your code silently and break something, if you
need to change its type, just create a new variable.

If you wish to get or set it's content, the functions available are:
```lua
SHARED_MEMORY.setVarValue("myVariable", "This is an updated value")
print(SHARED_MEMORY.getVarValue("myVariable"))
```

There is a shorter way to do that, and the type is inferred by the variable content, really much easier and faster:
### Shorter way
```lua
_Shared.myVariable = "This is an updated value"
print(_Shared.myVariable)
```
Always remember that the shorter way still calls getVarValue, and getting those variables in tight loops can be costly depending on the
size of the shared variable, remember that you can cache your variable with `local myVariable = _Shared.myVariable`

## Intrusive
The instrusive way will take care of the steps 3, 4, 5, 6 and 7

There are 2 ways to send your shared variables to your thread, the one which you specify which variables to use
or the other that sends every shared variable:

### Specifying
For specifying, you will need to use **|** as an escape argument, after that argument, every variable name will be converted to your shared
variable.
The first argument is the thread code that can be defined with lua string literal `[[ ]]` or you can send a file path.
Then, for every argument you define it in newThread, they will be sent first, for you not have to deal with assignment order
```lua
shareThread = SHARED_MEMORY.newThread("sample.lua", 55, "|", "myVariable")
--You can define any number of arguments on the vertical bar left side and right side
-- shareThread = SHARED_MEMORY.newThread("sample.lua", 55, 90, "testing some feature", "|", "myVariable", "myVariable2", "mySharedNumber", "mySharedArray")
```
Specifying is the preferred way when searching for performance, as your thread will not be aware of every variable update, only "myVariable"

### Unspecified
```lua
shareThread = SHARED_MEMORY.newThread("sample.lua", 55, 90, "anything", "*")
SHARED_MEMORY.start(shareThread)
```

### No code for update sharing
Other advantage of the intrusive way is that create a really nice syntactic sugar:
For every shared var it is using, calling the **=** symbol will make your new variable value available to every other thread,
by appending a setVarValue right after assigning it, so, this code:
`myVariable = "This is an updated value"` turns into this 
```lua
myVariable = "This is an updated value"
SHARED_MEMORY.setVarValue("myVariable", myVariable)
```

## Non instrusive way
There is actually no reason for using it unless you want to have full control of its pipeline, the intrusive way just modifies your code and then creates
a thread with it
### Third step
```lua
thread = love.thread.newThread("mythreadcode.lua")
thread:start(SHARED_MEMORY.registerThread(55, "|", "myVariable")) --Same of the last time, but now you call it inside thread:start
```
### Fourth step
```lua
require("love.event")
require("love.sound")
require "memoryaccess"
```
### Fifth step
```lua
SHARED_MEMORY.connectThread(...)
sentVar1, sentVar2, sharedMem1, sharedMem2 = ...
SHARED_MEMORY.connectVariables(sharedMem1, "myvariableDefined1", sharedMem2, "myvariableDefined2")
```
### Sixth step
```lua
__MEMORY_ACCESS_ON_UPDATE = function(toUpdate)
    if toUpdate == "myvariableDefined1" then
        myvariableDefined1 = SHARED_MEMORY.getVarValue("myvariableDefined1")
    elseif toUpdate == "myvariableDefined2" then
        myvariableDefined2 = SHARED_MEMORY.getVarValue("myvariableDefined2")
    end
end
```
### Seventh step
```lua
myvariableDefined1 = SHARED_MEMORY.getVarValue("myvariableDefined1")
myvariableDefined2 = SHARED_MEMORY.getVarValue("myvariableDefined2")
```

# **The eigthth step**
This step is unfortunately required for both ways, as I would need to search for a thread loop, it is much work for something
really simple to do, so, before any variable access, just call the simple function
```lua
SHARED_MEMORY._checkUpdates()
```

## Guaranteeing a great performance
This is a much easier way to define, although it is better for debugging purposes or if you don't need much extra performance
The performance is measured by how many times you modifiy a shared variable value, how many times you **getVarValue** your variable
and how many threads are listening to the same variable(as every thread will need to call **getVarValue** when any thread set its value)
Always remember that **getVarValue and setVarValue are data unserialization/serialization**

## Some gotchas
This code have some limitations
- It only accepts numbers, strings, arrays and maps
- It doesn't supports any kind of nested table(array nor map)
- It has a variable size limitation, currently is 2800 character values(To keep sample sizes small)
- You can change its size at your own need(Just search for SHARED_MEMORY.newVar), but changing its size will change for every variable, and i recommend not changing it at runtime


# Some sample code

main.lua:
```lua
require "sharedmemory"


function love.load()
    SHARED_MEMORY.newVar("maptest", SHARED_MEMORY.AVAILABLE_TYPES.MAP, 
    {
        ["hello"] = "oi",
        ["there"] = "hipreme"
    })
    globalCount = 1
    --Short way to mean the same thing above
    _Shared.numtest = globalCount
    _Shared.strtest = "String defined inside main"
    _Shared.arraytest = {5, 3, 10, 90}
    local shareThread = SHARED_MEMORY.newThread("sample.lua", 55, "*")
    SHARED_MEMORY.start(shareThread)
end

function love.keypressed(k)
    if(k == "k") then
        SHARED_MEMORY.setVarValue("maptest", {["hello"] = "god!"})
    elseif k == "j" then
        _Shared.maptest =  {["there"] = "nohipreme"}
    elseif k == "h" then
        print(SHARED_MEMORY.getVarValue("strtest"))
    elseif k == "g" then
        globalCount = globalCount + 1
        _Shared.numtest = globalCount
    end
end

function love.update(dt)
    
end
```
sample.lua:
```lua
require("love.timer")
maptest = {beware = "insider"}
numtest = 100
strtest = "my string was modified inside sample thread"
arraytest = {"hello", 525, "dear", "friend"}
while true do
    love.timer.sleep(1)
    print(numtest)
    SHARED_MEMORY._checkUpdates()
end
```
