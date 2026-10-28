import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

// Exercise the actual dashboard event handlers without a browser or cloud login.
// This intentionally tests navigation/state, not visual rendering or CSS layout.
class Element {
  constructor(tag) {
    this.tagName = tag; this.children = []; this.dataset = {}; this.attributes = {};
    this.events = {}; this.value = ''; this.hidden = false; this.disabled = false;
    this.type = ''; this.className = ''; this.textContent = '';
    this.classList = {
      add: value => { this.className += ' ' + value; },
      remove: value => { this.className = this.className.split(' ').filter(x => x !== value).join(' '); },
      toggle: (value, on) => { this.classList.remove(value); if (on) this.classList.add(value); },
    };
  }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; this.textContent = ''; }
  setAttribute(name, value) { this.attributes[name] = String(value); }
  removeAttribute(name) { delete this.attributes[name]; }
  addEventListener(type, handler) { (this.events[type] ||= []).push(handler); }
  showModal() { this.open = true; }
  close() { this.open = false; }
  reset() {}
  focus() {}
  reportValidity() { return true; }
  async emit(type) { for (const handler of this.events[type] || []) await handler({ preventDefault() {} }); }
}
async function dashboard() {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const source = await readFile(new URL('../app.js', import.meta.url), 'utf8');
  const elements = [], ids = new Map();
  for (const match of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*)>/gi)) {
    const el = new Element(match[1]);
    for (const attr of match[2].matchAll(/([a-z][a-z0-9-]*)="([^"]*)"/gi)) {
      const [, name, value] = attr; el.setAttribute(name, value);
      if (name === 'id') ids.set(value, el);
      if (name === 'class') el.className = value;
      if (name === 'type') el.type = value;
      if (name.startsWith('data-')) el.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value;
    }
    elements.push(el);
  }
  const document = {
    hidden: false,
    querySelector(selector) {
      const el = ids.get(selector.slice(1));
      assert.ok(el, 'Unknown DOM selector ' + selector); return el;
    },
    querySelectorAll(selector) {
      if (selector.startsWith('.')) return elements.filter(el => el.className.split(/\s+/).includes(selector.slice(1)));
      if (selector === 'dialog[open]') return elements.filter(el => el.tagName === 'dialog' && el.open);
      const key = selector.slice(1, -1);
      return elements.filter(el => Object.hasOwn(el.attributes, key));
    },
    createElement: tag => new Element(tag), createElementNS: (_, tag) => new Element(tag),
  };
  class Api {
    constructor() { this.calls = []; this.config = { configured: true }; this.response = { surveys: [], nextCursor: null }; }
    async loadConfig() { return this.config; }
    async request(path) { this.calls.push(path); return this.response; }
    signOut() {}
  }
  const context = vm.createContext({ document, Node: Element, AdminApi: Api, URLSearchParams,
    setTimeout, clearTimeout, setInterval, clearInterval, Intl, Date });
  const program = source.replace(/^import .*?;\s*/, '');
  const app = await vm.runInContext('(async () => {' + program + '\nreturn { state, api, renderOverview, renderSurveyProgress, loadSurveys, logout }; })()', context);
  app.state.authenticated = true;
  return { ...app, ids, elements };
}

test('overview report shortcut resets stale farmer/page filters and opens the real review queue', async () => {
  const app = await dashboard();
  app.state.farmerFilter = 'previous-farmer'; app.state.surveys.page = 4;
  app.ids.get('survey-search').value = 'previous search';
  const shortcut = app.elements.find(el => el.dataset.surveyStatus === 'awaiting_review');
  await shortcut.emit('click');
  const request = new URL(app.api.calls.at(-1), 'http://local.invalid');
  assert.equal(request.pathname, '/admin/surveys');
  assert.equal(request.searchParams.get('status'), 'awaiting_review');
  assert.equal(request.searchParams.has('farmer_id'), false);
  assert.equal(request.searchParams.has('cursor'), false);
  assert.equal(app.state.view, 'surveys');
  assert.equal(app.state.surveys.page, 0);
  assert.equal(app.ids.get('survey-search').value, '');
  assert.equal(app.ids.get('surveys-panel').attributes['aria-busy'], 'false');
});

test('status chips preserve selected farmer and search operates only on the loaded page', async () => {
  const app = await dashboard();
  app.state.farmerFilter = 'farmer-one';
  app.api.response = { surveys: [
    { surveyId: 'one', farmerName: 'Asha', farmName: 'East field', city: 'Pune', status: 'completed', recommendedCrop: 'Wheat' },
    { surveyId: 'two', farmerName: 'Ravi', farmName: 'West field', city: 'Mumbai', status: 'completed', recommendedCrop: 'Rice' },
  ], nextCursor: 'two' };
  const chip = app.elements.find(el => el.dataset.statusChip === 'completed');
  await chip.emit('click');
  assert.equal(new URL(app.api.calls.at(-1), 'http://local.invalid').searchParams.get('farmer_id'), 'farmer-one');
  assert.equal(chip.attributes['aria-pressed'], 'true');
  assert.equal(app.ids.get('surveys-table').children.length, 2);
  const callsBefore = app.api.calls.length;
  app.ids.get('survey-search').value = 'wHeAt';
  await app.ids.get('survey-search').emit('input');
  assert.equal(app.api.calls.length, callsBefore, 'Page search must not fetch unrelated records');
  assert.equal(app.ids.get('surveys-table').children.length, 1);
  assert.equal(app.ids.get('survey-page-label').textContent, '1 of 2 surveys on this page');
  assert.equal(app.ids.get('surveys-next').disabled, false, 'Search must not discard server pagination');
  app.ids.get('survey-search').value = 'no match';
  await app.ids.get('survey-search').emit('input');
  assert.equal(app.ids.get('surveys-empty').hidden, false);
});

test('overview counts reflect server data and the pipeline opens the selected stage', async () => {
  const app = await dashboard();
  app.renderOverview({ totals: { farmers: 8, pending: 3, awaiting_review: 2, completed: 4,
    surveys: 12, supportOpen: 1, approved: 2, in_progress: 1, rejected: 0, failed: 0, other: 0 },
    admin: { name: '<img src=x>', email: 'test@example.invalid' }, recentSurveys: [] });
  assert.equal(app.ids.get('stat-pending').textContent, '3');
  assert.equal(app.ids.get('pending-nav-count').textContent, '5');
  assert.equal(app.ids.get('queue-reports').textContent, '2');
  assert.equal(app.ids.get('queue-support').textContent, '1');
  assert.ok(app.ids.get('welcome-heading').textContent.includes('<img'));
  assert.equal(app.ids.get('welcome-heading').children.length, 0, 'Names must remain plain text');
  const stage = app.ids.get('status-breakdown').children.find(el => el.className.includes('stage-approved'));
  await stage.emit('click');
  assert.equal(new URL(app.api.calls.at(-1), 'http://local.invalid').searchParams.get('status'), 'approved');
});

test('report progress distinguishes unpublished review from release and hides cancelled journeys', async () => {
  const app = await dashboard(), progress = app.ids.get('survey-progress');
  app.renderSurveyProgress('awaiting_review');
  assert.equal(progress.hidden, false);
  assert.equal(progress.children[3].attributes['aria-current'], 'step');
  assert.equal(progress.children[4].className, '');
  app.renderSurveyProgress('completed');
  assert.equal(progress.children[4].attributes['aria-current'], 'step');
  app.renderSurveyProgress('rejected');
  assert.equal(progress.hidden, true);
});