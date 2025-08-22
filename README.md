# KaChing

[![Release](https://img.shields.io/github/v/release/mtp1032/KaChing?sort=semver)](https://github.com/mtp1032/KaChing/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/mtp1032/KaChing/total)](https://github.com/mtp1032/KaChing/releases)
[![Build](https://github.com/mtp1032/KaChing/actions/workflows/build_kaching.yaml/badge.svg)](https://github.com/mtp1032/KaChing/actions/workflows/build_kaching.yaml)

**Download:** ➜ [Latest release (zip)](https://github.com/mtp1032/KaChing/releases/latest)


# KaChing

Bulk-sell junk (gray) and, optionally, **white** armor/weapons.  
This is a from-scratch Classic/Turtle-WoW rewrite of my Retail addon.

## Table of Contents
- [KaChing](#kaching)
- [KaChing](#kaching-1)
  - [Table of Contents](#table-of-contents)
  - [Version](#version)
  - [What it does](#what-it-does)
  - [Installation](#installation)
  - [Usage](#usage)
  - [Options](#options)
  - [Notes \& Safeguards](#notes--safeguards)
  - [Known Issues](#known-issues)
  - [Roadmap (next major release)](#roadmap-next-major-release)
  - [Troubleshooting](#troubleshooting)
  - [Compatibility](#compatibility)

## Version

**Current:** `0.9.9`

## What it does

- **Sell all poor (gray) items** with one click. (Default)
- **Optionally** sell **common (white) armor & weapons**.
- **Exclusion list:** protect specific items (e.g., profession tools such as a pick ax or fishing pole of any quality) from being sold.

KaChing targets Classic 1.12/Turtle WoW (Lua 5.0).

## Installation

1. Download the release zip (e.g., `KaChing-v1.0.0-master.zip`).
2. Unzip; you will get a folder named `KaChing-v1.0.0-master/`.
3. **Rename that folder to `KaChing`**.
4. Move it to your addons directory:
   - `World of Warcraft\Interface\AddOns`
5. Enable **KaChing** in the AddOns section of the character select screen.

## Usage

1. Click on any merchant NPC to open the merchant's window.
2. Click the **KaChing** button in the **top-right** corner of the merchant frame.  
   KaChing sells:
   - All **gray** items
   - Plus **white armor & weapons** *if* that option is enabled
   - **Never** items on your exclusion list

> KaChing does **not** auto-sell on opening a Merchant NPC's frame. In this version—you choose when to sell by clicking the [KaChing] button.

## Options

Open KaChing’s options via the **minimap icon** (yellow `$$`):

- **[ ] Sell white armor & weapons**  
  When checked, KaChing will also sell white-quality armor/weapons (except items on the exclusion list).

- **Exclusion list**  
  - **Add:** drag & drop an item from your bags onto the upper input box (or shift-click with the box focused).
  - **View:** the lower list shows all excluded item names (lower-cased).
  - **Remove:** select a name in the list and click **Remove**.

All settings (checkbox and exclusion list) are saved per-character and persist across sessions.

## Notes & Safeguards

- KaChing **never** sells uncommon (green) or higher quality items.
- Rings, trinkets, shirts, tabards, recipes, reagents, trade goods, etc. **are not** treated as “white armor/weapons” and won’t be sold when the toggle is on.
- If an item is on the **exclusion list**, it will never be sold—even if it’s gray or white A/W.
- The addon includes “safe” wrappers to cope with Classic/TWoW tooltip and API behavior.

## Known Issues

None currently.

## Roadmap (next major release)

Optional filters for **useless soulbound** items, such as:
- Soulbound armor/weapons your class cannot equip (e.g., leather gloves in a priest's inventory)
- Soulbound recipes already known by the player

*(These will be opt-in and conservative.)*

## Troubleshooting

- **White A/W didn’t sell?**  
  Ensure the **Sell white armor & weapons** option is checked and the item isn’t on the exclusion list.
- **“Nothing to sell” but you expected sales?**  
  Items may be excluded, or not classified as armor/weapon; try hovering them—slot lines like “Feet/Chest/Head” indicate armor.
- **Seeing cursor “ghost” behavior?**  
  KaChing clears the cursor before/after selling; if it persists for a specific item, please report the exact item name or link.

## Compatibility

- **Client:** WoW 1.12-style (Turtle WoW / Classic-era)  
- **Lua:** 5.0 (no `select`, `%` modulo, _G, etc.)  
- **SavedVariables:** `KACHING_SAVED_OPTIONS`, `KaChing_ExcludedItemsList`
