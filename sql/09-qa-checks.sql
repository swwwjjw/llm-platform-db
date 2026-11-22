-- Роль 5: QA. Сценарии из docs/06-qa-checklist.md на данных 04-demo.sql.
-- Запускать только в отдельной учебной БД: psql -v ON_ERROR_STOP=1 -f sql/09-qa-checks.sql.
-- Отрицательные пробы откатываются; весь сценарий завершается ROLLBACK.
BEGIN;

DO $$
DECLARE
    v_editor bigint;
    v_viewer bigint;
    v_assistant bigint;
    v_second bigint;
    v_count bigint;
    v_cost numeric(18,8);
BEGIN
    SELECT user_id INTO STRICT v_editor FROM public.users WHERE email = 'editor@example.test';
    SELECT user_id INTO STRICT v_viewer FROM public.users WHERE email = 'viewer@example.test';
    SELECT assistant_id INTO STRICT v_assistant FROM public.assistants WHERE name = 'Помощник аналитика';
    SELECT assistant_id INTO STRICT v_second FROM public.assistants WHERE name = 'Помощник поддержки';

    -- QA-01: составные FK не допускают чужую версию и сообщение-сироту.
    BEGIN
        UPDATE public.llm_requests SET version_no = 2
        WHERE assistant_id = v_second AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL QA-01: версия другого ассистента принята';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO public.messages (assistant_id, conversation_no, message_no, request_no, role, content)
        VALUES (v_assistant, 1, 99, 999, 'user', 'Тест');
        RAISE EXCEPTION 'FAIL QA-01: сообщение без запроса принято';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    -- QA-02: UNIQUE email и составной PK доступа.
    BEGIN
        UPDATE public.users SET email = 'owner@example.test' WHERE user_id = v_editor;
        RAISE EXCEPTION 'FAIL QA-02: дубликат email принят';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO public.assistant_access (assistant_id, user_id, access_role)
        VALUES (v_assistant, v_editor, 'viewer');
        RAISE EXCEPTION 'FAIL QA-02: дубликат доступа принят';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    -- QA-03: обязательные поля не принимают NULL; неизвестная стоимость допустима.
    BEGIN
        UPDATE public.assistants SET name = NULL WHERE assistant_id = v_assistant;
        RAISE EXCEPTION 'FAIL QA-03: NULL в имени принят';
    EXCEPTION WHEN not_null_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.message_metadata SET metadata = NULL
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND message_no = 2;
        RAISE EXCEPTION 'FAIL QA-03: NULL в метаданных принят';
    EXCEPTION WHEN not_null_violation THEN NULL;
    END;
    IF NOT EXISTS (
        SELECT 1 FROM public.llm_requests
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 2
          AND cost_usd IS NULL AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'FAIL QA-03: нет запроса с допустимой неизвестной стоимостью';
    END IF;

    -- QA-04: допустимые значения статуса, стоимости и JSONB.
    BEGIN
        UPDATE public.llm_requests SET status = 'unknown'
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL QA-04: неверный статус принят';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET cost_usd = -0.01
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL QA-04: отрицательная стоимость принята';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.message_metadata SET metadata = '[]'::jsonb
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND message_no = 2;
        RAISE EXCEPTION 'FAIL QA-04: JSON-массив принят';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- QA-05: история настроек неизменяема, viewer не публикует, старый запрос хранит снимок.
    BEGIN
        UPDATE public.assistant_versions SET system_prompt = 'Подмена'
        WHERE assistant_id = v_assistant AND version_no = 1;
        RAISE EXCEPTION 'FAIL QA-05: изменение версии принято';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        PERFORM public.publish_assistant_version(v_assistant, v_viewer, 'demo/model-a', 'Тест', 0.5);
        RAISE EXCEPTION 'FAIL QA-05: viewer опубликовал версию';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    IF NOT EXISTS (
        SELECT 1 FROM public.llm_requests
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1 AND version_no = 1
    ) OR NOT EXISTS (
        SELECT 1 FROM public.assistant_versions
        WHERE assistant_id = v_assistant AND version_no = 2
    ) THEN
        RAISE EXCEPTION 'FAIL QA-05: нарушена связь запроса с исторической версией';
    END IF;

    -- QA-06: независимые контрольные факты набора для сравнения с 03-analytics.sql.
    SELECT COUNT(*), SUM(cost_usd) INTO v_count, v_cost
    FROM public.llm_requests
    WHERE started_at >= '2026-11-01 00:00:00+00'
      AND started_at < '2026-12-01 00:00:00+00';
    IF v_count IS DISTINCT FROM 4 OR v_cost IS DISTINCT FROM 0.03500000 THEN
        RAISE EXCEPTION 'FAIL QA-06: ожидались 4 запроса и 0.03500000 USD, получены % и %', v_count, v_cost;
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.llm_requests
    WHERE started_at >= '2026-11-01 00:00:00+00'
      AND started_at < '2026-12-01 00:00:00+00'
      AND cost_usd IS NULL;
    IF v_count IS DISTINCT FROM 1 OR NOT EXISTS (
        SELECT 1 FROM public.llm_requests
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1
          AND started_at = '2026-11-01 00:00:00+00'
    ) OR NOT EXISTS (
        SELECT 1 FROM public.llm_requests
        WHERE assistant_id = v_second AND conversation_no = 1 AND request_no = 2
          AND started_at = '2026-12-01 00:00:00+00'
    ) THEN
        RAISE EXCEPTION 'FAIL QA-06: нарушены контрольные данные стоимости или границ периода';
    END IF;

    -- QA-07: два ноябрьских события, включая ошибку инструмента при succeeded.
    SELECT COUNT(*) INTO v_count FROM public.request_errors
    WHERE occurred_at >= '2026-11-01 00:00:00+00'
      AND occurred_at < '2026-12-01 00:00:00+00';
    IF v_count IS DISTINCT FROM 2 OR NOT EXISTS (
        SELECT 1 FROM public.request_errors e
        JOIN public.llm_requests r USING (assistant_id, conversation_no, request_no)
        WHERE e.assistant_id = v_assistant AND e.source = 'tool'
          AND e.error_code = 'timeout' AND r.status = 'succeeded'
          AND e.occurred_at >= '2026-11-01 00:00:00+00'
          AND e.occurred_at < '2026-12-01 00:00:00+00'
    ) OR NOT EXISTS (
        SELECT 1 FROM public.request_errors
        WHERE assistant_id = v_assistant AND conversation_no = 2 AND request_no = 1
          AND source = 'llm' AND error_code = 'rate_limit'
          AND occurred_at >= '2026-11-01 00:00:00+00'
          AND occurred_at < '2026-12-01 00:00:00+00'
    ) OR NOT EXISTS (
        SELECT 1 FROM public.request_errors
        WHERE assistant_id = v_second AND conversation_no = 1 AND request_no = 2
          AND occurred_at = '2026-12-01 00:00:01+00'
    ) THEN
        RAISE EXCEPTION 'FAIL QA-07: неверные контрольные данные ошибок';
    END IF;

    RAISE NOTICE 'OK: QA-01...QA-07 пройдены; результаты подготовленных отчётов сравнить с docs/06-qa-checklist.md';
END;
$$;

ROLLBACK;
