-- Проект №2. Роль 4 (DBA). PostgreSQL 16+.
-- Выполнять владельцем таблиц/функций с правом CREATEROLE в отдельной учебной БД.
-- Создаются роли-группы NOLOGIN. Учётные записи LOGIN/пароли задаются отдельно.
-- Этот файл не меняет владельцев таблиц и не создаёт суперпользователей.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'llm_app') THEN
        CREATE ROLE llm_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'llm_analyst') THEN
        CREATE ROLE llm_analyst NOLOGIN;
    END IF;
END
$$;

-- Только в выделенной для проекта БД: запретить неявные права PUBLIC.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_assistant_version(bigint, bigint, text, text, numeric)
    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reject_version_change() FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO llm_app, llm_analyst;

-- Прикладная роль: доступ к данным для бизнес-операций.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO llm_app;
GRANT INSERT ON public.users, public.assistants, public.assistant_access,
    public.assistant_versions, public.conversations, public.llm_requests,
    public.messages, public.message_metadata, public.request_errors TO llm_app;
GRANT UPDATE (display_name) ON public.users TO llm_app;
GRANT UPDATE (name) ON public.assistants TO llm_app;
GRANT UPDATE (access_role) ON public.assistant_access TO llm_app;
GRANT DELETE ON public.assistant_access TO llm_app;
GRANT UPDATE (title) ON public.conversations TO llm_app;
GRANT UPDATE (status, finished_at, input_tokens, output_tokens, cost_usd)
    ON public.llm_requests TO llm_app;

-- GENERATED ALWAYS AS IDENTITY использует sequences. При вставке с обычными
-- DEFAULT значениями явное USAGE обычно не требуется, но выдаём явно для
-- совместимости и операций, использующих nextval().
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO llm_app;
GRANT EXECUTE ON FUNCTION public.publish_assistant_version(bigint, bigint, text, text, numeric)
    TO llm_app;

-- Аналитик: только чтение таблиц, необходимых для трёх отчётов.
GRANT SELECT ON public.users, public.assistants, public.conversations,
    public.llm_requests, public.request_errors TO llm_analyst;

-- ВАЖНО: publish_assistant_version имеет SECURITY INVOKER.
-- Поэтому llm_app нуждается в INSERT на assistant_versions и технически может
-- обойти функцию прямым INSERT. Кроме того, p_created_by передаётся вызывающим.
-- Для настоящего разграничения по пользователям нужны проверенная идентичность,
-- безопасная SECURITY DEFINER-функция и/или RLS с отдельными политиками.
-- GRANT сам по себе не заменяет проверки приложения, описанные в ER-модели.
