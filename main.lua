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
    
    --For actually using it in your thread, many steps are required as shown in the comment below, if you wish to use it in the "low-level"(by using
    --love.thread.newThread instead SHARED_MEMORY.newThread) way, you will need to mimic the code below with your defined variables, SHARED_MEMORY.newThread
    --already automatizes this process for you to focus only on your code, it will auto generate the update function and auto transform your sharedvar assignments
    --to SHARED_MEMORY.setVarValue() call,
    -- mthread = love.thread.newThread([[
    --     require("love.event")
    --     require("love.sound")
    --     require "memoryaccess"
    --     SHARED_MEMORY.connectThread(...)
    --     local sentVar1, sentVar2, sharedMem1, sharedMem2, sharedMem... = ...
    --     SHARED_MEMORY.connectVariables(sharedMem1, "myvariableDefined1", sharedMem2, "myvariableDefined2", sharedMem..., "myvariableDefined..."")
    --     --Now, how to gey your shared var value:
    --     myvariableDefined1 = SHARED_MEMORY.getVarValue("myvariableDefined1")
    --     --For actually getting to know what to do when the var update happnes, do:
    --     __MEMORY_ACCESS_ON_UPDATE = function(toUpdate)
    --         if toUpdate == "myvariableDefined1" then
    --             myvariableDefined1 = SHARED_MEMORY.getVarValue("myvariableDefined1")
    --         elseif toUpdate == "myvariableDefined2" then
    --             myvariableDefined2 = SHARED_MEMORY.getVarValue("myvariableDefined2")
    --         end
    --      end

    --     --If you wish to change the shared variable value:
    --     aNumber = 50
    --     SHARED_MEMORY.setVarValue("myvariableDefined1", aNumber) --this will share the changes
    --     aString = "a test string"
    --     SHARED_MEMORY.setVarValue("myvariableDefined2", aString)
    --     while(true) do
    --         SHARED_MEMORY._checkUpdates()
    --     end
    -- ]])
    -- mthread:start(SHARED_MEMORY.registerThread("teste"))

    --It is possible to specify which sharedvars to send, or you can just send every with "*", but beware that using always the * operator can be a bottleneck
    --if you have many sharedvars, they are updated on demand, so, if you have mynum defined for a variable and it changes, and you haven't sent it to your
    --shared thread, then, it won't listen to those updates and won't cause any cycle to be consumed when this var is updated
    --If you wish to specify only which vars instead of every, just pass a "|" symbol and then pass every variable name you need
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