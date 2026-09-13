# Final-score native crash — 2026-09-13 22:35

## Confirmed artifacts

Preserved directory: `C:/Users/harjeb/AppData/Local/Temp/dota2-rpg-score-crash-uo45ffki/`.

- `console.8997185207.log` and launcher `console.log`.
- Steam dump `crash_dota2.exe_20260913223533_1.dmp`.
- Native dump `dota2_2026_0913_223533_0_accessviolation.mdmp`.
- Analysis scripts, module/exception extraction and PE-unwind reports. Copies have the same SHA-256 as sources.

Both dumps show the same exception and recovered stack:

- Exception `0xC0000005`, thread 2824.
- Instruction `0x7FFDFC973226` = **server.dll+0x503226**.
- Read address `0x270`, RCX=0.
- Instruction `48 8B 99 70 02 00 00` = `mov rbx,[rcx+0x270]`.

This is a native null-pointer read, not merely a snapshot disconnect. Dump times 14:35:33/36 UTC match local 22:35:33/36.

## Recovered call chain

Using x64 PE unwind metadata and matching module timestamps (not speculative stack scanning):

```
server.dll+0x503226
server.dll+0x137F80F
server.dll+0x16A9F3E
server.dll+0x16AE160
server.dll+0x24F55CA
server.dll+0x5126BC
server.dll+0x1C6D42C
server.dll+0x1C6D7DB
server.dll+0x6B275D
server.dll+0x1BB233A
engine2.dll+0xB3D45
... engine2 frames ...
dota2.exe+0x4BE0
dota2.exe+0xE9F2
kernel32.dll / ntdll.dll
```

There is no Panorama/client frame in the recovered exception chain. Function symbols are unavailable; the exact native object/gameplay operation is unidentified.

## Console correlation and limits

22:35:32: chapter 15, Terrorblade entity 345 dies at game time 2145.10, final run life reaches zero, and `Run ended: all five lives lost.` is logged. Repeated missing `caster_silenced` localization warnings follow, then Breakpad initialization.

The terminal source path calls RunResults.Finish, transitions to result, stops battle, sends state/settlement/terminal/shop messages, and logs Run ended. The log reaches that final message. It does NOT establish score arithmetic, leaderboard HTTP, localization or UI rendering as the trigger. Native processing after that path remains possible.

The preceding session also has custom-event serialization failures at 22:16:52, but these are not proof of this crash's cause. UI71 inventory/neutral/mine changes were uninstalled at the time and must not be described as tested in this crash.

Tracked investigation: `dota2_rpg-p5wp`. No gameplay or process operations performed. Native root cause and mitigation remain open.
