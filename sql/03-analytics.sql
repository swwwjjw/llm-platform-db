-- Три параметризованных запроса. Период [начало, конец).
-- PREPARE выполняется один раз на соединение; затем вызывается EXECUTE.

-- 1. Стоимость и число запросов по ассистентам.
-- Сообщения сюда не присоединяем: несколько сообщений не умножают расходы.
PREPARE cost_by_assistant(timestamptz, timestamptz) AS
SELECT a.assistant_id, a.name,
       COUNT(*) AS request_count,
       SUM(r.cost_usd) AS known_cost_usd,
       COUNT(*) FILTER (WHERE r.cost_usd IS NULL) AS unknown_cost_count
FROM public.llm_requests AS r
JOIN public.assistants AS a ON a.assistant_id = r.assistant_id
WHERE r.started_at >= $1 AND r.started_at < $2
GROUP BY a.assistant_id, a.name
ORDER BY known_cost_usd DESC NULLS LAST, a.assistant_id;

-- 2. Стоимость по пользователям, отправлявшим запросы (владельцам диалогов).
PREPARE cost_by_user(timestamptz, timestamptz) AS
SELECT u.user_id, u.email,
       COUNT(*) AS request_count,
       SUM(r.cost_usd) AS known_cost_usd,
       COUNT(*) FILTER (WHERE r.cost_usd IS NULL) AS unknown_cost_count
FROM public.llm_requests AS r
JOIN public.conversations AS c
  ON c.assistant_id = r.assistant_id AND c.conversation_no = r.conversation_no
JOIN public.users AS u ON u.user_id = c.user_id
WHERE r.started_at >= $1 AND r.started_at < $2
GROUP BY u.user_id, u.email
ORDER BY known_cost_usd DESC NULLS LAST, u.user_id;

-- 3. Топ-10 ошибок по времени события, включая исправленные ошибки
-- в успешно завершённых запросах. Считаются события, а не запросы.
PREPARE top_errors(timestamptz, timestamptz) AS
SELECT source, error_code, COUNT(*) AS event_count
FROM public.request_errors
WHERE occurred_at >= $1 AND occurred_at < $2
GROUP BY source, error_code
ORDER BY event_count DESC, source, error_code
LIMIT 10;

-- Пример запуска (явный часовой пояс):
-- EXECUTE cost_by_assistant('2026-11-01 00:00:00+00', '2026-12-01 00:00:00+00');
-- EXECUTE cost_by_user('2026-11-01 00:00:00+00', '2026-12-01 00:00:00+00');
-- EXECUTE top_errors('2026-11-01 00:00:00+00', '2026-12-01 00:00:00+00');
