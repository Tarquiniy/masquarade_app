import asyncio
import secrets
from datetime import datetime, timedelta, timezone

from aiogram import Bot, Dispatcher, Router, types
from aiogram.enums import ParseMode
from aiogram.types import Message
from aiogram.fsm.storage.memory import MemoryStorage
import asyncpg
from aiogram.client.default import DefaultBotProperties

TOKEN = "7594245609:AAGK4IWj3G9zJf1HY1B2p6XGBEHF1AbLOa4"
SUPABASE_DB_URL = "postgresql://postgres.pedqpjmdhkcdssfshpzb:[LinaGideon13!]@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres"


bot = Bot(
    token=TOKEN,
    default=DefaultBotProperties(parse_mode=ParseMode.MARKDOWN)
)
dp = Dispatcher(storage=MemoryStorage())
router = Router()
dp.include_router(router)

async def generate_code():
    return secrets.token_hex(4).upper()

@router.message()
async def handle_start_command(message: Message):
    if message.text != "/start":
        return

    user = message.from_user
    if not user:
        await message.answer("Ошибка: не удалось получить пользователя.")
        return

    code = await generate_code()
    telegram_id = user.id
    username = user.username or "no_username"

    try:
        conn = await asyncpg.connect(SUPABASE_DB_URL)
        await conn.execute("""
            insert into login_codes (code, telegram_id, telegram_username, expires_at)
            values ($1, $2, $3, $4)
            on conflict (code) do nothing;
        """, code, telegram_id, username, datetime.now(timezone.utc) + timedelta(minutes=10))
        await conn.close()

        await message.answer(
            f"Ваш код для входа в приложение: `{code}`\n"
            f"Введите его в приложении в течение 10 минут."
        )
    except Exception as e:
        await message.answer(f"Ошибка при генерации кода: {e}")

async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
