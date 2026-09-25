# SMARTADS

SMARTADS is a Flutter billboard booking app with a Node.js and SQLite API. Video review and payment are simulated for this demo; no real AI review or money transfer is performed.

## Current local run

The API is running at `http://localhost:3000` and the Chrome app at `http://localhost:8080`.

## Run it again in Chrome

Start the API in one terminal:

```sh
cd /home/tchoua/Desktop/SMARTADS/BACKEND
PORT=3000 JWT_SECRET='replace-with-a-long-random-secret' ADMIN_EMAIL='admin@smartads.local' ADMIN_PASSWORD='ChangeMe123!' npm start
```

Build and serve the Flutter app in another terminal:

```sh
cd /home/tchoua/Desktop/SMARTADS/FRONTEND
flutter pub get
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define=API_BASE_URL=http://localhost:3000
python3 -m http.server 8080 --bind 0.0.0.0 --directory build/web
```

Open `http://localhost:8080` in Chrome. On systems without a working GPU, start Chrome with software rendering:

```sh
LIBGL_ALWAYS_SOFTWARE=1 google-chrome --app=http://localhost:8080 --use-gl=angle --use-angle=swiftshader --enable-webgl
```

## Demo accounts and flow

- Create advertiser and billboard-owner accounts from the signup page.
- Sign in as an owner and add a billboard with a location and hourly price in FCFA.
- Sign in as an advertiser, reserve an open slot, upload a supported video, and complete the simulated MTN Mobile Money or Orange Money payment form.
- Admin: `admin@smartads.local` / `ChangeMe123!` (created by the startup environment above).

The mock payment form validates a Cameroon mobile number. The API records the payment method and result but does not save the phone number or charge it.

## Android TV playback

SMARTADS can send confirmed bookings to VLC for Android over the local Wi-Fi.
The TV fetches each approved clip from the Node backend, while the ESP32
receives separate relay on/off commands. For VLC Remote Access pairing, ESP32
firmware, local `.env` settings, and the first-play walkthrough, see
[the backend setup guide](BACKEND/README.md#android-tv-vlc-playback-on-the-same-wi-fi).

Flutter screens and reusable service code are separated under `FRONTEND/lib/screens`, `FRONTEND/lib/services`, and `FRONTEND/lib/utils`; `main.dart` only configures and starts the app.
