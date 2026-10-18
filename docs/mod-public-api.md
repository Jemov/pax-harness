# Публичные функции модов / Mod public functions

Harness обнаруживает функции включённого мода через `mods.api`, а вызывает их через `mods.invoke`. Агент получает страницы каталога и ищет функции по имени; весь каталог не добавляется в каждое обращение к модели.

Мод явно объявляет контракт:

```gdscript
func api_info() -> Dictionary:
	return {"api_level": 1, "mod_version": "1.0", "methods": {"status": 1, "set_limit": 1}}

func api_has(method: String) -> bool:
	return method in ["status", "set_limit"]

func status() -> Dictionary:
	return {"limit": limit}

func set_limit(value: float) -> bool:
	limit = clampf(value, 0.0, 100.0)
	return true
```

Это пример контракта, не готовый обработчик сферы или другого конкретного объекта. Методы должны находиться в скрипте мода или его локальных базовых скриптах. Аргументы: JSON-совместимые значения; обязательность, порядок, типы и значения по умолчанию берутся из реальной сигнатуры. Приватные функции, унаследованные методы движка, колбэки, объекты и вариативные вызовы не открываются.

Ссылки живут десять минут и инвалидируются при смене мира, узла мода, версии или контракта. Галочка `mods.invoke` блокирует вызов независимо от загрузки группы. Наблюдаемое возвращаемое значение само по себе не подтверждает завершение изменения мира. `argument_values` содержит входные аргументы/defaults: тестовое основание формулы нельзя называть измеренной мощностью колонии. Если мод откладывает работу до следующего кадра, результат читается в следующем раунде.

Новый ID вызова действительно вызывает API заново, даже при совпадающих аргументах. Тот же ID возвращает запись прошлого вызова. Это позволяет перечитать конфигурацию после изменения и выполнить повторяемую команду после сброса; слепо повторять мутации под новыми ID нельзя.

Изменение конфигурации относится к области действия, которую определяет сам мод. Оно не становится персональным переключателем объекта и не обещает сохранение в партии, если мод этого не обеспечивает. Временные расширения конфигурации получают отдельного владельца; удалять чужие патчи нельзя.

## English

`mods.api` discovers an enabled mod's explicit `api_info` / `api_has` contract. `mods.invoke` calls an observed function reference with ordered JSON arguments. Discovery is searchable and paged; the full catalogue is not injected into every model request.

The example above is a general contract, not an object-specific implementation. Signatures come from actual mod scripts. Private/engine methods, callbacks, object arguments and variadic calls are excluded. References expire after ten minutes and are invalidated by world, mod identity, version or contract changes. The individual tool permission remains authoritative.

Returned query state is an observation. A mutation return value is not proof of completed gameplay: inspect its actual effects in a later round when callbacks are deferred. `argument_values` records inputs/defaults; supplied formula bases are not world measurements. Configuration changes retain the scope and persistence defined by the original mod. Use an isolated owner for temporary patches and never remove another mod's patches.
