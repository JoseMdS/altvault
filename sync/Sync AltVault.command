#!/bin/zsh
# Double-click to merge AltVault data across both WoW Forever accounts (game must be closed).
LUA=$(command -v lua || echo /opt/homebrew/bin/lua)
"$LUA" "${0:A:h}/altvault-sync.lua" "/Applications/World of Warcraft/_forever_"
echo; read -k1 "?Press any key to close..."
