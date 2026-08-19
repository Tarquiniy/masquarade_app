# Танкоград — Vampire: The Masquerade LARP App

A companion app for the **Танкоград** LARP community built around the *Vampire: The Masquerade* universe. The app supports character management, domain tracking, Masquerade violation reporting, in-game messaging, and Telegram notifications.

---

## Features

- **Character profiles** — vampire clan, sect, generation, blood power, hunger, disciplines, humanity pillars
- **Masquerade violations** — submit, review, and adjudicate violation reports
- **Domain system** — claim territories, monitor domain status in real-time via Supabase Realtime
- **Carpet Chat** — in-game political messaging powered by Firebase Firestore
- **Interactive map** — GPS-aware domain map using `flutter_map` and `geolocator`
- **Telegram notifications** — players link their Telegram account to receive in-game alerts
- **Role-based access** — Guest / Player / Storyteller / Admin
- **PWA + multi-platform** — deployed as a web app, with Android / iOS / desktop builds available

---

## Tech Stack

| Layer | Technology |
|---|---|
| App framework | Flutter / Dart |
| State management | flutter_bloc (BLoC pattern) |
| Backend / Auth / DB | Supabase (PostgreSQL, Realtime, Edge Functions) |
| Push notifications | Firebase Cloud Messaging |
| In-game chat | Firebase Firestore |
| Hosting | Firebase Hosting |
| Telegram bots | Python (`python-telegram-bot`, `aiogram`) |
| Edge Functions | Deno / TypeScript (Supabase Functions) |

---

## Project Structure

```
.
├── lib/                        # Flutter/Dart source
│   ├── main.dart               # App entry point
│   ├── blocs/                  # BLoC state management
│   │   ├── auth/
│   │   ├── domain/
│   │   ├── masquerade/
│   │   └── profile/
│   ├── models/                 # Data models
│   ├── repositories/           # Supabase data access layer
│   ├── screens/                # UI screens
│   ├── services/               # Business logic services
│   ├── utils/                  # Helpers (clan utils, debug, etc.)
│   └── widgets/                # Reusable UI components
├── supabase/
│   ├── config.toml
│   └── functions/
│       └── sendTelegram/       # Deno edge function for Telegram messages
├── bot.py                      # Telegram notification bot (python-telegram-bot)
├── telegram_bot_psycopg2.py    # Telegram login-code bot (aiogram + psycopg2)
├── requirements.txt            # Python dependencies
├── pubspec.yaml                # Flutter dependencies
├── package.json                # Node/Supabase CLI scripts
├── deploy.sh                   # Firebase deployment script
├── firebase.json               # Firebase Hosting config
├── netlify.toml                # Netlify deploy config (alternative hosting)
└── assets/
    ├── clans/                  # VtM clan icons
    ├── icons/
    ├── logo.png
    └── vtm_background.jpg
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.8.1
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- Python ≥ 3.10 (for Telegram bots)
- Node.js ≥ 18 (for Supabase JS tooling)

### Flutter App

```bash
# Install dependencies
flutter pub get

# Run in debug mode (Chrome / device)
flutter run -d chrome

# Build for web (production)
flutter build web --release
```

### Environment Variables

Copy `.env.example` to `.env` and fill in all values:

```bash
cp .env.example .env
```

| Variable | Description |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Bot token from [@BotFather](https://t.me/BotFather) |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_KEY` | Supabase service-role key (keep secret!) |
| `PG_DSN` | PostgreSQL connection string (for `telegram_bot_psycopg2.py`) |

### Python Telegram Bots

There are two independent bots:

**`bot.py`** — notification bot. Links a player's Telegram account to their profile by matching Telegram username to `external_name` in the `profiles` table.

**`telegram_bot_psycopg2.py`** — login-code bot. Generates a one-time login code so players can authenticate via Telegram without a password.

```bash
# Install Python dependencies
pip install -r requirements.txt

# Run the notification bot
python bot.py

# Run the login-code bot
python telegram_bot_psycopg2.py
```

### Supabase Edge Functions

The `sendTelegram` function sends Telegram messages in two modes:
- `notification` — sends to a specific player's chat
- `debug` — sends to the admin debug channel

Required Supabase secrets:

```bash
supabase secrets set TELEGRAM_NOTIFICATION_BOT_TOKEN=<token>
supabase secrets set TELEGRAM_DEBUG_BOT_TOKEN=<token>
supabase secrets set TELEGRAM_DEBUG_CHAT_ID=<chat_id>
```

Deploy the function:

```bash
supabase functions deploy sendTelegram
```

---

## Deployment

### Firebase Hosting (production)

```bash
./deploy.sh
```

The script builds the Flutter web app and deploys to Firebase Hosting. It also writes a `version.json` with the current build metadata.

### Manual deploy

```bash
flutter build web --release
firebase deploy --only hosting
```

---

## Clan Assets

The app includes icons for all nine playable clans:

| Clan | Description |
|---|---|
| Banu Haqim | Assassins and jurists |
| Brujah | Rebels and idealists |
| Gangrel | Ferals and wanderers |
| Malkavian | Seers touched by madness |
| Nosferatu | Masters of information and shadow |
| Toreador | Artists and sensualists |
| Tremere | Blood sorcerers |
| Tzimisce | Flesh-shapers |
| Ventrue | Lords and commanders |

---

## Security Notes

- **Never commit** `.env` or any file containing credentials. The `.gitignore` is configured to exclude `.env*` files.
- The Supabase **service-role key** has full database access — treat it as a root password.
- The `SUPABASE_KEY` in the Flutter app should use the **anon key** (row-level security enforced), not the service-role key.
- Supabase Edge Function secrets are stored securely in the Supabase vault and never exposed to the client.

---

## License

See [LICENSE](./LICENSE).
