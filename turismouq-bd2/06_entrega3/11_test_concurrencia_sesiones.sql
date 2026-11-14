-- =====================================================================
-- 11_test_concurrencia_sesiones.sql
-- Protocolo de Prueba Interactiva de Concurrencia para Dos Sesiones
-- =====================================================================

PROMPT =====================================================================
PROMPT GUIA DE EJECUCION PARA DOS TERMINALES O SESIONES SQL*PLUS / SQLCL
PROMPT =====================================================================

-- =====================================================================
-- EXPERIMENTO 1: CONCURRENCIA SIN FOR UPDATE (Lectura sucia de estado / Fallo tardío)
-- =====================================================================

-- [SESION 1]: Inicia intento de reserva para la Habitación 40 (Del 1 al 10 de Dic 2026)
/*
SET SERVEROUTPUT ON;
DECLARE v_id NUMBER; BEGIN
  sp_reservar_habitacion_concurrente(1, 40, DATE '2026-12-01', DATE '2026-12-10', 2, FALSE, v_id);
END;
/
-- En este punto la Sesión 1 NO ha hecho COMMIT.
*/

-- [SESION 2]: Ejecuta simultáneamente sobre la misma Habitación 40 (Del 5 al 15 de Dic 2026)
/*
SET SERVEROUTPUT ON;
DECLARE v_id NUMBER; BEGIN
  sp_reservar_habitacion_concurrente(2, 40, DATE '2026-12-05', DATE '2026-12-15', 2, FALSE, v_id);
END;
/
-- RESULTADO EXPERIMENTO 1:
-- Al no haber bloqueo preventivo de fila en habitacion, Sesión 2 lee reserva_habitacion
-- y no ve la reserva de Sesión 1 (porque READ COMMITTED no ve uncommitted data).
-- Al intentar insertar, el disparador trg_no_solape_habitacion o el motor aborta tardíamente
-- provocando ORA-20003 en Sesión 2 cuando Sesión 1 hace COMMIT.
*/


-- =====================================================================
-- EXPERIMENTO 2: CONCURRENCIA CON SELECT ... FOR UPDATE (Bloqueo Pesimista Ordenado)
-- =====================================================================

-- [SESION 1]: Bloquea la habitación e inicia la transacción
/*
SET SERVEROUTPUT ON;
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- SESION 1 INICIA TRANSACCION CON LOCK ---');
  sp_reservar_habitacion_concurrente(
    p_id_cliente     => 1,
    p_id_habitacion  => 50,
    p_fecha_checkin  => DATE '2026-12-10',
    p_fecha_checkout => DATE '2026-12-20',
    p_num_huespedes  => 2,
    p_usar_lock      => TRUE,
    p_id_reserva     => v_id
  );
END;
/
-- Mensaje: [LOCK ADQUIRIDO] Fila de habitacion 50 bloqueada exitosamente.
-- [RESERVA REGISTRADA] ID 25005. Pendiente de COMMIT.
-- (LA SESION 1 SE QUEDA SIN COMMIT)
*/

-- [SESION 2]: Intenta reservar la misma Habitación 50 con control pesimista
/*
SET SERVEROUTPUT ON;
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- SESION 2 INTENTA RESERVAR MISMA HABITACION ---');
  sp_reservar_habitacion_concurrente(
    p_id_cliente     => 2,
    p_id_habitacion  => 50,
    p_fecha_checkin  => DATE '2026-12-15',
    p_fecha_checkout => DATE '2026-12-25',
    p_num_huespedes  => 2,
    p_usar_lock      => TRUE,
    p_id_reserva     => v_id
  );
END;
/
-- RESULTADO INMEDIATO EN SESION 2:
-- La consola se queda DETENIDA / SUSPENDIDA esperando liberación del lock.
*/

-- [SESION 3 o DBA]: Monitoreo de Bloqueo en Tiempo Real
/*
SELECT sid_bloqueador, usuario_bloqueador, sid_esperando, usuario_esperando, segundos_bloqueado, evento_espera
  FROM v_monitoreo_bloqueos;

-- Consulta complementaria sobre V$LOCK para ver los modos:
SELECT sid, type, id1, id2, lmode, request,
       CASE lmode
         WHEN 0 THEN 'None'
         WHEN 2 THEN 'Row-S (SS)'
         WHEN 3 THEN 'Row-X (SX)'
         WHEN 4 THEN 'Share (S)'
         WHEN 5 THEN 'S/Row-X (SSX)'
         WHEN 6 THEN 'Exclusive (X)'
       END AS modo_adquirido,
       CASE request
         WHEN 6 THEN 'Exclusive (X) Solicitado'
         ELSE TO_CHAR(request)
       END AS peticion_espera
  FROM v$lock
 WHERE type IN ('TX', 'TM')
 ORDER BY sid;
*/

-- [FINALIZACION DEL EXPERIMENTO]:
-- En Sesión 1 ejecutar:
-- COMMIT;
-- Al instante, la Sesión 2 despierta del lock, evalúa la disponibilidad real recién confirmada
-- y genera la excepción controlada de negocio:
-- ORA-20003: Error: Habitacion no disponible en el rango solicitado.
