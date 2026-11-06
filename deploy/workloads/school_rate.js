import { browser } from 'k6/browser';
import { check, sleep } from 'k6';
import { Trend, Counter, Rate, Gauge } from 'k6/metrics';
import exec from 'k6/execution';

const fixture = JSON.parse(open('/fixture/manifest.json'));
const base = __ENV.BASE_URL;
const mode = __ENV.MODE || 'pilot';
const users = Number(__ENV.USERS || 1);
const warmup = Number(__ENV.WARMUP_SECONDS || 0);
const duration = Number(__ENV.MEASURE_SECONDS || 10);
const intervalMs = 5000;
const maxStartLagMs = 250;
if (base !== 'https://instantflow-benchmark.iagobussoletti.com.br' || fixture.fixture !== 'school-v1')
  throw new Error('Refusing an unrecognized benchmark target or fixture');
if (mode !== 'fixed-rate' || !Number.isInteger(users) || users < 1 || users > fixture.actors.length ||
    !Number.isInteger(warmup) || warmup < 0 || warmup > 60 || warmup % 5 ||
    !Number.isInteger(duration) || duration < 5 || duration > 180 || duration % 5)
  throw new Error('Invalid fixed-rate workload parameters');
const offered = new Counter('offered_cycles');
const finished = new Counter('completed_cycles');
const missed = new Counter('missed_start_deadlines');
const overruns = new Counter('cycle_deadline_overruns');
const scheduleLag = new Trend('schedule_lag_ms', true);
const cycleLatency = new Trend('scheduled_cycle_ms', true);
const saveLatency = new Trend('save_ack_ms', true);
const windowStart = new Gauge('measurement_start_unix_ms');
const windowEnd = new Gauge('measurement_end_unix_ms');
const readLatency = new Trend('record_read_ms', true);
const completed = new Counter('business_saves');
const failures = new Rate('business_failure');
export const options = {
  hosts: { 'instantflow-benchmark.iagobussoletti.com.br': '134.65.245.186' },
  scenarios: { school: { executor: 'per-vu-iterations', vus: users, iterations: 1,
    maxDuration: String(warmup + duration + 180) + 's', options: { browser: { type: 'chromium' } } } },
  thresholds: { checks: ['rate==1'], business_failure: ['rate==0'] },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max', 'count'],
};
function assert(ok, name) {
  check(ok, { [name]: v => v });
  if (!ok) throw new Error(name);
}
async function ready(page) {
  await page.waitForFunction(() => !!document.querySelector('[data-phx-main].phx-connected'), {timeout: 15000});
}
async function login(account) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto(base + '/entrar');
  await page.locator('#login-form input[type=email]').fill(account.email);
  await page.locator('#login-form input[type=password]').fill(account.password);
  await Promise.all([page.waitForNavigation({waitUntil: 'domcontentloaded'}), page.locator('#login-submit').click()]);
  await page.waitForFunction(() => window.location.pathname.startsWith('/o/'), {timeout: 15000});
  await ready(page);
  return {context, page};
}
function record(id) {
  return base + '/o/' + fixture.organization_slug + '/processos/' + fixture.workflow_id + '/registros/' + id;
}
async function revision(page, section='request') {
  return Number(await page.locator('#section-form-' + section + ' input[name="observed[revision]"]').getAttribute('value'));
}
async function waitRevision(page, previous, section='request') {
  await page.waitForFunction(arg => {
    const field = document.querySelector('#section-form-' + arg.section + ' input[name="observed[revision]"]');
    return field && Number(field.value) > arg.previous;
  }, {timeout: 15000}, {previous, section});
}
async function waitValue(page, field, value) {
  await page.waitForFunction(arg => document.querySelector(arg.field)?.value === arg.value,
    {timeout:15000}, {field, value});
}
async function save(page, field, value, measured, section='request') {
  const before = await revision(page, section);
  await page.locator(field).fill(value);
  await page.waitForFunction(key => document.querySelector('#section-status-' + key)?.textContent.includes('Rascunho não salvo'),
    {timeout:15000}, section);
  const start = Date.now();
  await page.locator('#save-' + section).click();
  await waitRevision(page, before, section);
  if (measured) {
    saveLatency.add(Date.now()-start);
    completed.add(1);
  }
  return start;
}
export function setup() { return {start_ms: Date.now() + 30000}; }
// Each actor has one in-flight cycle and a fixed, staggered arrival every 5s.
// Missing a slot fails the run; there is no dropped work or catch-up burst.
export function slotPlan(start, actorIndex, actorCount, warmupSeconds, measuredSeconds) {
  const count = (warmupSeconds + measuredSeconds) * 1000 / intervalMs;
  return Array.from({length: count}, (_, index) => ({
    at: start + actorIndex * intervalMs / actorCount + index * intervalMs,
    measured: index * intervalMs >= warmupSeconds * 1000,
  }));
}
async function fixedRate(schedule) {
  const actor = fixture.actors[exec.vu.idInTest - 1];
  const {context, page} = await login(actor);
  try {
    if (Date.now() > schedule.start_ms)
      throw new Error('Runner could not initialize browsers before the scheduled window');
    windowStart.add(schedule.start_ms + warmup * 1000);
    windowEnd.add(schedule.start_ms + (warmup + duration) * 1000);
    missed.add(0); overruns.add(0);
    let cycle = 0, lastValue = '';
    const slots = slotPlan(schedule.start_ms, exec.vu.idInTest - 1, users, warmup, duration);
    for (const slot of slots) {
      if (Date.now() < slot.at) sleep((slot.at - Date.now()) / 1000);
      const lag = Date.now() - slot.at;
      scheduleLag.add(lag);
      offered.add(1);
      if (lag > maxStartLagMs) {
        missed.add(1);
        throw new Error('Fixed-rate start deadline missed');
      }
      const readStart = Date.now();
      await page.goto(record(actor.ticket_id));
      await ready(page);
      await page.locator('#section-form-request').waitFor({state:'visible'});
      if (lastValue) assert(await page.locator('#section-request-location').inputValue() === lastValue, 'fresh authorized read retains last saved value');
      if (slot.measured) readLatency.add(Date.now() - readStart);
      lastValue = 'Sala taxa fixa ' + exec.vu.idInTest + ' ciclo ' + (++cycle);
      // Include every operation offered in the measured cohort, even when its
      // acknowledgement crosses the nominal window end. Final reads drain it.
      await save(page, '#section-request-location', lastValue, slot.measured);
      finished.add(1);
      if (slot.measured) cycleLatency.add(Date.now() - slot.at);
      if (Date.now() > slot.at + intervalMs) {
        overruns.add(1);
        throw new Error('Fixed-rate cycle completion deadline missed');
      }
      failures.add(false);
    }
    await page.goto(record(actor.ticket_id));
    await ready(page);
    await waitValue(page, '#section-request-location', lastValue);
    assert(true, 'final fresh read confirms persisted save');
  } finally { await context.close(); }
}
export default async function(schedule) {
  try {
    await fixedRate(schedule);
  } catch (error) {
    failures.add(true);
    throw error;
  }
}
export function handleSummary(data) {
  return {'/results/summary.json': JSON.stringify(data, null, 2)};
}
