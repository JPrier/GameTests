# Kitchen Crawl

A restaurant-sim roguelike made with Godot 4.7 (Compatibility renderer, web-first).

Survive 10 days: grab ingredients, cook patties, chop veg, plate orders and serve the counter.
Rent rises every night; angry customers cost reputation. After each day pick 1 of 3 upgrades
(new ingredients like tomato/cheese/fryer, extra stations, or perks). Random daily events
(Lunch Rush, Heatwave, Food Critic, Rainy Day, Payday...) keep each run different.

Controls: WASD/arrows + E/Space (hold E to chop) — or touch: left thumb joystick, right thumb action.

Web build: `godot --headless --export-release "Web" build/web/index.html`, then serve `build/web/`
from any static host (GitHub Pages, itch.io, Netlify). No special headers needed (no-threads build).
Tests: `gck test kitchen-crawl` (tests/test_main.gd).
