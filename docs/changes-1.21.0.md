# 1.21.0

## Русский

Общие инструменты `mods.api` / `mods.invoke` находят и вызывают функции, которые включённый мод явно экспортирует через `api_info` / `api_has`. Возвращаются реальные имена, порядок и типы аргументов. Вызов использует временную ссылку, проверяет текущий контракт и разрешение инструмента. Методы движка, приватные функции и аргументы-объекты/колбэки не открываются. Результат вызова не считается завершённым игровым действием: агент должен прочитать фактический результат.

Поддерживается управление некоторыми функциями модов, включая публичные функции без отдельной кнопки. Моды без такого контракта по-прежнему доступны через наблюдаемый интерфейс и данные; автоматического доступа к каждой функции любого мода не заявляется. Изменение конфигурации следует описывать как изменение конфигурации, а не как существующий у объекта переключатель.

Исправлена выдача старого ответа публичного API при новом чтении после изменения. Каждый новый ID действительно вызывает функцию; тот же ID сохраняет защиту от двойного выполнения. Возвращаются фактически переданные аргументы/defaults, чтобы тестовое основание формулы не путалось с измерением мира. Отложенные изменения перечитываются в следующем раунде.

## English

Generic `mods.api` / `mods.invoke` tools discover and invoke functions explicitly exported by an enabled mod through `api_info` / `api_has`. Actual names, parameter order and types are returned. Calls use expiring references, revalidate the current contract and respect tool permissions. Engine methods, private functions and object/callback arguments are not exposed. Dispatch is not completed gameplay: the agent must read back the actual result.

This enables control of some mod functions, including public functions without a dedicated button. Mods without this contract retain observed UI/data access; complete coverage of every function in every mod is not claimed. Configuration changes must be described as configuration changes, not as an existing object switch.

Fixed stale public API responses when reading again after a change. A new call ID invokes the function anew; the same ID retains duplicate-execution protection. Actual input/default parameter values are returned separately from observations. Read back deferred mutations in a later round.
