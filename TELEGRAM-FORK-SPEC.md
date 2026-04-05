# SPEC: Telegram iOS Fork с встроенным WebSocket-туннелем

## Цель проекта

Создать форк Telegram-iOS со встроенным WebSocket-туннелем для обхода замедления. Вместо прямого TCP к IP дата-центров Telegram (149.154.xxx.xxx), трафик оборачивается в WSS и идёт через `kws{N}.web.telegram.org` — веб-эндпоинты Telegram. Для DPI это выглядит как обычный HTTPS.

## Референс

Проект вдохновлён https://github.com/Flowseal/tg-ws-proxy (Python, для десктопа). Мы реализуем ту же идею нативно в Swift внутри iOS-клиента.

Схема работы:
```
Telegram App → MTProto данные → WebSocketTunnelTransport → WSS (kws{N}.web.telegram.org) → Telegram DC
```

Маппинг DC:
- DC 1 → wss://kws1.web.telegram.org
- DC 2 → wss://kws2.web.telegram.org
- DC 3 → wss://kws3.web.telegram.org
- DC 4 → wss://kws4.web.telegram.org
- DC 5 → wss://kws5.web.telegram.org

Fallback: если WSS недоступен (302 redirect) — прямой TCP.

## Порядок работы

### 1. Изучи структуру проекта

Найди:
- Транспортный слой MTProto (TCP-соединения к DC). Вероятно `submodules/MtProtoKit` или аналог — классы `MTTcpTransport`, `MTTransport` и т.д.
- IP-адреса дата-центров в коде (149.154.xxx.xxx)
- Протоколы/интерфейсы которые реализуют транспорты — нам нужно реализовать тот же интерфейс
- Экран настроек (Settings UI) — как устроены другие экраны настроек, какой UI-фреймворк используется
- Конфигурация сборки (BUILD файлы Bazel, configuration json)

### 2. Смени идентификаторы приложения

- Bundle Identifier → `com.ИДЕНТИФИКАТОР.messenger` (спроси у меня если не задан)
- Display Name → название форка (спроси у меня если не задано)
- Создай свой configuration.json на основе `build-system/template_minimal_development_configuration.json` с api_id и api_hash (спроси у меня значения)

### 3. Создай WebSocketTunnelTransport

Новый Swift-модуль рядом с существующим транспортным слоем. Требования:

- Реализует тот же протокол/интерфейс что существующий TCP-транспорт
- Использует нативный `URLSessionWebSocketTask` (iOS 13+), без внешних зависимостей
- Определяет DC ID из контекста соединения или MTProto obfuscation init-пакета (первые 64 байта)
- Устанавливает WSS к `kws{dcId}.web.telegram.org`
- Корректно передаёт MTProto данные через WebSocket (без двойного фрейминга)
- Ping/Pong keepalive каждые 30 секунд
- Reconnection с exponential backoff (1s, 2s, 4s, max 30s)
- Кэш доступности WS-эндпоинтов (если DC вернул 302 — помечаем как "WS недоступен")

Режимы работы:
```swift
enum TunnelMode: Int {
    case auto = 0      // прямой TCP → если таймаут >3с → WS-туннель
    case always = 1    // всегда WS
    case disabled = 2  // только прямой TCP
}
```

Хранение настройки: `UserDefaults`, ключ `"ws_tunnel_mode"`, по умолчанию `.auto`

### 4. Интегрируй туннель в транспортный слой

Найди где создаётся/выбирается транспорт и модифицируй:
- `TunnelMode.always` → WebSocketTunnelTransport
- `TunnelMode.auto` → TCP сначала, при таймауте/ошибке → WebSocketTunnelTransport
- `TunnelMode.disabled` → стандартный TCP

Логирование: при каждом соединении выводить в консоль тип транспорта и DC ID.

### 5. Добавь UI настроек

В существующий экран настроек (рядом с "Тип подключения" / "Прокси") добавь секцию "Антиблокировка":

- Сегментированный переключатель: Авто / Всегда / Выкл
- Статус-индикатор:
  - Зелёная точка + "Прямое соединение"
  - Синяя точка + "WS-туннель (DC N)"
  - Красная точка + "Нет соединения"
- Описание: "Обход замедления через WebSocket-туннель к веб-эндпоинтам Telegram"
- Футер: "В режиме 'Авто' переключение происходит автоматически при обнаружении замедления"

Используй тот же UI-фреймворк что и остальные настройки (AsyncDisplayKit/Texture или что используется в проекте).

### 6. GitHub Actions для сборки .ipa

Создай `.github/workflows/build-ipa.yml`:

- Триггер: `workflow_dispatch` + push тега
- Runner: `macos-14`
- Шаги: checkout с submodules → Xcode (версия из versions.json) → Bazel → импорт сертификата из Secrets (CERTIFICATE_P12, CERTIFICATE_PASSWORD, PROVISIONING_PROFILE) → генерация проекта → сборка release_arm64 → upload .ipa как artifact
- Кэширование Bazel между билдами

Создай `codesigning/setup.sh` — скрипт импорта сертификата из переменных окружения в Keychain.

### 7. README

Двуязычный (RU/EN):
- Что это (форк Telegram-iOS с обходом замедления)
- Как работает (WS-туннель, три режима)
- Установка (.ipa из Releases → AltStore/Sideloadly)
- Сборка из исходников
- Лицензия GPL v2

### 8. Финальная проверка

- Все новые файлы добавлены в BUILD (Bazel)
- Нет синтаксических ошибок в Swift
- UserDefaults ключи согласованы между UI и транспортом
- GitHub Actions YAML валиден
- .gitignore закрывает чувствительные файлы
- Все import-ы корректны

## Ограничения

- Никаких внешних зависимостей (только стандартные iOS фреймворки)
- Никаких сторонних серверов — только эндпоинты Telegram (kws*.web.telegram.org)
- Код должен соответствовать GPL v2
- Минимальная iOS версия — та же что у оригинального Telegram
