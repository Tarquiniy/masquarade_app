import os
import logging
import sys
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from supabase import create_client, Client
from dotenv import load_dotenv

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

load_dotenv()

TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')

if not TELEGRAM_BOT_TOKEN:
    logger.error("TELEGRAM_BOT_TOKEN is not set")
    sys.exit(1)

if not SUPABASE_URL:
    logger.error("SUPABASE_URL is not set")
    sys.exit(1)

if not SUPABASE_KEY:
    logger.error("SUPABASE_KEY is not set")
    sys.exit(1)

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    logger.info("Supabase client initialized")
except Exception as e:
    logger.error(f"Failed to initialize Supabase: {e}")
    sys.exit(1)


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Link Telegram account to in-game profile via /start."""
    try:
        user = update.effective_user
        chat_id = update.effective_chat.id
        username = user.username

        logger.info(f"Processing /start from {username} (chat_id: {chat_id})")

        if not username:
            await update.message.reply_text(
                "❌ У вас не установлен username в Telegram. "
                "Пожалуйста, установите username в настройках Telegram и попробуйте снова."
            )
            return

        response = supabase.table('profiles') \
            .update({'telegram_chat_id': str(chat_id)}) \
            .eq('external_name', username) \
            .execute()

        if response.data:
            await update.message.reply_text(
                "✅ Добро пожаловать в Танкоград! Уведомления инициализированы.\n"
                f"Ваш chat_id: {chat_id} успешно сохранен."
            )
            logger.info(f"Linked telegram_chat_id for {username}: {chat_id}")
        else:
            await update.message.reply_text(
                "❌ Пользователь с таким username не найден в системе.\n"
                "Убедитесь, что ваш Telegram username совпадает с external_name в профиле."
            )
            logger.warning(f"User {username} not found in database")

    except Exception as e:
        logger.error(f"Error in start_command: {e}")
        await update.message.reply_text(
            "❌ Произошла ошибка при обработке запроса. Попробуйте позже."
        )


def main():
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    application.add_handler(CommandHandler("start", start_command))
    logger.info("Bot started")
    application.run_polling()


if __name__ == '__main__':
    main()
