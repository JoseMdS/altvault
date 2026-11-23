# AltVault

A World of Warcraft (WoW Forever) addon to search bags, bank and gold across all your characters — and across two accounts with the sync script.

## Features

- Tracks bags, bank, equipped items and gold for every character you log in.
- `/vault` opens a window listing your characters, with search across all of them.
- Item tooltips show how many of that item each character holds.

## Install

Copy this folder to `Interface/AddOns/AltVault` in your WoW install (e.g. `/Applications/World of Warcraft/_forever_/Interface/AddOns/AltVault`), then log in to each character once so it gets recorded.

## Syncing two accounts

SavedVariables are per account, so each account only sees its own characters. The sync script merges AltVault data between all accounts in the install so every account sees every character.

**Run it with the game closed** (WoW overwrites SavedVariables when you log out).

- Double-click `sync/Sync AltVault.command`, or
- run `lua sync/altvault-sync.lua "/Applications/World of Warcraft/_forever_"`

Requires `lua` (e.g. `brew install lua`).

## Dokumentation

Design (LLD), beslut (ADR) och krav finns i [`docs/`](docs/index.md) och i [issues](https://github.com/JoseMdS/altvault/issues). Arbetssättet beskrivs i [dev-portal](https://github.com/JoseMdS/dev-portal).
