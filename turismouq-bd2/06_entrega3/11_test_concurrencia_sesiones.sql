-- =====================================================================
-- 11_test_concurrencia_sesiones.sql
-- Protocolo de Prueba Interactiva de Concurrencia para Dos Sesiones
-- Habitación de prueba: 51
-- =====================================================================

PROMPT =====================================================================
PROMPT GUIA DE EJECUCION PARA DOS TERMINALES O SESIONES SQL*PLUS / SQLCL
PROMPT =====================================================================

-- =====================================================================
-- LIMPIEZA PREVIA OPCIONAL (ejecutar solo si la habitación 51 tiene
-- reservas activas en los rangos de diciembre 2026 usados en el test)
-- =====================================================================
/*
BEGIN
  DELETE FROM pago
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion = 51
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.fecha_checkin < DATE '2026-12-15' AND rh.fecha_checkout > DATE '2026-12-01')
           OR (rh.fecha_checkin < DATE '2026-12-25' AND rh.fecha_checkout > DATE '2026-12-10') )
   );

  DELETE FROM reserva_habitacion
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion = 51
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.fecha_checkin < DATE '2026-12-15' AND rh.fecha_checkout > DATE '2026-12-01')
           OR (rh.fecha_checkin < DATE '2026-12-25' AND rh.fecha_checkout > DATE '2026-12-10') )
   );

  DELETE FROM reserva
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion = 51
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.fecha_checkin < DATE '2026-12-15' AND rh.fecha_checkout > DATE '2026-12-01')
           OR (rh.fecha_checkin < DATE '2026-12-25' AND rh.fecha_checkout > DATE '2026-12-10') )
   );
  COMMIT;
END;
/

-- Verificar que la habitación 51 quedó libre en ambos rangos:
SELECT COUNT(*) AS reservas_activas_hab51
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id_reserva = rh.id_reserva
 WHERE rh.id_habitacion = 51
   AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
   AND ( (rh.fecha_checkin < DATE '2026-12-15' AND rh.fecha_checkout > DATE '2026-12-01')
      OR (rh.fecha_checkin < DATE '2026-12-25' AND rh.fecha_checkout > DATE '2026-12-10') );
-- Esperado: 0
*/


-- =====================================================================
-- EXPERIMENTO 1: CONCURRENCIA SIN FOR UPDATE (Lectura sucia de estado / Fallo tardío)
-- Habitación: 51
-- Sesión A: 2026-12-01 a 2026-12-10
-- Sesión B: 2026-12-05 a 2026-12-15   (se solapa con A)
-- =====================================================================

-- [SESION A]: Inicia intento de reserva para la Habitación 51 (Del 1 al 10 de Dic 2026)
/*
SET SERVEROUTPUT ON;
DECLARE v_id NUMBER; BEGIN
  sp_reservar_habitacion_concurrente(1, 51, DATE '2026-12-01', DATE '2026-12-10', 2, FALSE, v_id);
  DBMS_OUTPUT.PUT_LINE('ID Reserva A: ' || v_id);
END;
/
-- En este punto la Sesión A NO ha hecho COMMIT.
*/

-- [SESION B]: Ejecuta simultáneamente sobre la misma Habitación 51 (Del 5 al 15 de Dic 2026)
/*
SET SERVEROUTPUT ON;
DECLARE v_id NUMBER; BEGIN
  sp_reservar_habitacion_concurrente(2, 51, DATE '2026-12-05', DATE '2026-12-15', 2, FALSE, v_id);
  DBMS_OUTPUT.PUT_LINE('ID Reserva B: ' || v_id);
END;
/
-- En este punto la Sesión B NO ha hecho COMMIT.
*/

-- [SESION A] y [SESION B]: Ambas intentan confirmar
/*
-- En Sesión A:
COMMIT;

-- En Sesión B:
COMMIT;
*/


-- =====================================================================
-- EXPERIMENTO 2: CONCURRENCIA CON SELECT ... FOR UPDATE (Bloqueo Pesimista Ordenado)
-- Habitación: 51
-- Sesión A: 2026-12-10 a 2026-12-20
-- Sesión B: 2026-12-15 a 2026-12-25   (se solapa con A)
-- =====================================================================

-- [SESION A]: Bloquea la habitación e inicia la transacción
/*
SET SERVEROUTPUT ON;
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- SESION A INICIA TRANSACCION CON LOCK ---');
  sp_reservar_habitacion_concurrente(
    p_id_cliente     => 3,
    p_id_habitacion  => 51,
    p_fecha_checkin  => DATE '2026-12-10',
    p_fecha_checkout => DATE '2026-12-20',
    p_num_huespedes  => 2,
    p_usar_lock      => TRUE,
    p_id_reserva     => v_id
  );
  DBMS_OUTPUT.PUT_LINE('ID Reserva A: ' || v_id);
END;
/
-- Mensaje: [LOCK ADQUIRIDO] Fila de habitacion 51 bloqueada exitosamente.
-- [RESERVA REGISTRADA] ID <id>. Pendiente de COMMIT.
-- (LA SESION A SE QUEDA SIN COMMIT)
*/

-- [SESION B]: Intenta reservar la misma Habitación 51 con control pesimista
/*
SET SERVEROUTPUT ON;
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- SESION B INTENTA RESERVAR MISMA HABITACION ---');
  sp_reservar_habitacion_concurrente(
    p_id_cliente     => 4,
    p_id_habitacion  => 51,
    p_fecha_checkin  => DATE '2026-12-15',
    p_fecha_checkout => DATE '2026-12-25',
    p_num_huespedes  => 2,
    p_usar_lock      => TRUE,
    p_id_reserva     => v_id
  );
  DBMS_OUTPUT.PUT_LINE('ID Reserva B: ' || v_id);
END;
/
-- RESULTADO INMEDIATO EN SESION B:
-- La consola se queda DETENIDA / SUSPENDIDA esperando liberación del lock.
*/

-- [FINALIZACION DEL EXPERIMENTO]:
-- En Sesión A ejecutar:
-- COMMIT;
-- Al instante, la Sesión B despierta del lock, evalúa la disponibilidad real recién confirmada
-- y genera la excepción controlada de negocio:
-- ORA-20003: Error: Habitacion no disponible en el rango solicitado.