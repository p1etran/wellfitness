# wellfitness

Scheduled scraper that records how many people are currently inside each
Wellfitness gym club in Poland. The point is to eventually work out the
quietest times to train.

No server, no always-on machine — everything runs on GitHub's runners.

## How it works

| File | Role |
| --- | --- |
| `poll.ps1` | Logs into the Wellfitness PerfectGym client portal, calls the occupancy endpoint, appends results to CSV. |
| `.github/workflows/poll.yml` | Cron job that runs `poll.ps1` on a schedule and commits the result back to the repo. `ubuntu-latest`, `pwsh`. |

## Upstream API

Undocumented — reverse-engineered from the web portal. Base:
`https://wellfitness.perfectgym.pl/ClientPortal2`

**1. `POST /Auth/Login`**

```json
{"RememberMe":false,"Login":"<email>","Password":"<pass>"}
```

Returns a JWT, in the response body and/or a `CpAuthToken` cookie. Tokens
expire after roughly 4 days, which is why the script logs in on every run
rather than storing one.

**2. `POST /Clubs/Clubs/GetMembersInClubs`**

Empty body. Auth via `Authorization: Bearer <jwt>` plus the session cookie.
Returns all ~105 clubs nationwide:

```json
{"UsersInClubList":[{"ClubName":…,"ClubAddress":…,"UsersLimit":null,"UsersCountCurrentlyInClub":12}]}
```

Both endpoints also require `CP-LANG: pl`, `CP-MODE: desktop`, and
`X-Requested-With: XMLHttpRequest`.

**`UsersLimit` is null for every club**, so there is no capacity figure —
only absolute headcounts. Clubs therefore cannot be compared against each
other on raw numbers; each club is only meaningful against its own history.

## Data files

**`clubs.csv`** — registry, one row per club:

```
id,name,address
```

Keyed on **address**, not name. A club can be renamed but doesn't move, so
this keeps a rename from splitting one location's history into two series.
IDs are assigned as `max(existing) + 1` and never recycled, so a closed club
keeps its ID forever and old rows stay valid.

**`samples-YYYY-MM.csv`** — one file per month, append-only:

```
ts,club_id,n
```

`ts` is UTC at minute resolution; `n` is the headcount. Long format is
deliberate: append-only, schema-stable, and new clubs need no special
handling. Roughly 3–4 MB per month.

## Credentials

Two GitHub repo secrets: `GYM_LOGIN` (account email) and `GYM_PASS`. Never in
the source. Repo is private.

## Verifying it's working

- **Actions log prints zero `new club:` lines** on a healthy run. The last
  line should read like `2026-07-31T00:36Z — 105 rows, 105 clubs known`.
- **Gap histogram on `ts` is mostly the polling interval.** Some drift and
  the occasional missing slot is expected (see below); a run of hour-plus
  gaps is not.
- Commits from `bot` should be landing on schedule. If the newest `sample …`
  commit is a day old, start at the Actions tab.

## Gotchas

- **The workflow is currently on `*/15`, and that does not fit the budget.**
  Private repos on the GitHub Free plan get 2,000 Linux minutes/month, and
  every job is billed rounded up to a full minute. 30-minute polling
  (~1,440 min/month) fits; 15-minute polling does not, and collection will
  silently stop partway through the month when the allowance runs out.
  Either move the cron to `*/30` or accept losing the back half of each month.
- **UTC storage.** Analysis must convert to `Europe/Warsaw`, not a hardcoded
  offset, or the DST change in late October shifts half the dataset by an hour.
- **Cron is best-effort.** Scheduled runs get delayed or dropped under load.
  At 30-minute polling expect ~40–46 samples/day rather than a clean 48.
  Gaps are normal.
- **Address changes are the one thing that breaks ID stability.** If a club's
  address string changes (relocation, typo fix), the script sees an unknown
  address and files it as a new club, splitting that location's history. The
  tell is a `new club:` line in the Actions log naming a club that has been in
  the data for months. Fix by hand in `clubs.csv`: delete the new row, correct
  the address on the old one.
- **Scheduled workflows are disabled after 60 days of repo inactivity.** The
  bot's own commits normally prevent this, but if collection goes quiet, check
  the Actions tab first.
- **`git add -A` in the workflow is load-bearing.** A `samples-*.csv` glob
  misses `clubs.csv` and deletions, which silently breaks ID persistence.

## Analysis

Lives in `index.html` — a static, dependency-free dashboard ("Wellfitness
Pulse") that reads `clubs.csv` and the `samples-*.csv` files directly in the
browser and recomputes everything on each load, so every bot commit enriches
it with zero extra work. It shows:

- a Leaflet map of all clubs (dark CARTO basemap), markers sized by current
  headcount — coordinates come from `clubs-geo.json`, which is hand-placed
  and approximate; edit it to refine positions;
- per-club detail: weekday × hour **median** heatmap, last-48 h sparkline,
  busiest/calmest picks;
- national weekday × hour rhythm plus by-hour and by-day profiles, with each
  club scaled to its own typical peak (90th percentile) since there is no
  capacity figure to normalise against;
- "right now" busiest/quietest leaderboards from the latest sample.

All times are converted to `Europe/Warsaw` via `Intl` (DST-safe). While the
dataset is younger than ~1 week the page scales colours against the national
field instead of each club's own (meaningless) peak, and shows a
"warming up — day N of ~21" banner. Only the newest 6 monthly sample files
are fetched per load to keep payloads bounded.

Leaflet is vendored in `vendor/leaflet/` so the only runtime network
dependency is the map tiles.

**Serving it:** the page fetches sibling CSV files, so it needs HTTP —
`python3 -m http.server` in the repo root, or GitHub Pages (requires the repo
to be public, or a paid plan, since Pages isn't available on private free
repos).

Needs roughly 3 weeks of data before the patterns mean anything, and August
is atypical — don't read much into the first month.
