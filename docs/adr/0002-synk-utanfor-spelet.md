---
status: beslutad
ägare: JoseMdS
datum: 2026-11-22
krav: [AV-KRAV-005]
---

# ADR-0002: Kontosynk med ett skript utanför spelet

## Sammanhang
José har karaktärer på två länkade konton. SavedVariables sparas per konto, så AltVault på konto A ser inte karaktärerna på konto B. Addons kan inte läsa andra kontons filer eller skicka data mellan konton på egen hand.

## Beslut
Ett Lua-skript (`sync/altvault-sync.lua`) körs med spelet stängt. Det läser `AltVaultDB` från alla konton i installationen, slår ihop karaktärerna (nyast `updated` vinner per karaktär) och skriver tillbaka samma data till varje konto. På Mac startas det med dubbelklick på `Sync AltVault.command`.

## Konsekvenser
- Inga beroenden på servern eller på att båda kontona är inloggade samtidigt.
- Användaren måste komma ihåg att köra synken, och spelet måste vara stängt (skriptet kontrollerar det).
- Kräver Lua på datorn, och Windows saknar ännu ett startskript ([AV-KRAV-007](https://github.com/JoseMdS/altvault/issues/11)).

## Alternativ som valdes bort
- **Skicka data mellan karaktärer i spelet (addon-meddelanden eller post):** kräver att båda är inloggade samtidigt och är begränsat i storlek.
- **Account-wide SavedVariables:** delas bara inom ett konto, inte mellan länkade konton.
