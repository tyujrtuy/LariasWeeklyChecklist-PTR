--[[
English (enUS) checklist data for Larias' Weekly Checklist

NOTE: This is the canonical enUS dataset; other locales must keep IDs identical
so completion tracking stays consistent across locales.
]]

-- @sheet-version: 14

local LOCALE = "enUS"

local LOCALE_REGISTRY_KEY = "LARIASWEEKLYCHECKLIST_LOCALE_REGISTRY"

local reg = _G[LOCALE_REGISTRY_KEY]
if type(reg) ~= "table" then
    reg = {}
    _G[LOCALE_REGISTRY_KEY] = reg
end
if type(reg.data) ~= "table" then reg.data = {} end
reg.sheet_version = "14"

local DATASET = {

    {
        id = "a932c06c",
        title = "Week 1 - Aug 18 - Season Starts",
        items = {
            { id = "ed3ed033", text = "Take a tier piece if your guild doesn't do splits. Take a socket if your guild does splits. WARNING: THIS MAY GIVE YOU A KEY - MAKE SURE TO GET A +10 KEY BEFORE TAKING AN ITEM." },
            { id = "1fb55f58", text = "You can freely spend any champion and below crests at any time." },
            { id = "1ad52558", text = "Do LFR for tier pieces." },
            { id = "bada8c98", text = "Start the Season 2 Bonus roll questline in the Voidstorm" },
            { id = "479fea56", text = "Complete 2x weekly spark quests for a total of 4" },
            { id = "e20bf519", text = "Complete ?? Azta'rec for 60 uncapped hero Crests and 30 uncapped Myth Crests. Confirmed for S2. Recommend Snakesays addon to make it really easy." },
            { id = "d786018f", text = "If you have a premade group, you can get a +10 key for everyone. You can have a team of 4 alts + 1 main, get a key from the lady you downgrade your key at, level it up to +11 then run it on mains and everyone gets a +10. There is a better way, though, that worked in S1: fill your inventory completely with items (blacksmith hammers are a good choice). Get one person to get a +2 and push it to an 11 without anyone else looting the chest. The loot will be mailed to you. Once you get to a +11, unclog your inventory and then loot the +11." },
            { id = "1798a832", text = "Complete 1 Tier 11 delve with a map for a quick hero item and the season 2 Cracked Keystone quest for 20 uncapped Hero and Myth crests. Azta'rec has a high chance of dropping a map but if he doesn't drop you one, an easy source of the \"boss summoning\" for delves is doing the weekly nightmare prey quest. It's guaranteed to give you one. If you have friends/guildies with extra time, they can do it, then you summon the boss in a 5-man delve and everyone loots a map. WARNING: This gives a keystone for m+. If you plan on using the \"fill your inventory\" trick to get a higher tier key, do that before doing this." },
            { id = "c20c805a", text = "Do not pug the new \"world/lair boss\" on normal+ difficulties. You'll be doing this with your guild." },
            { id = "0cbc66bc", text = "Farm +10's for 3/6h 311 item level pieces, vault slots and all your various Crests." },
            { id = "c68ca026", text = "Full clear Normal/Heroic." },
            { id = "57c283c4", text = "Before entering Mythic, upgrade three 3/6 hero track items to 6/6 - the items you pick will depend on whether you plan on bonus rolling an item in that slot. You should not upgrade slots that you are intending to bonus roll mythic items in. This should take 180/180 hero crests." },
            { id = "69319517", text = "If crafting a 2h weapon, you can go ahead and craft this at 5/6M for 80 Myth crests. However, this is a big commitment and Blizzard has announced a tuning patch for August 25th. If you might swap specs (boomie -> feral, fdk -> unholy etc) that require a different weapon type, you should hold off." },
            { id = "7bad141c", text = "If not crafting a 2h weapon, craft an item at 5/6M for 80 Myth crests." },
            { id = "f7ab089c", text = "As always, if you get a mythic item before the guide expects you to, upgrade it if you have the hero crests to save the myth crests" },
            { id = "c84b4730", text = "If being a degen CHECK GUIDE, get it geared and crest capped.  this no longer works, downgraded crests count against cap" },
            { id = "d3caf44e", text = "Total Crests spent so far: 180/180 Heroic | 80/150 Mythic" },
        },
    },
    {
        id = "4c73f265",
        title = "Week 2 - Aug 25",
        items = {
            { id = "2cb1a5fb", text = "IMPORTANT: Check Guide for links to resources for where to bonus roll." },
            { id = "d800e84b", text = "Open your vault - Check Guide for what to take." },
            { id = "82c130d3", text = "Do LFR for tier pieces if you still need tier." },
            { id = "5a34820f", text = "Do the timewalking quest for a chance at tier" },
            { id = "70348198", text = "Complete weekly spark quest" },
            { id = "a032b050", text = "Farm +12's if you need to for crests. You don't have to spam M+ this season if you can get your crests from other sources." },
            { id = "663d01ea", text = "Heroic: Upgrade a 3/6h item to 6/6h for 60 Heroic Crests. Use 40 Hero crests for two myth 1/6 items that you need to upgrade to 2/6 first." },
            { id = "4e1c826e", text = "Mythic(bonus rolled a Heroic boss): Craft your second item at 5/6M for 80 Myth crests. Upgrade your bonus roll item to 6/6M using 80 Myth Crests. Don't forget to upgrade a heroic item to 6/6 heroic for 20 Heroic Crests in that slot first." },
            { id = "11e358a5", text = "Mythic(bonus rolled mythic or took 6/6 item from vault): Craft your second item at 5/6M for 80 Myth crests. If you get a drop item, upgrade it to 6/6M using 80 Myth crests." },
            { id = "c84b4730", text = "If being a degen CHECK GUIDE, get it geared and crest capped.  this no longer works, downgraded crests count against cap" },
            { id = "9e721538", text = "Total Crests spent so far: 280/280 Heroic | 240/250 Mythic" },
        },
    },
    {
        id = "89ce7292",
        title = "Week 3 - Sep 1 - Current week",
        items = {
            { id = "d800e84b", text = "Open your vault - Check Guide for what to take." },
            { id = "82c130d3", text = "Do LFR for tier pieces if you still need tier." },
            { id = "d70a8aae", text = "Do the delve weekly for a chance at tier if you still need tier" },
            { id = "70348198", text = "Complete weekly spark quest" },
            { id = "a032b050", text = "Farm +12's if you need to for crests. You don't have to spam M+ this season if you can get your crests from other sources." },
            { id = "be0f768b", text = "Heroic: Upgrade a 3/6h item to 6/6h for 60 Heroic Crests. Upgrade 1 3/6h items to 4/6h for 20 Heroic Crests. Use 20 Hero crests for a myth 1/6 item that you need to upgrade to 2/6 first." },
            { id = "0f46d1be", text = "Mythic(bonus rolled a Heroic boss): Either craft your third item at 5/6M for 80 Myth crests OR upgrade your bonus roll item to 6/6M using 80 Myth Crests. Don't forget to upgrade a heroic item to 6/6 heroic for 20 Heroic Crests in that slot first." },
            { id = "dd6a18d6", text = "Mythic(bonus rolled mythic or took 6/6 item from vault): Craft your third item at 5/6M for 80 Myth crests." },
            { id = "c84b4730", text = "If being a degen CHECK GUIDE, get it geared and crest capped.  this no longer works, downgraded crests count against cap" },
            { id = "f7ab089c", text = "As always, if you get a mythic item before the guide expects you to, upgrade it if you have the hero crests to save the myth crests" },
            { id = "c20119f7", text = "Total Crests spent so far: 380/380 Heroic | 320/350 Mythic" },
        },
    },
    {
        id = "fd6e56ee",
        title = "Week 4 - Sep 8",
        items = {
            { id = "d800e84b", text = "Open your vault - Check Guide for what to take." },
            { id = "70348198", text = "Complete weekly spark quest" },
            { id = "a032b050", text = "Farm +12's if you need to for crests. You don't have to spam M+ this season if you can get your crests from other sources." },
            { id = "744d79f9", text = "Heroic: Upgrade 1 3/6h item to 6/6h for 60 Heroic Crests. You are done with hero crests with absolutely perfect drops this week. Otherwise, it will be next week." },
            { id = "6aef7ab9", text = "Mythic(bonus rolled a Heroic boss the first 2 weeks): Craft your third item at 5/6M for 80 Myth crests and upgrade your bonus roll item OR drop item to 4/6M using 40 Myth Crests. Don't forget to upgrade a heroic item to 6/6 heroic for 20 Heroic Crests in that slot first." },
            { id = "8454275a", text = "Mythic(bonus rolled mythic or took 6/6 item from vault):  If you get a drop item, upgrade it to 6/6M using 80 Myth crests. If you get a second drop item, upgrade it to 4/6M using 40 Myth Crests." },
            { id = "7fa9a5b8", text = "Total Crests spent so far: 480/480 Heroic | 440/450 Mythic" },
        },
    },
    {
        id = "9d16aa2f",
        title = "Week 5 - Sep 15 - Done with Hero Crests",
        items = {
            { id = "d800e84b", text = "Open your vault - Check Guide for what to take." },
            { id = "70348198", text = "Complete weekly spark quest" },
            { id = "a032b050", text = "Farm +12's if you need to for crests. You don't have to spam M+ this season if you can get your crests from other sources." },
            { id = "4b0e1a28", text = "Heroic: Upgrade any remaining items to 6/6h." },
            { id = "c266c060", text = "Mythic(all paths): Either Craft your fourth item at 5/6M for 80 Myth crests or upgrade a natural drop to 6/6M using 80 myth crests. Upgrade a drop item to 5/6M using 20 Myth Crests." },
        },
    },
    {
        id = "ebe5928e",
        title = "Week 6 - Sep 22+ -",
        items = {
            { id = "d800e84b", text = "Open your vault - Check Guide for what to take." },
            { id = "70348198", text = "Complete weekly spark quest" },
            { id = "1df64ea4", text = "Have a wonderful Season 2 and best of luick to everyone!" },
        },
    },
}

reg.data[LOCALE] = DATASET
