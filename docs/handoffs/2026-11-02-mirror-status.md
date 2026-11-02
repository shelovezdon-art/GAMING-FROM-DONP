# Mirror status — 2026-11-02 end of session

Studio is the source of truth (`docs/practice/ROBLOX-PRACTICE.md` §1). These are the QA/backup copies.
Measured directly against live Studio byte lengths, not taken from any agent's report.

| Repo file | Studio bytes | Repo body bytes | Status |
|---|---|---|---|
| `src/football/team/AWMotion.lua` | 21,175 | 21,175 | ✅ exact |
| `src/football/team/AthleteMotion.client.lua` | 17,878 | 17,878 | ✅ exact |
| `src/football/team/Config.lua` | 17,290 | 17,290 | ✅ exact |
| `src/football/team/Rules.lua` | 26,674 | 26,674 | ✅ exact |
| `src/football/team/TeamFootballClient.client.lua` | 80,528 | 80,528 | ✅ exact |
| `src/football/team/DripClient.client.lua` | 14,003 | 14,003 | ✅ exact |
| `src/basketball/Hoops3Client.client.lua` | 42,130 | 42,130 | ✅ exact |
| `src/football/team/TeamFootballService.server.lua` | 123,205 | 34,610 | ❌ **TRUNCATED (~28%)** |
| `src/football/team/DripService.server.lua` | 11,708 | 10,781 | ⚠️ stale (basketball earn handlers) |
| `src/football/team/DripCatalog.lua` | 5,579 | 4,894 | ⚠️ stale (basketball earn rates) |
| `src/basketball/HoopsCamera.lua` | 18,887 | 15,978 | ⚠️ stale (wobble fixes) |
| `FootballService` (ServerScriptService) | 61,890 | — | ❌ never mirrored |
| `BroadcastHUD` (StarterPlayerScripts) | 15,880 | — | ❌ never mirrored (camera stand-down fix) |
| `Hoops3Service` + `Hoops3Modules.*` | — | — | ❌ never mirrored (actively being edited) |

## What went wrong
A second mirror run was launched while the first was still writing (orchestrator error, not an agent error).
The first run detected the conflict, removed its own stray block from the other run's file, and stopped — the
correct behaviour — but `TeamFootballService.server.lua` was left holding only the newer run's first chunk.
**Lesson: never run two mirror jobs against the same directory; one owner per directory per run.**

## Next action
One mirror run, after the basketball gameplay wave finishes (so `Hoops3Service`/`Hoops3Modules` stop moving),
covering: TeamFootballService, DripService, DripCatalog, HoopsCamera, FootballService, BroadcastHUD,
Hoops3Service, Hoops3Modules.*. Verify header+source = file size per file, and grep a marker per file.
