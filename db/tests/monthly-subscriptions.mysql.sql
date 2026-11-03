-- Ejecutar después de schema.sql, únicamente en una base aislada de pruebas.
-- No ejecuta cobros. Los datos de prueba se revierten al terminar.
DELIMITER $$
CREATE PROCEDURE test_monthly_subscriptions()
BEGIN
    DECLARE test_user_id BIGINT;
    DECLARE rejected BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    INSERT INTO users (public_id, role_id, username, password_hash)
    SELECT '91ec2603-77f2-4997-80e4-7ff527085205', id,
           CONCAT('test_', UUID()), 'fixture-not-used-for-authentication'
    FROM roles WHERE name = 'STUDENT';
    SET test_user_id = LAST_INSERT_ID();

    -- Fin de mes, recuperación del día original y conservación de hora UTC.
    INSERT INTO subscriptions (user_id, billing_anchor_at, billing_cycle, starts_at, ends_at, amount_paid, currency)
    VALUES
      (test_user_id, '2027-01-31 12:30:00', 0, '2027-01-31 12:30:00', '2027-02-28 12:30:00', 10, 'USD'),
      (test_user_id, '2027-01-31 12:30:00', 1, '2027-02-28 12:30:00', '2027-03-31 12:30:00', 10, 'USD'),
      (test_user_id, '2027-01-31 12:30:00', 2, '2027-03-31 12:30:00', '2027-04-30 12:30:00', 10, 'USD'),
      (test_user_id, '2028-01-31 12:30:00', 0, '2028-01-31 12:30:00', '2028-02-29 12:30:00', 10, 'USD'),
      (test_user_id, '2028-01-31 12:30:00', 1, '2028-02-29 12:30:00', '2028-03-31 12:30:00', 10, 'USD'),
      (test_user_id, '2029-11-15 12:30:00', 1, '2029-12-15 12:30:00', '2030-01-15 12:30:00', 10, 'USD');

    -- Sumar un mes al último fin perdería el día 31: debe rechazarse.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 3819 SET rejected = TRUE;
        INSERT INTO subscriptions (user_id, billing_anchor_at, billing_cycle, starts_at, ends_at, amount_paid, currency)
        VALUES (test_user_id, '2027-01-31 12:30:00', 3, '2027-04-30 12:30:00', '2027-05-30 12:30:00', 10, 'USD');
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Se aceptó una renovación que pierde el día original';
    END IF;

    ROLLBACK;
    SELECT 'Pruebas mensuales correctas' AS result;
END$$
DELIMITER ;
CALL test_monthly_subscriptions();
DROP PROCEDURE test_monthly_subscriptions;
