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
    CONSTRAINT chk_users_email CHECK (email IS NULL OR CHAR_LENGTH(TRIM(email)) > 0)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

CREATE TABLE courses (
    id BIGINT NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    estimated_duration_minutes INT NOT NULL,
    difficulty_level VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT chk_courses_title CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT chk_courses_description CHECK (CHAR_LENGTH(TRIM(description)) > 0),
    CONSTRAINT chk_courses_duration CHECK (estimated_duration_minutes > 0),
    CONSTRAINT chk_courses_difficulty CHECK (difficulty_level IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED'))
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
-- No fija aún precios ni periodicidad comercial (mensual, anual, etc.).
CREATE TABLE subscriptions (
    id BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    starts_at DATETIME(6) NOT NULL,
    ends_at DATETIME(6) NOT NULL,
    amount_paid DECIMAL(12,2) NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    CONSTRAINT uq_subscriptions_user_start UNIQUE (user_id, starts_at),
    INDEX idx_subscriptions_user_end (user_id, ends_at),
    CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT chk_subscriptions_period CHECK (ends_at > starts_at),
    CONSTRAINT chk_subscriptions_amount CHECK (amount_paid >= 0),
    CONSTRAINT chk_subscriptions_currency CHECK (REGEXP_LIKE(currency, '^[A-Z]{3}$', 'c'))
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- El progreso se deriva sumando coverage_percentage de los módulos completados.
-- No duplicar un porcentaje calculado en users ni en courses.
-- La aplicación debe verificar acceso al curso antes de registrar finalizaciones.
CREATE TABLE module_completions (
    user_id BIGINT NOT NULL,
    module_id BIGINT NOT NULL,
    completed_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, module_id),
    INDEX idx_module_completions_module (module_id),
    CONSTRAINT fk_module_completions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_module_completions_module FOREIGN KEY (module_id) REFERENCES course_modules (id) ON DELETE RESTRICT
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_as_ci;

-- REGLA ENTRE FILAS, pendiente de implementar en los casos de uso:
-- La configuración completa de módulos debe sumar exactamente 100.00 por curso.
-- Guardar el conjunto en una transacción bloqueando primero la fila del curso;
-- validar SUM(coverage_percentage) = 100.00 antes de confirmar la operación.
-- Un CHECK por fila no garantiza esta suma. El SQL por sí solo permite otros totales.
