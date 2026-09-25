# SMARTADS backend

A Node.js API backed by SQLite (`node:sqlite`, Node 22.5+) and Gemini video understanding. It supports advertiser/owner signup, login, billboard listings and owner management, AI video approval, booking availability, a mock payment step, booking schedules, and admin user management.

## Run

```sh
cp .env.example .env
# Set GEMINI_API_KEY and a private JWT_SECRET in .env.
npm start
```

## Android TV VLC playback on the same Wi-Fi

SMARTADS runs the schedule in the Node backend. At the booked start time, it
asks VLC on the Android TV to open a local M3U playlist. The playlist points
back to the approved video on this backend and repeats it for the booking
period. At the end, SMARTADS pauses VLC and turns the configured ESP32 relay
off. The TV fetches the video directly; the ESP32 receives only relay commands.

VLC must be open on the TV, with Remote Access enabled. VLC for Android's
Remote Access feature is available in version 3.6 and later. The backend uses
the URL and one-time code displayed by VLC; it keeps the resulting session in
memory, so a backend restart requires a fresh VLC code.

Add these settings to the existing `BACKEND/.env` (keep its current Gemini and
JWT entries):

```dotenv
SMARTADS_TIMEZONE=Africa/Douala
SMARTADS_PUBLIC_URL=http://192.168.1.10:3000
SMARTADS_PLAYBACK_BILLBOARD_ID=
VLC_REMOTE_URL=https://192.168.1.20:8443
VLC_REMOTE_OTP=copy-the-current-code-from-vlc
ESP32_RELAY_URL=http://192.168.1.30/relay
ESP32_DEVICE_TOKEN=use-the-same-random-token-as-the-esp32
ESP32_POWER_ON_DELAY_MS=5000
```

Replace the example IP addresses with the backend computer, TV, and ESP32
addresses on your Wi-Fi. Set a DHCP reservation for the TV and ESP32 if
possible. `SMARTADS_PUBLIC_URL` must be reachable from the TV; `localhost` will
not work there. Leave `SMARTADS_PLAYBACK_BILLBOARD_ID` blank only when there is
exactly one billboard in the SQLite database. The owner billboard card shows
the ID and has a copy button when multiple billboards exist.

### ESP32 setup

Open `BACKEND/esp32/SMARTADSRelay.ino` in Arduino IDE. Set the Wi-Fi name and
password, choose the relay input GPIO, and set a long random device token.
Upload it to the ESP32. The sketch accepts authenticated `POST /relay`
requests with plain text `ON` or `OFF`. Set `ESP32_RELAY_URL` to the printed
ESP32 address followed by `/relay`, and copy the same token into
`ESP32_DEVICE_TOKEN`.

The sample sketch starts with the relay off. Its default relay input is GPIO
26 and assumes an active-low relay board; change those constants to match your
hardware. The relay should not cut mains power to the Android TV if you expect
SMARTADS to reach VLC for later bookings. If the relay does power off the TV,
the TV must boot and VLC must be opened again before the next playback command
can work.

### First playback walkthrough

1. Connect the backend computer, Android TV, and ESP32 to the same non-guest
   Wi-Fi network. Make sure the router allows devices to communicate locally.
2. Install/update VLC for Android to version 3.6 or later. Open VLC on the TV,
   enable **Remote Access** in VLC settings, and note the displayed remote URL
   and one-time password. Keep VLC open in the foreground.
3. Find the backend computer's Wi-Fi IPv4 address and set it in
   `SMARTADS_PUBLIC_URL`, for example `http://192.168.1.10:3000`.
4. Copy the VLC URL and current one-time password into `VLC_REMOTE_URL` and
   `VLC_REMOTE_OTP`. Use the base URL only (scheme, IP, and port). Keep this
   value in the backend `.env`; it does not belong in Flutter.
5. Configure the ESP32 as described above. If relay control is not ready yet,
   leave the two `ESP32_...` settings blank; VLC playback can be tried without
   relay switching.
6. Restart the backend with `npm start`. Check the owner dashboard's playback
   card. It should report VLC connected; configuration problems are shown
   there. Refresh the VLC one-time password and update `.env` after restarting
   the backend.
7. In SMARTADS, make a booking for the configured billboard and complete the
   existing simulated payment step so its status becomes `confirmed`. For a
   quick local demonstration, use an available slot that is currently in
   progress; otherwise leave VLC open and wait for the booked start time.
8. At the start, the backend sends the playlist URL to VLC. VLC requests the
   playlist and the MP4/WebM clip from the backend over Wi-Fi. The clip repeats
   until the slot ends. The backend then pauses VLC and switches the relay off
   when relay control is configured.

The simulated payment form remains a demo gate that marks a booking confirmed;
it does not charge money. The schedule only plays confirmed bookings.

The video review endpoint rejects clips longer than 3 seconds, checks the content with `GEMINI_MODEL` (default `gemini-3.8-flash`), then removes the temporary Gemini Files API copy. The original approved or rejected upload is retained in `uploads/` with its review record. Gemini uploads are limited to 120 MB.

The backend requires `ffprobe` on `PATH` to validate each clip's actual duration.

Alternatively, set `PORT`, `JWT_SECRET`, `GEMINI_API_KEY`, `ADMIN_EMAIL`, and `ADMIN_PASSWORD` in the environment before `npm start`. The optional admin account is created on the first startup when both admin variables are set. SQLite data is stored in `smartads.sqlite`.

For a local demo without an env-file loader:

```sh
PORT=3000 JWT_SECRET='use-a-long-random-secret' ADMIN_EMAIL=admin@smartads.local ADMIN_PASSWORD='ChangeMe123!' node server.js
```

## API overview

- `POST /api/auth/signup` — `{ name, email, password, role }`, where role is `advertiser` or `owner`
- `POST /api/auth/login`, `GET /api/auth/me`
- `GET /api/billboards`; owners can `POST /api/billboards` and `PATCH /api/billboards/:id`
- `POST /api/videos/verify` — authenticated multipart upload; rejects videos over 3 seconds and returns Gemini's AI review
- `GET /api/bookings`; advertisers can `POST /api/bookings` with `{ billboardId, reviewId, date, startTime, endTime }`
- `POST /api/bookings/:id/payments/mock` — demo payment and confirmation with `{ provider, mobileNumber }`; accepts MTN Mobile Money or Orange Money, validates a Cameroon number, and does not store the number or charge it
- Admin: `GET /api/admin/users`, `PATCH /api/admin/users/:id` with `{ status: "active" | "suspended" }`, or `DELETE /api/admin/users/:id`

Send authenticated requests with `Authorization: Bearer <token>`. Payment remains simulated; the Gemini API key must stay in the backend environment and must never be added to Flutter code.
