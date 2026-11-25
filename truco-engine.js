/* Truco argentino · motor de reglas (1 contra 1, con flor opcional, a 30 o 15 puntos).
 * Funciona en Node (servidor) y en el navegador. Es PURO: no guarda nada, recibe el estado y devuelve el nuevo.
 * El servidor es quien lo ejecuta; el navegador solo recibe la "vista" de cada jugador (sin las cartas del rival).
 *
 * Cartas: texto "NúmeroPalo", ej. "1E" (ancho de espada), "7O" (siete de oro). Palos: E espada, B basto, O oro, C copa.
 * Jugadores: 0 y 1.
 */
(function (root, factory) {
  if (typeof module === "object" && module.exports) module.exports = factory();
  else root.Truco = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  const SUITS = ["E", "B", "O", "C"];
  const NUMS = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12];
  const num = (c) => parseInt(c, 10);
  const suit = (c) => c.slice(-1);

  /* Jerarquía del truco (14 = la más fuerte) */
  function power(c) {
    if (c === "1E") return 14;
    if (c === "1B") return 13;
    if (c === "7E") return 12;
    if (c === "7O") return 11;
    const n = num(c);
    if (n === 3) return 10;
    if (n === 2) return 9;
    if (n === 1) return 8; // ases falsos (copa y oro)
    if (n === 12) return 7;
    if (n === 11) return 6;
    if (n === 10) return 5;
    if (n === 7) return 4; // sietes falsos (copa y basto)
    if (n === 6) return 3;
    if (n === 5) return 2;
    return 1; // 4
  }

  const ev = (c) => (num(c) <= 7 ? num(c) : 0); // valor para envido/flor: las figuras valen 0

  function envidoPts(cards) {
    let best = 0;
    for (const s of SUITS) {
      const v = cards.filter((c) => suit(c) === s).map(ev).sort((a, b) => b - a);
      if (v.length >= 2) best = Math.max(best, 20 + v[0] + v[1]);
    }
    if (best === 0) best = Math.max(...cards.map(ev));
    return best;
  }
  const isFlor = (cards) => cards.length === 3 && cards.every((c) => suit(c) === suit(cards[0]));
  const florPts = (cards) => 20 + cards.reduce((a, c) => a + ev(c), 0);

  function newDeck() {
    const d = [];
    for (const s of SUITS) for (const n of NUMS) d.push(n + s);
    return d;
  }
  function shuffle(a, rng) {
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  const clone = (o) => JSON.parse(JSON.stringify(o));
  const ENV_VAL = { envido: 2, real: 3 };

  /* ---------- creación ---------- */
  function newGame(opts, rng) {
    opts = Object.assign({ target: 30, flor: true, mano: 0 }, opts || {});
    const st = { opts: { target: opts.target, flor: !!opts.flor }, score: [0, 0], mano: opts.mano, over: false, winner: null, h: null, seq: 0 };
    startHand(st, rng);
    return st;
  }

  function startHand(st, rng, carry) {
    const d = shuffle(newDeck(), rng);
    const cards = [d.slice(0, 3), d.slice(3, 6)];
    st.seq++;
    st.h = {
      n: st.seq,
      mano: st.mano,
      cards,
      left: [cards[0].slice(), cards[1].slice()],
      table: [[], []],
      trick: 0,
      tricks: [],
      turn: st.mano,
      level: 1, // valor del truco ya aceptado (1 = sin cantar)
      owner: null, // quien puede subir el truco (el último que dijo quiero)
      pending: null, // {kind:'truco',by,level} | {kind:'envido',by,calls:[],stash}
      envidoDone: false,
      log: [],
    };
    const h = st.h;
    h.log.push({ e: "deal", mano: st.mano });
    (carry || []).forEach((x) => h.log.push(x)); // resultado de la mano anterior, para mostrarlo
    if (st.opts.flor) {
      const f = [isFlor(cards[0]), isFlor(cards[1])];
      if (f[0] || f[1]) {
        h.envidoDone = true; // la flor anula el envido
        if (f[0] && f[1]) {
          const a = florPts(cards[0]), b = florPts(cards[1]);
          const w = a > b ? 0 : b > a ? 1 : st.mano;
          h.log.push({ e: "flor2", pts: [a, b], winner: w, value: 6 });
          if (addScore(st, w, 6, rng, true)) return;
        } else {
          const w = f[0] ? 0 : 1;
          h.log.push({ e: "flor", p: w, pts: florPts(cards[w]), value: 3 });
          if (addScore(st, w, 3, rng, true)) return;
        }
      }
    }
  }

  /* suma puntos; devuelve true si terminó la partida */
  function addScore(st, p, pts, rng, noNext) {
    st.score[p] += pts;
    if (st.score[p] >= st.opts.target) {
      st.over = true;
      st.winner = p;
      return true;
    }
    return false;
  }

  function endHand(st, winner, pts, why, rng) {
    const h = st.h;
    h.log.push({ e: "handEnd", winner, pts, why });
    h.ended = { winner, pts, why };
    if (addScore(st, winner, pts, rng)) return;
    st.mano = 1 - st.mano;
    startHand(st, rng, [{ e: "handEnd", winner, pts, why }]);
  }

  /* ---------- resolución de bazas ---------- */
  function handWinner(tricks, mano) {
    if (tricks.length < 2) return null;
    const [a, b, c] = tricks;
    if (a !== -1 && a === b) return a;
    if (a === -1 && b !== -1) return b;
    if (b === -1 && a !== -1) return a;
    if (a === -1 && b === -1) return tricks.length === 3 ? (c !== -1 ? c : mano) : null;
    // a y b decididas y distintas
    return tricks.length === 3 ? (c !== -1 ? c : a) : null;
  }

  /* ---------- envido ---------- */
  function envidoRaises(calls) {
    const last = calls[calls.length - 1];
    const out = [];
    if (last === "envido") {
      if (calls.filter((c) => c === "envido").length < 2) out.push("envido");
      out.push("real", "falta");
    } else if (last === "real") out.push("falta");
    return out;
  }
  function faltaValue(st) {
    return Math.max(1, st.opts.target - Math.max(st.score[0], st.score[1]));
  }
  function envidoValue(st, calls, accepted) {
    if (accepted) {
      if (calls.includes("falta")) return faltaValue(st);
      return calls.reduce((a, c) => a + ENV_VAL[c], 0);
    }
    const prev = calls.slice(0, -1);
    return prev.length ? prev.reduce((a, c) => a + ENV_VAL[c], 0) : 1;
  }
  const envidoOpen = (h) => h.trick === 0 && !h.envidoDone && h.level === 1;

  /* ---------- acciones permitidas ---------- */
  function legalActions(st, p) {
    if (st.over || !st.h) return [];
    const h = st.h, pend = h.pending, out = [];
    if (pend) {
      if (p !== 1 - pend.by) return [];
      out.push({ type: "quiero" }, { type: "noquiero" });
      if (pend.kind === "truco") {
        if (pend.level < 4) out.push({ type: "truco", level: pend.level + 1 });
        if (envidoOpen(h) && pend.level === 2) for (const c of ["envido", "real", "falta"]) out.push({ type: "envido", call: c });
      } else {
        for (const c of envidoRaises(pend.calls)) out.push({ type: "envido", call: c });
      }
      return out;
    }
    if (p !== h.turn) return [];
    for (const c of h.left[p]) out.push({ type: "play", card: c });
    if (h.level < 4 && (h.level === 1 || h.owner === p)) out.push({ type: "truco", level: h.level + 1 });
    if (envidoOpen(h)) for (const c of ["envido", "real", "falta"]) out.push({ type: "envido", call: c });
    out.push({ type: "mazo" });
    return out;
  }

  const sameAction = (a, b) => a.type === b.type && a.card === b.card && a.call === b.call;

  /* ---------- aplicar una acción (devuelve un estado nuevo) ---------- */
  function act(state, p, action, rng) {
    if (state.over) throw new Error("La partida ya terminó.");
    const legal = legalActions(state, p);
    if (!legal.some((l) => sameAction(l, action))) throw new Error("Jugada no permitida ahora.");
    const st = clone(state);
    const h = st.h;
    const pend = h.pending;
    const log = (o) => h.log.push(o);

    switch (action.type) {
      case "play": {
        h.left[p].splice(h.left[p].indexOf(action.card), 1);
        h.table[p].push(action.card);
        log({ e: "play", p, card: action.card, trick: h.trick });
        if (h.table[0].length === h.table[1].length) {
          const a = power(h.table[0][h.trick]), b = power(h.table[1][h.trick]);
          const w = a > b ? 0 : b > a ? 1 : -1;
          h.tricks.push(w);
          log({ e: "trick", winner: w, trick: h.trick });
          h.trick++;
          const hw = handWinner(h.tricks, h.mano);
          if (hw !== null) {
            endHand(st, hw, h.level, "cartas", rng);
            return st;
          }
          h.turn = w === -1 ? h.mano : w;
        } else h.turn = 1 - p;
        return st;
      }
      case "mazo": {
        log({ e: "mazo", p });
        endHand(st, 1 - p, h.level, "mazo", rng);
        return st;
      }
      case "truco": {
        if (pend && pend.kind === "truco") {
          // el que responde sube: acepta lo anterior y canta el siguiente
          h.level = pend.level;
          h.owner = p;
          log({ e: "quiero", p });
          h.pending = { kind: "truco", by: p, level: pend.level + 1 };
        } else h.pending = { kind: "truco", by: p, level: h.level + 1 };
        log({ e: "truco", p, level: h.pending.level });
        return st;
      }
      case "envido": {
        if (!pend) h.pending = { kind: "envido", by: p, calls: [action.call], stash: null };
        else if (pend.kind === "truco") h.pending = { kind: "envido", by: p, calls: [action.call], stash: pend };
        else {
          pend.calls.push(action.call);
          pend.by = p;
        }
        log({ e: "envido", p, call: action.call });
        return st;
      }
      case "quiero":
      case "noquiero": {
        const acc = action.type === "quiero";
        const by = pend.by;
        if (pend.kind === "truco") {
          if (acc) {
            h.level = pend.level;
            h.owner = p;
            h.pending = null;
            log({ e: "quiero", p });
            return st;
          }
          log({ e: "noquiero", p });
          endHand(st, by, h.level, "noquiero", rng);
          return st;
        }
        // envido
        const value = envidoValue(st, pend.calls, acc);
        h.envidoDone = true;
        let winner;
        if (acc) {
          const a = envidoPts(h.cards[0]), b = envidoPts(h.cards[1]);
          winner = a > b ? 0 : b > a ? 1 : h.mano;
          log({ e: "envidoRes", acc: true, pts: [a, b], winner, value, calls: pend.calls, p });
        } else {
          winner = by;
          log({ e: "envidoRes", acc: false, winner, value, calls: pend.calls, p });
        }
        h.pending = pend.stash || null;
        if (addScore(st, winner, value, rng)) return st;
        return st;
      }
    }
    throw new Error("Acción desconocida.");
  }

  /* ---------- vista para un jugador (sin cartas del rival) ---------- */
  function view(state, p) {
    const h = state.h;
    const pend = h && h.pending;
    const lastLog = h ? h.log.slice(-40) : [];
    return {
      me: p,
      score: state.score,
      target: state.opts.target,
      over: state.over,
      winner: state.winner,
      hand: h && {
        n: h.n,
        mano: h.mano,
        mine: h.left[p],
        oppLeft: h.left[1 - p].length,
        table: h.table,
        trick: h.trick,
        tricks: h.tricks,
        turn: h.turn,
        level: h.level,
        owner: h.owner,
        pending: pend ? { kind: pend.kind, by: pend.by, level: pend.level, calls: pend.calls } : null,
        envidoDone: h.envidoDone,
        myEnvido: h.cards[p] && envidoPts(h.cards[p]),
        myDealt: h.cards[p],
        ended: h.ended || null,
        log: lastLog,
        logN: h.log.length,
      },
      legal: legalActions(state, p),
    };
  }

  /* ---------- bot ---------- */
  // skill (0-100): % de veces que la máquina juega "con cabeza". El resto elige una jugada legal al azar.
  function botAct(v, rng, skill) {
    const L = v.legal;
    if (!L.length) return null;
    if (skill != null && skill < 100 && rng() * 100 >= skill) {
      const pool = L.filter((a) => a.type !== "mazo");
      const from = pool.length ? pool : L;
      return from[Math.floor(rng() * from.length)];
    }
    const h = v.hand, me = v.me, r = rng();
    const find = (t, extra) => L.find((a) => a.type === t && (!extra || Object.keys(extra).every((k) => a[k] === extra[k])));
    const mine = h.mine.slice().sort((a, b) => power(b) - power(a));
    const pw = mine.map(power);
    const env = h.myEnvido + (h.mano === me ? 1 : 0);
    const won = h.tricks.filter((t) => t === me).length, lost = h.tricks.filter((t) => t === 1 - me).length;
    const score = (pw[0] || 0) * 0.6 + (pw[1] || 0) * 0.4 + (won > lost ? 3 : lost > won ? -3 : 0);
    const pend = h.pending;

    if (pend && pend.kind === "envido") {
      const opts = L.filter((a) => a.type === "envido").map((a) => a.call);
      const calls = pend.calls;
      const big = calls.length >= 2 || calls.includes("real");
      if (env >= 32 && opts.includes("falta") && r < 0.5) return find("envido", { call: "falta" });
      if (env >= 30 && opts.includes("real") && r < 0.6) return find("envido", { call: "real" });
      if (env >= 27 && opts.includes("envido") && r < 0.35) return find("envido", { call: "envido" });
      const need = calls.includes("falta") ? 30 : big ? 28 : 25;
      if (env >= need || r < 0.07) return find("quiero");
      return find("noquiero");
    }
    if (pend && pend.kind === "truco") {
      const lvl = pend.level;
      if (find("envido") && h.trick === 0 && env >= 30 && r < 0.4) return find("envido", { call: "envido" });
      const need = lvl === 2 ? 8 : lvl === 3 ? 10 : 12;
      if (score >= 12.5 && find("truco") && r < 0.55) return find("truco");
      if (score >= need || r < 0.06) return find("quiero");
      return find("noquiero");
    }
    // mi turno, sin nada pendiente
    if (find("envido") && h.trick === 0) {
      if (env >= 31 && r < 0.6) return find("envido", { call: "real" });
      if (env >= 27 && r < 0.7) return find("envido", { call: "envido" });
      if (env <= 22 && r < 0.05) return find("envido", { call: "envido" });
    }
    if (find("truco")) {
      if (score >= 11 && r < 0.6) return find("truco");
      if (score >= 9 && h.trick >= 1 && won > lost && r < 0.5) return find("truco");
      if (r < 0.03) return find("truco");
    }
    // elegir carta
    const opp = h.table[1 - me][h.trick];
    const plays = mine;
    if (opp) {
      const beat = plays.filter((c) => power(c) > power(opp)).sort((a, b) => power(a) - power(b));
      const tie = plays.filter((c) => power(c) === power(opp));
      if (beat.length) return { type: "play", card: beat[0] };
      if (tie.length && h.trick === 0 && r < 0.5) return { type: "play", card: tie[0] };
      return { type: "play", card: plays[plays.length - 1] };
    }
    if (h.trick === 0) {
      const pick = pw[0] >= 12 ? plays[Math.min(1, plays.length - 1)] : plays[0];
      return { type: "play", card: r < 0.35 ? plays[plays.length - 1] : pick };
    }
    return { type: "play", card: plays[0] };
  }

  return { SUITS, NUMS, power, envidoPts, florPts, isFlor, newGame, startHand, legalActions, act, view, botAct, handWinner, envidoValue, faltaValue, ENV_VAL };
});
