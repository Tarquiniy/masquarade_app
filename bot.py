import os
import logging
import sys
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from supabase import create_client, Client
from dotenv import load_dotenv

# Настройка логирования
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

load_dotenv()

# Конфигурация - используем значения по умолчанию, если переменные окружения не установлены
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '8398725116:AAHlIONC2IMvX54M6jtFpAiwIRTpgzZ6DVk')
SUPABASE_URL = os.getenv('SUPABASE_URL', 'https://pedqpjmdhkcdssfshpzb.supabase.co')  # ЗАМЕНИТЕ на ваш реальный URL
SUPABASE_KEY = os.getenv('SUPABASE_KEY', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBlZHFwam1kaGtjZHNzZnNocHpiIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0ODA3ODYyMSwiZXhwIjoyMDYzNjU0NjIxfQ.OC77nLTwtzeUvWL3DNwnZNhmhdaTBJNE6YhRDVfm4S4')  # ЗАМЕНИТЕ на ваш реальный ключ

# Проверка обязательных параметров
if not TELEGRAM_BOT_TOKEN:
    logging.error("TELEGRAM_BOT_TOKEN не установлен или имеет значение по умолчанию")
    sys.exit(1)

if not SUPABASE_URL or SUPABASE_URL == 'https://your-project-ref.supabase.co':
    logging.error("SUPABASE_URL не установлен или имеет значение по умолчанию")
    sys.exit(1)

if not SUPABASE_KEY or SUPABASE_KEY == 'your-supabase-service-key':
    logging.error("SUPABASE_KEY не установлен или имеет значение по умолчанию")
    sys.exit(1)

try:
    # Инициализация Supabase
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    logging.info("Supabase клиент успешно инициализирован")
except Exception as e:
    logging.error(f"Ошибка инициализации Supabase: {e}")
    sys.exit(1)

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Обработчик команды /start"""
    try:
        user = update.effective_user
        chat_id = update.effective_chat.id
        username = user.username
        
        logging.info(f"Обработка /start от пользователя {username} (chat_id: {chat_id})")
        
        if not username:
            await update.message.reply_text(
                "❌ У вас не установлен username в Telegram. "
                "Пожалуйста, установите username в настройках Telegram и попробуйте снова."
            )
            return
        
        # Обновляем запись в Supabase
        response = supabase.table('profiles') \
            .update({'telegram_chat_id': str(chat_id)}) \
            .eq('external_name', username) \
            .execute()
        
        if response.data:
            await update.message.reply_text(
                "✅ Добро пожаловать в Танкоград! Уведомления инициализированы.\n"
                f"Ваш chat_id: {chat_id} успешно сохранен."
            )
            logging.info(f"Updated telegram_chat_id for user {username}: {chat_id}")
        else:
            await update.message.reply_text(
                "❌ Пользователь с таким username не найден в системе.\n"
                "Убедитесь, что ваш Telegram username совпадает с external_name в профиле."
            )
            logging.warning(f"User {username} not found in database")
            
    except Exception as e:
        logging.error(f"Error in start_command: {e}")
        await update.message.reply_text(
            "❌ Произошла ошибка при обработке запроса. Попробуйте позже."
        )

def main():
    """Запуск бота"""
    try:
        # Создаем приложение
        application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
        
        # Добавляем обработчик команды /start
        application.add_handler(CommandHandler("start", start_command))
        
        # Запускаем бота
        logging.info("Бот запущен...")
        application.run_polling()
        
    except Exception as e:
        logging.error(f"Ошибка запуска бота: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()