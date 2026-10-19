# 1.22.0

## Русский

Добавлен общий запасной способ взаимодействия с интерфейсами без доступного API: видимый виртуальный курсор внутри игры. Наведение, клики, перетаскивание, прокрутка и ввод текста доступны модели с поддержкой изображений. Системная мышь остаётся у игрока. Инструменты включаются отдельно в настройках Харнеса.

Каждое действие требует полученного моделью актуального снимка и возвращает новый кадр для проверки. Ввод игрока немедленно прерывает действие; агент не может продолжать клики до нового сообщения. Смена модели, мира, размера окна и использованный снимок не позволяют повторить устаревшую команду. Ошибка передачи изображения не подменяется разрешением кликать вслепую. Доставка ввода не считается подтверждением игровой сделки.

В Pax Universe 0.31.6 живая vision-модель по снимкам включила нарисованный на самописном полотне реактор без API, выбрала обычное игровое поле, ввела русский текст и проверила оба результата по новым кадрам. Дополнительные проверки покрывают обычную кнопку, перетаскивание, колесо, фокус, масштабирование, разрешения и отмену. Ограничения описаны в [документации](virtual-input.md).

Снимки, полученные моделью, показываются в сообщении компактной лентой. Нажатие открывает точный кадр целиком; превью сохраняются независимо от срока действия кадра для ввода. Чат скрывается один раз на всю серию действий и возвращается с ответом, без постоянного мигания.

## English

Added a general fallback for interfaces without usable APIs: a visible virtual cursor inside the game. Vision models can hover, click, drag, scroll and enter text while the player retains the system mouse. Each tool has its own Harness settings checkbox.

Every action requires a current image received by the model and returns a new frame for verification. Player input immediately interrupts actions and blocks retries until a new message. Changed models/worlds/window sizes and consumed images cannot authorize stale commands. Image delivery errors do not enable blind clicks. Input dispatch is not proof of a completed game transaction.

In Pax Universe 0.31.6, a live vision model used screenshots to activate a reactor drawn on a custom canvas without an API, select a native input field, enter Russian text and verify both results from new frames. Additional checks cover native buttons, dragging, wheel input, focus, scaling, permissions and cancellation. See [limitations and usage](virtual-input.md).

Exact model screenshots appear in a compact transcript strip. Click to view the complete image; previews persist independently of temporary input grants. Chat hides once for the full interaction sequence and returns with the answer, avoiding repeated flashing.
