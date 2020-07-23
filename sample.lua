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