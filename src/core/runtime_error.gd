extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Stable, non-secret diagnostics shared by transport and tool receipts.
static func make(code: String, details: Variant = {}, http_status: int = 0) -> Dictionary:
	var category := "tool"
	var message := L.text("Инструмент не смог выполнить действие. Проверьте причину и текущее состояние.")
	var retryable := false
	if code == "cancelled": category = "cancelled"; message = L.text("Запрос остановлен.")
	elif code == "tools.disabled_by_player": category = "permission"; message = L.text("Инструмент выключен игроком в настройках Харнеса.")
	elif code in ["ui.vision_disabled","ui.image_not_observed"]: category="permission"; message=L.text("Виртуальный ввод доступен после просмотра игрового снимка моделью с поддержкой изображений.")
	elif code in ["ui.input_interrupted","ui.player_input_active"]: category="conflict"; message=L.text("Виртуальный ввод остановлен: управление у игрока или задача отменена. Для продолжения отправьте новое сообщение.")
	elif code=="ui.screen_view_paused": category="conflict";message=L.text("Работа с экраном приостановлена. Для продолжения отправьте новое сообщение.")
	elif code=="ui.input_focus_required": category="tool"; message=L.text("Сначала выберите игровое поле виртуальным курсором.")
	elif code=="ui.input_readback_failed": category="tool"; message=L.text("Ввод отправлен, но новый снимок получить не удалось. Проверьте экран перед повтором.")
	elif code == "vision_input_disabled": category = "permission"; message = L.text("Передача изображений выключена для этой модели. Включите профиль и «Изображения на вход» в тонкой настройке.")
	elif code == "vision_unsupported_transport": category = "provider"; message = L.text("Этот формат API пока не поддерживает передачу снимков. Поддерживаются Chat Completions, Responses, Messages и Gemini.")
	elif code == "images.not_configured": category = "configuration"; message = L.text("Генератор изображений не настроен. Откройте Настройки → Нейросеть → Генерация фото.")
	elif code.begins_with("images."): category = "generation"; message = L.text("Не удалось создать изображение. Подробная причина сохранена в результате инструмента.")
	elif code.begins_with("vision_") or code.begins_with("ui.image_"):
		category = "generation"; message = L.text("Не удалось передать игровой снимок: ")+code+L.text(". Попросите помощника сделать новый снимок после проверки выбранной модели.")
	elif code == "charts.invalid_response":
		category = "model_format"; message = L.text("Не удалось исправить формат диаграммы.")
		if details is Array and not details.is_empty() and details[0] is Dictionary: message += " "+str(details[0].get("reason",""))
	elif code in ["agent_round_limit","agent_call_limit"]: category = "budget"; message = L.text("Достигнут предел шагов за один ответ. Продолжить можно следующим сообщением.")
	elif "context" in code or "overflow" in code: category = "context"; message = L.text("Переполнен контекст запроса.")
	elif "timeout" in code: category = "timeout"; message = L.text("Истекло время ожидания ответа.")
	elif "loop" in code or "duplicate_action" in code: category = "loop"; message = L.text("Одинаковое действие повторяется без продвижения.")
	elif "stale" in code or "changed" in code or "read_required" in code: category = "conflict"; message = L.text("Сначала прочитайте актуальные данные; их версия могла измениться.")
	elif "not_enabled" in code or "permission" in code or "forwarded" in code: category = "permission"; message = L.text("Действие недоступно в этом запросе.")
	elif "schema" in code or "invalid_call" in code or "envelope" in code or "template" in code or "unknown_tool" in code: category = "model_format"; message = L.text("Формат ответа или аргументы не соответствуют схеме.")
	elif "json" in code or "parse" in code or code.begins_with("invalid_stream_"): category = "parsing"; message = L.text("Не удалось разобрать полный ответ модели.")
	elif code == "provider_stream_error": category = "provider"; message = L.text("Сервис модели вернул ошибку генерации.")
	elif "incomplete" in code or "truncat" in code or "finish_reason" in code: category = "generation"; message = L.text("Генерация оборвалась. Незавершённые команды не выполнялись.")
	elif code.begins_with("stream_") or code.begins_with("http_") or code == "agent_transport_error":
		category = "network"; message = L.text("Не удалось получить ответ сервиса модели.")
	if http_status in [401,403]: category = "authentication"; message = L.text("Сервис модели отклонил доступ. Проверьте подключение.")
	if http_status == 404: category = "provider"; message = L.text("Сервис не нашёл выбранную модель или адрес API. Проверьте ID и доступность модели.")
	if http_status in [400,422]: category = "provider"; message = L.text("Сервис модели отклонил параметры запроса. Проверьте совместимость модели и формата API.")
	if http_status == 429: category = "rate_limit"; message = L.text("Сервис модели временно ограничил частоту запросов.")
	retryable = http_status in [408,429,500,502,503,504] or code in ["stream_connection_error","stream_request_error","stream_empty_response","stream_incomplete","stream_timeout"]
	return {"code":code,"category":category,"message":message,"retryable":retryable,"http_status":http_status,"details":details}

static func delay_ms(attempt: int, retry_after: String = "", now: float = -1) -> int:
	var seconds := 0.0
	if retry_after.strip_edges().is_valid_float(): seconds = maxf(0,retry_after.to_float())
	elif retry_after != "":
		var pattern := RegEx.create_from_string("^[A-Za-z]{3}, (\\d{2}) ([A-Za-z]{3}) (\\d{4}) (\\d{2}):(\\d{2}):(\\d{2}) GMT$")
		var found: RegExMatch = pattern.search(retry_after.strip_edges())
		var months := ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
		if found != null and found.get_string(2) in months:
			var year: int = int(found.get_string(3))
			var month: int = months.find(found.get_string(2))+1
			var days: Array = [31,29 if year%4==0 and (year%100!=0 or year%400==0) else 28,31,30,31,30,31,31,30,31,30,31]
			if year>=1 and int(found.get_string(1))>=1 and int(found.get_string(1))<=days[month-1] and int(found.get_string(4))<24 and int(found.get_string(5))<60 and int(found.get_string(6))<60:
				var stamp: float = Time.get_unix_time_from_datetime_dict({"year":year,"month":month,"day":int(found.get_string(1)),"hour":int(found.get_string(4)),"minute":int(found.get_string(5)),"second":int(found.get_string(6))})
				seconds = maxf(0,stamp-(Time.get_unix_time_from_system() if now < 0 else now))
	if not is_finite(seconds): seconds = 86400
	return ceili(minf(86400000,maxf(minf(8000,1000*pow(2,attempt-1)),seconds*1000)))
