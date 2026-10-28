import { AdminApi } from './portal-api.js';

const $ = selector => document.querySelector(selector);
const api = new AdminApi();
const state = {
  authenticated: false, view: 'overview', timer: null, refreshing: false,
  farmers: { cursors: [null], page: 0, next: null, rows: [], request: 0 },
  surveys: { cursors: [null], page: 0, next: null, rows: [], request: 0 },
  support: { cursors: [null], page: 0, next: null, rows: [], request: 0 },
  activeThread: null, teamMembers: null,
  farmerFilter: null, farmerName: '', activeSurvey: null, activeFarmer: null,
};
const statusNames = { pending: 'Approval requested', approved: 'Visit approved', awaiting_review: 'Report ready', completed: 'Released', done: 'Completed',
  rejected: 'Rejected', failed: 'Failed', inProgress: 'In progress', in_progress: 'In progress' };
const dateFormatter = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const numberFormatter = new Intl.NumberFormat();

function node(tag, text, className) {
  const element = document.createElement(tag);
  if (text !== undefined && text !== null) element.textContent = String(text);
  if (className) element.className = className;
  return element;
}
function date(value) {
  if (!value) return '—';
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? '—' : dateFormatter.format(parsed);
}
function count(value) { return typeof value === 'number' ? numberFormatter.format(value) : '—'; }
function initials(name) { return String(name || 'Farmer').split(/\s+/).slice(0, 2).map(part => part[0]).join('').toUpperCase(); }
function badge(status) {
  return node('span', statusNames[status] || status || 'Unknown',
    'status ' + (Object.hasOwn(statusNames, status) ? status : 'unknown'));
}
function button(label, action, ariaLabel) {
  const element = node('button', label, 'text-button');
  element.type = 'button';
  if (ariaLabel) element.setAttribute('aria-label', ariaLabel);
  element.addEventListener('click', action);
  return element;
}
function person(name, secondary) {
  const wrap = node('div', null, 'person-cell');
  wrap.append(node('span', initials(name), 'avatar'));
  const text = node('div');
  text.append(node('strong', name || 'Farmer'));
  if (secondary) text.append(node('small', secondary));
  wrap.append(text);
  return wrap;
}
function cell(row, content) {
  const td = node('td');
  if (content instanceof Node) td.append(content);
  else td.textContent = content ?? '—';
  row.append(td);
}
function detail(target, label, value) {
  const wrap = node('div', null, 'detail-item');
  wrap.append(node('span', label), node('strong', value ?? '—'));
  target.append(wrap);
}
function icon(name) {
  const element = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  element.classList.add('ui-icon'); element.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
  use.setAttribute('href', '/admin/icons.svg#' + name); element.append(use);
  return element;
}
function setListBusy(type, busy) {
  $('#' + type + '-panel').setAttribute('aria-busy', String(busy));
}
function syncSurveyFilters() {
  for (const chip of document.querySelectorAll('[data-status-chip]')) {
    chip.setAttribute('aria-pressed', String(chip.dataset.statusChip === $('#survey-status').value));
  }
}
async function openSurveyQueue(status, clearFarmer = true) {
  if (!state.authenticated) return;
  if (clearFarmer) state.farmerFilter = null;
  $('#survey-status').value = status;
  $('#survey-search').value = '';
  resetPages('surveys'); syncSurveyFilters();
  await setView('surveys');
}
function renderSurveyProgress(status) {
  const progress = $('#survey-progress'); progress.replaceChildren();
  const stages = [['pending', 'Requested'], ['approved', 'Assigned'], ['in_progress', 'On site'],
    ['awaiting_review', 'In review'], ['completed', 'Released']];
  const index = stages.findIndex(([key]) => key === (status === 'done' ? 'completed' : status));
  progress.hidden = index < 0;
  if (index < 0) return;
  stages.forEach(([, label], step) => {
    const item = node('li', label, step <= index ? 'reached' : '');
    if (step === index) item.setAttribute('aria-current', 'step');
    progress.append(item);
  });
}

function showToast(message) {
  $('#toast').textContent = message;
  $('#toast').hidden = false;
  clearTimeout(showToast.timeout);
  showToast.timeout = setTimeout(() => { $('#toast').hidden = true; }, 5000);
}
function showError(error) {
  if (!state.authenticated) return;
  if (error.status === 401 || error.status === 403) {
    logout();
    $('#login-error').textContent = 'Your administrator session ended. Please sign in again.';
    return;
  }
  $('#workspace-error').textContent = error.message || 'Unable to refresh. Please try again.';
  $('#workspace-error').hidden = false;
}
function clearError() { $('#workspace-error').hidden = true; }
function logout() {
  api.signOut();
  state.authenticated = false;
  clearInterval(state.timer);
  state.timer = null;
  state.farmerFilter = null;
  state.activeFarmer = null;
  state.activeSurvey = null;
  state.farmers.request++;
  state.surveys.request++;
  for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close();
  state.support.rows = []; state.support.request++; state.activeThread = null; state.teamMembers = null;
  state.farmers.rows = [];
  state.surveys.rows = [];
  for (const selector of ['#recent-surveys', '#farmers-table', '#surveys-table',
    '#status-breakdown', '#survey-details', '#farmer-details', '#farmer-summary', '#support-table', '#survey-progress']) {
    $(selector).replaceChildren();
  }
  for (const key of ['farmers', 'pending', 'completed', 'surveys']) {
    $('#stat-' + key).textContent = '—';
  }
  for (const id of ['queue-pending', 'queue-reports', 'queue-support', 'pending-nav-count', 'support-nav-count']) $('#' + id).textContent = '—';
  $('#welcome-heading').textContent = 'Welcome back.';
  $('#admin-email').textContent = '';
  $('#survey-result').textContent = '';
  $('#support-message').textContent = ''; $('#support-sender').textContent = ''; $('#support-reply').value = '';
  $('#toast').hidden = true;
  $('#dashboard-view').hidden = true;
  $('#login-view').hidden = false;
  $('#password').value = '';
  $('#password').type = 'password'; $('#toggle-password').textContent = 'Show';
  $('#toggle-password').setAttribute('aria-pressed', 'false'); $('#toggle-password').setAttribute('aria-label', 'Show password');
  $('#login-error').textContent = '';
  clearError();
  $('#email').focus();
}

function renderOverview(data) {
  if (!state.authenticated) return;
  const totals = data.totals;
  for (const key of ['farmers', 'pending', 'completed', 'surveys']) {
    $('#stat-' + key).textContent = count(totals[key]);
  }
  $('#pending-nav-count').textContent = count(totals.pending + totals.awaiting_review);
  $('#support-nav-count').textContent = count(totals.supportOpen);
  $('#queue-pending').textContent = count(totals.pending);
  $('#queue-reports').textContent = count(totals.awaiting_review);
  $('#queue-support').textContent = count(totals.supportOpen);
  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  const firstName = String(data.admin?.name || 'Admin').trim().split(/\s+/)[0] || 'Admin';
  $('#welcome-heading').textContent = greeting + ', ' + firstName + '.';
  $('#admin-email').textContent = data.admin?.email || '';
  $('#admin-avatar').textContent = initials(data.admin?.name || 'Admin');
  const tbody = $('#recent-surveys');
  tbody.replaceChildren();
  for (const survey of data.recentSurveys) {
    const row = node('tr');
    cell(row, person(survey.farmerName, date(survey.createdAt)));
    const farm = node('div');
    farm.append(node('strong', survey.farmName || survey.city || 'Farm'), node('small', survey.city || ''));
    cell(row, farm);
    cell(row, badge(survey.status));
    cell(row, button('View report', () => openSurvey(survey.surveyId), 'Open survey for ' + survey.farmerName));
    tbody.append(row);
  }
  $('#recent-empty').hidden = data.recentSurveys.length > 0;
  const breakdown = $('#status-breakdown');
  breakdown.replaceChildren();
  for (const [key, label] of [['pending', 'Approval requested'], ['approved', 'Visit approved'], ['in_progress', 'Team on site'], ['awaiting_review', 'Report ready'], ['completed', 'Released'],
    ['rejected', 'Rejected'], ['failed', 'Failed'], ['other', 'Other']]) {
    if (key === 'other' && !totals.other) continue;
    const row = node('button', null, 'breakdown-row stage-' + key);
    row.type = 'button'; row.disabled = key === 'other';
    if (!row.disabled) row.addEventListener('click', () => openSurveyQueue(key));
    row.setAttribute('aria-label', label + ': ' + count(totals[key]) + '. View surveys');
    const meter = node('meter');
    meter.min = 0; meter.max = Math.max(1, totals.surveys); meter.value = totals[key];
    meter.setAttribute('aria-label', label + ': ' + totals[key]);
    row.append(node('span', label), node('strong', count(totals[key])), meter);
    breakdown.append(row);
  }
  $('#updated-label').textContent = 'Updated ' + new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

async function refreshDashboard() {
  if (!state.authenticated || state.refreshing) return;
  state.refreshing = true; state.teamMembers = null;
  $('#refresh-button').disabled = true;
  $('#refresh-button').classList.add('is-refreshing');
  $('#refresh-button').setAttribute('aria-busy', 'true');
  try {
    const data = await api.request('/admin/overview');
    if (!state.authenticated) return;
    clearError();
    renderOverview(data);
    if (state.view === 'farmers') await loadFarmers();
    if (state.view === 'surveys') await loadSurveys();
    if (state.view === 'support') await loadSupport();
  } catch (error) { showError(error); }
  finally {
    state.refreshing = false; $('#refresh-button').disabled = false;
    $('#refresh-button').classList.remove('is-refreshing'); $('#refresh-button').setAttribute('aria-busy', 'false');
  }
}

async function setView(view) {
  if (!state.authenticated) return;
  state.view = view;
  for (const panel of document.querySelectorAll('.view-panel')) panel.hidden = panel.id !== view + '-panel';
  for (const nav of document.querySelectorAll('.nav-link')) {
    const active = nav.dataset.view === view;
    nav.classList.toggle('active', active);
    if (active) nav.setAttribute('aria-current', 'page');
    else nav.removeAttribute('aria-current');
  }
  $('#breadcrumb-view').textContent = view[0].toUpperCase() + view.slice(1);
  if (view === 'farmers') await loadFarmers();
  if (view === 'surveys') { syncSurveyFilters(); await loadSurveys(); }
  if (view === 'support') await loadSupport();
}

function queryPath(path, params) {
  const query = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== null && value !== undefined && value !== '') query.set(key, String(value));
  }
  return path + '?' + query.toString();
}
function updatePagination(type) {
  const page = state[type];
  $('#' + type + '-page').textContent = 'Page ' + (page.page + 1);
  $('#' + type + '-prev').disabled = page.page === 0;
  $('#' + type + '-next').disabled = !page.next;
}
async function loadFarmers() {
  const request = ++state.farmers.request;
  setListBusy('farmers', true);
  $('#farmers-prev').disabled = $('#farmers-next').disabled = true;
  try {
    const data = await api.request(queryPath('/admin/farmers', {
      limit: 20, cursor: state.farmers.cursors[state.farmers.page],
    }));
    if (!state.authenticated || request !== state.farmers.request) return;
    state.farmers.rows = data.farmers;
    state.farmers.next = data.nextCursor;
    renderFarmers();
    updatePagination('farmers');
  } catch (error) { if (request === state.farmers.request) showError(error); }
  finally { if (request === state.farmers.request) setListBusy('farmers', false); }
}
function renderFarmers() {
  const search = $('#farmer-search').value.trim().toLowerCase();
  const farmers = state.farmers.rows.filter(farmer =>
    (farmer.name + ' ' + farmer.email).toLowerCase().includes(search));
  const tbody = $('#farmers-table');
  tbody.replaceChildren();
  for (const farmer of farmers) {
    const row = node('tr');
    cell(row, person(farmer.name));
    cell(row, farmer.email || '—');
    cell(row, farmer.phone || '—');
    cell(row, date(farmer.createdAt));
    cell(row, button('View farmer ↗', () => openFarmer(farmer.id)));
    tbody.append(row);
  }
  $('#farmers-empty').hidden = farmers.length > 0;
  $('#farmer-page-label').textContent = count(farmers.length) + ' farmers shown on this page';
}
async function loadSurveys() {
  const request = ++state.surveys.request;
  setListBusy('surveys', true);
  $('#surveys-prev').disabled = $('#surveys-next').disabled = true;
  syncSurveyFilters();
  try {
    const data = await api.request(queryPath('/admin/surveys', {
      limit: 20, status: $('#survey-status').value, farmer_id: state.farmerFilter,
      cursor: state.surveys.cursors[state.surveys.page],
    }));
    if (!state.authenticated || request !== state.surveys.request) return;
    state.surveys.rows = data.surveys;
    state.surveys.next = data.nextCursor;
    renderSurveys();
    $('#clear-farmer-filter').hidden = !state.farmerFilter;
    $('#survey-subtitle').textContent = state.farmerFilter
      ? 'Survey history for ' + state.farmerName + '.'
      : 'Review requests and track recommendations across all farmers.';
    updatePagination('surveys');
  } catch (error) { if (request === state.surveys.request) showError(error); }
  finally { if (request === state.surveys.request) setListBusy('surveys', false); }
}
function renderSurveys() {
  const search = $('#survey-search').value.trim().toLowerCase();
  const rows = state.surveys.rows.filter(survey =>
    [survey.farmerName, survey.farmerEmail, survey.farmName, survey.city, survey.surveyId,
      survey.recommended_crop, survey.recommendedCrop].filter(Boolean).join(' ').toLowerCase().includes(search));
  const tbody = $('#surveys-table'); tbody.replaceChildren();
  for (const survey of rows) {
    const row = node('tr');
    cell(row, person(survey.farmerName, survey.farmerEmail));
    const farm = node('div');
    farm.append(node('strong', survey.farmName || survey.city || 'Farm'),
      node('small', [survey.city, survey.soilType || survey.soil_type].filter(Boolean).join(' · ')));
    cell(row, farm); cell(row, date(survey.createdAt)); cell(row, badge(survey.status));
    cell(row, survey.recommended_crop || survey.recommendedCrop || '—');
    cell(row, button(['pending', 'awaiting_review'].includes(survey.status) ? 'Review survey' : 'View details',
      () => openSurvey(survey.surveyId), 'Open survey for ' + (survey.farmerName || 'farmer')));
    tbody.append(row);
  }
  $('#surveys-empty').hidden = rows.length > 0;
  $('#survey-page-label').textContent = count(rows.length) + ' of ' + count(state.surveys.rows.length) + ' surveys on this page';
}
function resetPages(type) {
  state[type].cursors = [null]; state[type].page = 0; state[type].next = null;
}
async function page(type, direction) {
  const data = state[type];
  if (direction > 0) {
    if (!data.next) return;
    data.cursors[data.page + 1] = data.next;
    data.page++;
  } else if (data.page > 0) data.page--;
  else return;
  if (type === 'farmers') { $('#farmer-search').value = ''; await loadFarmers(); }
  else if (type === 'support') await loadSupport();
  else { $('#survey-search').value = ''; await loadSurveys(); }
}

async function openFarmer(id) {
  state.activeFarmer = id;
  $('#farmer-dialog-title').textContent = 'Loading farmer…';
  $('#farmer-details').replaceChildren();
  $('#farmer-summary').replaceChildren();
  $('#view-farmer-surveys').disabled = true;
  $('#farmer-dialog').showModal();
  try {
    const data = await api.request('/admin/farmers/' + encodeURIComponent(id));
    if (!state.authenticated || state.activeFarmer !== id || !$('#farmer-dialog').open) return;
    state.farmerName = data.farmer.name;
    $('#farmer-dialog-title').textContent = data.farmer.name;
    const target = $('#farmer-details');
    detail(target, 'Email', data.farmer.email || '—');
    detail(target, 'Phone', data.farmer.phone || '—');
    detail(target, 'Joined', date(data.farmer.createdAt));
    detail(target, 'Farmer ID', data.farmer.id);
    for (const [key, label] of [['surveys', 'Surveys'], ['pending', 'Awaiting approval'], ['completed', 'Completed']]) {
      const item = node('div');
      item.append(node('strong', count(data.stats[key])), node('span', label));
      $('#farmer-summary').append(item);
    }
    $('#view-farmer-surveys').disabled = false;
  } catch (error) {
    $('#farmer-dialog').close();
    showError(error);
  }
}

async function loadTeamMembers() {
  if (state.teamMembers) return state.teamMembers;
  const members = [];
  let cursor = null;
  do {
    const data = await api.request(queryPath('/admin/team-members', { limit: 100, cursor }));
    if (!state.authenticated) return [];
    members.push(...data.members); cursor = data.nextCursor;
  } while (cursor);
  state.teamMembers = members;
  return members;
}

async function openSurvey(id) {
  state.activeSurvey = { surveyId: id };
  $('#survey-dialog-title').textContent = 'Loading survey…';
  $('#survey-details').replaceChildren(); $('#survey-result').hidden = true;
  $('#survey-progress').hidden = true;
  $('#assignment-fields').hidden = $('#survey-actions').hidden = true;
  $('#team-assignee').disabled = true; $('#survey-notes').disabled = true;
  $('#survey-error').textContent = ''; $('#process-form').reset();
  if (!$('#survey-dialog').open) $('#survey-dialog').showModal();
  try {
    const data = await api.request('/survey/' + encodeURIComponent(id));
    if (!state.authenticated || state.activeSurvey?.surveyId !== id || !$('#survey-dialog').open) return;
    state.activeSurvey = data;
    renderSurveyProgress(data.status);
    $('#survey-dialog-title').textContent = data.farmName || data.farmerName || 'Farm survey';
    const target = $('#survey-details');
    for (const [label, value] of [
      ['Farmer', data.farmerName], ['Contact phone', data.contactPhone || '—'],
      ['Address', data.farmAddress || 'Contact farmer for the address'],
      ['Status', statusNames[data.status] || data.status],
      ['Location', data.city], ['Soil type', data.soilType || data.soil_type],
      ['Season', (data.season || '') + ' ' + (data.year || '')],
      ['Assigned team', data.assignedTeamName || 'Not assigned'],
    ]) detail(target, label, value);
    if (data.moisture != null) detail(target, 'Moisture (team recorded)', data.moisture + '%');
    if (data.temperature != null) detail(target,
      data.temperatureSource === 'simulated' ? 'Temperature (SIMULATED)' : 'Temperature (team recorded)', data.temperature + ' °C');
    if (data.recommendationNotice) detail(target, 'Demo input', data.recommendationNotice);
    if (data.nitrogen != null) detail(target, 'Manual N / P / K', [data.nitrogen, data.phosphorus, data.potassium].join(' / '));
    if (data.teamNotes) detail(target, 'Field team notes', data.teamNotes);
    if (data.cropPlan) {
      detail(target, 'Farmer crop plan', data.cropPlan.proposedCrop);
      detail(target, 'Planned sowing / irrigation', [data.cropPlan.sowingDate || 'Not specified', data.cropPlan.irrigation].join(' / '));
    }
    if (data.fieldEvidence) {
      const evidence = data.fieldEvidence;
      detail(target, 'Evidence record ID', evidence.submissionId);
      detail(target, 'Captured / received', [evidence.capturedAt || 'Not recorded', evidence.receivedAt].join(' / '));
      detail(target, 'Nutrient evidence', [evidence.nutrientSource, evidence.nutrientUnit, evidence.soilTestReference || 'No soil-test reference'].join(' / '));
      detail(target, 'Moisture source', evidence.moistureSource);
      if (evidence.soilTestAttachmentUrl) detail(target, 'Soil report attachment link', evidence.soilTestAttachmentUrl);
      detail(target, 'Recorded by', evidence.recordedBy);
    }
    if (data.adminNotes) detail(target, 'Admin notes', data.adminNotes);
    if (data.emailNotifications?.length) {
      const mailStates = { queued: 'Queued', sending: 'Sending', sent: 'Accepted by mail provider',
        failed: 'Sending failed', not_configured: 'Sender setup needed',
        skipped_no_recipient: 'No valid farmer email', skipped_obsolete: 'Older update skipped' };
      for (const email of data.emailNotifications) {
        detail(target, 'Email: ' + (statusNames[email.surveyStatus] || email.surveyStatus),
          mailStates[email.deliveryStatus] || email.deliveryStatus);
      }
    }
    const prediction = data.status === 'awaiting_review' ? data.draftPrediction : data;
    if (prediction?.recommended_crop || prediction?.recommendedCrop) {
      $('#survey-result').textContent = (data.status === 'awaiting_review'
        ? 'DRAFT — not yet released to the farmer.\n' : 'RELEASED RESULT\n')
        + 'Recommended crop: ' + (prediction.recommended_crop || prediction.recommendedCrop)
        + '\nEstimated rainfall: ' + (prediction.predicted_rainfall_mm ?? prediction.predictedRainfall ?? '—') + ' mm'
        + '\nCrop classifier: Random Forest. Rainfall estimator: Random Forest regression.'
        + (prediction.recommendationNotice ? '\n' + prediction.recommendationNotice : '');
      $('#survey-result').hidden = false;
    }
    const canApprove = data.status === 'pending';
    const canPublish = data.status === 'awaiting_review' && !!data.draftPrediction;
    const canReject = ['pending', 'approved', 'in_progress', 'awaiting_review', 'failed'].includes(data.status);
    $('#assignment-fields').hidden = !canApprove;
    $('#team-assignee').disabled = !canApprove;
    $('#survey-notes').disabled = !canReject;
    $('#survey-notes').value = '';
    $('#survey-actions').hidden = !canReject;
    $('#reject-survey').hidden = !canReject;
    $('#approve-survey').hidden = !(canApprove || canPublish);
    $('#approve-survey').textContent = canPublish ? 'Release to farmer' : 'Approve & assign visit';
    $('#approve-survey').disabled = true; $('#reject-survey').disabled = false;
    if (canApprove) {
      const members = await loadTeamMembers();
      if (state.activeSurvey?.surveyId !== id || !$('#survey-dialog').open) return;
      const select = $('#team-assignee'); select.replaceChildren(node('option', 'Choose a field team member'));
      select.firstChild.value = '';
      for (const member of members) {
        const option = node('option', member.name + (member.email ? ' · ' + member.email : ''));
        option.value = member.id; select.append(option);
      }
      $('#approve-survey').disabled = members.length === 0;
      if (!members.length) $('#survey-error').textContent = 'No field team accounts are available. Ask the project owner to provision an account with the team role.';
    } else {
      $('#approve-survey').disabled = !canPublish;
    }
  } catch (error) { $('#survey-error').textContent = error.message; if ([401, 403].includes(error.status)) showError(error); }
}

async function processSurvey(action) {
  const survey = state.activeSurvey;
  if (!survey) return;
  if (action === 'approve' && !$('#process-form').reportValidity()) return;
  $('#approve-survey').disabled = $('#reject-survey').disabled = true; $('#survey-error').textContent = '';
  try {
    const body = { surveyId: survey.surveyId, action, notes: $('#survey-notes').value.trim() || null };
    if (action === 'approve') body.teamId = $('#team-assignee').value;
    const result = await api.request('/admin/process-survey', { method: 'POST', body });
    if (!state.authenticated) return;
    $('#survey-dialog').close();
    showToast(action === 'publish' ? 'Result released to farmer: ' + result.crop
      : action === 'approve' ? 'Visit approved and assigned to the field team.' : 'Survey rejected.');
    await refreshDashboard();
  } catch (error) {
    if (!state.authenticated) return;
    $('#survey-error').textContent = error.message;
    if ([401, 403].includes(error.status)) showError(error);
  } finally { $('#approve-survey').disabled = $('#reject-survey').disabled = false; }
}

async function loadSupport() {
  const request = ++state.support.request;
  setListBusy('support', true);
  try {
    const data = await api.request(queryPath('/admin/support', { limit: 20, cursor: state.support.cursors[state.support.page] }));
    if (!state.authenticated || request !== state.support.request) return;
    state.support.rows = data.messages; state.support.next = data.nextCursor;
    const tbody = $('#support-table'); tbody.replaceChildren();
    for (const thread of data.messages) {
      const row = node('tr');
      cell(row, person(thread.farmerName, thread.farmerEmail));
      cell(row, thread.subject); cell(row, date(thread.createdAt));
      cell(row, node('span', thread.status === 'answered' ? 'Answered' : 'Needs reply', 'status ' + (thread.status === 'answered' ? 'completed' : 'pending')));
      cell(row, button('Open message ↗', () => {
        state.activeThread = thread;
        $('#support-title').textContent = thread.subject;
        $('#support-message').textContent = thread.message;
        $('#support-sender').textContent = 'From ' + thread.farmerName;
        $('#support-reply').value = thread.adminReply || '';
        $('#support-error').textContent = ''; $('#send-reply').disabled = false;
        $('#support-dialog').showModal();
      }));
      tbody.append(row);
    }
    $('#support-empty').hidden = data.messages.length > 0;
    updatePagination('support');
  } catch (error) { if (request === state.support.request) showError(error); }
  finally { if (request === state.support.request) setListBusy('support', false); }
}

$('#login-form').addEventListener('submit', async event => {
  event.preventDefault();
  $('#login-submit').disabled = true;
  $('#login-submit').textContent = 'Signing in…';
  $('#login-error').textContent = '';
  try {
    const data = await api.signIn($('#email').value.trim(), $('#password').value);
    state.authenticated = true;
    state.view = 'overview';
    resetPages('farmers'); resetPages('surveys'); resetPages('support');
    $('#login-view').hidden = true;
    $('#dashboard-view').hidden = false;
    $('#password').value = '';
    renderOverview(data);
    await setView('overview');
    state.timer = setInterval(() => { if (!document.hidden) refreshDashboard(); }, 30000);
  } catch (error) { $('#login-error').textContent = error.message; }
  finally { $('#login-submit').disabled = !api.config?.configured; $('#login-submit').textContent = 'Sign in to workspace'; }
});
$('#sign-out').addEventListener('click', logout);
$('#mobile-sign-out').addEventListener('click', logout);
$('#refresh-button').addEventListener('click', refreshDashboard);
for (const nav of document.querySelectorAll('[data-view]')) nav.addEventListener('click', () => setView(nav.dataset.view));
for (const link of document.querySelectorAll('[data-open-view]')) link.addEventListener('click', () => setView(link.dataset.openView));
$('#open-pending').addEventListener('click', () => openSurveyQueue('pending'));
for (const link of document.querySelectorAll('[data-survey-status]')) {
  link.addEventListener('click', () => openSurveyQueue(link.dataset.surveyStatus));
}
for (const chip of document.querySelectorAll('[data-status-chip]')) {
  chip.addEventListener('click', () => openSurveyQueue(chip.dataset.statusChip, false));
}
$('#survey-status').addEventListener('change', () => {
  $('#survey-search').value = ''; resetPages('surveys'); syncSurveyFilters(); loadSurveys();
});
$('#survey-search').addEventListener('input', renderSurveys);
$('#toggle-password').addEventListener('click', () => {
  const showing = $('#password').type !== 'password';
  $('#password').type = showing ? 'password' : 'text';
  $('#toggle-password').textContent = showing ? 'Show' : 'Hide';
  $('#toggle-password').setAttribute('aria-pressed', String(!showing));
  $('#toggle-password').setAttribute('aria-label', showing ? 'Show password' : 'Hide password');
});
$('#today-label').textContent = new Intl.DateTimeFormat(undefined, { weekday: 'short', day: 'numeric', month: 'short' }).format(new Date());
$('#farmer-search').addEventListener('input', renderFarmers);
for (const type of ['farmers', 'surveys', 'support']) {
  $('#' + type + '-prev').addEventListener('click', () => page(type, -1));
  $('#' + type + '-next').addEventListener('click', () => page(type, 1));
}
$('#clear-farmer-filter').addEventListener('click', () => {
  state.farmerFilter = null; resetPages('surveys'); loadSurveys();
});
$('#close-survey').addEventListener('click', () => $('#survey-dialog').close());
$('#close-farmer').addEventListener('click', () => $('#farmer-dialog').close());
$('#view-farmer-surveys').addEventListener('click', () => {
  state.farmerFilter = state.activeFarmer;
  $('#farmer-dialog').close();
  openSurveyQueue('', false);
});
$('#process-form').addEventListener('submit', event => { event.preventDefault(); processSurvey(state.activeSurvey?.status === 'awaiting_review' ? 'publish' : 'approve'); });
$('#reject-survey').addEventListener('click', () => processSurvey('reject'));

$('#close-support').addEventListener('click', () => $('#support-dialog').close());
$('#support-form').addEventListener('submit', async event => {
  event.preventDefault();
  if (!state.activeThread || !$('#support-form').reportValidity()) return;
  $('#send-reply').disabled = true; $('#support-error').textContent = '';
  try {
    await api.request('/admin/support/' + encodeURIComponent(state.activeThread.threadId) + '/reply',
      { method: 'POST', body: { reply: $('#support-reply').value.trim() } });
    if (!state.authenticated) return;
    $('#support-dialog').close(); showToast('Reply sent to the farmer.'); await refreshDashboard();
  } catch (error) { $('#support-error').textContent = error.message; }
  finally { $('#send-reply').disabled = false; }
});

try {
  const config = await api.loadConfig();
  $('#login-submit').disabled = !config.configured;
  $('#login-submit').textContent = 'Sign in to workspace';
  if (!config.configured) $('#login-error').textContent = 'Administrator sign-in needs configuration. Contact your project administrator.';
} catch (error) {
  $('#login-error').textContent = error.message + ' Reload this page to reconnect.';
  $('#login-submit').textContent = 'Connection unavailable';
}
