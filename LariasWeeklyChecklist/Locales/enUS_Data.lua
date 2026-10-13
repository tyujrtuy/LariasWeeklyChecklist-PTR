--[[
English (enUS) checklist data for Larias' Weekly Checklist

NOTE: This is the canonical enUS dataset; other locales must keep IDs identical
so completion tracking stays consistent across locales.
]]

-- @sheet-version: 15

local LOCALE = "enUS"

local LOCALE_REGISTRY_KEY = "LARIASWEEKLYCHECKLIST_LOCALE_REGISTRY"

local reg = _G[LOCALE_REGISTRY_KEY]
if type(reg) ~= "table" then
    reg = {}
    _G[LOCALE_REGISTRY_KEY] = reg
end
if type(reg.data) ~= "table" then reg.data = {} end
reg.sheet_version = "15"

local DATASET = {

    {
        id = "4a875b42",
        title = "Week 9 - Oct 13",
        items = {
            { id = "d9564251", text = "If your guild isn't going to spend time doing Mythic Kithix, you can instead choose to bonus roll heroic 3 times over the next 3 weeks to get all your BIS items without stepping into Mythic. These items will be 1/6m but this doesn't matter as Crests uncap next week." },
            { id = "7c57fe59", text = "If you will be doing Mythic Kithix, be aware that bonus roll loot tables are different for different difficulties - you CAN bonus roll heroic and then get the same item bonus rolling mythic." },
            { id = "b8dc5e31", text = "Complete the new delve labyrinth for a guaranteed mythic item level piece in the slot of your choice." },
        },
    },
    {
        id = "eed82be5",
        title = "Week 10 - Oct 20",
        items = {
            { id = "9999766a", text = "Crests uncap - go nuts!" },
            { id = "7eee8c3c", text = "Venomstones can be obtained. You need 10 total per item, so you need to do 50 keys if you want to upgrade 2 weapons, 2 trinkets, and your neck." },
        },
    },
}

reg.data[LOCALE] = DATASET
