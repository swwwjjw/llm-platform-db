-- Проект №2. Роль 3: SQL-разработчик. PostgreSQL 16+.
-- Выполнять в отдельной пустой учебной БД.
BEGIN;

CREATE TABLE public.users (
    user_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email text NOT NULL UNIQUE,
    display_name text NOT NULL CHECK (btrim(display_name) <> ''),
    platform_role text NOT NULL DEFAULT 'member'
        CHECK (platform_role IN ('member', 'admin')),
    CHECK (email = lower(btrim(email)) AND email <> '')
);

CREATE TABLE public.assistants (
    assistant_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    owner_id bigint NOT NULL REFERENCES public.users(user_id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (btrim(name) <> ''),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE public.assistant_access (
    assistant_id bigint NOT NULL REFERENCES public.assistants(assistant_id) ON DELETE RESTRICT,
    user_id bigint NOT NULL REFERENCES public.users(user_id) ON DELETE RESTRICT,
    access_role text NOT NULL CHECK (access_role IN ('viewer', 'editor')),
    granted_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (assistant_id, user_id)
);

CREATE TABLE public.assistant_versions (
    assistant_id bigint NOT NULL REFERENCES public.assistants(assistant_id) ON DELETE RESTRICT,
    version_no bigint NOT NULL CHECK (version_no > 0),
    created_by bigint NOT NULL REFERENCES public.users(user_id) ON DELETE RESTRICT,
    model_key text NOT NULL CHECK (model_key ~ '^[^/[:space:]]+/[^/[:space:]]+$'),
    system_prompt text NOT NULL CHECK (btrim(system_prompt) <> ''),
    temperature numeric(4,3) NOT NULL
        CHECK (temperature BETWEEN 0 AND 2),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (assistant_id, version_no)
);

CREATE TABLE public.conversations (
    assistant_id bigint NOT NULL REFERENCES public.assistants(assistant_id) ON DELETE RESTRICT,
    conversation_no bigint NOT NULL CHECK (conversation_no > 0),
    user_id bigint NOT NULL REFERENCES public.users(user_id) ON DELETE RESTRICT,
    title text NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (assistant_id, conversation_no)
);

CREATE TABLE public.llm_requests (
    assistant_id bigint NOT NULL,
    conversation_no bigint NOT NULL,
    request_no bigint NOT NULL CHECK (request_no > 0),
    version_no bigint NOT NULL,
    started_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at timestamptz NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'succeeded', 'failed')),
    input_tokens bigint NULL CHECK (input_tokens >= 0),
    output_tokens bigint NULL CHECK (output_tokens >= 0),
    cost_usd numeric(18,8) NULL CHECK (cost_usd >= 0 AND cost_usd <> 'NaN'::numeric),
    PRIMARY KEY (assistant_id, conversation_no, request_no),
    FOREIGN KEY (assistant_id, conversation_no)
        REFERENCES public.conversations(assistant_id, conversation_no) ON DELETE RESTRICT,
    FOREIGN KEY (assistant_id, version_no)
        REFERENCES public.assistant_versions(assistant_id, version_no) ON DELETE RESTRICT,
    CHECK (
        (status = 'pending' AND finished_at IS NULL)
        OR (status IN ('succeeded', 'failed') AND finished_at IS NOT NULL
            AND finished_at >= started_at)
    )
);

CREATE TABLE public.messages (
    assistant_id bigint NOT NULL,
    conversation_no bigint NOT NULL,
    message_no bigint NOT NULL CHECK (message_no > 0),
    request_no bigint NOT NULL,
    role text NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
    content text NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (assistant_id, conversation_no, message_no),
    FOREIGN KEY (assistant_id, conversation_no, request_no)
        REFERENCES public.llm_requests(assistant_id, conversation_no, request_no) ON DELETE RESTRICT,
    CHECK (role <> 'user' OR content IS NOT NULL)
);

CREATE TABLE public.message_metadata (
    assistant_id bigint NOT NULL,
    conversation_no bigint NOT NULL,
    message_no bigint NOT NULL,
    metadata jsonb NOT NULL CHECK (jsonb_typeof(metadata) = 'object'),
    PRIMARY KEY (assistant_id, conversation_no, message_no),
    FOREIGN KEY (assistant_id, conversation_no, message_no)
        REFERENCES public.messages(assistant_id, conversation_no, message_no) ON DELETE RESTRICT
);

CREATE TABLE public.request_errors (
    assistant_id bigint NOT NULL,
    conversation_no bigint NOT NULL,
    request_no bigint NOT NULL,
    error_no bigint NOT NULL CHECK (error_no > 0),
    source text NOT NULL CHECK (source IN ('llm', 'tool')),
    error_code text NOT NULL CHECK (btrim(error_code) <> ''),
    detail text NULL,
    occurred_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (assistant_id, conversation_no, request_no, error_no),
    FOREIGN KEY (assistant_id, conversation_no, request_no)
        REFERENCES public.llm_requests(assistant_id, conversation_no, request_no) ON DELETE RESTRICT
);

COMMIT;
