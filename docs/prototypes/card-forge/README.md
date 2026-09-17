# Visual reference only

This browser study records the visual and interaction direction reviewed by the user. It is not the Dota UI delivery and is never installed into the game.

The native implementation lives in `content/dota_addons/dota2_rpg_endless/panorama`. See `docs/CARD_FORGE_UI98.md` for the native entry, behavior, validation and installation.

The five card backs reference the original repository `pics` files. Optional browser-only hero artwork can be restored with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File docs/prototypes/card-forge/fetch-assets.ps1
```

The art is downloaded from Valve's Dota 2 CDN for this Dota project; it is not original art created by this project. Images remain local under the repository's existing ignore policy. The native UI uses Dota's own `DOTAHeroImage` and has no dependency on these downloads.
