-- Публикация настроек и защита исторических версий.
BEGIN;

CREATE FUNCTION public.reject_version_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Опубликованную версию нельзя изменить или удалить; создайте новую'
        USING ERRCODE = '23514';
END;
$$;

CREATE TRIGGER assistant_versions_immutable
BEFORE UPDATE OR DELETE ON public.assistant_versions
FOR EACH ROW EXECUTE FUNCTION public.reject_version_change();

CREATE FUNCTION public.publish_assistant_version(
    p_assistant_id bigint,
    p_created_by bigint,
    p_model_key text,
    p_system_prompt text,
    p_temperature numeric
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_owner_id bigint;
    v_version_no bigint;
BEGIN
    -- Блокировка держится до конца внешней транзакции. Все публикации
    -- одного ассистента через эту функцию выполняются последовательно.
    SELECT owner_id INTO v_owner_id
    FROM public.assistants
    WHERE assistant_id = p_assistant_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ассистент % не существует', p_assistant_id
            USING ERRCODE = '23503';
    END IF;

    IF p_created_by IS NULL OR (
        p_created_by <> v_owner_id AND NOT EXISTS (
            SELECT 1 FROM public.assistant_access
            WHERE assistant_id = p_assistant_id
              AND user_id = p_created_by AND access_role = 'editor'
        )
    ) THEN
        RAISE EXCEPTION 'Пользователь % не может публиковать настройки ассистента %',
            p_created_by, p_assistant_id USING ERRCODE = '42501';
    END IF;

    -- Проверяем исходное значение до округления к numeric(4,3).
    IF p_temperature IS NULL OR NOT (p_temperature BETWEEN 0 AND 2) THEN
        RAISE EXCEPTION 'Температура должна находиться в диапазоне [0, 2]'
            USING ERRCODE = '23514';
    END IF;

    SELECT COALESCE(MAX(version_no), 0) + 1 INTO v_version_no
    FROM public.assistant_versions
    WHERE assistant_id = p_assistant_id;

    INSERT INTO public.assistant_versions (
        assistant_id, version_no, created_by, model_key, system_prompt, temperature
    ) VALUES (
        p_assistant_id, v_version_no, p_created_by,
        p_model_key, p_system_prompt, p_temperature
    );

    RETURN v_version_no;
END;
$$;

COMMIT;
