-- Диагностика после выполнения 06-indexes.sql и 07-security.sql.
-- Скрипт ничего не меняет: результаты выводятся SELECT-запросами.

-- 1. У всех девяти таблиц должен быть PK.
SELECT t.table_name,
       EXISTS (
           SELECT 1 FROM information_schema.table_constraints c
           WHERE c.table_schema = 'public'
             AND c.table_name = t.table_name
             AND c.constraint_type = 'PRIMARY KEY'
       ) AS has_primary_key
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_type = 'BASE TABLE'
  AND t.table_name IN (
      'users','assistants','assistant_access','assistant_versions',
      'conversations','llm_requests','messages','message_metadata','request_errors'
  )
ORDER BY t.table_name;

-- 2. Список ограничений: PK, FK, UNIQUE, CHECK.
SELECT conrelid::regclass AS table_name, contype AS constraint_type, conname
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
ORDER BY table_name::text, constraint_type, conname;

-- 3. Индексы, созданные DBA.
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND indexname IN (
    'idx_llm_requests_started_at', 'idx_request_errors_occurred_at',
    'idx_conversations_user_created', 'idx_messages_request',
    'idx_assistant_access_user'
)
ORDER BY tablename, indexname;

-- 4. Контрольные права для ролей.
SELECT has_table_privilege('llm_app', 'public.llm_requests', 'INSERT') AS app_can_insert_requests,
       has_table_privilege('llm_app', 'public.assistant_versions', 'DELETE') AS app_can_delete_versions,
       has_table_privilege('llm_analyst', 'public.llm_requests', 'SELECT') AS analyst_can_read_requests,
       has_table_privilege('llm_analyst', 'public.llm_requests', 'INSERT') AS analyst_can_insert_requests;

-- 5. Реальный план на демоданных (на маленькой БД Seq Scan допустим).
EXPLAIN (ANALYZE, BUFFERS)
SELECT assistant_id, SUM(cost_usd)
FROM public.llm_requests
WHERE started_at >= '2026-11-01 00:00:00+00'
  AND started_at <  '2026-12-01 00:00:00+00'
GROUP BY assistant_id;
