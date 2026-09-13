# UI68：排除可选小精灵

用户反馈招募的小精灵显示异常，授权难以处理时从可选英雄移除。本次采用该方案：普通招募池排除 Wisp（123→122），天梯手选/随机列表和技能调试服务端目录也排除 Wisp。默认主机仍为 Wisp，相关隐藏、保护和背包处理不变。原生英雄元数据及独立调试原始目录保留完整，仅在实际选择目录过滤。

源码检查发现 OnNPCSpawn 的 owned-hero 出生保护显式排除 Wisp，而后续按名称把 Wisp 作为主机隐藏和保护。出生事件先于 lineupHeroName 赋值时存在误识别风险；本轮没有实机验证具体视觉根因，没有改写原生粒子效果。现有对局已生成的小精灵不会由安装动作移除，需重载地图后使用新目录。

103/103 全量离线回归通过，新增既有测试断言覆盖招募生成一致性、调试拒绝 Wisp 和天梯公布目录排除 Wisp。报告 C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui68-regression.json。6 个 addon 文件已安装并逐字节核对，中英文均 UI68。备份 C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-ui68-rc0m4af6。没有操作游戏，实机效果未验收。

远程走位排查按用户“又好了，先不管”暂停，未提交或部署该排查改动；候选补丁保存在 C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-xir3-deferred.patch，问题 dota2_rpg-xir3 保持开放。
