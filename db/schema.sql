DROP SCHEMA IF EXISTS course_platform;

CREATE SCHEMA course_platform;
	SET NAMES utf8mb4;
	SET time_zone = '+00:00';

USE course_platform;

CREATE TABLE roles (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(50) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_roles_name UNIQUE (name),
    CONSTRAINT chk_roles_name CHECK (CHAR_LENGTH(TRIM(name)) > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Catálogo inicial. Los permisos de cada rol se definirán en la aplicación.
INSERT INTO roles (name) VALUES ('STUDENT'), ('INSTRUCTOR'), ('ADMIN');

CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    -- Generado por la aplicación como UUID v4, en formato canónico en minúsculas.
    public_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role_id BIGINT NOT NULL,
    username VARCHAR(50) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(254) NULL,
    first_name VARCHAR(100) NULL,
    last_name VARCHAR(100) NULL,
    phone VARCHAR(30) NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_users_public_id UNIQUE (public_id),
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email UNIQUE (email),
    INDEX idx_users_role (role_id),
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles (id) ON DELETE RESTRICT,
    CONSTRAINT chk_users_public_id CHECK (
        REGEXP_LIKE(public_id, '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', 'c')
    ),
    CONSTRAINT chk_users_username CHECK (CHAR_LENGTH(TRIM(username)) > 0),
    CONSTRAINT chk_users_password_hash CHECK (CHAR_LENGTH(TRIM(password_hash)) > 0),
    CONSTRAINT chk_users_email CHECK (email IS NULL OR CHAR_LENGTH(TRIM(email)) > 0),
    CONSTRAINT chk_users_phone CHECK (phone IS NULL OR CHAR_LENGTH(TRIM(phone)) > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE courses (
    id BIGINT NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    estimated_duration_minutes INT NOT NULL,
    difficulty_level VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    publication_status VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'DRAFT',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT chk_courses_title CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT chk_courses_description CHECK (CHAR_LENGTH(TRIM(description)) > 0),
    CONSTRAINT chk_courses_duration CHECK (estimated_duration_minutes > 0),
    CONSTRAINT chk_courses_difficulty CHECK (difficulty_level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED')),
    CONSTRAINT chk_courses_publication_status CHECK (publication_status IN ('DRAFT', 'PUBLISHED'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE course_modules (
    id BIGINT NOT NULL AUTO_INCREMENT,
    course_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    position INT NOT NULL,
    coverage_percentage DECIMAL(5,2) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_course_modules_position UNIQUE (course_id, position),
    CONSTRAINT fk_course_modules_course FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_course_modules_title CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT chk_course_modules_position CHECK (position > 0),
    CONSTRAINT chk_course_modules_coverage CHECK (coverage_percentage > 0 AND coverage_percentage <= 100)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Solo compras confirmadas. Cada compra concede acceso sin vencimiento.
-- Los intentos de pago y reembolsos requieren un flujo posterior independiente.
CREATE TABLE course_purchases (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    amount_paid DECIMAL(12,2) NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    purchased_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_course_purchases_user_course UNIQUE (user_id, course_id),
    INDEX idx_course_purchases_course (course_id),
    CONSTRAINT fk_course_purchases_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_course_purchases_course FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_course_purchases_amount CHECK (amount_paid >= 0),
    CONSTRAINT chk_course_purchases_currency CHECK (REGEXP_LIKE(currency, '^[A-Z]{3}$', 'c'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Cada fila representa un período adquirido de acceso a TODO el catálogo.
-- Acceso vigente cuando starts_at <= instante actual AND instante actual < ends_at.
-- Ciclos mensuales calculados SIEMPRE desde el ancla original, en UTC.
CREATE TABLE subscriptions (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    billing_anchor_at DATETIME(6) NOT NULL,
    billing_cycle INT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    amount_paid DECIMAL(12,2) NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_subscriptions_user_start UNIQUE (user_id, starts_at),
    CONSTRAINT uq_subscriptions_cycle UNIQUE (user_id, billing_anchor_at, billing_cycle),
    INDEX idx_subscriptions_user_end (user_id, ends_at),
    CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_subscriptions_period CHECK (ends_at > starts_at),
    CONSTRAINT chk_subscriptions_cycle CHECK (billing_cycle >= 0),
    CONSTRAINT chk_subscriptions_monthly_dates CHECK (
        DATE_ADD(billing_anchor_at, INTERVAL billing_cycle MONTH) IS NOT NULL
        AND DATE_ADD(billing_anchor_at, INTERVAL (billing_cycle + 1) MONTH) IS NOT NULL
        AND starts_at = DATE_ADD(billing_anchor_at, INTERVAL billing_cycle MONTH)
        AND ends_at = DATE_ADD(billing_anchor_at, INTERVAL (billing_cycle + 1) MONTH)
    ),
    CONSTRAINT chk_subscriptions_amount CHECK (amount_paid >= 0),
    CONSTRAINT chk_subscriptions_currency CHECK (REGEXP_LIKE(currency, '^[A-Z]{3}$', 'c'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE lessons (
    id BIGINT NOT NULL AUTO_INCREMENT,
    module_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NULL,
    position INT NOT NULL,
    video_key VARCHAR(512) COLLATE utf8mb4_bin NOT NULL,
    video_revision INT NOT NULL DEFAULT 1,
    duration_seconds DECIMAL(12,3) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_lessons_module_position UNIQUE (module_id, position),
    CONSTRAINT fk_lessons_module FOREIGN KEY (module_id) REFERENCES course_modules (id) ON DELETE RESTRICT,
    CONSTRAINT chk_lessons_title CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT chk_lessons_position CHECK (position > 0),
    CONSTRAINT chk_lessons_video_key CHECK (CHAR_LENGTH(TRIM(video_key)) > 0),
    CONSTRAINT chk_lessons_video_revision CHECK (video_revision > 0),
    CONSTRAINT chk_lessons_duration CHECK (duration_seconds > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Intervalos [start_seconds, end_seconds) realmente reproducidos.
-- El servidor debe validar acceso, eventos de reproducción y límites del video.
-- Un salto del segundo 10 al 90 NO es un intervalo reproducido de 10 a 90.
CREATE TABLE lesson_watch_intervals (
    user_id BIGINT NOT NULL,
    lesson_id BIGINT NOT NULL,
    video_revision INT NOT NULL DEFAULT 1,
    start_seconds DECIMAL(12,3) NOT NULL,
    end_seconds DECIMAL(12,3) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, lesson_id, video_revision, start_seconds, end_seconds),
    INDEX idx_lesson_watch_intervals_lesson (lesson_id),
    CONSTRAINT fk_lesson_watch_intervals_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_lesson_watch_intervals_lesson FOREIGN KEY (lesson_id) REFERENCES lessons (id) ON DELETE RESTRICT,
    CONSTRAINT chk_lesson_watch_intervals_revision CHECK (video_revision > 0),
    CONSTRAINT chk_lesson_watch_intervals_bounds CHECK (start_seconds >= 0 AND end_seconds > start_seconds)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Estado reconocido, no auditoría: el backend debe guardarlo en la misma
-- transacción que registra reproducción y ANTES de editar contenido o pesos.
CREATE TABLE lesson_progress_state (
    user_id BIGINT NOT NULL,
    lesson_id BIGINT NOT NULL,
    max_progress_percentage DECIMAL(12,9) NOT NULL DEFAULT 0,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, lesson_id),
    CONSTRAINT fk_lesson_progress_state_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_lesson_progress_state_lesson FOREIGN KEY (lesson_id) REFERENCES lessons (id) ON DELETE RESTRICT,
    CONSTRAINT chk_lesson_progress_state_percentage CHECK (max_progress_percentage BETWEEN 0 AND 100)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE module_completion_records (
    user_id BIGINT NOT NULL,
    module_id BIGINT NOT NULL,
    completed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, module_id),
    CONSTRAINT fk_module_completion_records_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_module_completion_records_module FOREIGN KEY (module_id) REFERENCES course_modules (id) ON DELETE RESTRICT
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE course_progress_state (
    user_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    max_progress_percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, course_id),
    CONSTRAINT fk_course_progress_state_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_course_progress_state_course FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE RESTRICT,
    CONSTRAINT chk_course_progress_state_percentage CHECK (max_progress_percentage BETWEEN 0 AND 100)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- Suma la unión de los intervalos: solapamientos y repeticiones no suman dos veces.
-- Se recortan a la duración como defensa adicional ante datos fuera de rango.
CREATE VIEW lesson_progress AS
WITH bounded_intervals AS (
    SELECT w.user_id, w.lesson_id, w.start_seconds,
           LEAST(w.end_seconds, l.duration_seconds) AS end_seconds
    FROM lesson_watch_intervals w
    JOIN lessons l ON l.id = w.lesson_id
    WHERE w.start_seconds < l.duration_seconds AND w.video_revision = l.video_revision
), ordered_intervals AS (
    SELECT user_id, lesson_id, start_seconds, end_seconds,
           MAX(end_seconds) OVER (
               PARTITION BY user_id, lesson_id
               ORDER BY start_seconds, end_seconds
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
           ) AS previous_end
    FROM bounded_intervals
), watched_totals AS (
    SELECT user_id, lesson_id,
           SUM(GREATEST(0, end_seconds - GREATEST(start_seconds, COALESCE(previous_end, start_seconds)))) AS watched_seconds
    FROM ordered_intervals
    GROUP BY user_id, lesson_id
), progress_keys AS (
    SELECT user_id, lesson_id FROM watched_totals
    UNION
    SELECT user_id, lesson_id FROM lesson_progress_state
), effective_progress AS (
    SELECT k.user_id, k.lesson_id, COALESCE(t.watched_seconds, 0) AS watched_seconds,
           GREATEST(COALESCE(s.max_progress_percentage, 0),
                    TRUNCATE(CAST(COALESCE(t.watched_seconds, 0) AS DECIMAL(40,18)) * 100.0 / l.duration_seconds, 9)) AS progress_percentage
    FROM progress_keys k
    JOIN lessons l ON l.id = k.lesson_id
    LEFT JOIN watched_totals t ON t.user_id = k.user_id AND t.lesson_id = k.lesson_id
    LEFT JOIN lesson_progress_state s ON s.user_id = k.user_id AND s.lesson_id = k.lesson_id
)
SELECT user_id, lesson_id, watched_seconds, progress_percentage,
       (progress_percentage >= 90) AS is_completed
FROM effective_progress;

-- Un módulo vacío nunca está completo. Una lección sin avance tampoco.
-- Se conservan también las finalizaciones ya reconocidas antes de agregar lecciones.
CREATE VIEW module_completions AS
SELECT user_id, module_id FROM module_completion_records
UNION
SELECT p.user_id, l.module_id
FROM lessons l
JOIN lesson_progress p ON p.lesson_id = l.id
GROUP BY p.user_id, l.module_id
HAVING SUM(p.is_completed) = (
    SELECT COUNT(*) FROM lessons required_lessons
    WHERE required_lessons.module_id = l.module_id
);

CREATE VIEW course_progress AS
WITH current_totals AS (
    SELECT mc.user_id, m.course_id, SUM(m.coverage_percentage) AS progress_percentage
    FROM module_completions mc
    JOIN course_modules m ON m.id = mc.module_id
    GROUP BY mc.user_id, m.course_id
), progress_keys AS (
    SELECT user_id, course_id FROM current_totals
    UNION
    SELECT user_id, course_id FROM course_progress_state
)
SELECT k.user_id, k.course_id,
       GREATEST(COALESCE(s.max_progress_percentage, 0), COALESCE(t.progress_percentage, 0)) AS progress_percentage
FROM progress_keys k
LEFT JOIN current_totals t ON t.user_id = k.user_id AND t.course_id = k.course_id
LEFT JOIN course_progress_state s ON s.user_id = k.user_id AND s.course_id = k.course_id;

-- El backend debe persistir el máximo, nunca reemplazarlo por un valor inferior,
-- y no eliminar estados ni finalizaciones. Las vistas no escriben ese estado.
-- Incrementar video_revision al reemplazar video_key o duration_seconds, después
-- de guardar el progreso previo; los intervalos antiguos no describen el video nuevo.

-- REGLA ENTRE FILAS, pendiente de implementar en los casos de uso:
-- La configuración completa de módulos debe sumar exactamente 100.00 por curso.
-- Guardar el conjunto en una transacción bloqueando primero la fila del curso;
-- validar SUM(coverage_percentage) = 100.00 antes de confirmar la operación.
-- Publicar exige módulos, al menos una lección por módulo y suma de pesos 100.00.
-- Se permite agregar módulos y lecciones a cursos publicados: guardar todos los
-- cambios y redistribuir pesos en la misma transacción, validando antes del commit.
-- publication_status no certifica por sí mismo que estas reglas se hayan cumplido.
-- Un CHECK por fila no garantiza esta suma. El SQL por sí solo permite otros totales.
