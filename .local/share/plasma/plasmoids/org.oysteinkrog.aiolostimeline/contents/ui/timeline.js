// The pool capacity projection behind the aiolos Accounts Timeline, ported from
// crates/dashboard/assets/accounts/pool_forecast_time.js (renderTimeline) and pool_core.js
// (getWindowDurMs, computeBurnRatePerMs) in the aiolos repo, as of v2.2.2. Keep the maths the
// same as there, so this window and the dashboard draw the same line.
//
// Input is the "pool" object from aiolostimeline-fetch: {nowMs, accounts: [{name, paused,
// routable, mx, windows: [{label, pct, resets}], rates: {h1, h24, d7}}]}.
.pragma library

var HOUR = 3600000;
var DAY = 24 * HOUR;
var SPAN = 7 * DAY;
var PROJS = ["optimistic", "current", "24h", "7d"];
var SUBCAPS = ["Opus (Wk)", "Sonnet (Wk)", "Fable (Wk)", "Opus+Other (Wk)"];

function windowDurMs(label) {
    if (label === "5-hour")
        return 5 * HOUR;
    if (label === "Daily")
        return DAY;
    if (label === "Weekly" || SUBCAPS.indexOf(label) >= 0)
        return 7 * DAY;
    if (label === "Monthly" || label === "Extra (Mo)")
        return 30 * DAY;
    return DAY;
}

// Burn rate in percent per ms for one window under one projection.
function burnRate(now, pair, proj) {
    if (proj === "optimistic")
        return 0;
    var dur = windowDurMs(pair.label);
    var elapsed = pair.resets ? dur - (pair.resets - now) : dur;
    if (elapsed <= 0)
        elapsed = dur;
    var current = pair.pct / elapsed;
    if (proj === "current")
        return current;
    var rr = pair.rates || {};
    var h1 = rr.h1 || 0;
    if (h1 <= 0)
        return current;
    var cap = 100 / dur;
    if (proj === "24h")
        return Math.min(current * (rr.h24 || 0) / h1, cap);
    if (proj === "7d")
        return Math.min(current * (rr.d7 || 0) / h1, cap);
    return current;
}

// mode "all" counts the model sub-caps too, "routable" only 5-hour and Weekly.
// accts "all" leaves out paused accounts only, "routable" also the blocked ones.
function model(pool, mode, accts) {
    mode = mode || "all";
    accts = accts || "all";
    var now = pool.nowMs;
    var accounts = [];
    (pool.accounts || []).forEach(function (a) {
        if (a.paused)
            return;
        if (accts === "routable" && a.routable === false)
            return;
        accounts.push(a);
    });
    var maxNx = 0;
    accounts.forEach(function (a) {
        maxNx += a.mx;
    });
    var pairs = [];
    accounts.forEach(function (a, ai) {
        (a.windows || []).forEach(function (w) {
            if (w.label === "Extra (Mo)")
                return;
            if (mode === "routable" && SUBCAPS.indexOf(w.label) >= 0)
                return;
            pairs.push({acct: ai, label: w.label, pct: w.pct, resets: w.resets, rates: a.rates});
        });
    });
    // Reset events: 5-hour and Daily windows recur, the rest reset once.
    var events = [];
    pairs.forEach(function (p, i) {
        if (!p.resets)
            return;
        var t = p.resets, dur = windowDurMs(p.label), recurring = p.label === "5-hour" || p.label === "Daily", n = 0;
        while (t <= now + SPAN && n++ < 60) {
            if (t > now)
                events.push({ms: t, idx: i});
            if (recurring)
                t += dur;
            else
                break;
        }
    });
    events.sort(function (a, b) {
        return a.ms - b.ms;
    });
    return {now: now, end: now + SPAN, maxNx: maxNx, accounts: accounts, pairs: pairs, events: events};
}

// A walker over one projection: pct(t) for t moving forward, applying resets as it goes.
function walker(m, proj) {
    var rates = m.pairs.map(function (p) {
        return burnRate(m.now, p, proj);
    });
    var pct = m.pairs.map(function (p) {
        return p.pct;
    });
    var last = m.pairs.map(function () {
        return m.now;
    });
    var next = 0;
    function freeAt(t) {
        var acctMax = m.accounts.map(function () {
            return -1;
        });
        m.pairs.forEach(function (p, i) {
            var d = Math.min(100, pct[i] + rates[i] * (t - last[i]));
            if (d > acctMax[p.acct])
                acctMax[p.acct] = d;
        });
        var nx = 0;
        m.accounts.forEach(function (a, ai) {
            nx += acctMax[ai] < 0 ? a.mx : a.mx * Math.max(0, 1 - acctMax[ai] / 100);
        });
        return nx / m.maxNx * 100;
    }
    function apply(e) {
        pct[e.idx] = 0;
        last[e.idx] = e.ms;
    }
    return {
        freeAt: freeAt,
        // Applies the next reset only, as the dashboard does: two resets at the same time
        // draw two steps.
        resetNext: function () {
            apply(m.events[next++]);
        },
        // Applies every reset at or before t. Returns the events applied.
        resetTo: function (t) {
            var done = [];
            while (next < m.events.length && m.events[next].ms <= t) {
                var e = m.events[next++];
                apply(e);
                done.push(e);
            }
            return done;
        }
    };
}

// The stepped line as the dashboard draws it: [{t, pct}], flat until a reset, then down to
// the value just before it and up to the value after it.
function series(m, proj) {
    var w = walker(m, proj);
    var pts = [{t: m.now, pct: w.freeAt(m.now)}];
    m.events.forEach(function (e) {
        pts.push({t: e.ms, pct: w.freeAt(e.ms)});
        w.resetNext();
        pts.push({t: e.ms, pct: w.freeAt(e.ms)});
    });
    pts.push({t: m.end, pct: w.freeAt(m.end)});
    return pts;
}

// Free pool capacity at time t under one projection, in percent.
function valueAt(m, proj, t) {
    var w = walker(m, proj);
    w.resetTo(t);
    return w.freeAt(t);
}

// The first time free capacity drops below `pct`, sampled every 15 min, or null.
function crossing(m, proj, pct) {
    var w = walker(m, proj), step = 15 * 60000;
    for (var t = m.now; t <= m.end; t += step) {
        w.resetTo(t);
        if (w.freeAt(t) < pct)
            return t;
    }
    return null;
}

// Resets within `radius` ms of t, nearest first: [{ms, name, label}].
function resetsNear(m, t, radius) {
    return m.events.filter(function (e) {
        return Math.abs(e.ms - t) <= radius;
    }).sort(function (a, b) {
        return Math.abs(a.ms - t) - Math.abs(b.ms - t);
    }).map(function (e) {
        var p = m.pairs[e.idx];
        return {ms: e.ms, name: m.accounts[p.acct].name, label: p.label};
    });
}

// The Room chart: aiolos's own forecast of usable capacity (pool.capacity, in Nx, one value
// per 5-hour slot from now) and the recorded past from the fetch's history file
// (history: [[time_ms, now_avail, weekly_room], ...], the last 48 hours).
var ROOM_PAST = 48 * HOUR;
// A gap longer than this between two samples means the fetch was not running: the line
// breaks there instead of drawing a straight line across.
var ROOM_GAP = 10 * 60000;

// A round step so that `parts` steps reach at least `max`: 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 8
// times a power of 10.
function niceStep(max, parts) {
    var raw = Math.max(max, 1e-9) / parts;
    var p = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10));
    var steps = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
    for (var i = 0; i < steps.length; i++)
        if (steps[i] * p >= raw)
            return steps[i] * p;
    return 10 * p;
}

function roomModel(pool, history) {
    var cap = pool && pool.capacity;
    if (!cap || !cap.slots || !cap.slots.length)
        return null;
    var now = pool.nowMs, slotMs = cap.slotMs || 5 * HOUR;
    // Forecast: each slot's value holds until the next slot. That is the lower bound, since
    // capacity only rises inside a slot as accounts reset.
    var forecast = cap.slots.map(function (v, s) {
        return {t: now + s * slotMs, v: v};
    }).filter(function (p) {
        return p.t <= now + SPAN;
    });
    var past = (history || []).filter(function (h) {
        return h[0] >= now - ROOM_PAST && h[0] <= now;
    }).map(function (h) {
        return {t: h[0], v: h[1], room: h[2]};
    });
    var vMax = cap.ceiling || 0, rMax = 0;
    forecast.forEach(function (p) {
        vMax = Math.max(vMax, p.v);
    });
    past.forEach(function (p) {
        vMax = Math.max(vMax, p.v);
        rMax = Math.max(rMax, p.room);
    });
    rMax = Math.max(rMax, pool.weeklyRoom || 0, 100);
    vMax = Math.max(vMax, 1);
    var parts = 4, vStep = niceStep(vMax * 1.04, parts), rStep = niceStep(rMax * 1.04, parts);
    return {
        now: now,
        start: now - ROOM_PAST,
        end: now + SPAN,
        slotMs: slotMs,
        nowAvail: cap.nowAvail,
        ceiling: cap.ceiling,
        forecast: forecast,
        past: past,
        parts: parts,
        vStep: vStep,
        vTop: vStep * parts,
        rStep: rStep,
        rTop: rStep * parts
    };
}

// The forecast value at t (a slot holds until the next one), or null before now.
function roomForecastAt(rm, t) {
    if (t < rm.now)
        return null;
    var s = Math.min(rm.forecast.length - 1, Math.floor((t - rm.now) / rm.slotMs));
    return rm.forecast[s].v;
}

// The recorded sample nearest to t, or null if none lies within ROOM_GAP of it.
function roomPastAt(rm, t) {
    var best = null;
    rm.past.forEach(function (p) {
        if (Math.abs(p.t - t) <= ROOM_GAP && (best === null || Math.abs(p.t - t) < Math.abs(best.t - t)))
            best = p;
    });
    return best;
}

// The next reset of a window with this label that has some use on it (pct > 0), over the
// accounts that are not paused: {ms, name}, or null.
function nextReset(pool, label) {
    var best = null;
    (pool.accounts || []).forEach(function (a) {
        if (a.paused)
            return;
        (a.windows || []).forEach(function (w) {
            if (w.label !== label || !w.resets || w.resets <= pool.nowMs || !(w.pct > 0))
                return;
            if (best === null || w.resets < best.ms)
                best = {ms: w.resets, name: a.name};
        });
    });
    return best;
}
