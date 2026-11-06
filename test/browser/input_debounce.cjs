// Requires the disposable server in input_debounce_server.exs and an installed
// Playwright-compatible driver. PLAYWRIGHT_MODULE may name an existing installation.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const fixture = JSON.parse(fs.readFileSync(path.join(root, '.local/input-debounce-fixture.json')));
const base = 'http://127.0.0.1:4011';
const checks = [];
const counts = {};

function observe(page) {
  const sent = [];
  const waiters = [];
  page.on('websocket', ws => {
    const pending = new Map();
    ws.on('framesent', ({payload}) => {
      const frame = JSON.parse(payload);
      if (frame[3] !== 'event') return;
      const event = frame[4].event;
      sent.push(event);
      pending.set(frame[1], event);
    });
    ws.on('framereceived', ({payload}) => {
      const frame = JSON.parse(payload);
      if (frame[3] !== 'phx_reply') return;
      const event = pending.get(frame[1]);
      pending.delete(frame[1]);
      const index = waiters.findIndex(w => w.event === event);
      if (index >= 0) waiters.splice(index, 1)[0].resolve();
    });
  });
  return {
    sent,
    ack(event) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`Missing ${event} acknowledgement`)), 10000);
        waiters.push({event, resolve: () => {clearTimeout(timer); resolve();}});
      });
    }
  };
}

async function open(context, key) {
  const page = await context.newPage();
  const events = observe(page);
  await page.goto(`${base}/o/horizonte/solicitacoes/${fixture.records[key]}`);
  await page.locator('[data-phx-main].phx-connected').waitFor();
  await page.locator('#section-form-request').waitFor();
  return {page, events};
}

async function dirty(page, value) {
  await page.locator('#section-request-summary').fill(value);
  await page.locator('#section-request-summary[phx-debounce="250"]').waitFor();
  await page.locator('#section-form-request:not(.phx-change-loading)').waitFor();
  // LiveView finishes restoring locked inputs on the render cycle after its
  // acknowledgement. Measure the subsequent burst after that initial edit settles.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function revision(page) {
  return Number(await page.locator('#section-form-request input[name="observed[revision]"]').inputValue());
}

async function saved(page, previous) {
  await page.waitForFunction(old =>
    Number(document.querySelector('#section-form-request input[name="observed[revision]"]').value) > old,
  previous);
}

(async () => {
  const browser = await chromium.launch({headless: true});
  const errors = [];
  try {
    const context = await browser.newContext();
    context.on('page', page => page.on('pageerror', e => errors.push(e.message)));
    const login = await context.newPage();
    await login.goto(`${base}/entrar`);
    await login.locator('#login-form input[type=email]').fill(fixture.email);
    await login.locator('#login-form input[type=password]').fill('fictional-password-123');
    await Promise.all([login.waitForURL('**/o/**'), login.locator('#login-submit').click()]);
    await login.close();

    const typing = await open(context, 'typing');
    assert.equal(await typing.page.locator('#section-request-summary').getAttribute('phx-debounce'), null);
    await dirty(typing.page, 'Immediate first edit ');
    assert.equal(await typing.page.locator('#transition-submit').isDisabled(), true);
    typing.events.sent.length = 0;
    const typingAck = typing.events.ack('draft');
    await typing.page.locator('#section-request-summary').pressSequentially('abcdefghijklmnop', {delay: 10});
    await typingAck;
    counts.rapid_text_draft_events = typing.events.sent.filter(e => e === 'draft').length;
    assert.equal(counts.rapid_text_draft_events, 1);
    checks.push('The first edit is immediate; sixteen subsequent keystrokes produce one draft event and keep transitions blocked.');

    const immediate = await open(context, 'immediate');
    await dirty(immediate.page, 'Dirty before submit');
    const old = await revision(immediate.page);
    immediate.events.sent.length = 0;
    await immediate.page.evaluate(() => {
      const input = document.querySelector('#section-request-summary');
      input.value = 'Final characters submitted immediately';
      input.dispatchEvent(new InputEvent('input', {bubbles: true}));
      input.form.requestSubmit(document.querySelector('#save-request'));
    });
    await saved(immediate.page, old);
    await immediate.page.reload();
    await immediate.page.locator('[data-phx-main].phx-connected').waitFor();
    assert.equal(await immediate.page.locator('#section-request-summary').inputValue(), 'Final characters submitted immediately');
    counts.immediate_submit_draft_events = immediate.events.sent.filter(e => e === 'draft').length;
    assert.equal(counts.immediate_submit_draft_events, 0);
    checks.push('An immediate save cancels the pending debounce and persists every current character.');

    const reason = await open(context, 'reason');
    await reason.page.evaluate(() => {
      const input = document.querySelector('#transition-form textarea');
      input.value = 'Required reason submitted before debounce';
      input.dispatchEvent(new InputEvent('input', {bubbles: true}));
      input.form.requestSubmit(document.querySelector('#transition-cancel_draft'));
    });
    await reason.page.locator('#transition-cancel_draft').waitFor({state: 'detached'});
    await reason.page.reload();
    await reason.page.getByText('Required reason submitted before debounce', {exact: true}).waitFor();
    assert.equal(reason.events.sent.filter(e => e === 'reason').length, 0);
    checks.push('A transition carries its current required reason without waiting for a change event.');

    const first = await open(context, 'conflict');
    const second = await open(context, 'conflict');
    await dirty(second.page, 'Local draft');
    const observed = await revision(second.page);
    await dirty(first.page, 'Remote saved value');
    const peerRevision = await revision(first.page);
    const draftAck = second.events.ack('draft');
    await second.page.locator('#section-request-summary').fill('Local final characters');
    await first.page.locator('#save-request').click();
    await saved(first.page, peerRevision);
    await second.page.locator('#conflict-request').waitFor();
    await draftAck;
    assert.equal(await second.page.locator('#section-request-summary').inputValue(), 'Local final characters');
    assert.equal(await revision(second.page), observed);
    assert.equal(await second.page.locator('#section-request-summary').evaluate(el => el === document.activeElement), true);
    await second.page.locator('#conflict-request button[phx-click=compare]').click();
    await second.page.locator('#comparison-request button[phx-click=reapply]').click();
    const reapplied = await revision(second.page);
    await second.page.locator('#save-request').click();
    await saved(second.page, reapplied);
    checks.push('A peer save during debounce preserves focus, the local draft and its observed revision until explicit reapply.');

    const reconnect = await open(context, 'reconnect');
    await dirty(reconnect.page, 'Draft before disconnect');
    await reconnect.page.evaluate(() => window.liveSocket.disconnect());
    await reconnect.page.waitForFunction(() => document.querySelector('#save-request').disabled);
    await reconnect.page.locator('#section-request-summary').fill('Unsent offline draft');
    await reconnect.page.evaluate(() => window.liveSocket.connect());
    await reconnect.page.locator('[data-phx-main].phx-connected').waitFor();
    await reconnect.page.waitForFunction(() => !document.querySelector('#save-request').disabled);
    assert.equal(await reconnect.page.locator('#section-request-summary').inputValue(), 'Unsent offline draft');
    assert.equal(reconnect.events.sent.filter(e => e === 'save').length, 0);
    const recoveredRevision = await revision(reconnect.page);
    await reconnect.page.locator('#save-request').click();
    await saved(reconnect.page, recoveredRevision);
    checks.push('Disconnect/reconnect recovers the pending draft without automatically submitting a mutation.');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(root, '.local/input-debounce-browser.json'), JSON.stringify({status: 'passed', checks, counts}, null, 2));
    console.log(JSON.stringify({status: 'passed', checks, counts}, null, 2));
  } finally {
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
