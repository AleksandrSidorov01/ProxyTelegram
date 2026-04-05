# ProxyTelegram

[English](#english) | [Русский](#russian)

---

<a name="english"></a>
## English

### About

ProxyTelegram is an unofficial fork of Telegram for iOS with built-in WebSocket tunnel support for bypassing blocks and censorship.

### Features

- **WebSocket Tunnel**: Automatic connection through WebSocket when Telegram is blocked
- **Three Modes**:
  - **Auto**: Automatically switches to WebSocket tunnel when blocking is detected
  - **Always**: Always uses WebSocket tunnel for all connections
  - **Disabled**: Uses only direct TCP connections
- **Status Indicator**: Shows current connection type (Direct/Tunnel/Disconnected)
- **Based on Official Telegram**: All original Telegram features are preserved

### Installation

#### Option 1: Download Pre-built IPA

1. Download the latest `ProxyTelegram.ipa` from [Releases](../../releases)
2. Install using one of these methods:
   - **AltStore**: Open the IPA file in AltStore
   - **Sideloadly**: Use Sideloadly to sign and install
   - **Xcode**: Sign manually and install via Xcode

#### Option 2: Build from Source

Requirements:
- macOS 13+
- Xcode 15.2+
- Bazel 7.4.2+

```bash
# Clone the repository
git clone --recursive https://github.com/YOUR_USERNAME/ProxyTelegram.git
cd ProxyTelegram

# Build
python3 build-system/Make/Make.py \
  build \
  --configurationPath=build-system/ptelegram-configuration.json \
  --codesigningInformationPath=build-system/fake-codesigning \
  --configuration=release_arm64
```

### Usage

1. Open ProxyTelegram
2. Go to **Settings** → **Data and Storage**
3. Find **Anti-blocking** section
4. Choose mode:
   - **Auto** (recommended): Automatically uses tunnel when needed
   - **Always**: Always uses tunnel
   - **Disabled**: Tunnel disabled

### Technical Details

- **WebSocket Endpoints**: `wss://kws{1-5}.web.telegram.org/apiws`
- **Transport Layer**: Custom MTProto transport implementation
- **Auto Mode**: Tracks connection attempts and switches to tunnel after first failure
- **DC Availability Cache**: Remembers unavailable datacenters for 5 minutes

### Differences from Official Telegram

- Custom Bundle ID: `com.aleksandr.ProxyTegram`
- Custom API credentials (api_id/api_hash)
- WebSocket tunnel support
- Anti-blocking settings UI

### Building

See [TELEGRAM-FORK-SPEC.md](TELEGRAM-FORK-SPEC.md) for detailed build instructions and architecture documentation.

### License

This project is based on [Telegram for iOS](https://github.com/TelegramMessenger/Telegram-iOS) which is licensed under GPL v2.

### Disclaimer

This is an unofficial fork. Use at your own risk. The authors are not responsible for any issues arising from the use of this application.

---

<a name="russian"></a>
## Русский

### О проекте

ProxyTelegram — неофициальный форк Telegram для iOS со встроенной поддержкой WebSocket туннеля для обхода блокировок и цензуры.

### Возможности

- **WebSocket Туннель**: Автоматическое подключение через WebSocket при блокировке Telegram
- **Три режима работы**:
  - **Авто**: Автоматически переключается на WebSocket туннель при обнаружении блокировки
  - **Всегда**: Всегда использует WebSocket туннель для всех подключений
  - **Выключено**: Использует только прямые TCP подключения
- **Индикатор статуса**: Показывает текущий тип подключения (Прямое/Туннель/Отключено)
- **На основе официального Telegram**: Все оригинальные функции Telegram сохранены

### Установка

#### Вариант 1: Скачать готовый IPA

1. Скачайте последний `ProxyTelegram.ipa` из [Releases](../../releases)
2. Установите одним из способов:
   - **AltStore**: Откройте IPA файл в AltStore
   - **Sideloadly**: Используйте Sideloadly для подписи и установки
   - **Xcode**: Подпишите вручную и установите через Xcode

#### Вариант 2: Сборка из исходников

Требования:
- macOS 13+
- Xcode 15.2+
- Bazel 7.4.2+

```bash
# Клонируйте репозиторий
git clone --recursive https://github.com/YOUR_USERNAME/ProxyTelegram.git
cd ProxyTelegram

# Соберите
python3 build-system/Make/Make.py \
  build \
  --configurationPath=build-system/ptelegram-configuration.json \
  --codesigningInformationPath=build-system/fake-codesigning \
  --configuration=release_arm64
```

### Использование

1. Откройте ProxyTelegram
2. Перейдите в **Настройки** → **Данные и память**
3. Найдите секцию **Антиблокировка**
4. Выберите режим:
   - **Авто** (рекомендуется): Автоматически использует туннель при необходимости
   - **Всегда**: Всегда использует туннель
   - **Выключено**: Туннель отключён

### Технические детали

- **WebSocket эндпоинты**: `wss://kws{1-5}.web.telegram.org/apiws`
- **Транспортный слой**: Кастомная реализация MTProto транспорта
- **Авто режим**: Отслеживает попытки подключения и переключается на туннель после первой неудачи
- **Кэш доступности DC**: Запоминает недоступные датацентры на 5 минут

### Отличия от официального Telegram

- Кастомный Bundle ID: `com.aleksandr.ProxyTegram`
- Кастомные API credentials (api_id/api_hash)
- Поддержка WebSocket туннеля
- UI настроек антиблокировки

### Сборка

См. [TELEGRAM-FORK-SPEC.md](TELEGRAM-FORK-SPEC.md) для подробных инструкций по сборке и документации архитектуры.

### Лицензия

Этот проект основан на [Telegram for iOS](https://github.com/TelegramMessenger/Telegram-iOS), который распространяется под лицензией GPL v2.

### Отказ от ответственности

Это неофициальный форк. Используйте на свой риск. Авторы не несут ответственности за любые проблемы, возникающие при использовании этого приложения.

