# RoE Helper

A window-based Records of Eminence helper for Ashita v4, built on [commandobill/roe](https://github.com/commandobill/roe) (original by Cair, ported to Ashita by Commandobill).

Everything from the original is kept (profiles, blacklist, settings), plus:

- `/roehelper` opens the helper window (zone RoEs, element stones, dailies, repeatables).
- Per-zone combat RoEs and day/weather stones.
- Repeatables list (`/roehelper repeat add|rem|list`).
- When you take an RoE yourself, its id is logged to chat so you can add it to the repeatables.
- Shared theme with a pinned close button.

## Install

1. Make sure no older copy of the addon is loaded (`/addon unload roehelper`).
2. Clone (or download and unzip) this repository into your Ashita addons folder, **in a folder named `roehelper`**:
   ```
   cd <Ashita>\addons
   git clone https://github.com/Adamantking/roe-helper.git roehelper
   ```
3. In game: `/addon load roehelper`  (add it to your default script to load it on startup).

> Everything here is tested to the best of my ability - please report what breaks.
>Claude was used in the creation of this addon.

The addon is called `roehelper` and its command is `/roehelper`, so it can be loaded next to the original `roe` addon. Saved profiles and settings of the original live in `<Ashita>\config\addons\roe\` - copy that folder to `...\config\addons\roehelper\` if you want to keep them.

## Commands

`/roehelper help` lists every command: `/roehelper`, `/roehelper zone`, `/roehelper repeat ...`, `/roehelper add|rem <id or name>`, `/roehelper save|set|unset|list`, `/roehelper settings`, `/roehelper blacklist`, `/roehelper status`.

## Notes

Like the original, this sends accept (0x10C) and cancel (0x10D) RoE packets directly, one every 0.5-0.6 seconds. Check your server's rules on automation.

## Credits

Original addon by Cair, Ashita port by Commandobill (MIT). This fork keeps their copyright notices - see `LICENSE`.

## AI assistance

The window UI and additions to the original addon were written with the help of Claude (Anthropic); the original code by Cair and Commandobill is theirs. It has not been fully tested in game, so expect bugs and please report them.
