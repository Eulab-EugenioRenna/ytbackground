# ytbackground audio server

Server HTTP minimale che usa `yt-dlp` per restituire l'audio di un video YouTube via richieste POST.

## Endpoint

### `GET /health`

Verifica che il servizio sia attivo.

### `POST /audio/stream`

Restituisce lo stream audio come `audio/mpeg`.

Supporta anche `GET /audio/stream?videoId=...`, utile per client come iOS `AVPlayer`.

### `POST /audio/file`

Scarica e restituisce un file audio come allegato.

Supporta anche `GET /audio/file?videoId=...`.

## Body JSON

```json
{
  "videoId": "dQw4w9WgXcQ"
}
```

`videoId` puo' essere sia l'ID YouTube sia l'URL completo del video.

## Avvio locale

Prerequisiti:

- `node >= 20`
- `yt-dlp`
- `ffmpeg`

Esegui:

```bash
cd server
npm start
```

## Docker

Build:

```bash
docker build -t ytbackground-audio-server ./server
```

Run:

```bash
docker run --rm -p 3000:3000 ytbackground-audio-server
```

## Docker Compose

Dalla root del progetto:

```bash
docker compose up --build
```

Per fermarlo:

```bash
docker compose down
```

## Esempi curl

Stream:

```bash
curl -X POST http://localhost:3000/audio/stream \
  -H 'Content-Type: application/json' \
  -d '{"videoId":"dQw4w9WgXcQ"}' \
  --output sample.mp3
```

Stream via GET:

```bash
curl "http://localhost:3000/audio/stream?videoId=dQw4w9WgXcQ" --output sample.mp3
```

File:

```bash
curl -X POST http://localhost:3000/audio/file \
  -H 'Content-Type: application/json' \
  -d '{"videoId":"dQw4w9WgXcQ"}' \
  -OJ
```

## Variabili ambiente

- `HOST`: default `0.0.0.0`
- `PORT`: default `3000`
- `TEMP_ROOT`: directory temporanea per i download file
- `MAX_BODY_SIZE`: dimensione massima body request in byte, default `32768`
