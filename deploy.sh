#!/bin/bash

# Скрипт деплоя для Tankograd App
# Обновляет version.json и деплоит на Firebase

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Выход при ошибке любой команды
set -e

echo -e "${YELLOW}Starting deployment process...${NC}"

# Проверяем, установлен ли Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Flutter не найден. Убедитесь, что он установлен и добавлен в PATH.${NC}"
    exit 1
fi

# Проверяем, установлен ли Firebase CLI
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}Firebase CLI не найден. Установите его: npm install -g firebase-tools${NC}"
    exit 1
fi

# Собираем проект
echo -e "${YELLOW}Building project...${NC}"
flutter build web --release

# Получаем текущую дату и хэш коммита
CURRENT_DATE=$(date +%Y-%m-%dT%H:%M:%SZ)
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_NUMBER=$(date +%s)

# Создаем или обновляем version.json ПОСЛЕ сборки
echo -e "${YELLOW}Updating version.json...${NC}"
cat > build/web/version.json << EOF
{
  "version": "1.0.$BUILD_NUMBER",
  "build_date": "$CURRENT_DATE",
  "commit_hash": "$COMMIT_HASH",
  "timestamp": "$(date +%s)"
}
EOF

echo -e "${GREEN}Version.json updated:${NC}"
cat build/web/version.json

# Деплоим на Firebase
echo -e "${YELLOW}Deploying to Firebase...${NC}"
firebase deploy --only hosting

echo -e "${GREEN}Deployment completed successfully!${NC}"