-- Проект №2. Роль 4 (DBA). PostgreSQL 16+.
-- Выполнить после 01-schema.sql; при наличии данных затем выполнить ANALYZE.
-- Индексы PK/UNIQUE уже создаются автоматически и здесь не дублируются.

-- Периодические отчёты по стоимости (03-analytics.sql): WHERE started_at BETWEEN ...
CREATE INDEX IF NOT EXISTS idx_llm_requests_started_at
    ON public.llm_requests (started_at);

-- Рейтинг ошибок за период (03-analytics.sql): WHERE occurred_at BETWEEN ...
CREATE INDEX IF NOT EXISTS idx_request_errors_occurred_at
    ON public.request_errors (occurred_at);

-- Быстрый список диалогов пользователя от новых к старым.
CREATE INDEX IF NOT EXISTS idx_conversations_user_created
    ON public.conversations (user_id, created_at DESC);

-- Связь от запроса к сообщениям (FK не создаёт индекс автоматически).
CREATE INDEX IF NOT EXISTS idx_messages_request
    ON public.messages (assistant_id, conversation_no, request_no);

-- Список ассистентов, к которым пользователь получил доступ.
-- PK (assistant_id, user_id) уже покрывает поиск пользователей ассистента,
-- но не эффективен для поиска по одному user_id.
CREATE INDEX IF NOT EXISTS idx_assistant_access_user
    ON public.assistant_access (user_id, assistant_id);

-- Сведения о селективности/планах обновятся автосбором статистики;
-- в учебной БД можно выполнить ANALYZE вручную после загрузки демоданных.
