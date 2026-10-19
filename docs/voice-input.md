# Голосовой ввод

Нажмите микрофон в поле сообщения, произнесите запрос и нажмите ещё раз. Запись продолжается до нажатия кнопки остановки. Во время записи работает индикатор уровня. После остановки доступны прослушивание, удаление и отправка; рядом можно написать текст. Закрытие чата или переход в другой чат отменяет незавершённую запись.

Harness использует выбранную в игре модель. Если модель и API принимают аудио, запись передаётся как WAV. Поддержка проверяется по входным модальностям API или реальной попыткой передачи записи; одно название Gemini/Gemma не считается подтверждением. Модель не заменяется.

Если аудиовход недоступен, Harness использует распознаватель, настроенный в **Настройки → Голос**, и передаёт модели распознанный текст. Длинная запись распознаётся частями после остановки; текст собирается в исходном порядке, аудиозапись сохраняется целиком. Если распознаватель отсутствует или занят, появляется ошибка с указанием причины; запись остаётся в черновике для повторной отправки. Можно удалить её и продолжить обычным текстом. Для локального распознавания нужны установленные средства Whisper из настроек игры; они не входят в архив мода.

Под голосовым сообщением написано, передано ли аудио напрямую или распознано в текст. Запись можно прослушать и после отправки. В истории хранится ссылка на локальное аудиовложение, а не длинная строка WAV в контексте. Расшифровка остаётся в истории для следующих ходов; WAV передаётся только при обработке этого сообщения. Голосовые вложения сохраняются в очереди и при сохранении партии. Распознавание не создаёт скрытых игровых приказов.

Прямой вход реализован для Chat Completions (`input_audio`, WAV) и Gemini `generateContent` (`inlineData`, `audio/wav`). Другие форматы используют распознавание. Даже если сама модель понимает звук, промежуточный API может его отклонять.

# English

Click the microphone in the composer, speak, then click it again to stop. Recording continues until you stop it, with a live level meter. Preview, remove or send the recording with optional text. Closing the chat or selecting another chat cancels an unfinished recording.

Harness keeps the selected game model. If both the model and API accept audio, it sends WAV directly. Input-modality metadata or an actual audio request determines support; a Gemini/Gemma name alone is insufficient. The model is never switched.

When native audio input is unavailable, Harness uses the recognizer configured under **Settings → Voice** and sends the recognized text. Long recordings are transcribed in segments after you stop; text is joined in order while the full audio remains intact. A missing or busy recognizer produces an actionable error and preserves the draft recording for retry. Remove the clip to continue with ordinary text. Local recognition requires the game's Whisper installation; these components are not included in the mod archive.

Each voice message indicates whether audio was passed directly or transcribed to text, and remains playable after sending. History stores a local attachment handle rather than a long WAV string in context. The transcript remains for later turns; WAV is sent only when processing that message. Queues and campaign saves preserve voice attachments. Recognition does not write hidden game orders.

Native input supports Chat Completions (`input_audio`, WAV) and Gemini `generateContent` (`inlineData`, `audio/wav`). Other formats use transcription. An intermediary API may reject audio even when the model itself supports it.
