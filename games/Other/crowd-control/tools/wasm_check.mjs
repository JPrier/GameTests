// CI check: run the wasm build through the same glue the browser uses and print the state checksum
// after N ticks with the same commands as `crowd checksum`. Native and wasm must match exactly.
//   node tools/wasm_check.mjs scenarios/stadium_departure.json 2000 tools/check_commands.json
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
await import(join(here, "..", "web", "crowd_glue.js"));
const S = globalThis.CrowdSim;
const [scenarioPath, ticksArg, commandsPath] = process.argv.slice(2);
const ticks = Number(ticksArg || 2000);
const commands = commandsPath ? JSON.parse(readFileSync(commandsPath, "utf8")) : [];
await S.initBytes(readFileSync(join(here, "..", "web", "crowd_sim.wasm")));
if (S.status !== "ready") throw new Error("wasm failed: " + S.error);
const err = S.load(readFileSync(scenarioPath, "utf8"), "");
if (err) throw new Error("load failed: " + err);
let k = 0;
let tick = 0;
while (tick < ticks && !S.isOver()) {
  while (k < commands.length && commands[k].tick <= tick) {
    const r = JSON.parse(S.command(JSON.stringify(commands[k].cmd)));
    if (!r.ok) console.error("command rejected:", r.error);
    k++;
  }
  S.step(1);
  tick = S.tick();
}
console.log(S.checksum());
