import { AdminApi } from '/admin/portal-api.js';
import { DEMO_NOTICE, generateDemoTemperature, matchesDemoTemperature } from './demo-temperature.js';
const $ = selector => document.querySelector(selector);
const api = new AdminApi({ role: 'team' });
const state = { signedIn: false, visits: [], active: null, page: 0, cursors: [null], next: null, request: 0, loading: false, timer: null };
const labels = { approved: 'Visit approved', in_progress: 'Visit in progress', awaiting_review: 'Admin review',
  completed: 'Result released', rejected: 'Cancelled / rejected' };
function node(tag, text, className) {
  const el = document.createElement(tag);
  if (text !== undefined && text !== null) el.textContent = String(text);
  if (className) el.className = className;
  return el;
}
function toast(message) {
  $('#toast').textContent = message; $('#toast').hidden = false;
  clearTimeout(toast.timer); toast.timer = setTimeout(() => { $('#toast').hidden = true; }, 5000);
}
function signOut() {
  clearInterval(state.timer); state.timer = null;
  api.signOut(); state.signedIn = false; state.visits = []; state.active = null; state.request++;
  $('#visits').replaceChildren(); $('#visit-details').replaceChildren();
  if ($('#visit-dialog').open) $('#visit-dialog').close();
  $('#team-view').hidden = true; $('#login-view').hidden = false; $('#password').value = '';
}
function showError(error) {
  if (error.status === 401 || error.status === 403) {
    signOut(); $('#login-error').textContent = error.message; return;
  }
  $('#error').textContent = error.message; $('#error').hidden = false;
}
async function loadVisits() {
  const request = ++state.request; state.loading = true;
  $('#previous').disabled = $('#next').disabled = true;
  $('#refresh').disabled = true;
  try {
    const params = new URLSearchParams({ limit: '20' });
    if ($('#status-filter').value) params.set('status', $('#status-filter').value);
    if (state.cursors[state.page]) params.set('cursor', state.cursors[state.page]);
    const data = await api.request('/team/visits?' + params);
    if (!state.signedIn || state.request !== request) return;
    state.visits = data.visits; state.next = data.nextCursor;
    $('#error').hidden = true; $('#visits').replaceChildren();
    for (const visit of data.visits) {
      const card = node('article', undefined, 'visit-card');
      const top = node('div', undefined, 'visit-top');
      top.append(node('span', labels[visit.status] || visit.status, 'status ' + visit.status));
      card.append(top, node('h2', visit.farmName || 'Farm survey'),
        node('p', visit.farmerName, 'owner'),
        node('p', visit.farmAddress || visit.city, 'address'),
        node('p', [visit.city, visit.soilType || visit.soil_type, visit.season, visit.year].filter(Boolean).join(' · '), 'metadata'));
      const open = node('button', ['approved', 'in_progress'].includes(visit.status) ? 'Open visit & readings ↗' : 'View report ↗', 'button secondary full');
      open.addEventListener('click', () => openVisit(visit.surveyId));
      card.append(open); $('#visits').append(card);
    }
    $('#empty').hidden = data.visits.length > 0;
    $('#page-count').textContent = data.visits.length + ' visits on this page';
    $('#page-number').textContent = 'Page ' + (state.page + 1);
    $('#previous').disabled = state.page === 0; $('#next').disabled = !state.next;
  } catch (error) { if (request === state.request) showError(error); }
  finally { if (request === state.request) { state.loading = false; $('#refresh').disabled = false; } }
}
function detail(label, value) {
  const el = node('div', undefined, 'detail-item');
  el.append(node('span', label), node('strong', value ?? '—')); $('#visit-details').append(el);
}
function syncDemoControls() {
  $('#demo-controls').hidden = !$('#temperature-demo').checked;
  $('#demo-notice').hidden = !$('#temperature-demo').checked;
  $('#demo-notice').textContent = DEMO_NOTICE;
}
$('#temperature-demo').addEventListener('change', () => {
  $('#temperature').value = ''; syncDemoControls();
});
$('#temperature-category').addEventListener('change', () => { $('#temperature').value = ''; });
$('#generate-temperature').addEventListener('click', () => {
  $('#temperature').value = generateDemoTemperature($('#temperature-category').value).toFixed(1);
});
async function openVisit(id) {
  $('#visit-title').textContent = 'Loading visit…'; $('#visit-details').replaceChildren();
  $('#readings-form').reset(); $('#form-error').textContent = '';
  $('#reading-fields').hidden = $('#submit-readings').hidden = $('#start-visit').hidden = true;
  $('#visit-state').textContent = '';
  state.active = { surveyId: id };
  if (!$('#visit-dialog').open) $('#visit-dialog').showModal();
  try {
    const data = await api.request('/team/visits/' + encodeURIComponent(id));
    if (!state.signedIn || state.active?.surveyId !== id || !$('#visit-dialog').open) return;
    state.active = data;
    $('#visit-title').textContent = data.farmName || 'Farm visit';
    detail('Farmer', data.farmerName); detail('Phone', data.contactPhone || '—');
    detail('Farm address', data.farmAddress || 'Address unavailable — contact admin');
    detail('Location', data.city); detail('Soil', data.soilType || data.soil_type);
    detail('Season', [data.season, data.year].filter(Boolean).join(' '));
    if (data.adminNotes) detail('Admin notes', data.adminNotes);
    const editable = ['approved', 'in_progress'].includes(data.status);
    $('#temperature-demo').checked = data.temperatureSource === 'simulated';
    $('#temperature-category').value = data.temperatureCategory || 'moderate';
    $('#temperature-demo').disabled = $('#temperature-category').disabled = $('#generate-temperature').disabled = !editable;
    syncDemoControls();
    if (data.temperatureSource === 'simulated') detail('Temperature source', DEMO_NOTICE);
    $('#reading-fields').hidden = $('#submit-readings').hidden = !editable;
    $('#start-visit').hidden = data.status !== 'approved';
    $('#start-visit').disabled = $('#submit-readings').disabled = false;
    for (const field of ['moisture', 'temperature', 'nitrogen', 'phosphorus', 'potassium']) {
      $('#' + field).value = data[field] ?? '';
      $('#' + field).disabled = !editable;
      if (!editable && data[field] !== null && data[field] !== undefined) {
        detail(field === 'temperature' && data.temperatureSource === 'simulated'
          ? 'Temperature (SIMULATED °C)' : field[0].toUpperCase() + field.slice(1), data[field]);
      }
    }
    $('#visit-state').textContent = data.status === 'awaiting_review'
      ? 'Your report has been submitted. The admin will review and release the recommendation.'
      : data.status === 'completed'
        ? 'Released crop recommendation: ' + (data.recommended_crop || data.recommendedCrop || '—')
        : data.status === 'rejected' ? 'This visit has been cancelled or rejected. Do not submit readings.'
          : 'Record the gadget readings and manually supplied N/P/K values for this visit.';
  } catch (error) { $('#form-error').textContent = error.message; }
}
$('#login-form').addEventListener('submit', async event => {
  event.preventDefault(); $('#login-submit').disabled = true; $('#login-error').textContent = '';
  try {
    const data = await api.signIn($('#email').value.trim(), $('#password').value);
    state.signedIn = true; state.page = 0; state.cursors = [null];
    $('#member-name').textContent = data.member?.name || 'Field team';
    $('#login-view').hidden = true; $('#team-view').hidden = false; $('#password').value = '';
    await loadVisits();
    clearInterval(state.timer);
    state.timer = setInterval(() => {
      if (state.signedIn && !document.hidden && !state.loading) loadVisits();
    }, 30000);
  } catch (error) { $('#login-error').textContent = error.message; }
  finally { $('#login-submit').disabled = !api.config?.configured; }
});
$('#status-filter').addEventListener('change', () => { state.page = 0; state.cursors = [null]; loadVisits(); });
$('#refresh').addEventListener('click', loadVisits); $('#sign-out').addEventListener('click', signOut);
$('#close-visit').addEventListener('click', () => $('#visit-dialog').close());
$('#next').addEventListener('click', () => {
  if (!state.next) return; state.cursors[++state.page] = state.next; loadVisits();
});
$('#previous').addEventListener('click', () => { if (state.page > 0) { state.page--; loadVisits(); } });
$('#start-visit').addEventListener('click', async () => {
  $('#start-visit').disabled = true;
  try {
    await api.request('/team/visits/' + encodeURIComponent(state.active.surveyId) + '/start', { method: 'POST' });
    await openVisit(state.active.surveyId);
    $('#status-filter').value = 'in_progress'; state.page = 0; state.cursors = [null]; await loadVisits();
  } catch (error) { $('#form-error').textContent = error.message; }
  finally { $('#start-visit').disabled = false; }
});
$('#readings-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (!$('#readings-form').reportValidity() || !state.active) return;
  const body = { notes: $('#notes').value.trim() || null };
  for (const field of ['moisture', 'temperature', 'nitrogen', 'phosphorus', 'potassium']) body[field] = Number($('#' + field).value);
  if ($('#temperature-demo').checked) {
    body.temperatureSource = 'simulated';
    body.temperatureCategory = $('#temperature-category').value;
    if (!matchesDemoTemperature(body.temperatureCategory, body.temperature)) {
      $('#form-error').textContent = 'Temperature must match the selected demo range.'; return;
    }
  }
  $('#submit-readings').disabled = true; $('#form-error').textContent = '';
  try {
    await api.request('/team/visits/' + encodeURIComponent(state.active.surveyId) + '/readings', { method: 'POST', body });
    if (!state.signedIn) return;
    $('#visit-dialog').close(); toast('Report submitted for admin review.');
    $('#status-filter').value = 'awaiting_review'; state.page = 0; state.cursors = [null]; await loadVisits();
  } catch (error) { $('#form-error').textContent = error.message; }
  finally { $('#submit-readings').disabled = false; }
});
try {
  const config = await api.loadConfig();
  $('#login-submit').disabled = !config.configured; $('#login-submit').textContent = 'Sign in to field workspace ↗';
  if (!config.configured) $('#login-error').textContent = 'Sign-in is not configured. Contact the project administrator.';
} catch (error) { $('#login-error').textContent = error.message + ' Reload this page to reconnect.'; }
