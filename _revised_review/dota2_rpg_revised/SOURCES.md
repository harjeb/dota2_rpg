# 技术参考来源

> 访问与核对日期：2026-09-05。Valve Workshop 接口与 Dota 版本可能变化，发布前应再次核对并在上传后的专用服务器实测。

## Valve Developer Community

- Dota 2 Workshop Tools 入口  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools
- Panorama / Custom UI Manifest  
  https://developer.valvesoftware.com/wiki/Panorama/Overview/Custom_UI_Manifest
- Custom Net Tables  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Custom_Nettables
- Custom Game Events  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Custom_Game_Events
- Lua API 总表  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API
- ExecuteOrderFromTable  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/Global.ExecuteOrderFromTable
- SetExecuteOrderFilter  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/CDOTABaseGameMode.SetExecuteOrderFilter
- FindUnitsInRadius  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/Global.FindUnitsInRadius
- AddExperience  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/CDOTA_BaseNPC_Hero.AddExperience
- SetUseCustomHeroLevels  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/CDOTABaseGameMode.SetUseCustomHeroLevels
- SetCustomHeroMaxLevel  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/CDOTABaseGameMode.SetCustomHeroMaxLevel
- SetCustomXPRequiredToReachNextLevel  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/CDOTABaseGameMode.SetCustomXPRequiredToReachNextLevel
- CreateItem  
  https://developer.valvesoftware.com/wiki/Dota_2_Workshop_Tools/Scripting/API/Global.CreateItem

## 当前商店兼容问题

- ValveSoftware/Dota2-Gameplay #34007 — Custom Games Item shop display broken in 7.41e  
  https://github.com/ValveSoftware/Dota2-Gameplay/issues/34007
- ValveSoftware/Dota2-Gameplay #34145 — Please fix shop.txt bug in Custom Games!  
  https://github.com/ValveSoftware/Dota2-Gameplay/issues/34145

## 当前英雄目录

- Dota 2 官方英雄页  
  https://www.dota2.com/heroes

本项目不在文档中写死英雄总数；实际招募池由当前版本目录与 `hero_compatibility` 构建结果共同决定。


## 命石与英雄变体兼容问题

- ValveSoftware/Dota2-Gameplay #26579 — facet/variant information and creation API limitations in custom games  
  https://github.com/ValveSoftware/Dota2-Gameplay/issues/26579
- ValveSoftware/Dota2-Gameplay #26448 — custom hero grid cannot preselect a facet  
  https://github.com/ValveSoftware/Dota2-Gameplay/issues/26448

首发版因此不开放任意命石选择；每名英雄只允许一个已在当前补丁专用服务器验证的变体。
