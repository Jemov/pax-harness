# 1.22.1

## Русский

Исправлена потеря статистики запросов, когда игровой API дополняет промпт после первичного хука. Токены и кэш теперь привязаны к конкретному транспортному запросу и сохраняются до разбора ответа игровым API; поздний ai_answer не считает их повторно. Запасной учёт через ai_answer использует окончательный вариант запроса.

Контекст делится по фактически отправленным текстам и схемам только загруженных групп инструментов. Общее число входных токенов берётся из API; доли частей контекста остаются приблизительными. При отсутствии usage значения не выдумываются. Записи сохраняются с чатом; утраченные ранее API-данные старых ответов восстановить точно невозможно.

## English

Fixed missing request statistics when the game API augments the prompt after the initial hook. Token and cache usage are bound to a specific transport request and saved before native response parsing. A later ai_answer cannot count the same usage again. Hook-based fallback uses the finalized request.

Context proportions use actual outgoing text and schemas from loaded tool groups only. Total input tokens come from the API; the component split remains approximate. Missing API usage stays unknown. Statistics persist with the chat; previously lost API usage cannot be reconstructed accurately.
