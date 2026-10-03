# Flightle

A daily flight puzzle. A real flight route is drawn with both airports hidden; the plane flies from
DEP to ARR with north up and no map. Name the departure and arrival airports in 6 guesses.

- Type a city or 3-letter code (on-screen keyboard or a real one). Enter picks the top match.
- Each end of a guess shows its distance and a direction arrow toward the real airport. A correct end
  locks in, so later guesses only need the other one. Guessing the right airport for the wrong end
  shows blue.
- Every miss unlocks a clue, in order: airline, aircraft, altitude profile, distance and flight
  time, local departure time.
- When the game ends the coastline map fades in under the route.
- Everyone gets the same flight each day (UTC). `?day=YYYY-MM-DD` replays a past day.

**Play:** https://jprier.github.io/GameTests/flightle/

## Data

`data/flightle.json` is built by `data/build_data.py` from
[mwgg/Airports](https://github.com/mwgg/Airports) and Natural Earth 110m land. Routes are real,
regularly flown routes with a typical operator, aircraft and approximate local departure time. The
track is the great-circle path, and the altitude profile is modelled from distance and aircraft type.
Days cycle through all routes in a date-seeded order with no repeats inside a cycle.

```bash
cd data && python3 build_data.py airports.json ne_110m_land.geojson
```

To add routes, append lines to `ROUTES` in the builder (`FROM-TO|Airline|Aircraft|HH:MM`) and rebuild.
Note that changing the route list reshuffles future days.

## Dev mode

`?dev=1` on the web, or any debug build. Press `` ` `` or long-press the title to open the panel:
jump to any date, previous/next/random day, reset the day, reveal the answer, instant win or lose.
Dev progress is saved apart from real progress, and share links never include `dev=1`.
Agents can call `dev_set_day()`, `dev_win()`, `dev_lose()`, `dev_reset()`, `guess(from, to)` via
`gck eval`; `get_agent_state()` exposes the day, seed, answer, guesses, feedback and share text.
