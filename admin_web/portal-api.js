export class PortalError extends Error {
  constructor(message, status = 0) { super(message); this.name = 'PortalError'; this.status = status; }
}

const AUTH_ERRORS = {
  INVALID_LOGIN_CREDENTIALS: 'The email or password is incorrect.',
  INVALID_PASSWORD: 'The email or password is incorrect.',
  EMAIL_NOT_FOUND: 'The email or password is incorrect.',
  USER_DISABLED: 'This account has been disabled. Contact your project administrator.',
  TOO_MANY_ATTEMPTS_TRY_LATER: 'Too many sign-in attempts. Please wait and try again.',
  API_KEY_INVALID: 'Administrator sign-in needs configuration. Contact your project administrator.',
  OPERATION_NOT_ALLOWED: 'Email and password sign-in is not enabled for this project.',
  TOKEN_EXPIRED: 'Your session expired. Please sign in again.',
  INVALID_REFRESH_TOKEN: 'Your session expired. Please sign in again.',
};

export class AdminApi {
  constructor({ baseUrl = '', fetcher = globalThis.fetch.bind(globalThis), timeoutMs = 90000, role = 'admin' } = {}) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.role = role;
    this.fetcher = fetcher;
    this.timeoutMs = timeoutMs;
    this.session = null;
    this.config = null;
    this.epoch = 0;
    this.refreshInFlight = null;
  }

  async fetchJson(url, options = {}) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetcher(url, {
        ...options, cache: 'no-store', signal: controller.signal,
      });
      let data;
      try { data = await response.json(); }
      catch { throw new PortalError('The server returned an unexpected response.', response.status); }
      if (!response.ok) {
        const code = data.error?.message?.split(' : ')[0];
        const detail = Array.isArray(data.detail)
          ? data.detail.map(item => item.msg || 'Check the form.').join(' ')
          : data.detail;
        throw new PortalError(
          AUTH_ERRORS[code] || detail || 'The request could not be completed. Please try again.',
          response.status,
        );
      }
      return data;
    } catch (error) {
      if (error instanceof PortalError) throw error;
      if (error.name === 'AbortError') throw new PortalError('The request timed out. Please try again.');
      throw new PortalError('Could not connect. Check your connection and try again.');
    } finally {
      clearTimeout(timeout);
    }
  }

  async loadConfig() {
    this.config = await this.fetchJson(this.baseUrl + '/admin/config');
    return this.config;
  }

  async signIn(email, password) {
    this.signOut();
    const epoch = this.epoch;
    if (!this.config?.configured) throw new PortalError('Administrator sign-in is not configured yet.');
    const data = await this.fetchJson(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key='
        + encodeURIComponent(this.config.apiKey),
      { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, returnSecureToken: true }) },
    );
    if (epoch !== this.epoch) throw new PortalError('Sign-in was cancelled.');
    this.session = {
      idToken: data.idToken, refreshToken: data.refreshToken,
      expiresAt: Date.now() + Number(data.expiresIn) * 1000,
    };
    try {
      // The server verifies the token and users/{uid}.role before returning data.
      const overview = await this.request(this.role === 'team' ? '/team/overview' : '/admin/overview');
      if (epoch !== this.epoch || !this.session) throw new PortalError('Sign-in was cancelled.', 401);
      return overview;
    } catch (error) {
      if (epoch === this.epoch) this.signOut();
      if (error.status === 403) {
        throw new PortalError(this.role === 'team'
          ? 'This account does not have field-team access. Ask your administrator for the correct account.'
          : 'This account does not have administrator access. Farmers use the phone app; field staff use the team workspace.', 403);
      }
      throw error;
    }
  }

  signOut() {
    this.epoch++;
    this.session = null;
    this.refreshInFlight = null;
  }

  async refreshToken() {
    if (this.refreshInFlight) return this.refreshInFlight;
    if (!this.session) throw new PortalError('Please sign in again.', 401);
    const epoch = this.epoch;
    const token = this.session.refreshToken;
    const pending = this.fetchJson(
      'https://securetoken.googleapis.com/v1/token?key=' + encodeURIComponent(this.config.apiKey),
      { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: token }).toString() },
    ).then(data => {
      if (epoch !== this.epoch || !this.session) throw new PortalError('Please sign in again.', 401);
      this.session = { idToken: data.id_token, refreshToken: data.refresh_token,
        expiresAt: Date.now() + Number(data.expires_in) * 1000 };
    }).finally(() => {
      if (this.refreshInFlight === pending) this.refreshInFlight = null;
    });
    this.refreshInFlight = pending;
    return pending;
  }

  async request(path, { method = 'GET', body } = {}, retry = true) {
    if (!this.session) throw new PortalError('Please sign in again.', 401);
    if (this.session.expiresAt - Date.now() < 45000) await this.refreshToken();
    const options = { method, headers: { Authorization: 'Bearer ' + this.session.idToken } };
    if (body !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    try {
      return await this.fetchJson(this.baseUrl + path, options);
    } catch (error) {
      if (error.status === 401 && retry) {
        await this.refreshToken();
        return this.request(path, { method, body }, false);
      }
      throw error;
    }
  }
}
