// Fixed functional burst with isolated cookie contexts and explicit barriers.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.argv[5]);
const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const output = process.argv[3];
const base = 'https://instantflow-benchmark.iagobussoletti.com.br';
const users = Number(process.argv[4]);
const rounds = 3;
if (fixture.fixture !== 'school-v1' || ![2, 5].includes(users))
  throw new Error('Refusing unsupported contention workload parameters');
const accounts = fixture.actors.slice(0, users);
if (new Set(accounts.map(a => a.user_id)).size !== users ||
    !Number.isInteger(fixture.contention_ticket_id) ||
    fixture.actors.some(a => a.ticket_id === fixture.contention_ticket_id))
  throw new Error('Invalid shared-record fixture');
const record = base + '/o/' + fixture.organization_slug + '/processos/' +
  fixture.workflow_id + '/registros/' + fixture.contention_ticket_id;
const metrics = { checks: { values: { passes: 0, fails: 0 } } };
const checkResults = {};
class Counter {
  constructor(name) { this.values = { count: 0 }; metrics[name] = { values: this.values }; }
  add(value) { this.values.count += value; }
}
class Rate {
  constructor(name) { this.values = { rate: 0 }; this.count = 0; this.failures = 0; metrics[name] = { values: this.values }; }
  add(failed) { this.count++; this.failures += Number(failed); this.values.rate = this.failures / this.count; }
}
class Trend {
  constructor(name) { this.values = []; metrics[name] = { samples: this.values }; }
  add(value) { this.values.push(value); }
}
class CheckError extends Error {}
const saves = new Counter('business_saves');
const failures = new Rate('business_failure');
const conflicts = new Counter('expected_conflicts');
const preserved = new Counter('preserved_drafts');
const completedRounds = new Counter('contention_rounds');
const reapplied = new Counter('explicit_reapplications');
const independent = new Counter('independent_section_saves');
const transitions = new Counter('terminal_transitions');
const roundLatency = new Trend('contention_round_ms', true);
function assert(value, label) {
  checkResults[label] ||= { name: label, passes: 0, fails: 0 };
  const outcome = value ? 'passes' : 'fails';
  checkResults[label][outcome]++; metrics.checks.values[outcome]++;
  if (!value) throw new CheckError(label);
}
async function ready(page) {
  await page.waitForFunction(() => !!document.querySelector('[data-phx-main].phx-connected'), null, { timeout: 15000 });
}
async function login(browser, account) {
  const context = await browser.newContext();
  const page = await context.newPage();
  const response = await page.goto(base + '/entrar');
  const address = await response.serverAddr();
  assert(response.status() === 200 && address.ipAddress === '134.65.245.186', 'browser uses the verified direct-origin HTTPS route');
  await page.locator('#login-form input[type=email]').fill(account.email);
  await page.locator('#login-form input[type=password]').fill(account.password);
  await Promise.all([page.waitForURL('**/o/**'), page.locator('#login-submit').click()]);
  await ready(page);
  await page.goto(record); await ready(page);
  return { context, page };
}
async function revision(page, section = 'request') {
  return Number(await page.locator('#section-form-' + section + ' input[name="observed[revision]"]').getAttribute('value'));
}
async function draft(page, section, field, value) {
  await page.locator(field).fill(value);
  await page.waitForFunction(key => document.querySelector('#section-status-' + key)?.textContent.includes('Rascunho não salvo'),
    section, { timeout: 15000 });
}
async function submit(page, section) {
  // Dispatch all prepared forms even if a peer notification arrives before a
  // slower click. This exercises stale-command rejection in the real LiveView.
  await page.evaluate(key => document.querySelector('#section-form-' + key)
    .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })), section);
}
async function settled(page, section, previous) {
  await page.waitForFunction(arg => {
    const form = document.querySelector('#section-form-' + arg.section);
    return form && !form.classList.contains('phx-submit-loading') &&
      (document.querySelector('#conflict-' + arg.section) ||
       Number(form.querySelector('input[name="observed[revision]"]').value) > arg.previous);
  }, { section, previous }, { timeout: 15000 });
}
async function fresh(page) { await page.goto(record); await ready(page); }
async function saved(page, section, previous) {
  await settled(page, section, previous);
  assert(await page.locator('#conflict-' + section).count() === 0, 'independent or reconciled write has no conflict');
  assert(await revision(page, section) === previous + 1, 'accepted write advances its section exactly once');
  saves.add(1);
}

async function run() {
  const browser = await chromium.launch({ headless: true, executablePath: process.argv[6],
    args: ['--host-resolver-rules=MAP instantflow-benchmark.iagobussoletti.com.br 134.65.245.186'] });
  const clients = [];
  try {
    // Sequential setup is outside the contention rounds; the operations below
    // run concurrently across independent cookie contexts and LiveViews.
    for (const account of accounts) clients.push(await login(browser, account));
    const teacher = await login(browser, fixture.teacher);
    assert(await teacher.page.locator('#section-form-request').count() === 0 &&
      await teacher.page.locator('#transition-approve').count() === 0,
      'requester remains unable to edit or approve during review');
    await teacher.context.close();
    let lastWinner = 0;
    let lastLoser = 1;
    for (let round = 1; round <= rounds; round++) {
      await Promise.all(clients.map(c => fresh(c.page)));
      const revisions = await Promise.all(clients.map(c => revision(c.page)));
      assert(revisions.every(r => r === revisions[0]), 'editors start from the same section revision');
      const values = clients.map((_, i) => 'Contention round ' + round + ' editor ' + i);
      await Promise.all(clients.map((c, i) => draft(c.page, 'request', '#section-request-location', values[i])));
      const started = Date.now();
      await Promise.all(clients.map(c => submit(c.page, 'request')));
      await Promise.all(clients.map(c => settled(c.page, 'request', revisions[0])));
      roundLatency.add(Date.now() - started);
      const outcomes = await Promise.all(clients.map(async (c, i) => ({
        index: i, conflict: await c.page.locator('#conflict-request').count() > 0,
        revision: await revision(c.page), value: await c.page.locator('#section-request-location').inputValue(),
      })));
      const winners = outcomes.filter(o => !o.conflict);
      assert(winners.length === 1, 'same-section contention accepts exactly one writer');
      const winner = winners[0]; lastWinner = winner.index;
      assert(winner.revision === revisions[0] + 1 && winner.value === values[winner.index],
        'winning revision contains exactly the winning draft');
      saves.add(1);
      for (const loser of outcomes.filter(o => o.conflict)) {
        assert(loser.revision === revisions[0] && loser.value === values[loser.index],
          'conflicting writer retains its original revision and draft');
        conflicts.add(1); preserved.add(1); lastLoser = loser.index;
      }
      // A clean fresh read confirms storage independently of the dirty peers.
      await fresh(clients[winner.index].page);
      assert(await revision(clients[winner.index].page) === revisions[0] + 1 &&
        await clients[winner.index].page.locator('#section-request-location').inputValue() === values[winner.index],
        'fresh authorized read confirms the sole committed winner');
      completedRounds.add(1);
    }
    const loser = clients[lastLoser].page;
    const chosen = await loser.locator('#section-request-location').inputValue();
    await loser.locator('#conflict-request button[phx-click=compare]').click();
    await loser.locator('#comparison-request button[phx-click=reapply]').click();
    await loser.locator('#conflict-request').waitFor({ state: 'hidden' });
    const current = await revision(loser);
    await submit(loser, 'request'); await saved(loser, 'request', current);
    reapplied.add(1);
    const peer = clients[lastWinner].page;
    await peer.waitForFunction(value => document.querySelector('#section-request-location')?.value === value,
      chosen, { timeout: 15000 });
    assert(await peer.locator('#transition-approve').isDisabled(), 'clean peer must review new data before approval');
    await fresh(loser);
    assert(await loser.locator('#section-request-location').inputValue() === chosen, 'explicit reconciliation persists the chosen draft');

    const a = clients[0].page, b = clients[1].page;
    await Promise.all([fresh(a), fresh(b)]);
    const beforeA = await revision(a), beforeB = await revision(b, 'logistics');
    await Promise.all([
      draft(a, 'request', '#section-request-location', 'Shared room after independent writes'),
      draft(b, 'logistics', '#section-logistics-resources', 'Independent resources retained'),
    ]);
    await Promise.all([submit(a, 'request'), submit(b, 'logistics')]);
    await Promise.all([saved(a, 'request', beforeA), saved(b, 'logistics', beforeB)]);
    independent.add(2);
    await fresh(a);
    assert(await a.locator('#section-request-location').inputValue() === 'Shared room after independent writes' &&
      await a.locator('#section-logistics-resources').inputValue() === 'Independent resources retained',
      'fresh read retains both concurrent independent-section writes');
    await a.locator('#transition-approve').click();
    await a.locator('#transition-approve').waitFor({ state: 'detached' });
    await fresh(a);
    assert(await a.locator('#section-form-request').count() === 0 &&
      await a.locator('#section-form-logistics').count() === 0 &&
      await a.locator('#transition-approve').count() === 0,
      'fresh-state approval persists a terminal read-only record');
    transitions.add(1); failures.add(false);
  } catch (error) {
    failures.add(true);
    process.exitCode = 1;
    // Playwright error logs can contain input values. Keep diagnostics private,
    // and expose only assertion names/error classes in the aggregate summary.
    fs.writeFileSync(path.join(output, 'failure-private.json'), JSON.stringify({ message: error.message }), { mode: 0o600 });
    metrics.failure = error instanceof CheckError ? error.message : error.name;
  } finally {
    await browser.close();
    fs.writeFileSync(path.join(output, 'summary.json'), JSON.stringify({ metrics,
      root_group: { groups: [], checks: Object.values(checkResults) } }, null, 2), { mode: 0o600 });
  }
}
run().catch(() => { console.error('Browser driver failed; confirm guarded restoration.'); process.exitCode = 1; });
