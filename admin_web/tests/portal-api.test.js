import test from 'node:test';
import assert from 'node:assert/strict';
import { AdminApi, PortalError } from '../portal-api.js';
import { generateDemoTemperature, matchesDemoTemperature } from '../../team_web/demo-temperature.js';

test('demo temperature generation uses the requested 20 and 30 boundaries', () => {
  for (const [category, lower, upper] of [['low', 15, 19.9], ['moderate', 20, 29.9], ['high', 30, 35]]) {
    assert.equal(generateDemoTemperature(category, () => 0), lower);
    assert.equal(generateDemoTemperature(category, () => 0.999999), upper);
    assert.ok(matchesDemoTemperature(category, lower));
    assert.ok(matchesDemoTemperature(category, upper));
  }
  assert.equal(matchesDemoTemperature('low', 20), false);
  assert.equal(matchesDemoTemperature('moderate', 30), false);
  assert.equal(matchesDemoTemperature('high', 29.9), false);
  assert.equal(matchesDemoTemperature('high', NaN), false);
});

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status, headers: { 'Content-Type': 'application/json' },
});
const config = { apiKey: 'public-test-key', projectId: 'test-project', configured: true };

test('sign-in verifies the admin role before returning dashboard data', async () => {
  const requests = [];
  const api = new AdminApi({ fetcher: async (url, options) => {
    requests.push({ url, options });
    if (url.endsWith('/admin/config')) return json(config);
    if (url.includes('signInWithPassword')) {
      assert.deepEqual(JSON.parse(options.body),
        { email: 'admin@example.invalid', password: 'not-a-real-password', returnSecureToken: true });
      return json({ idToken: 'verified-token', refreshToken: 'refresh', expiresIn: '3600' });
    }
    assert.equal(url, '/admin/overview');
    assert.equal(options.headers.Authorization, 'Bearer verified-token');
    return json({ totals: { farmers: 3 } });
  } });
  await api.loadConfig();
  const data = await api.signIn('admin@example.invalid', 'not-a-real-password');
  assert.equal(data.totals.farmers, 3);
  assert.equal(requests.length, 3);
  assert.equal(requests[0].options.cache, 'no-store');
});

test('farmer login is rejected and tokens are cleared', async () => {
  const api = new AdminApi({ fetcher: async url => {
    if (url.includes('signInWithPassword')) {
      return json({ idToken: 'farmer-token', refreshToken: 'refresh', expiresIn: '3600' });
    }
    return json({ detail: 'Admin access required' }, 403);
  } });
  api.config = config;
  await assert.rejects(api.signIn('farmer@example.invalid', 'password'),
    error => error instanceof PortalError && error.status === 403 && error.message.includes('phone app'));
  assert.equal(api.session, null);
});

test('a 401 refreshes the token and retries once', async () => {
  const authHeaders = [];
  let refreshed = 0;
  const api = new AdminApi({ fetcher: async (url, options) => {
    if (url.includes('securetoken')) {
      refreshed++;
      assert.match(options.body, /grant_type=refresh_token/);
      return json({ id_token: 'new', refresh_token: 'new-refresh', expires_in: '3600' });
    }
    authHeaders.push(options.headers.Authorization);
    return authHeaders.length === 1 ? json({ detail: 'expired' }, 401) : json({ farmers: [] });
  } });
  api.config = config;
  api.session = { idToken: 'old', refreshToken: 'old-refresh', expiresAt: Date.now() + 3600000 };
  assert.deepEqual(await api.request('/admin/farmers'), { farmers: [] });
  assert.equal(refreshed, 1);
  assert.deepEqual(authHeaders, ['Bearer old', 'Bearer new']);
});

test('concurrent expiry uses one refresh request', async () => {
  let refreshes = 0;
  const api = new AdminApi({ fetcher: async url => {
    if (url.includes('securetoken')) {
      refreshes++;
      await new Promise(resolve => setTimeout(resolve, 5));
      return json({ id_token: 'new', refresh_token: 'refresh', expires_in: '3600' });
    }
    return json({ ok: true });
  } });
  api.config = config;
  api.session = { idToken: 'old', refreshToken: 'refresh', expiresAt: 0 };
  await Promise.all([api.request('/admin/overview'), api.request('/admin/farmers')]);
  assert.equal(refreshes, 1);
});

test('signing out during refresh cannot restore the old session', async () => {
  let finish;
  const api = new AdminApi({ fetcher: () => new Promise(resolve => { finish = resolve; }) });
  api.config = config;
  api.session = { idToken: 'old', refreshToken: 'refresh', expiresAt: 0 };
  const pending = api.refreshToken();
  api.signOut();
  finish(json({ id_token: 'new', refresh_token: 'refresh', expires_in: '3600' }));
  await assert.rejects(pending, error => error.status === 401);
  assert.equal(api.session, null);
});

test('a timed-out mutation is not automatically repeated', async () => {
  let calls = 0;
  const api = new AdminApi({ timeoutMs: 5, fetcher: async (_url, options) => {
    calls++;
    await new Promise((_, reject) => options.signal.addEventListener('abort', () =>
      reject(new DOMException('Aborted', 'AbortError')), { once: true }));
  } });
  api.config = config;
  api.session = { idToken: 'token', refreshToken: 'refresh', expiresAt: Date.now() + 3600000 };
  await assert.rejects(api.request('/admin/process-survey',
    { method: 'POST', body: { surveyId: 'one', action: 'reject' } }),
  error => error.message.includes('timed out'));
  assert.equal(calls, 1);
});

test('invalid password errors are readable and never expose server error objects', async () => {
  const api = new AdminApi({ fetcher: async () =>
    json({ error: { message: 'INVALID_LOGIN_CREDENTIALS' } }, 400) });
  api.config = config;
  await assert.rejects(api.signIn('admin@example.invalid', 'incorrect'),
    error => error.message === 'The email or password is incorrect.');
});

test('signing out while admin verification is pending cannot complete sign-in', async () => {
  let finishOverview;
  const api = new AdminApi({ fetcher: async url => {
    if (url.includes('signInWithPassword')) {
      return json({ idToken: 'token', refreshToken: 'refresh', expiresIn: '3600' });
    }
    return new Promise(resolve => { finishOverview = resolve; });
  } });
  api.config = config;
  const pending = api.signIn('admin@example.invalid', 'password');
  while (!finishOverview) await new Promise(resolve => setImmediate(resolve));
  api.signOut();
  finishOverview(json({ totals: { farmers: 99 } }));
  await assert.rejects(pending, error => error.status === 401);
  assert.equal(api.session, null);
});

test('every fixed DOM selector is present and farmer data is rendered as text', async () => {
  const { readFile } = await import('node:fs/promises');
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const script = await readFile(new URL('../app.js', import.meta.url), 'utf8');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(ids.length, new Set(ids).size, 'Duplicate element IDs');
  for (const match of script.matchAll(/\$\(['"]#([^'"]+)['"]\)/g)) {
    assert.ok(ids.includes(match[1]), 'Missing DOM element: ' + match[1]);
  }
  assert.equal(script.includes('.innerHTML'), false);
  assert.equal(script.includes('localStorage'), false);
  assert.equal(script.includes('sessionStorage'), false);
});


test('field team login verifies the team endpoint and keeps admin APIs separate', async () => {
  const requested = [];
  const api = new AdminApi({ role: 'team', fetcher: async (url, options) => {
    requested.push(url);
    if (url.includes('signInWithPassword')) {
      return json({ idToken: 'team-token', refreshToken: 'refresh', expiresIn: '3600' });
    }
    assert.equal(url, '/team/overview');
    assert.equal(options.headers.Authorization, 'Bearer team-token');
    return json({ member: { uid: 'field-1', name: 'Field team' } });
  } });
  api.config = config;
  const result = await api.signIn('field@example.invalid', 'password');
  assert.equal(result.member.uid, 'field-1');
  assert.equal(requested.some(url => url.endsWith('/admin/overview')), false);
});

test('a non-team account cannot enter the field workspace', async () => {
  const api = new AdminApi({ role: 'team', fetcher: async url => {
    if (url.includes('signInWithPassword')) return json({
      idToken: 'farmer-token', refreshToken: 'refresh', expiresIn: '3600' });
    return json({ detail: 'Team access required' }, 403);
  } });
  api.config = config;
  await assert.rejects(api.signIn('farmer@example.invalid', 'password'),
    error => error.status === 403 && error.message.includes('field-team'));
  assert.equal(api.session, null);
});

test('field workspace controls are wired and do not render untrusted HTML', async () => {
  const { readFile } = await import('node:fs/promises');
  const html = await readFile(new URL('../../team_web/index.html', import.meta.url), 'utf8');
  const script = await readFile(new URL('../../team_web/team.js', import.meta.url), 'utf8');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(ids.length, new Set(ids).size);
  for (const match of script.matchAll(/\$\(['"]#([^'"]+)['"]\)/g)) {
    assert.ok(ids.includes(match[1]), 'Missing field control: ' + match[1]);
  }
  assert.equal(script.includes('.innerHTML'), false);
  assert.equal(script.includes('localStorage'), false);
});
