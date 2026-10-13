--[[
Chinese Simplified (zhCN) checklist data for Larias' Weekly Checklist

NOTE: IDs are kept identical to the current enUS dataset so completion tracking
stays consistent across locales.
]]

-- @sheet-version: 15

local LOCALE = "zhCN"

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
        title = "第9周 - 10月13日",
        items = {
            { id = "d9564251", text = "如果你的公会不打算花时间打史诗基希克斯，你可以选择在接下来的3周里在英雄难度额外掷骰3次，不用进史诗难度就能拿到全部毕业装备。这些装备虽然是1/6神话轨，但下周纹章就取消上限了，所以并无大碍。" },
            { id = "7c57fe59", text = "如果你要打史诗基希克斯，请注意不同难度的额外掷骰掉落列表是不同的——你可以在英雄难度额外掷骰拿到某件装备，随后在史诗难度额外掷骰再次拿到同一件装备。" },
            { id = "b8dc5e31", text = "完成新的地下堡迷宫，即可自选部位必定获得一件神话装等装备。" },
        },
    },
    {
        id = "eed82be5",
        title = "第10周 - 10月20日",
        items = {
            { id = "9999766a", text = "纹章取消上限——尽情刷吧！" },
            { id = "7eee8c3c", text = "可以获取毒液石了。每件装备总共需要10枚毒液石，因此如果你想升级2把武器、2个饰品和项链，总共需要打50次大秘境。" },
        },
    },
}

reg.data[LOCALE] = DATASET
