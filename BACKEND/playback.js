'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');

const PLAYBACK_GRACE_MS = 5 * 60 * 1000;
const MAX_PLAYLIST_ITEMS = 120000;

function firstLanAddress() {
  const interfaces = os.networkInterfaces();
  for (const records of Object.values(interfaces)) {
    for (const record of records || []) {
      if (record.family !== 'IPv4' || record.internal) continue;
      if (/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(record.address)) return record.address;
    }
  }
  return '127.0.0.1';
}

function zonedParts(timestamp, timeZone) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(timestamp));
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    date: `${values.year}-${values.month}-${values.day}`,
    time: `${values.hour}:${values.minute}`,
    second: values.second,
  };
}

function wallClockToEpoch(date, time, timeZone) {
  const [year, month, day] = date.split('-').map(Number);
  const [hour, minute] = time.split(':').map(Number);
  const target = Date.UTC(year, month - 1, day, hour, minute, 0);
  let guess = target;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const part = zonedParts(guess, timeZone);
    const [actualYear, actualMonth, actualDay] = part.date.split('-').map(Number);
    const [actualHour, actualMinute] = part.time.split(':').map(Number);
    const represented = Date.UTC(actualYear, actualMonth - 1, actualDay, actualHour, actualMinute, Number(part.second));
    guess += target - represented;
  }
  return guess;
}

function requestVlcRaw(baseUrl, route, { method = 'GET', headers = {}, body = '' } = {}) {
  const target = new URL(route, `${baseUrl.replace(/\/$/, '')}/`);
  const transport = target.protocol === 'https:' ? https : http;
  const requestHeaders = { ...headers };
  if (body && !requestHeaders['content-length']) requestHeaders['content-length'] = Buffer.byteLength(body);
  return new Promise((resolve, reject) => {
    const request = transport.request(target, {
      method,
      headers: requestHeaders,
      // VLC Android creates a self-signed HTTPS certificate for its LAN remote
      // access server. The base URL is explicitly supplied by the local owner.
      rejectUnauthorized: false,
    }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode || 0,
        headers: response.headers,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.setTimeout(8000, () => request.destroy(new Error('VLC request timed out.')));
    request.on('error', reject);
    if (body) request.write(body);
    request.end();
  });
}

function createPlaybackService({ db, getVideoDurationSeconds, port }) {
  const timezone = process.env.SMARTADS_TIMEZONE || 'Africa/Douala';
  const remoteBaseUrl = String(process.env.VLC_REMOTE_URL || '').trim().replace(/\/$/, '');
  const remoteOtp = String(process.env.VLC_REMOTE_OTP || '').trim();
  const esp32Url = String(process.env.ESP32_RELAY_URL || '').trim();
  const esp32Token = String(process.env.ESP32_DEVICE_TOKEN || '').trim();
  const explicitBillboardId = String(process.env.SMARTADS_PLAYBACK_BILLBOARD_ID || '').trim();
  const streamBaseUrl = String(process.env.SMARTADS_PUBLIC_URL || `http://${firstLanAddress()}:${port}`).trim().replace(/\/$/, '');
  const playbackSecret = process.env.PLAYBACK_URL_SECRET || process.env.JWT_SECRET || 'smartads-local-demo-secret-change-me';
  const powerOnDelayMs = Math.max(0, Number(process.env.ESP32_POWER_ON_DELAY_MS || 5000));

  let sessionCookie = '';
  let authenticationPromise = null;
  let interval = null;
  let tickRunning = false;
  let activeBookingId = '';
  let relayOn = false;
  let nextConnectionAttemptAt = 0;
  let state = {
    enabled: false,
    vlcConnected: false,
    relayConfigured: Boolean(esp32Url && esp32Token),
    publicStreamUrl: streamBaseUrl,
    billboardId: null,
    activeBookingId: null,
    lastCommandAt: null,
    lastError: null,
  };

  function configuredBillboardId() {
    const boards = db.prepare('SELECT id FROM billboards ORDER BY created_at').all();
    if (explicitBillboardId) return boards.some((board) => board.id === explicitBillboardId) ? explicitBillboardId : null;
    return boards.length === 1 ? boards[0].id : null;
  }

  function updateConfigurationStatus() {
    const boards = db.prepare('SELECT id FROM billboards ORDER BY created_at').all();
    state.billboardId = configuredBillboardId();
    const streamHost = new URL(streamBaseUrl).hostname;
    const streamAddressReady = !['localhost', '127.0.0.1', '::1'].includes(streamHost);
    state.enabled = Boolean(remoteBaseUrl && remoteOtp && streamAddressReady && state.billboardId);
    if (!remoteBaseUrl || !remoteOtp) state.lastError = 'Set VLC_REMOTE_URL and VLC_REMOTE_OTP after enabling VLC Remote Access.';
    else if (!streamAddressReady) state.lastError = 'Set SMARTADS_PUBLIC_URL to the backend computer Wi-Fi address so the TV can fetch video.';
    else if (!state.billboardId && boards.length === 0) state.lastError = 'Create a billboard before configuring playback.';
    else if (!state.billboardId && explicitBillboardId) state.lastError = 'SMARTADS_PLAYBACK_BILLBOARD_ID does not match a registered billboard.';
    else if (!state.billboardId) state.lastError = 'Set SMARTADS_PLAYBACK_BILLBOARD_ID when more than one billboard is registered.';
    else if (state.lastError?.startsWith('Set ') || state.lastError?.startsWith('Create a billboard') || state.lastError?.startsWith('SMARTADS_PLAYBACK_BILLBOARD_ID')) state.lastError = null;
  }

  async function authenticateVlc() {
    if (!remoteBaseUrl || !remoteOtp) throw new Error('VLC Remote Access address or one-time password is not configured.');
    const form = new URLSearchParams({ code: remoteOtp }).toString();
    const result = await requestVlcRaw(remoteBaseUrl, '/verify-code', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: form,
    });
    const cookies = result.headers['set-cookie'] || [];
    const cookie = cookies.map((value) => value.split(';')[0]).filter(Boolean).join('; ');
    if (!cookie || result.status < 200 || result.status >= 400) {
      throw new Error(`VLC rejected the one-time password (HTTP ${result.status}). Refresh its Remote Access code and update VLC_REMOTE_OTP.`);
    }
    sessionCookie = cookie;
    const probe = await requestVlc('/wsticket');
    if (probe.status < 200 || probe.status >= 300) {
      sessionCookie = '';
      throw new Error(`VLC Remote Access login did not complete (HTTP ${probe.status}).`);
    }
    state.vlcConnected = true;
    state.lastError = null;
  }

  async function ensureVlcSession() {
    if (sessionCookie) return;
    if (!authenticationPromise) {
      authenticationPromise = authenticateVlc().finally(() => { authenticationPromise = null; });
    }
    return authenticationPromise;
  }

  async function requestVlc(route, options = {}) {
    if (!sessionCookie && options.auth !== false) await ensureVlcSession();
    const headers = { ...(options.headers || {}) };
    if (sessionCookie && options.auth !== false) headers.cookie = sessionCookie;
    const response = await requestVlcRaw(remoteBaseUrl, route, { ...options, headers });
    if (response.status === 401 || response.status === 403) {
      state.vlcConnected = false;
      throw new Error(`VLC returned HTTP ${response.status}. Check that playback control is enabled and VLC is open on the TV.`);
    }
    if (response.status < 200 || response.status >= 300) {
      throw new Error(`VLC Remote Access returned HTTP ${response.status}.`);
    }
    return response;
  }

  function makeSignature(bookingId, expiresAt) {
    return crypto.createHmac('sha256', playbackSecret).update(`${bookingId}\n${expiresAt}`).digest('base64url');
  }

  function signedPlaybackQuery(booking, expiresAt) {
    const query = new URLSearchParams({ booking: booking.id, exp: String(expiresAt) });
    query.set('sig', makeSignature(booking.id, expiresAt));
    return query.toString();
  }

  function publicPlaylistUrl(booking, expiresAt) {
    return `${streamBaseUrl}/api/playback/playlist/${encodeURIComponent(booking.id)}.m3u?${signedPlaybackQuery(booking, expiresAt)}`;
  }

  function validateSignedBooking(reviewId, query) {
    const bookingId = String(query.get('booking') || '');
    const expiresAt = Number(query.get('exp') || 0);
    const supplied = String(query.get('sig') || '');
    if (!bookingId || !Number.isSafeInteger(expiresAt) || expiresAt < Date.now() || expiresAt > Date.now() + 24 * 60 * 60 * 1000) return null;
    const expected = Buffer.from(makeSignature(bookingId, expiresAt));
    const actual = Buffer.from(supplied);
    if (!actual.length || expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null;
    const booking = reviewId
      ? db.prepare(`SELECT b.*, r.file_path, r.mime_type, r.status AS review_status
          FROM bookings b JOIN video_reviews r ON r.id=b.review_id
          WHERE b.id=? AND b.review_id=? AND b.status='confirmed'`).get(bookingId, reviewId)
      : db.prepare(`SELECT b.*, r.file_path, r.mime_type, r.status AS review_status
          FROM bookings b JOIN video_reviews r ON r.id=b.review_id
          WHERE b.id=? AND b.status='confirmed'`).get(bookingId);
    if (!booking || booking.review_status !== 'approved') return null;
    const endAt = wallClockToEpoch(booking.booking_date, booking.end_time, timezone);
    if (expiresAt > endAt + PLAYBACK_GRACE_MS || Date.now() > endAt + PLAYBACK_GRACE_MS) return null;
    return { booking, expiresAt, endAt };
  }

  function sendError(res, status, message) {
    res.writeHead(status, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    res.end(message);
  }

  function streamFile(req, res, filePath, mimeType) {
    let stat;
    try { stat = fs.statSync(filePath); } catch { return sendError(res, 404, 'Advertisement video not found.'); }
    const rangeHeader = req.headers.range;
    let start = 0;
    let end = stat.size - 1;
    let status = 200;
    if (rangeHeader) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
      if (!match) return sendError(res, 416, 'Invalid byte range.');
      if (!match[1]) {
        const suffix = Number(match[2]);
        if (!suffix) return sendError(res, 416, 'Invalid byte range.');
        start = Math.max(0, stat.size - suffix);
      } else {
        start = Number(match[1]);
        if (match[2]) end = Math.min(end, Number(match[2]));
      }
      if (start >= stat.size || end < start) {
        res.writeHead(416, { 'content-range': `bytes */${stat.size}`, 'cache-control': 'no-store' });
        res.end();
        return;
      }
      status = 206;
    }
    const headers = {
      'content-type': mimeType || 'application/octet-stream',
      'accept-ranges': 'bytes',
      'content-length': String(end - start + 1),
      'cache-control': 'private, no-store',
    };
    if (status === 206) headers['content-range'] = `bytes ${start}-${end}/${stat.size}`;
    res.writeHead(status, headers);
    if (req.method === 'HEAD') {
      res.end();
      return;
    }
    const stream = fs.createReadStream(filePath, { start, end });
    res.on('close', () => stream.destroy());
    stream.on('error', () => { if (!res.headersSent) sendError(res, 500, 'Unable to read advertisement video.'); else res.destroy(); });
    stream.pipe(res);
  }

  async function serveMediaRequest(req, res, route, url) {
    const playlistMatch = /^\/api\/playback\/playlist\/([^/]+)\.m3u$/.exec(route);
    if (playlistMatch) {
      const bookingId = decodeURIComponent(playlistMatch[1]);
      const signed = validateSignedBooking(null, url.searchParams);
      if (!signed || signed.booking.id !== bookingId) return sendError(res, 403, 'Playback link is invalid or expired.');
      const review = db.prepare('SELECT id,file_path,mime_type FROM video_reviews WHERE id=?').get(signed.booking.review_id);
      let duration;
      try { duration = getVideoDurationSeconds(review.file_path); } catch { return sendError(res, 500, 'Could not prepare the scheduled advertisement.'); }
      const clipUrl = `${streamBaseUrl}/api/playback/media/${encodeURIComponent(review.id)}?${signedPlaybackQuery(signed.booking, signed.expiresAt)}`;
      const slotSeconds = Math.max(1, Math.ceil((signed.endAt - wallClockToEpoch(signed.booking.booking_date, signed.booking.start_time, timezone)) / 1000));
      const entries = Math.ceil(slotSeconds / duration) + 1;
      if (!Number.isSafeInteger(entries) || entries > MAX_PLAYLIST_ITEMS) return sendError(res, 413, 'This clip is too short to repeat for the full booking slot.');
      const lines = ['#EXTM3U'];
      for (let index = 0; index < entries; index += 1) {
        lines.push(`#EXTINF:${duration.toFixed(3)},SMARTADS advertisement`);
        lines.push(clipUrl);
      }
      const body = `${lines.join('\n')}\n`;
      res.writeHead(200, {
        'content-type': 'audio/x-mpegurl; charset=utf-8',
        'content-length': Buffer.byteLength(body),
        'cache-control': 'private, no-store',
      });
      res.end(req.method === 'HEAD' ? undefined : body);
      return;
    }

    const mediaMatch = /^\/api\/playback\/media\/([^/]+)$/.exec(route);
    if (!mediaMatch) return sendError(res, 404, 'Playback resource not found.');
    const reviewId = decodeURIComponent(mediaMatch[1]);
    const signed = validateSignedBooking(reviewId, url.searchParams);
    if (!signed) return sendError(res, 403, 'Playback link is invalid or expired.');
    streamFile(req, res, signed.booking.file_path, signed.booking.mime_type);
  }

  async function callEsp32(stateName) {
    if (!esp32Url || !esp32Token) return false;
    const response = await fetch(esp32Url, {
      method: 'POST',
      headers: { authorization: `Bearer ${esp32Token}`, 'content-type': 'text/plain' },
      body: stateName.toUpperCase(),
      signal: AbortSignal.timeout(4000),
    });
    if (!response.ok) throw new Error(`ESP32 relay returned HTTP ${response.status}.`);
    return true;
  }

  async function setRelayForBillboard(billboardId, stateName) {
    updateConfigurationStatus();
    if (!state.billboardId || billboardId !== state.billboardId) return false;
    if (!esp32Url || !esp32Token) return false;
    await callEsp32(stateName);
    relayOn = stateName === 'on';
    state.lastCommandAt = new Date().toISOString();
    if (stateName === 'off') {
      activeBookingId = '';
      state.activeBookingId = null;
    }
    return true;
  }

  async function pauseVlc() {
    await requestVlc('/playback-event?message=pause');
  }

  async function switchBillboardPower(billboardId, isOn) {
    if (!state.billboardId || billboardId !== state.billboardId || !esp32Url || !esp32Token) return;
    if (!isOn) {
      try { await pauseVlc(); } catch { /* Power-off must still proceed if VLC has lost Wi-Fi. */ }
      await setRelayForBillboard(billboardId, 'off');
      return;
    }
    await setRelayForBillboard(billboardId, 'on');
  }

  async function playBooking(booking) {
    if (esp32Url && esp32Token && !relayOn) {
      await callEsp32('on');
      relayOn = true;
      state.lastCommandAt = new Date().toISOString();
      if (powerOnDelayMs) await delay(powerOnDelayMs);
    }
    const endAt = wallClockToEpoch(booking.booking_date, booking.end_time, timezone);
    const expiresAt = endAt + PLAYBACK_GRACE_MS;
    const playlistUrl = publicPlaylistUrl(booking, expiresAt);
    const playRoute = `/play?${new URLSearchParams({ id: '0', path: playlistUrl }).toString()}`;
    await requestVlc(playRoute);
    activeBookingId = booking.id;
    state.activeBookingId = booking.id;
    state.lastCommandAt = new Date().toISOString();
    state.lastError = null;
    state.vlcConnected = true;
  }

  async function stopBooking() {
    try { await pauseVlc(); } finally {
      if (esp32Url && esp32Token && relayOn) {
        await callEsp32('off');
        relayOn = false;
        state.lastCommandAt = new Date().toISOString();
      }
      activeBookingId = '';
      state.activeBookingId = null;
    }
  }

  function activeBookingNow() {
    updateConfigurationStatus();
    if (!state.billboardId) return null;
    const current = zonedParts(Date.now(), timezone);
    return db.prepare(`SELECT b.*, r.file_path, r.mime_type
      FROM bookings b
      JOIN video_reviews r ON r.id=b.review_id
      JOIN billboards x ON x.id=b.billboard_id
      WHERE b.billboard_id=? AND x.is_active=1 AND b.booking_date=? AND b.status='confirmed'
      AND b.start_time<=? AND b.end_time>?
      ORDER BY b.start_time LIMIT 1`).get(state.billboardId, current.date, current.time, current.time) || null;
  }

  async function tick() {
    if (tickRunning) return;
    tickRunning = true;
    try {
      updateConfigurationStatus();
      if (!state.enabled) return;
      const booking = activeBookingNow();
      if (!booking) {
        if (activeBookingId || relayOn) await stopBooking();
        return;
      }
      if (booking.id === activeBookingId) return;
      if (!sessionCookie && Date.now() < nextConnectionAttemptAt) return;
      try {
        await playBooking(booking);
      } catch (error) {
        state.lastError = error.message || 'Could not start the scheduled playback.';
        state.vlcConnected = Boolean(sessionCookie);
        nextConnectionAttemptAt = Date.now() + 15000;
      }
    } catch (error) {
      state.lastError = error.message || 'Playback scheduler failed.';
    } finally {
      tickRunning = false;
    }
  }

  function start() {
    updateConfigurationStatus();
    if (!state.enabled) {
      console.log(`SMARTADS playback scheduler is waiting for configuration: ${state.lastError}`);
    } else {
      console.log(`SMARTADS playback scheduler ready for billboard ${state.billboardId} in ${timezone}.`);
      void ensureVlcSession().catch((error) => {
        state.lastError = error.message || 'Could not connect to VLC Remote Access.';
        console.error(`SMARTADS could not connect to VLC Remote Access: ${state.lastError}`);
      });
    }
    interval = setInterval(() => { void tick(); }, 2000);
    interval.unref?.();
    void tick();
  }

  function getStatus() {
    updateConfigurationStatus();
    return { ...state };
  }

  function stop() {
    if (interval) clearInterval(interval);
    interval = null;
  }

  return {
    start,
    stop,
    getStatus,
    serveMediaRequest,
    switchBillboardPower,
  };
}

module.exports = { createPlaybackService };
