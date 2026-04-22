const http = require('http');
const os = require('os');
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const { randomUUID } = require('crypto');

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';
const TEMP_ROOT = process.env.TEMP_ROOT || path.join(os.tmpdir(), 'ytbackground-audio');
const MAX_BODY_SIZE = Number(process.env.MAX_BODY_SIZE || 32 * 1024);

fs.mkdirSync(TEMP_ROOT, { recursive: true });

function log(message, details = {}) {
  const payload = Object.entries(details)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${key}=${JSON.stringify(value)}`)
    .join(' ');
  process.stdout.write(`[ytbackground] ${message}${payload ? ` ${payload}` : ''}\n`);
}

function sendJson(response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body)
  });
  response.end(body);
}

function parseJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = '';

    request.on('data', (chunk) => {
      body += chunk;
      if (Buffer.byteLength(body) > MAX_BODY_SIZE) {
        reject(new Error('Request body too large'));
        request.destroy();
      }
    });

    request.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error('Invalid JSON body'));
      }
    });

    request.on('error', reject);
  });
}

function getRequestURL(request) {
  return new URL(request.url, `http://${request.headers.host || 'localhost'}`);
}

function normalizeVideoId(rawVideoId) {
  if (typeof rawVideoId !== 'string') {
    return null;
  }

  const trimmed = rawVideoId.trim();
  if (!trimmed) {
    return null;
  }

  return trimmed;
}

function buildVideoUrl(videoId) {
  if (videoId.startsWith('http://') || videoId.startsWith('https://')) {
    return videoId;
  }

  return `https://www.youtube.com/watch?v=${videoId}`;
}

function spawnYtDlp(args) {
  return spawn('yt-dlp', args, {
    stdio: ['ignore', 'pipe', 'pipe']
  });
}

function sanitizeFileName(name) {
  const normalized = String(name || 'audio')
    .replace(/[<>:"/\\|?*\x00-\x1f]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();

  return normalized || 'audio';
}

function getFileExtensionFromName(fileName) {
  const ext = path.extname(fileName).toLowerCase();
  if (!ext) {
    return '.m4a';
  }
  return ext;
}

function parseRangeHeader(rangeHeader, fileSize) {
  if (typeof rangeHeader !== 'string') {
    return null;
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
  if (!match) {
    return 'invalid';
  }

  const [, startValue, endValue] = match;
  if (!startValue && !endValue) {
    return 'invalid';
  }

  let start;
  let end;

  if (!startValue) {
    const suffixLength = Number(endValue);
    if (!Number.isInteger(suffixLength) || suffixLength <= 0) {
      return 'invalid';
    }

    start = Math.max(fileSize - suffixLength, 0);
    end = fileSize - 1;
  } else {
    start = Number(startValue);
    end = endValue ? Number(endValue) : fileSize - 1;

    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || start > end) {
      return 'invalid';
    }
  }

  if (start >= fileSize) {
    return 'invalid';
  }

  end = Math.min(end, fileSize - 1);
  return { start, end };
}

function fetchMetadata(videoUrl) {
  return new Promise((resolve, reject) => {
    const child = spawnYtDlp(['--dump-single-json', '--no-playlist', videoUrl]);
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });

    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `yt-dlp exited with code ${code}`));
        return;
      }

      try {
        const parsed = JSON.parse(stdout);
        resolve(parsed);
      } catch {
        reject(new Error('Failed to parse yt-dlp metadata output'));
      }
    });
  });
}

function streamAudio(response, videoUrl, suggestedName) {
  return new Promise((resolve, reject) => {
    const child = spawnYtDlp([
      '-f',
      'bestaudio/best',
      '--no-playlist',
      '--extract-audio',
      '--audio-format',
      'mp3',
      '--audio-quality',
      '0',
      '--output',
      '-',
      videoUrl
    ]);

    let stderr = '';
    let headersSent = false;
    const requestId = response.req?.requestId;

    child.stderr.on('data', (chunk) => {
      stderr += chunk;
      log('yt-dlp stream stderr', {
        requestId,
        line: String(chunk).trim()
      });
    });

    child.stdout.once('data', (firstChunk) => {
      headersSent = true;
      log('stream response started', {
        requestId,
        bytes: firstChunk.length,
        fileName: `${suggestedName}.mp3`
      });
      response.writeHead(200, {
        'Content-Type': 'audio/mpeg',
        'Content-Disposition': `inline; filename="${suggestedName}.mp3"`,
        'Transfer-Encoding': 'chunked'
      });
      response.write(firstChunk);
      child.stdout.pipe(response);
    });

    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `yt-dlp exited with code ${code}`));
        return;
      }

      if (!headersSent) {
        response.writeHead(204);
        response.end();
      }

      log('stream response completed', {
        requestId,
        exitCode: code,
        headersSent
      });

      resolve();
    });

    response.on('close', () => {
      if (!response.writableEnded) {
        child.kill('SIGTERM');
      }
    });
  });
}

async function downloadAudioFile(response, videoUrl, suggestedName) {
  const jobId = randomUUID();
  const requestId = response.req?.requestId;
  const outputTemplate = path.join(TEMP_ROOT, `${jobId}.%(ext)s`);
  let downloadedFile;
  const args = [
    '-f',
    'bestaudio/best',
    '--no-playlist',
    '--extract-audio',
    '--audio-format',
    'mp3',
    '--audio-quality',
    '0',
    '--output',
    outputTemplate,
    videoUrl
  ];

  await new Promise((resolve, reject) => {
    const child = spawnYtDlp(args);
    let stderr = '';

    child.stderr.on('data', (chunk) => {
      stderr += chunk;
      log('yt-dlp file stderr', {
        requestId,
        jobId,
        line: String(chunk).trim()
      });
    });

    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `yt-dlp exited with code ${code}`));
        return;
      }
      resolve();
    });
  });

  const files = fs
    .readdirSync(TEMP_ROOT)
    .filter((file) => file.startsWith(`${jobId}.`))
    .map((file) => path.join(TEMP_ROOT, file));

  if (files.length !== 1) {
    throw new Error('Downloaded file not found');
  }

  downloadedFile = files[0];
  const ext = getFileExtensionFromName(downloadedFile);
  const finalName = `${suggestedName}${ext}`;
  const stat = fs.statSync(downloadedFile);
  const requestedRange = parseRangeHeader(response.req?.headers.range, stat.size);

  if (requestedRange === 'invalid') {
    response.writeHead(416, {
      'Content-Range': `bytes */${stat.size}`,
      'Accept-Ranges': 'bytes'
    });
    response.end();
    return;
  }

  const start = requestedRange?.start ?? 0;
  const end = requestedRange?.end ?? (stat.size - 1);
  const isPartial = requestedRange != null;

  log('file response ready', {
    requestId,
    jobId,
    path: downloadedFile,
    size: stat.size,
    range: response.req?.headers.range,
    start,
    end,
    partial: isPartial
  });

  response.writeHead(isPartial ? 206 : 200, {
    'Content-Type': 'audio/mpeg',
    'Content-Length': end - start + 1,
    'Content-Disposition': `inline; filename="${finalName}"`,
    'Accept-Ranges': 'bytes',
    ...(isPartial ? { 'Content-Range': `bytes ${start}-${end}/${stat.size}` } : {})
  });

  try {
    await new Promise((resolve, reject) => {
      const readStream = fs.createReadStream(downloadedFile, { start, end });
      readStream.on('error', reject);
      readStream.on('close', resolve);
      readStream.pipe(response);
    });
    log('file response completed', {
      requestId,
      jobId,
      bytes: end - start + 1,
      partial: isPartial
    });
  } finally {
    if (downloadedFile && fs.existsSync(downloadedFile)) {
      fs.unlinkSync(downloadedFile);
      log('temporary file deleted', {
        requestId,
        jobId,
        path: downloadedFile
      });
    }
  }
}

async function handleAudioRequest(request, response, asAttachment) {
  let videoId;

  if (request.method === 'GET') {
    videoId = normalizeVideoId(getRequestURL(request).searchParams.get('videoId'));
  } else {
    const contentType = request.headers['content-type'] || '';
    if (!contentType.includes('application/json')) {
      sendJson(response, 415, { error: 'Content-Type must be application/json' });
      return;
    }

    let payload;
    try {
      payload = await parseJsonBody(request);
    } catch (error) {
      sendJson(response, 400, { error: error.message });
      return;
    }

    videoId = normalizeVideoId(payload.videoId);
  }

  if (!videoId) {
    sendJson(response, 400, { error: 'Missing videoId' });
    return;
  }

  const videoUrl = buildVideoUrl(videoId);
  log('audio request accepted', {
    requestId: request.requestId,
    method: request.method,
    path: getRequestURL(request).pathname,
    videoId,
    asAttachment,
    range: request.headers.range,
    userAgent: request.headers['user-agent']
  });

  try {
    const metadata = await fetchMetadata(videoUrl);
    const suggestedName = sanitizeFileName(metadata.title || videoId);
    log('metadata resolved', {
      requestId: request.requestId,
      title: metadata.title,
      duration: metadata.duration,
      suggestedName
    });

    if (asAttachment) {
      await downloadAudioFile(response, videoUrl, suggestedName);
      return;
    }

    await streamAudio(response, videoUrl, suggestedName);
  } catch (error) {
    log('audio request failed', {
      requestId: request.requestId,
      message: error.message
    });
    if (!response.headersSent) {
      sendJson(response, 502, { error: error.message });
    } else if (!response.writableEnded) {
      response.destroy(error);
    }
  }
}

const server = http.createServer(async (request, response) => {
  request.requestId = randomUUID();
  const requestURL = getRequestURL(request);

  log('request received', {
    requestId: request.requestId,
    method: request.method,
    path: requestURL.pathname,
    search: requestURL.search,
    range: request.headers.range,
    userAgent: request.headers['user-agent']
  });

  response.on('finish', () => {
    log('response finished', {
      requestId: request.requestId,
      statusCode: response.statusCode,
      path: requestURL.pathname
    });
  });

  if (request.method === 'GET' && requestURL.pathname === '/health') {
      sendJson(response, 200, { ok: true });
    return;
  }

  if ((request.method === 'GET' || request.method === 'POST') && requestURL.pathname === '/audio/stream') {
    await handleAudioRequest(request, response, false);
    return;
  }

  if ((request.method === 'GET' || request.method === 'POST') && requestURL.pathname === '/audio/file') {
    await handleAudioRequest(request, response, true);
    return;
  }

  sendJson(response, 404, { error: 'Not found' });
});

server.listen(PORT, HOST, () => {
  process.stdout.write(`ytbackground audio server listening on http://${HOST}:${PORT}\n`);
});
