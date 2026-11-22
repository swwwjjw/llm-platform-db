-- Необязательные демонстрационные данные для пустой схемы.
-- Имена моделей условные; внешние API не вызываются.
BEGIN;

DO $$
DECLARE
    v_owner bigint;
    v_editor bigint;
    v_viewer bigint;
    v_assistant bigint;
    v_second bigint;
BEGIN
    INSERT INTO public.users (email, display_name)
    VALUES ('owner@example.test', 'Владелец') RETURNING user_id INTO v_owner;
    INSERT INTO public.users (email, display_name)
    VALUES ('editor@example.test', 'Редактор') RETURNING user_id INTO v_editor;
    INSERT INTO public.users (email, display_name)
    VALUES ('viewer@example.test', 'Пользователь') RETURNING user_id INTO v_viewer;

    INSERT INTO public.assistants (owner_id, name, created_at)
    VALUES (v_owner, 'Помощник аналитика', '2026-10-31 00:00:00+00')
    RETURNING assistant_id INTO v_assistant;
    INSERT INTO public.assistant_access (assistant_id, user_id, access_role)
    VALUES (v_assistant, v_editor, 'editor'), (v_assistant, v_viewer, 'viewer');
    -- Датированный начальный снимок для воспроизводимых примеров отчётов.
    INSERT INTO public.assistant_versions (
        assistant_id, version_no, created_by, model_key, system_prompt, temperature, created_at
    ) VALUES (v_assistant, 1, v_owner, 'demo/model-a', 'Помогай аналитику.', 0.5,
              '2026-10-31 00:00:00+00');

    INSERT INTO public.assistants (owner_id, name, created_at)
    VALUES (v_owner, 'Помощник поддержки', '2026-10-31 00:00:00+00')
    RETURNING assistant_id INTO v_second;
    INSERT INTO public.assistant_access (assistant_id, user_id, access_role)
    VALUES (v_second, v_viewer, 'viewer');
    INSERT INTO public.assistant_versions (
        assistant_id, version_no, created_by, model_key, system_prompt, temperature, created_at
    ) VALUES (v_second, 1, v_owner, 'demo/model-b', 'Помогай поддержке.', 0.2,
              '2026-10-31 00:00:00+00');

    INSERT INTO public.conversations (assistant_id, conversation_no, user_id, title)
    VALUES (v_assistant, 1, v_owner, 'Отчёт'),
           (v_assistant, 2, v_editor, 'Анализ'),
           (v_second, 1, v_viewer, 'Поддержка');

    INSERT INTO public.llm_requests (
        assistant_id, conversation_no, request_no, version_no,
        started_at, finished_at, status, input_tokens, output_tokens, cost_usd
    ) VALUES
        (v_assistant, 1, 1, 1, '2026-11-01 00:00:00+00', '2026-11-01 00:00:05+00',
         'succeeded', 100, 50, 0.01),
        (v_assistant, 2, 1, 1, '2026-11-10 10:00:00+00', '2026-11-10 10:00:05+00',
         'failed', 200, 0, 0.02),
        (v_assistant, 1, 2, 1, '2026-11-20 10:00:00+00', NULL,
         'pending', NULL, NULL, NULL),
        (v_second, 1, 1, 1, '2026-11-15 10:00:00+00', '2026-11-15 10:00:05+00',
         'succeeded', 50, 25, 0.005),
        (v_second, 1, 2, 1, '2026-12-01 00:00:00+00', '2026-12-01 00:00:05+00',
         'succeeded', 1000, 100, 0.9);

    INSERT INTO public.messages (
        assistant_id, conversation_no, message_no, request_no, role, content, created_at
    ) VALUES
        (v_assistant, 1, 1, 1, 'user', 'Составь отчёт.', '2026-11-01 00:00:00+00'),
        (v_assistant, 1, 2, 1, 'assistant', NULL, '2026-11-01 00:00:01+00'),
        (v_assistant, 1, 3, 1, 'tool', 'Данные найдены.', '2026-11-01 00:00:04+00'),
        (v_assistant, 1, 4, 1, 'assistant', 'Отчёт готов.', '2026-11-01 00:00:05+00'),
        (v_assistant, 1, 5, 2, 'user', 'Продолжи.', '2026-11-20 10:00:00+00'),
        (v_assistant, 2, 1, 1, 'user', 'Проанализируй данные.', '2026-11-10 10:00:00+00'),
        (v_second, 1, 1, 1, 'user', 'Помоги.', '2026-11-15 10:00:00+00'),
        (v_second, 1, 2, 1, 'assistant', 'Чем помочь?', '2026-11-15 10:00:05+00'),
        (v_second, 1, 3, 2, 'user', 'Новый вопрос.', '2026-12-01 00:00:00+00'),
        (v_second, 1, 4, 2, 'assistant', 'Новый ответ.', '2026-12-01 00:00:05+00');

    INSERT INTO public.message_metadata (assistant_id, conversation_no, message_no, metadata)
    VALUES (v_assistant, 1, 2,
            '{"tool_calls":[{"tool_name":"search_documents","status":"success"}]}'),
           (v_assistant, 1, 4,
            '{"citations":[{"document_id":"doc-123","source":"internal_knowledge_base"}]}');

    INSERT INTO public.request_errors (
        assistant_id, conversation_no, request_no, error_no, source, error_code, occurred_at
    ) VALUES
        (v_assistant, 1, 1, 1, 'tool', 'timeout', '2026-11-01 00:00:02+00'),
        (v_assistant, 2, 1, 1, 'llm', 'rate_limit', '2026-11-10 10:00:05+00'),
        (v_second, 1, 2, 1, 'tool', 'timeout', '2026-12-01 00:00:01+00');

    -- Новая версия не меняет ссылки уже созданных запросов.
    PERFORM public.publish_assistant_version(v_assistant, v_editor, 'demo/model-a',
        'Помогай аналитику, указывай источники.', 0.3);
END;
$$;

COMMIT;
