# City-Scale Crowd Control

- **Status:** Inbox
- **Genre / format:** Systems-management simulation, logistics puzzle, run-based strategy
- **Players / platform:** Single-player, browser; desktop and mobile-friendly
- **Pitch:** Manage the systems that crowds move through, from a few hundred people in a queue to hundreds of thousands moving across a city. Shape flows through capacity, information, infrastructure, and incentives while simple local decisions create complex global outcomes.
- **Core interaction:** Read crowd flow, identify a cause or emerging bottleneck, then adjust routes, capacity, staffing, or information and observe the downstream effects.
- **Session length:** A short event scenario, with longer campaign or roguelike runs
- **Replay / daily hook:** Reusable venue, crowd, schedule, transport, weather, objective, and event components can generate distinct scenarios; deterministic daily challenges could let players compare solutions.
- **Prototype scope:** One compact venue with an entrance, two exits, a station, parking, a plaza, corridors, one controllable gate, one digital sign, and a placeable barrier; simulate approximately 1,000–5,000 people.
- **Open questions:** How to make crowd safety understandable without making it binary; how far to simulate individuals versus aggregates; how to make crowd behavior readable and satisfying at multiple scales.
- **Related games / overlap:** Systems-management, logistics, simulation, and roguelike management games.
- **Claim:** 

## Core fantasy

Start by managing a queue of a few hundred people. Eventually orchestrate the movement of hundreds of thousands or even millions across a complex city-scale environment.

The player should not directly control individual NPCs. They operate the system people move through: flows, capacity, incentives, information, infrastructure, and emergency response. The intended feel combines a systems-management game, logistics puzzle, simulation, roguelike or run-based management, and a visually readable large-scale crowd simulation. The crowd itself is the primary gameplay system.

## Design pillars

### 1. Indirect control

The player almost never commands individuals. They influence behavior by opening or closing gates, laying out one-way routes, moving barriers, opening exits, redirecting transit, adjusting entry rates, assigning staff, changing signs, making announcements, showing wait estimates, changing lighting or visual guidance, opening or restricting attractions, changing queue layouts, and deploying temporary infrastructure.

The player should feel like an operations controller rather than an RTS commander.

### 2. Local behavior, global consequences

People make mostly local decisions, while the player is responsible for global system behavior. Small interventions can create large downstream consequences:

- A shortcut relieves a plaza but overwhelms a train station.
- Closing a road protects pedestrians but delays buses.
- Opening more gates increases inflow beyond downstream capacity.
- Redirecting a crowd creates counterflow elsewhere.
- Advertising a less crowded exit overloads it.
- Holding one group briefly lets another route clear safely.

The player reasons about networks, bottlenecks, and downstream effects.

### 3. Readability over realism

The simulation may be realistic internally, but the interface must help the player quickly understand where people are, where they want to go, where they are moving, why congestion is occurring, and what may happen next. Avoid realism that makes causes impossible to diagnose.

## Scenario loop

### Preparation

Give the player operational information such as expected attendance; travel-mode split; event schedule; arrival and departure curves; critical capacity limits; staff and budget; emergency routes; transit schedules; weather; construction; nearby events; attendee characteristics; and available monitoring equipment.

The player prepares by placing barriers, assigning entrances, defining queues, choosing gate capacities, designating one-way paths, deploying signage, configuring transit, positioning staff, and selecting monitoring equipment.

### Live operations

The simulation runs continuously. The player monitors density, route use, queue lengths, throughput, wait times, frustration, walking speed, directionality, transit loading, gate utilization, bottlenecks, accessibility, and safety, then intervenes as conditions change.

### Resolution

Report competing dimensions separately rather than reducing performance to one pass/fail score:

- Safety
- Throughput
- Average and maximum wait
- Crowd experience
- Operating cost
- Accessibility
- Reliability
- Incident count
- Emergency readiness

A plan may be safe but inefficient, fast but risky, cheap but unpleasant, or optimized but brittle.

## Example event: stadium release

A stadium releases 40,000 attendees over about 35 minutes:

- 12,000 need a subway station with a safe platform capacity of 1,500.
- 8,000 travel to parking garages.
- 6,000 head to rideshare pickup zones.
- 5,000 use buses.
- 3,000 remain in nearby bars and restaurants.
- The rest disperse through surrounding neighborhoods.

Potential complications include a subway delay, failed escalator, overloaded rideshare zone, blocked garage exit, unexpected stadium exit closure, rain driving people toward covered routes, or a nearby event ending at the same time.

The challenge is to prevent dangerous overcrowding while moving people efficiently.

## Crowd simulation

Represent people with a small set of useful attributes rather than expensive cognition for every NPC:

- Destination, walking speed, patience, urgency, and route confidence
- Familiarity with the environment and willingness to follow signs or staff
- Tendency to follow others or avoid dense areas
- Group membership, mobility limitations, intoxication, and risk tolerance

Choose routes by perceived cost, not just shortest distance. A conceptual model is:

> perceived route cost = distance + congestion + uncertainty + inconvenience + social influence + personal preference

Different people weight those factors differently. A tourist may rely on signs; a local may take a familiar shortcut; friends may stay together despite a slower route; a person in a dense crowd may assume others know where they are going; an impatient person may abandon a queue; and a person with reduced mobility may prioritize elevators and accessible paths.

### Groups

Families, friend groups, tour groups, rival fan groups, school groups, staff, organized marches, and commuters can try to stay together. This may cause stoppages, wider formations, queue delays, counterflow, waiting for missing members, and sudden clustering. Group behavior should create believable dynamics without requiring complex AI.

### Gameplay-critical macro phenomena

- **Compression:** When inflow exceeds outflow, density rises, speed and maneuverability fall, and congestion can reinforce itself. The player must reason about inflow versus outflow capacity.
- **Counterflow:** Opposing streams sharply reduce corridor throughput. The player can use one-way routing, timed directional phases, or alternate routes.
- **Queue spillback:** Queues can block exits, sidewalks, platforms, vendors, emergency routes, and other queues.
- **Shockwaves:** Stopping or slowing at the front of a dense crowd causes a readable backward-moving disruption.
- **Herding:** People follow a popular route even when it is worse, creating a feedback loop that overloads Exit A while Exit B stays empty.
- **Pulsed movement:** Lights, trains, gate releases, performances, and scheduled events produce movement waves that the player can synchronize.

## Information and uncertainty

The player does not receive perfect knowledge automatically. Information comes from CCTV, crowd-counting cameras, ticket scanners, transit telemetry, staff reports, drones, Wi-Fi/Bluetooth estimates, gate counters, emergency calls, and security reports. Sources differ in precision and latency.

For example, a sensor might report “North Plaza Density: HIGH” without identifying the cause. The cause could be a broken escalator, stopped group, vendor queue, performer, transit delay, incorrect sign, medical event, or people waiting for friends. Better monitoring technology becomes a progression path.

## Player tools and resources

### Hard control

Fences, gates, turnstiles, road closures, restricted corridors, temporary walls, one-way routes, pedestrian bridges, and controlled entrances physically constrain movement. They are reliable but can create severe unintended consequences.

### Soft control

Directional signage, digital signs, estimated waits, announcements, staff guidance, lighting, floor markings, incentives, notifications, and transit information influence decisions without forcing them. Effects vary by person. For example, a “Exit B — 3 minutes / Exit A — 12 minutes” display might redirect 65% of those who see it, not everyone.

### Capacity control

Adjust gate release rates, train frequency, bus loading, queue admission, elevator priority, escalator direction, and checkpoint staffing.

### Finite operational resources

Staff, security, barriers, signs, buses, portable scanners, temporary lighting, crowd sensors, mobile medical teams, and traffic officers. Each scenario requires prioritization.

## Safety, experience, and accessibility

Safety is probabilistic and systemic, not a binary “avoid disaster” check. Track people per square meter, flow speed, sudden speed changes, opposing flows, blocked exits, inaccessible emergency paths, queue spillback, crushing and fall risk, and agitation. High density alone is not automatically catastrophic; combinations of density, movement, direction, and obstruction create risk.

People also react to waiting time, uncertainty, perceived fairness, visibility, comfort, toilets and food access, weather exposure, ability to stay with their group, staff communication, and confidence in instructions. Poor conditions can cause queue abandonment, sign noncompliance, unauthorized shortcuts, arguments, counterflow, and unpredictable movement. Clear communication improves compliance.

Accessibility is part of the simulation. Some attendees need elevators, ramps, accessible gates, seating, slower walking speeds, extra queue space, or shorter routes. A high-throughput design that traps attendees with mobility needs should score poorly.

## Events and progression

Dynamic events force adaptation and interact with the current crowd state: train or bus breakdown, escalator failure, power outage, weather change, lightning alert, scanner failure, restroom closure, road accident, celebrity appearance, protest, fire alarm, false rumor, evacuation, cellular outage, bridge closure, schedule changes, nearby event release, security incident, lost child, medical incident, or an attendance surge. The same incident should have different consequences in different crowd states. Avoid ending a scenario after one mistake; let conditions deteriorate and allow recovery.

Progression can move through:

- **Early:** Small theaters and local events, 500–2,000 attendees; queues, entrances, exits, signs, throughput.
- **Mid:** Concert venues, conventions, fairs, and arenas, 5,000–40,000; transit, multiple destinations, groups, multiple entrances, bidirectional movement.
- **Late mid:** Stadiums and festivals, 40,000–150,000; large transit systems, crowd waves, queue spillback, mixed traffic, large operations teams.
- **Late:** City-scale New Year’s Eve, championship parades, marathons, festivals, protests, evacuations, and simultaneous events; hundreds of thousands or millions, with district-level controls.

A roguelike or semi-roguelike campaign strings events together. Between events, acquire or upgrade sensors, staff, barriers, scanners, communications, prediction tools, pedestrian bridges, shuttle buses, lighting, signage, drones, and queue automation. Run modifiers include construction, transit strikes, viral attendance surges, heat waves, and doubled security screening.

## Scenario and venue systems

Generate replayable scenarios from reusable components:

> Venue + Crowd + Schedule + Transportation + Weather + Objectives + Random Events

The same stadium might host a pop concert with high transit and rideshare use, unfamiliar attendees, and a sharp departure surge; a local football match with repeat visitors, families, and parking demand; or a championship with higher attendance, rival groups, alcohol use, downtown celebrations, and simultaneous events.

Build venues from reusable components: corridors, plazas, gates, stairs, escalators, elevators, platforms, garages, streets, sidewalks, bridges, stops, checkpoints, restaurants, restrooms, stages, and exits. Each exposes capacity, effective throughput, direction, accessibility, current status, failure state, and connections. Keep scenario logic separate from map-specific assumptions.

## Visualization and prediction

At close zoom, show individuals and recognizable groups navigating obstacles and forming natural queues. At medium zoom, emphasize streams, queues, and bottlenecks. At far zoom, aggregate people into density and directional flow, with hotspots and transit streams.

Useful overlays include density, velocity, direction, destination, wait time, predicted congestion, safety risk, transit use, queue spillback, accessibility, and information coverage.

Later upgrades can provide imperfect predictions such as “North Station platform may exceed safe capacity in approximately 6 minutes.” High-level play should reward acting before problems occur.

After a scenario, provide a timeline replay with density, incidents, queue lengths, route changes, interventions, and throughput. A “what caused this?” view should explain changes, for example: “Congestion at 20:17 increased because Gate 4 inflow rose 38%, escalator throughput fell 50%, 1,200 attendees rerouted from Exit 2, and a train was delayed 4 minutes.”

## Run modes

- **Campaign:** Progress through increasingly difficult venues and events.
- **Roguelike run:** Handle successive randomized events while upgrading the toolkit.
- **Sandbox:** Choose venue, population, schedule, failures, and behavior parameters.
- **Challenge scenarios:** Solve authored problems such as clearing a station in 20 minutes or handling two opposing marches.
- **Daily challenge:** A deterministic shared scenario seed for comparing strategies.

## Prototype target

Do not start at city scale. Build one compact venue with one main entrance, two exits, one train station, one parking destination, one plaza, several corridors, one controllable gate, one digital sign, and one placeable barrier type. Simulate approximately 1,000–5,000 people.

Implement:

1. Destination-based movement
2. Congestion-aware route selection
3. Basic group behavior
4. Queue formation
5. Density-dependent walking speed
6. Gate capacity
7. Signage-based rerouting
8. One random infrastructure failure
9. Density and direction overlays
10. Multi-dimensional end-of-scenario scoring

Create focused scenarios to test emergence:

- Do equal-capacity exits develop uneven usage through herding?
- Can signage redistribute demand?
- Does a closed corridor create believable rerouting?
- Does excessive inflow create spillback?
- Does counterflow measurably reduce throughput?
- Can one-way routing predictably relieve congestion?

Do not expand until the crowd is fun to observe and manipulate.

## Architecture goals

Keep route selection, individual behavior, aggregation, pathfinding, signage response, safety calculation, scoring, scenario generation, event generation, and visualization independently swappable. Make the system data-driven: venue geometry, population traits, events, capacities, and objectives should be configurable rather than embedded in core simulation logic.

Do not assume each person needs a full behavior tree or expensive pathfinding every frame. Explore hierarchical pathfinding, flow fields, crowd zones, spatial partitioning, shared route planning, agent LOD, aggregate simulation at distance, GPU simulation, and event-driven updates. Close-range agents can behave individually while distant crowds use aggregates; transitions should preserve believable behavior.

## Emergence and learning

Scenarios should produce outcomes the designer did not script: a shortcut becomes popular, people follow a bad route, queues merge, an underused gate overloads, a train delay backs up a plaza, travelers switch stations, staff redirect one crowd into another, or a small disturbance creates a large congestion wave.

The target reaction is: “I didn’t expect that, but I understand why it happened.” The player should learn to reason about capacity, queues, bottlenecks, demand, throughput, flow direction, network effects, incentives, uncertainty, and resilience. Early they ask, “Why is this queue so long?” Later they ask, “If I release 2,000 people from the south gate, what happens to the rail platform six minutes from now?”

## Tone

Keep the game approachable, dynamic, and satisfying rather than sterile or like enterprise simulation software. Use readable systemic simulation, stylized crowds, lively venues, clear information design, and beautiful flow patterns. Serious safety concepts can be present while the experience still feels like a game.

## Success criteria

The prototype succeeds if:

1. Thousands of people simulate efficiently.
2. Crowds naturally create visible bottlenecks.
3. Small player actions meaningfully change global flow.
4. Downstream consequences are understandable.
5. Some behavior is unexpected but explainable.
6. Watching the crowd is satisfying even without input.
7. Players can diagnose why congestion occurred.
8. Multiple strategies can solve the same scenario.
9. Safety, efficiency, and experience create real tradeoffs.
10. The simulation can later scale toward much larger populations.

> The game is not about commanding a crowd. It is about designing and operating the system the crowd moves through.
