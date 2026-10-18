# Pax Harness

Добавляет полноценный харнес для игрового ИИ в **Pax Universe**: удобный чат, игровые инструменты, работу с данными и наглядные ответы. Использует модель и подключение из настроек игры.

**Как открыть:** включите мод, загрузите или начните партию и нажмите обычную кнопку **«ВИ»**. Настройки: **меню игры → Настройки → Харнес**. Модель и API: **Настройки → Нейросеть**.

## Возможности

- Несколько чатов, поиск, разделы, закрепление, переименование и ссылки на другие чаты через `@`.
- Потоковые ответы, компактная очередь сообщений, уточнения во время работы, редактирование и отмена очереди.
- Инструкции для чата и партии, план задачи, сжатие длинной истории. Переписка и черновики сохраняются с партией.
- Игровые инструменты для чтения состояния и выполнения доступных действий. Описания подгружаются группами по мере необходимости. В настройках можно отключать отдельные группы и функции.
- Чтение доступных сущностей модов и управление некоторыми их функциями через наблюдаемые элементы интерфейса. После действия агент перечитывает результат; отправленный приказ или нажатие кнопки сами по себе не означают завершённую сделку.
- Обмен ресурсами со странами через штатные предложения и принятие сделок. Проверка условий, изменений запасов и договора; отдельное поручение из переписки не подменяет сделку.
- **39 видов диаграмм**, графики функций, таблицы с поиском, сортировкой, страницами и экспортом CSV. Расчёты и иллюстративные примеры отделяются от наблюдаемых игровых данных.
- Карты провинций, морей, озёр и побережий с изменениями текущего сценария и модов. Поиск небесных тел и звёзд, переход к реальным объектам игрового космоса.
- Открытие зарегистрированных игровых панелей. Снимки игрового экрана для моделей с разрешённым и поддерживаемым входом изображений.
- Генерация иллюстраций через настроенный игровой генератор, включая ComfyUI с API workflow. До двух картинок-референсов в сообщении; если модель не принимает изображения, текст всё равно отправляется с предупреждением.
- **Создание собственных воксельных объектов и иконок по запросу.** 3D-предпросмотр с вращением и масштабированием прямо в чате, переход камерой к применённому объекту в космосе.
- Новые ресурсы, панели объектов, искусственные миры и поверхности звёзд или газовых гигантов с нативными территориями.
- **Рабочая логика созданных объектов:** агент составляет программу с переменными, событиями, условиями, циклами, таймерами и доступными действиями над миром. Состояние сохраняется с партией.
- **Собственный интерфейс объекта:** агент составляет вкладки, строки, колонки, сетки, таблицы, показатели, прогресс, поля текста и чисел, ползунки, переключатели, выбор и кнопки. Элементы используют тему игры; логику и обработчики пишет агент.
- При установленной **«Сфере Дайсона»** доступны реальные корабли, местные 3D-маршруты и операции программ над кораблями и запасами. Очередь верфи, стоимость производства или реакцию врат на пролёт составляет агент из общего набора операций.
- Русский и английский интерфейс следуют языку игры. Для остальных языков используется английский.

## Примеры запросов

> Сравни производство и потребление еды. Покажи дефицит и объясни, что ограничивает рост.

> Сравни выручку и прибыль компаний по отраслям. Покажи таблицу и диаграмму, укажи единицы и охват данных.

> Создай собственный воксельный объект в космосе над Марсом: парящие круглые врата без подставки, с иконкой. Подготовь предпросмотр и проект для моего подтверждения.

> Для этих врат создай выход у другого тела и напиши рабочую логику переноса корабля при пролёте. Добавь заряд, счётчик проходов и интерфейс пополнения. Сначала подготовь проект. Для настоящего корабля используй установленную «Сферу Дайсона».

> Создай интерфейс бюро экспедиций: название и описание заявки, направление, размер команды, страховка, подача, отмена и журнал. Это учебный пульт, без расхода ресурсов и отправки людей.

Новые сущности и программы появляются в партии после нажатия игроком **«Применить»**. Обычные воксельные модели работают без дополнительных компонентов; отдельно висящие разрушаемые объекты требуют **Voxel Tools**. Качество выполнения зависит от выбранной модели. Чтение данных и управление некоторыми функциями модов.

Для Pax Universe 0.31.5.

## English

Adds a complete harness for the in-game AI in **Pax Universe**: a conversational workspace, game tools, data analysis and visual answers. Uses the model and API connection selected in the game.

**Open:** enable the mod, load or start a campaign, and click the normal **VI / assistant** button. Settings: **Game menu → Settings → Harness**. Model and API: **Settings → AI**.

### Features

- Multiple chats, search, sections, pinning, renaming and `@` chat references.
- Streaming responses, a compact message queue, corrections while working, editing and cancelling queued messages.
- Chat and campaign instructions, task plans and history compaction. Conversations and drafts persist with the campaign.
- Game-state readers and available game actions. Tool groups load on demand; individual groups and functions can be disabled in settings.
- Read exposed mod entities and control some mod features through observed interface controls. The assistant reads results back after acting; a submitted order or dispatched click alone does not prove a completed transaction.
- Exchange resources with countries through native proposals and deal acceptance. Verify terms, stock changes and treaty state; a separate task in correspondence does not substitute for a deal.
- **39 chart types**, function plots, searchable/sortable/paged tables and CSV export. Calculations and illustrative examples are distinguished from observed game data.
- Province, sea, lake and coastline maps include current scenario/mod changes. Search actual bodies and stars and navigate the game's space catalogue.
- Open registered game panels. Capture the game viewport for models with explicitly enabled and supported image input.
- Generate illustrations through the configured game image service, including ComfyUI API workflows. Attach up to two image references; when image input is unavailable, text still goes through with a warning.
- **Author custom voxel objects and icons on request.** Rotate and zoom their 3D previews directly in chat and focus the space camera on an applied object.
- New resources, object panels, artificial worlds and surfaces for stars/gas giants with native territories.
- **Working entity logic:** the agent composes programs from state, events, conditions, loops, timers and available world operations. Program state persists with the campaign.
- **Custom object controls:** the agent composes tabs, rows, columns, grids, tables, values, progress, text/numeric inputs, sliders, toggles, choices and buttons. Widgets inherit the game theme; the agent authors handlers and behavior.
- With **Dyson Sphere Program** installed, programs can use real ships, local 3D routes and ship/stock operations. The agent composes shipyard queues, production costs or gate crossing behavior from general operations.
- Russian and English follow the game language. Other languages fall back to English.

### Example requests

> Compare food production and consumption. Show the deficit and explain what limits growth.

> Compare company revenue and profit by industry in a table and chart. State units and coverage.

> Create a custom voxel object in space above Mars: floating circular gates without a pedestal, with an icon. Prepare a preview and a project for my approval.

> Add an exit near another body and author working ship-transfer logic for these gates. Include charge, a crossing counter and recharge controls. Prepare a project first. Use the installed Dyson Sphere Program for the real ship.

> Create expedition bureau controls: request name and description, destination, team size, insurance, submission, cancellation and a journal. This is a training console; do not spend resources or send people.

New entities and programs enter the campaign after the player clicks **Apply**. Ordinary voxel models need no extra component; detached destructible volumes require **Voxel Tools**. Results depend on the selected model. Read data and control some mod features.

For Pax Universe 0.31.5.
