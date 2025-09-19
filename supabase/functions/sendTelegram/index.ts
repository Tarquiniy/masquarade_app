// supabase/functions/sendTelegram/index.ts

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const { text, chat_id, mode } = body as { text?: string; chat_id?: string; mode?: string };

    if (!text || typeof text !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing "text"' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!chat_id || typeof chat_id !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing "chat_id"' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!mode || (mode !== 'notification' && mode !== 'debug')) {
      return new Response(JSON.stringify({ error: 'Missing or invalid "mode". Must be "notification" or "debug"' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // получаем секреты
    const notificationToken = Deno.env.get('TELEGRAM_NOTIFICATION_BOT_TOKEN');
    const debugToken = Deno.env.get('TELEGRAM_DEBUG_BOT_TOKEN');
    const debugChatId = Deno.env.get('TELEGRAM_DEBUG_CHAT_ID');
    // note: можно не передавать debugChatId в теле, использовать секрет

    if (!notificationToken || !debugToken || !debugChatId) {
      return new Response(JSON.stringify({ error: 'Missing bot secret(s)' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // решаем, каким ботом
    let botTokenToUse: string;
    let finalChatId: string;

    if (mode === 'notification') {
      botTokenToUse = notificationToken;
      finalChatId = chat_id;  // отправляем уведомление получателю
    } else {
      // mode === 'debug'
      botTokenToUse = debugToken;
      finalChatId = debugChatId;  // дебаг чат (фиксированный)
    }

    // отправка в Telegram
    const telegramRes = await fetch(`https://api.telegram.org/bot${botTokenToUse}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: finalChatId, text, parse_mode: 'HTML' }),
    });

    const telegramBody = await telegramRes.json().catch(() => ({}));

    if (!telegramRes.ok) {
      return new Response(JSON.stringify({ error: telegramBody }), {
        status: telegramRes.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ data: telegramBody }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
