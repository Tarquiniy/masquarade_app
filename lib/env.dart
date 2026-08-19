// Supabase project URL (public)
const String supabase_url = 'https://pedqpjmdhkcdssfshpzb.supabase.co';

// Supabase anon key — client-safe (RLS enforced on all tables).
// Pass at build time: --dart-define=SUPABASE_ANON_KEY=...
const String supabase_anonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

// Supabase service-role key — bypasses RLS, used in MediaService for storage.
// Pass at build time: --dart-define=SUPABASE_SERVICE_KEY=...
const String supabase_serviceKey = String.fromEnvironment(
  'SUPABASE_SERVICE_KEY',
  defaultValue: '',
);

// Firebase web config (public — access controlled by Firebase Security Rules)
const String firebase_apiKey = 'AIzaSyCpQyNCQYkSajBX5Wr8Ii9wlDP4nX6wchE';
const String firebase_authDomain = 'tankograd.firebaseapp.com';
const String firebase_projectId = 'tankograd';
const String firebase_storageBucket = 'tankograd.firebasestorage.app';
const String firebase_messagingSenderId = '255328966030';
const String firebase_appId = '1:255328966030:web:dd88de76c1a68c6cdf80df';

// Telegram notification bot token.
// Pass at build time: --dart-define=TELEGRAM_NOTIFICATION_BOT_TOKEN=...
const String telegramNotificationBotToken = String.fromEnvironment(
  'TELEGRAM_NOTIFICATION_BOT_TOKEN',
  defaultValue: '',
);
