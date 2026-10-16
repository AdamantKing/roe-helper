# RoE Helper

A window-based Records of Eminence helper for Ashita v4, built on [commandobill/roe](https://github.com/commandobill/roe) (original by Cair, ported to Ashita by Commandobill).

Everything from the original is kept (profiles, blacklist, settings), plus:

- `/roe` opens the helper window (zone RoEs, element stones, dailies, repeatables).
- Per-zone combat RoEs and day/weather stones.
- Repeatables list (`/roe repeat add|rem|list`).
- When you take an RoE yourself, its id is logged to chat so you can add it to the repeatables.
- Shared theme with a pinned close button.

## Install

1. Make sure no older copy of the addon is loaded (`/addon unload roe`).
2. Clone (or download and unzip) this repository into your Ashita addons folder, **in a folder named `roe`**:
   ```
   cd <Ashita>\addons
   git clone https://github.com/Adamantking/roe-helper.git roe
   ```
3. In game: `/addon load roe`  (add it to your default script to load it on startup).

> Everything here is tested to the best of my ability, changes/fixes will be made as necessary.
> Claude was used heavily in the creation of this addon.


## Commands

`/roe help` lists every command: `/roe`, `/roe zone`, `/roe repeat ...`, `/roe add|rem <id or name>`, `/roe save|set|unset|list`, `/roe settings`, `/roe blacklist`, `/roe status`.

## Notes

Like the original, this sends accept (0x10C) and cancel (0x10D) RoE packets directly, one every 0.5-0.6 seconds. Check your server's rules on automation.

## Credits

Original addon by Cair, Ashita port by Commandobill (MIT). This fork keeps their copyright notices - see `LICENSE`.
