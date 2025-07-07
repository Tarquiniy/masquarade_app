import psycopg2
import secrets
from datetime import datetime, timedelta, timezone
from aiogram import Bot, Dispatcher, Router
from aiogram.enums import ParseMode
from aiogram.types import Message
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.client.default import DefaultBotProperties
import asyncio

TOKEN = "7594245609:AAGK4IWj3G9zJf1HY1B2p6XGBEHF1AbLOa4"
PG_DSN = "dbname='postgres' user='postgres.pedqpjmdhkcdssfshpzb' password='LinaGideon13!' host='aws-0-ap-southeast-1.pooler.supabase.com' port='6543'"

bot = Bot(
    token=TOKEN,
    default=DefaultBotProperties(parse_mode=ParseMode.MARKDOWN)
)
dp = Dispatcher(storage=MemoryStorage())
router = Router()
dp.include_router(router)

def generate_code():
    return secrets.token_hex(4).upper()

@router.message()
async def greet_or_start(message: Message):
    if message.text and message.text.startswith("/start"):
        await handle_start_command(message)
    else:
        await message.answer("Приветствую! ✨\nВведите команду /start, чтобы авторизоваться и получить код.")

async def handle_start_command(message: Message):
    user = message.from_user
    if not user:
        await message.answer("Ошибка: не удалось получить пользователя.")
        return

    code = generate_code()
    telegram_id = user.id
    username = user.username or "no_username"

    try:
        conn = psycopg2.connect(PG_DSN)
        cur = conn.cursor()

        cur.execute(
            "SELECT id FROM predefined_profiles WHERE external_name = %s AND source = 'telegram' LIMIT 1;",
            (username,)
        )
        profile_row = cur.fetchone()

        if not profile_row:
            await message.answer("Профиль с вашим Telegram username не найден.\nОбратитесь к администратору.");
            cur.close()
            conn.close()
            return

        cur.execute(
            '''
INSERT INTO login_codes (code, telegram_id, external_name, expires_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (code) DO NOTHING;
            ''',
            (code, telegram_id, username, datetime.now(timezone.utc) + timedelta(minutes=10))
        )
        conn.commit()
        cur.close()
        conn.close()

        await message.answer(
            f"Ваш код для входа в приложение: `{code}`\n"
            f"Введите его в приложении в течение 10 минут."
        )
    except Exception as e:
        await message.answer(f"Ошибка при генерации кода: {e}")

async def main():
    await dp.start_polling(bot) # type: ignore

if __name__ == "__main__":
    asyncio.run(main())
