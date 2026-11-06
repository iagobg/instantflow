// node --experimental-vm-modules deploy/test_school_rate.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

async function workload({readMs = 1000, saveMs = 500, sleepLag = 0, persist = true} = {}) {
  let now = 0, saved = '', displayed = '', revision = 0, closed = false;
  const samples = new Map();
  const checks = [];
  const metric = class {
    constructor(name) { this.name = name; samples.set(name, []); }
    add(value) { samples.get(this.name).push(value); }
  };
  const page = {
    async goto(url) {
      if (url.includes('/registros/')) { now += readMs; displayed = saved; }
    },
    async waitForNavigation() {},
    async waitForFunction(_fn, _options, arg) {
      if (arg && typeof arg === 'object' && 'previous' in arg) assert.ok(revision > arg.previous);
      if (arg && typeof arg === 'object' && 'field' in arg) assert.equal(displayed, arg.value);
    },
    locator(selector) {
      return {
        async fill(value) { if (selector === '#section-request-location') displayed = value; },
        async click() {
          if (selector === '#save-request') {
            now += saveMs;
            if (persist) saved = displayed;
            revision++;
          }
        },
        async waitFor() {},
        async inputValue() { return displayed; },
        async getAttribute() { return String(revision); },
      };
    },
  };
  const fixture = {fixture: 'school-v1', organization_slug: 'synthetic', workflow_id: 1,
    actors: Array.from({length: 10}, (_, i) => ({ticket_id: i + 1, email: 'synthetic', password: 'synthetic'}))};
  const context = vm.createContext({
    __ENV: {BASE_URL: 'https://instantflow-benchmark.iagobussoletti.com.br', MODE: 'fixed-rate',
      USERS: '10', WARMUP_SECONDS: '5', MEASURE_SECONDS: '10'},
    open: () => JSON.stringify(fixture), Date: {now: () => now},
  });
  const imports = {
    'k6/browser': {browser: {async newContext() {
      return {async newPage() { return page; }, async close() { closed = true; }};
    }}},
    'k6': {check(value, predicates) {
      const ok = Object.values(predicates).every(predicate => predicate(value));
      checks.push(ok); return ok;
    }, sleep(seconds) { now += seconds * 1000 + sleepLag; }},
    'k6/metrics': {Trend: metric, Counter: metric, Rate: metric, Gauge: metric},
    'k6/execution': {default: {vu: {idInTest: 10}}},
  };
  const module = new vm.SourceTextModule(fs.readFileSync(path.join(__dirname, 'workloads/school_rate.js'), 'utf8'), {context});
  await module.link(async name => {
    const exports = imports[name];
    assert.ok(exports, 'Only reviewed k6 imports are available');
    return new vm.SyntheticModule(Object.keys(exports), function() {
      for (const [key, value] of Object.entries(exports)) this.setExport(key, value);
    }, {context});
  });
  await module.evaluate();
  return {module, samples, checks, closed: () => closed, now: () => now};
}

const sum = values => values.reduce((a, b) => a + b, 0);

test('all actors receive staggered slots and the complete measured cohort', async () => {
  const w = await workload();
  const slots = [];
  for (let actor = 0; actor < 10; actor++) {
    const plan = w.module.namespace.slotPlan(1000, actor, 10, 60, 180);
    assert.equal(plan.length, 48);
    assert.equal(plan.filter(slot => slot.measured).length, 36);
    slots.push(...plan.map(slot => slot.at));
  }
  slots.sort((a, b) => a - b);
  assert.equal(new Set(slots).size, 480);
  assert.ok(slots.slice(1).every((at, index) => at - slots[index] === 500));
});

test('late-window acknowledgements remain measured and every save gets a fresh read', async () => {
  const w = await workload();
  await w.module.namespace.default({start_ms: 1000});
  assert.equal(sum(w.samples.get('offered_cycles')), 3);
  assert.equal(sum(w.samples.get('completed_cycles')), 3);
  assert.equal(sum(w.samples.get('business_saves')), 2);
  assert.equal(w.samples.get('save_ack_ms').length, 2);
  assert.equal(w.samples.get('record_read_ms').length, 2);
  assert.equal(w.checks.length, 3);
  assert.ok(w.checks.every(Boolean));
  assert.ok(w.now() > w.samples.get('measurement_end_unix_ms')[0]);
  assert.ok(w.closed());
});

test('missed starts fail without a catch-up burst and close the browser context', async () => {
  const w = await workload({sleepLag: 300});
  await assert.rejects(w.module.namespace.default({start_ms: 1000}), /start deadline/);
  assert.equal(sum(w.samples.get('offered_cycles')), 1);
  assert.equal(sum(w.samples.get('completed_cycles')), 0);
  assert.equal(sum(w.samples.get('missed_start_deadlines')), 1);
  assert.ok(w.samples.get('business_failure').includes(true));
  assert.ok(w.closed());
});

test('an overlong cycle fails instead of silently reducing offered load', async () => {
  const w = await workload({readMs: 4500, saveMs: 1000});
  await assert.rejects(w.module.namespace.default({start_ms: 1000}), /completion deadline/);
  assert.equal(sum(w.samples.get('offered_cycles')), 1);
  assert.equal(sum(w.samples.get('cycle_deadline_overruns')), 1);
  assert.ok(w.closed());
});

test('an acknowledgement without persistence fails on the next fresh read', async () => {
  const w = await workload({persist: false});
  await assert.rejects(w.module.namespace.default({start_ms: 1000}), /retains last saved value/);
  assert.ok(w.checks.includes(false));
  assert.ok(w.samples.get('business_failure').includes(true));
  assert.ok(w.closed());
});
