-- Проверки на данных 04-demo.sql. При нарушении ожиданий скрипт выдаёт ошибку.
-- Все изменения теста откатываются. Запускать с psql -v ON_ERROR_STOP=1.
BEGIN;

DO $$
DECLARE
    v_assistant bigint;
    v_second bigint;
    v_owner bigint;
    v_editor bigint;
    v_viewer bigint;
    v_new_version bigint;
BEGIN
    SELECT assistant_id, owner_id INTO STRICT v_assistant, v_owner
    FROM public.assistants WHERE name = 'Помощник аналитика';
    SELECT assistant_id INTO STRICT v_second
    FROM public.assistants WHERE name = 'Помощник поддержки';
    SELECT user_id INTO STRICT v_editor FROM public.users WHERE email = 'editor@example.test';
    SELECT user_id INTO STRICT v_viewer FROM public.users WHERE email = 'viewer@example.test';

    -- Исключение правильного типа перехватывается; отсутствие исключения роняет проверку.
    BEGIN
        INSERT INTO public.assistant_access VALUES (v_assistant, v_editor, 'viewer', now());
        RAISE EXCEPTION 'FAIL: дубликат PK принят';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO public.conversations VALUES (v_assistant, 99, -1, NULL, now());
        RAISE EXCEPTION 'FAIL: отсутствующий пользователь принят';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET cost_usd = -0.01
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: отрицательная стоимость принята';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET cost_usd = 'NaN'::numeric
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: NaN вместо стоимости принят';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET input_tokens = -1
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: отрицательные токены приняты';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET finished_at = NULL
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: завершённый запрос без finished_at принят';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET finished_at = started_at - interval '1 second'
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: окончание до начала принято';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.llm_requests SET version_no = 2
        WHERE assistant_id = v_second AND conversation_no = 1 AND request_no = 1;
        RAISE EXCEPTION 'FAIL: версия другого ассистента принята';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.messages SET content = NULL
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND message_no = 1;
        RAISE EXCEPTION 'FAIL: пользовательское сообщение без content принято';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.message_metadata SET metadata = '[]'::jsonb
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND message_no = 2;
        RAISE EXCEPTION 'FAIL: JSON-массив вместо объекта принят';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.assistant_versions SET system_prompt = 'Изменение истории'
        WHERE assistant_id = v_assistant AND version_no = 1;
        RAISE EXCEPTION 'FAIL: изменение исторической версии разрешено';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        DELETE FROM public.assistant_versions
        WHERE assistant_id = v_assistant AND version_no = 2;
        RAISE EXCEPTION 'FAIL: удаление исторической версии разрешено';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        PERFORM public.publish_assistant_version(v_assistant, v_viewer, 'demo/model-a', 'Промпт', 0.5);
        RAISE EXCEPTION 'FAIL: viewer опубликовал настройки';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.publish_assistant_version(v_assistant, v_owner, 'demo/model-a', 'Промпт', 2.0001);
        RAISE EXCEPTION 'FAIL: температура выше 2 принята';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        DELETE FROM public.assistants WHERE assistant_id = v_assistant;
        RAISE EXCEPTION 'FAIL: удалён ассистент с историей';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    v_new_version := public.publish_assistant_version(v_assistant, v_editor,
        'demo/model-a', 'Тестовая третья версия', 0.7);
    IF v_new_version <> 3 THEN
        RAISE EXCEPTION 'FAIL: ожидалась версия 3, получена %', v_new_version;
    END IF;
    IF (SELECT version_no FROM public.llm_requests
        WHERE assistant_id = v_assistant AND conversation_no = 1 AND request_no = 1) <> 1 THEN
        RAISE EXCEPTION 'FAIL: версия старого запроса изменилась';
    END IF;

    RAISE NOTICE 'OK: 17 проверок ограничений и версионирования пройдены';
END;
$$;

ROLLBACK;
