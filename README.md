# LariasWeeklyChecklist

Larias' Weekly Checklist 主插件 + 简体中文配套插件。

目录结构：

- `LariasWeeklyChecklist`：主插件
- `LariasWeeklyChecklist_Localization`：简体中文本地化配套插件

安装时把两个文件夹放入 `World of Warcraft\_retail_\Interface\AddOns\`。

## 官方原版 + Localization 的说明

这个插件的架构是“主插件 + 本地化配套插件”，中文文字主要来自
`LariasWeeklyChecklist_Localization`。如果你的客户端是中文，只安装官方原版主插件
再加上这个 localization，通常就能自动显示中文。

不过本 release 里的 `LariasWeeklyChecklist` 并不完全是官方原版，它额外包含了几处
本地化相关和界面调整：

- 语言设置菜单里增加了“简体中文”选项。
- 小号汇总默认改为弹出到主框体左侧。
- 小号汇总和几个弹出框体的背景改得更不透明。

因此：

- 只安装 `LariasWeeklyChecklist_Localization`，中文客户端下通常也能显示中文，但不会
  包含上面这些主插件调整。
- 希望与当前 release 保持完全一致时，请直接安装完整 zip。zip 同时包含主插件和
  localization，是最省事、最不容易装错的安装方式。
- 不要用官方原版主插件替换本 release 中的 `LariasWeeklyChecklist`，否则会丢失上述
  已调整的弹出位置和背景透明度。
