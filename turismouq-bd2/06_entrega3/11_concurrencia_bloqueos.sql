-- =====================================================================
-- 11_concurrencia_bloqueos.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 3 - Subpunto 2.2: Concurrencia y Control de Bloqueos (15%)
-- =====================================================================
-- DECISIÓN ARQUITECTURAL:
-- 1. En Oracle (nivel READ COMMITTED por defecto), dos transacciones concurrentes
--    pueden consultar simultáneamente la disponibilidad de una habitación.
--    Ambas ven la habitación libre (lectura no bloqueante), y ambas intentan
--    insertar en RESERVA_HABITACION.
-- 2. CASO SIN CONTROL PESIMISTA (Sin FOR UPDATE):
--    El trigger compuesto detecta la colisión solo en AFTER STATEMENT,
--    provocando aborto tardío de transacción y excepciones ORA-20003 no gestionadas.
-- 3. CASO CON CONTROL PESIMISTA (Con SELECT ... FOR UPDATE):
--    Se implementa el procedimiento SP_BLOQUEAR_HABITACION que ejecuta
--    SELECT id_habitacion FROM habitacion WHERE id_habitacion = p_id FOR UPDATE;
--    Esto adquiere un bloqueo exclusivo a nivel de fila (Row Exclusive Lock / TX en Modo 6).
--    La Sesión B se encola en espera determinista hasta que la Sesión A confirme o aborte.
-- 4. Se proporcionan vistas/consultas de monitoreo sobre V$LOCK, V$SESSION y DBA_WAITERS.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- 1. PROCEDIMIENTO CON CONTROL PESIMISTA EXPLÍCITO (SELECT ... FOR UPDATE)
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_reservar_habitacion_concurrente (
    p_id_cliente      IN  NUMBER,
    p_id_habitacion   IN  NUMBER,
    p_fecha_checkin   IN  DATE,
    p_fecha_checkout  IN  DATE,
    p_num_huespedes   IN  NUMBER,
    p_usar_lock       IN  BOOLEAN,
    p_id_reserva      OUT NUMBER
) IS
    v_dummy          NUMBER;
    v_id_alojamiento habitacion.id_alojamiento%TYPE;
    v_solapes        NUMBER := 0;
BEGIN
    -- PASO A: Bloqueo Pesimista opcional según el parámetro del experimento
    IF p_usar_lock THEN
        -- Adquiere Row-X lock sobre el recurso físico 'habitacion'.
        -- Si otra sesión ya lo tiene bloqueado, esta sentencia ESPERA automáticamente.
        SELECT id_habitacion, id_alojamiento
          INTO v_dummy, v_id_alojamiento
          FROM habitacion
         WHERE id_habitacion = p_id_habitacion
           FOR UPDATE;
        
        DBMS_OUTPUT.PUT_LINE('[LOCK ADQUIRIDO] Fila de habitacion ' || p_id_habitacion || ' bloqueada exitosamente.');
    ELSE
        SELECT id_alojamiento
          INTO v_id_alojamiento
          FROM habitacion
         WHERE id_habitacion = p_id_habitacion;
         
        DBMS_OUTPUT.PUT_LINE('[SIN LOCK] Lectura consistente simple realizada.');
    END IF;

    -- PASO B: Verificación de solapamiento
    SELECT COUNT(*)
      INTO v_solapes
      FROM reserva_habitacion rh
      JOIN reserva r ON r.id_reserva = rh.id_reserva
     WHERE rh.id_habitacion = p_id_habitacion
       AND r.estado IN ('CONFIRMADA', 'PENDIENTE', 'COMPLETADA')
       AND rh.fecha_checkin  < p_fecha_checkout
       AND rh.fecha_checkout > p_fecha_checkin;

    IF v_solapes > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Error: Habitacion no disponible en el rango solicitado.');
    END IF;

    -- PASO C: Creación de la reserva
    INSERT INTO reserva (
        id_cliente,
        id_alojamiento,
        fecha_creacion,
        fecha_checkin,
        fecha_checkout,
        estado
    ) VALUES (
        p_id_cliente,
        v_id_alojamiento,
        SYSDATE,
        p_fecha_checkin,
        p_fecha_checkout,
        'PENDIENTE'
    ) RETURNING id_reserva INTO p_id_reserva;

    INSERT INTO reserva_habitacion (
        id_reserva,
        id_habitacion,
        fecha_checkin,
        fecha_checkout,
        num_huespedes
    ) VALUES (
        p_id_reserva,
        p_id_habitacion,
        p_fecha_checkin,
        p_fecha_checkout,
        p_num_huespedes
    );

    DBMS_OUTPUT.PUT_LINE('[RESERVA REGISTRADA] ID ' || p_id_reserva || '. Pendiente de COMMIT en la sesion.');
    -- NOTA: Se omite COMMIT intencionalmente para permitir la demostración interactiva
END sp_reservar_habitacion_concurrente;
/

-- ---------------------------------------------------------------------
-- 2. VISTA DE MONITOREO DE SESIONES Y BLOQUEOS EN TIEMPO REAL
-- (Requiere privilegios de SELECT sobre V$LOCK, V$SESSION o rol DBA)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_monitoreo_bloqueos AS
SELECT 
    b.sid                AS sid_bloqueador,
    b.serial#            AS serial_bloqueador,
    b.username           AS usuario_bloqueador,
    w.sid                AS sid_esperando,
    w.serial#            AS serial_esperando,
    w.username           AS usuario_esperando,
    w.blocking_session   AS id_sesion_causante,
    w.seconds_in_wait    AS segundos_bloqueado,
    w.wait_class         AS clase_espera,
    w.event              AS evento_espera
FROM v$session w
JOIN v$session b ON b.sid = w.blocking_session
WHERE w.blocking_session IS NOT NULL;
