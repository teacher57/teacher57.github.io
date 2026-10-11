// Digital tree evolution — a live, never-ending port of TechnoShaman's Pixilang project
// (https://dzen.ru/a/XmMwgmmclhNUOwU2). Same rules as the original; see the Projects card.
(() => {
  "use strict";

  const W = 256, H = 100, MAX_CELLS = 16000, GENES = 16;
  const LEVEL_BIAS = 6, ENERGY_WASTE = 13, ENERGY_FOR_START = 300, ENERGY_TO_GROW = 18;
  const SUN_LAYERS = 3, LIFE_MIN = 88, LIFE_SPREAD = 5, MUTATION_CHANCE = 4, STEPS_PER_GEN = 90;
  const FREE = 0, WOOD = 1, SPROUT = 2, SEED = 3;
  const PASTEL = 0.45;

  // Evolved genomes (generation ~1308) from a long desktop run, so the page starts with real trees.
  const SAVED = [[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,57,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,50,22,43,13,48,29,52,47,35,40,14,7,19,11,15,1,58,17,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,36,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,37,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,51,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57],[40,15,61,23,7,31,50,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,51,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57],[40,15,61,23,7,31,50,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,51,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57],[40,15,61,23,7,31,50,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,42,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,52,22,43,13,48,29,20,47,35,40,14,7,19,11,15,1,58,16,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,56,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,52,22,43,13,48,29,20,47,35,40,14,7,19,11,15,1,58,16,50,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,56,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,52,22,43,13,48,29,20,47,35,40,14,7,19,11,15,1,58,16,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,56,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,52,22,43,13,48,29,20,47,35,40,14,7,19,11,15,1,58,16,0,54,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,56,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,43,30,8,53,40,60,10,52,22,43,13,48,29,20,47,35,40,14,7,19,11,15,1,58,16,0,7,58,62,12,0,26,6,2,57,9,5,52,43,38,60,47,14,3,14,48,1,12,56,7,38,51,60,30,4,25,55],[40,15,61,23,7,31,50,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,51,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57],[40,15,61,23,7,31,50,29,30,8,53,40,22,10,26,16,43,13,8,29,52,47,26,31,14,7,19,11,15,14,53,16,51,44,58,53,12,0,26,6,54,57,9,5,21,43,38,46,13,14,3,14,48,1,12,36,7,38,51,60,30,4,25,57]];
  const SAVED_GEN = 1308;

  const rand = (n) => Math.floor(Math.random() * n);

  // ---- colors: hashed from the genome, so identical genomes share a color
  function genomeKey(g) { return g.map((v) => (v < GENES ? v : GENES)).join(","); }
  function genomeColor(g) {
    let h = 2166136261;
    for (const v of genomeKey(g)) { h ^= v.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
    const hue = (h % 360), sat = 55 + ((h >>> 9) % 40), light = 62 + ((h >>> 17) % 14);
    return hslToRgb(hue / 360, sat / 100, light / 100);
  }
  function hslToRgb(h, s, l) {
    const f = (n) => {
      const k = (n + h * 12) % 12, a = s * Math.min(l, 1 - l);
      return Math.round(255 * (l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))));
    };
    return [f(0), f(8), f(4)];
  }
  const pastel = (c) => c.map((v) => Math.round(v + (255 - v) * PASTEL));
  const css = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;

  // ---- world state (flat typed arrays; cell 0 is the sentinel of the circular cell list)
  const grid = new Int32Array(W * H);
  const cx = new Int16Array(MAX_CELLS), cy = new Int16Array(MAX_CELLS), gene = new Int8Array(MAX_CELLS);
  const state = new Uint8Array(MAX_CELLS), energy = new Int32Array(MAX_CELLS);
  const prev = new Int32Array(MAX_CELLS), next = new Int32Array(MAX_CELLS);
  const tree = new Array(MAX_CELLS).fill(null);
  let free = [], trees = [], step = 0, generation = 0, restarts = -1;

  function newTree(genome) {
    const color = genomeColor(genome);
    const t = { genome, color, wood: css(pastel(color)), seed: css(pastel(color.map((v) => 255 - v))),
                energy: ENERGY_FOR_START, mass: 1, age: LIFE_MIN + rand(LIFE_SPREAD), alive: true, cells: new Set() };
    trees.push(t);
    return t;
  }

  function newCell(x, y, g, st, t, before) {
    const c = free.pop();
    if (c === undefined) return 0;
    cx[c] = x; cy[c] = y; gene[c] = g; state[c] = st; energy[c] = 0; tree[c] = t;
    const p = prev[before];
    prev[c] = p; next[c] = before; next[p] = c; prev[before] = c;
    grid[y * W + x] = c;
    t.cells.add(c);
    return c;
  }

  function removeCell(c) {
    next[prev[c]] = next[c]; prev[next[c]] = prev[c];
    grid[cy[c] * W + cx[c]] = 0;
    state[c] = FREE; tree[c] = null;
    free.push(c);
  }

  function reset() {
    grid.fill(0); state.fill(FREE); prev.fill(0); next.fill(0); tree.fill(null);
    free = []; for (let i = MAX_CELLS - 1; i > 0; i--) free.push(i);
    trees = []; step = 0; restarts++;
    generation = SAVED_GEN;
    // plant the saved genomes evenly along the ground
    const k = SAVED.length;
    for (let i = 0; i < k; i++) {
      const t = newTree(SAVED[i].slice());
      newCell(Math.floor((i + 0.5) * W / k), 0, 0, SPROUT, t, 0);
    }
  }

  function sun() {
    for (let x = 0; x < W; x++) {
      let dose = SUN_LAYERS;
      for (let y = H - 1; y >= 0; y--) {
        const c = grid[y * W + x];
        if (!c) continue;
        const gain = dose * (y + LEVEL_BIAS);
        if (state[c] === SPROUT) energy[c] += gain; else tree[c].energy += gain;
        if (--dose === 0) break;
      }
    }
  }

  function kill(t) {
    for (const c of t.cells) removeCell(c);
    t.cells.clear(); t.alive = false;
  }

  function dieOfOldAge(t) {
    for (const c of [...t.cells].sort((a, b) => a - b)) {
      if (state[c] === SPROUT) {
        const child = newTree(t.genome.slice());
        if (rand(MUTATION_CHANCE) === 0) {
          child.genome[rand(64)] = rand(64);
          Object.assign(child, newTreeColors(child.genome));
        }
        state[c] = SEED; tree[c] = child; gene[c] = 0; energy[c] = 0;
        child.cells.add(c);
      } else {
        removeCell(c);
      }
    }
    t.cells.clear(); t.alive = false;
  }

  function newTreeColors(genome) {
    const color = genomeColor(genome);
    return { color, wood: css(pastel(color)), seed: css(pastel(color.map((v) => 255 - v))) };
  }

  function wasteEnergy() {
    for (const t of trees.slice()) {
      if (!t.alive) continue;
      t.energy -= t.mass * ENERGY_WASTE;
      t.age -= 1;
      if (t.energy < 0) kill(t);
      else if (t.age <= 0) dieOfOldAge(t);
    }
    trees = trees.filter((t) => t.alive);
  }

  function grow(c) {
    const nxt = next[c], st = state[c], x = cx[c], y = cy[c];
    if (st === SEED) {
      if (y === 0) state[c] = SPROUT;
      else if (grid[(y - 1) * W + x] === 0) { grid[y * W + x] = 0; grid[(y - 1) * W + x] = c; cy[c] = y - 1; }
      else {
        const t = tree[c];
        t.cells.delete(c); removeCell(c);
        if (t.cells.size === 0) t.alive = false;
      }
      return nxt;
    }
    if (st !== SPROUT || energy[c] < ENERGY_TO_GROW) return nxt;
    const t = tree[c], base = 4 * gene[c], g = t.genome;
    // up, left, right, down — upper branches claim space first
    const targets = [[g[base + 1], x, y + 1], [g[base], (x + W - 1) % W, y],
                     [g[base + 2], (x + 1) % W, y], [g[base + 3], x, y - 1]];
    for (const [v, tx, ty] of targets) {
      if (v < GENES && ty >= 0 && ty < H && grid[ty * W + tx] === 0) {
        if (newCell(tx, ty, v, SPROUT, t, c)) t.mass++;
      }
    }
    energy[c] = 0; state[c] = WOOD;
    return nxt;
  }

  function tick() {
    sun(); wasteEnergy();
    for (let c = next[0]; c !== 0;) c = grow(c);
    step++;
    if (step % STEPS_PER_GEN === 0) generation++;
    if (next[0] === 0) reset();  // life died out: start again from the saved trees
  }

  // ---- drawing
  const canvas = document.getElementById("trees-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const stats = document.getElementById("trees-stats");
  const speedBtn = document.getElementById("trees-speed");
  const SPEEDS = [1, 4, 16];
  let speedIdx = 0, visible = true, lastTick = 0;

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(w * H / W * dpr);
  }

  function draw() {
    const cw = canvas.width, ch = canvas.height, cell = cw / W;
    ctx.fillStyle = "#0f1117";
    ctx.fillRect(0, 0, cw, ch);
    const gap = cell >= 4 ? Math.max(1, cell * 0.08) : 0;
    for (let c = next[0]; c !== 0; c = next[c]) {
      const t = tree[c];
      ctx.fillStyle = state[c] === WOOD ? t.wood : state[c] === SEED ? t.seed : "#ffffff";
      const x0 = Math.floor(cx[c] * cell), y0 = Math.floor((H - 1 - cy[c]) * cell);
      const x1 = Math.floor((cx[c] + 1) * cell), y1 = Math.floor((H - cy[c]) * cell);
      ctx.fillRect(x0 + gap / 2, y0 + gap / 2, x1 - x0 - gap, y1 - y0 - gap);
    }
    stats.textContent = `generation ${generation} · ${trees.length} trees` + (restarts ? ` · restarted ${restarts}×` : "");
  }

  function frame(now) {
    // ~30 ticks per second at 1×, independent of the screen's refresh rate
    const ticks = Math.min(Math.floor((now - lastTick) / 33), 4) * SPEEDS[speedIdx];
    if (ticks > 0) {
      lastTick = now;
      for (let i = 0; i < ticks; i++) tick();
      if (visible) draw();
    }
    requestAnimationFrame(frame);
  }

  speedBtn.addEventListener("click", () => {
    speedIdx = (speedIdx + 1) % SPEEDS.length;
    speedBtn.textContent = `Speed ${SPEEDS[speedIdx]}×`;
  });
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(canvas);
  window.addEventListener("resize", () => { resize(); draw(); });

  reset();
  for (let i = 0; i < 400; i++) tick();  // fast-forward so visitors see grown trees, not seedlings
  resize();
  draw();
  requestAnimationFrame((now) => { lastTick = now; frame(now); });
})();
