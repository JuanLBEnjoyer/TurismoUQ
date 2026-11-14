-- =====================================================================
-- 10_test_transacciones.sql
-- Script de prueba con evidencia de Rollback Parcial y Atomicidad
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 50

PROMPT =====================================================================
PROMPT PRE-CHECK DE VALIDACION DE CONDICIONES DE PRUEBA
PROMPT =====================================================================
DECLARE
  v_c1 NUMBER;
  v_c2 NUMBER;
  v_r15 NUMBER;
  v_r16 NUMBER;
BEGIN
  v_c1 := pkg_turismouq.fn_valor_estadia(15, DATE '2026-11-20', DATE '2026-11-23');
  v_c2 := pkg_turismouq.fn_valor_estadia(16, DATE '2026-11-25', DATE '2026-11-28');

  SELECT COUNT(*) INTO v_r15
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
   WHERE rh.id_habitacion = 15
     AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
     AND rh.fecha_checkin  < DATE '2026-11-23'
     AND rh.fecha_checkout > DATE '2026-11-20';

  SELECT COUNT(*) INTO v_r16
    FROM reserva_habitacion rh
    JOIN reserva r ON r.id_reserva = rh.id_reserva
   WHERE rh.id_habitacion = 16
     AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
     AND rh.fecha_checkin  < DATE '2026-11-28'
     AND rh.fecha_checkout > DATE '2026-11-25';

  IF v_c1 <= 0 OR v_c2 <= 0 OR v_r15 > 0 OR v_r16 > 0 THEN
    RAISE_APPLICATION_ERROR(-20101,
      'Pre-check fallo. c1=' || v_c1 || ' c2=' || v_c2 ||
      ' reservas_h15=' || v_r15 || ' reservas_h16=' || v_r16);
  END IF;
  DBMS_OUTPUT.PUT_LINE('Pre-check OK: c1=' || v_c1 || ' c2=' || v_c2);
END;
/

PROMPT =====================================================================
PROMPT CASO 1: TRANSACCION EXITOSA COMPLETA (RESERVA + PAGO)
PROMPT =====================================================================
DECLARE
  v_id_reserva   NUMBER;
  v_id_pago      NUMBER;
  v_estado_final VARCHAR2(20);
  v_costo        NUMBER;
BEGIN
  -- Calculamos el valor exacto para garantizar pago suficiente
  v_costo := pkg_turismouq.fn_valor_estadia(15, DATE '2026-11-20', DATE '2026-11-23');
  
  DBMS_OUTPUT.PUT_LINE('--- INICIANDO CASO 1 ---');
  DBMS_OUTPUT.PUT_LINE('Costo calculado de la estadia: $' || v_costo);

  pkg_turismouq.sp_reserva_con_pago_atomico (
    p_id_cliente     => 1,
    p_id_habitacion  => 15,
    p_fecha_checkin  => DATE '2026-11-20',
    p_fecha_checkout => DATE '2026-11-23',
    p_num_huespedes  => 2,
    p_monto_pago     => v_costo,
    p_metodo_pago    => 'TARJETA_CREDITO',
    p_id_reserva     => v_id_reserva,
    p_id_pago        => v_id_pago,
    p_estado_final   => v_estado_final
  );

  DBMS_OUTPUT.PUT_LINE('Resultado Caso 1:');
  DBMS_OUTPUT.PUT_LINE('  ID Reserva: ' || v_id_reserva);
  DBMS_OUTPUT.PUT_LINE('  ID Pago:    ' || v_id_pago);
  DBMS_OUTPUT.PUT_LINE('  Estado:     ' || v_estado_final);
END;
/

PROMPT Verificacion en Tablas Base Caso 1:
SELECT id_reserva, id_cliente, id_alojamiento, estado, fecha_checkin, fecha_checkout
  FROM reserva
 WHERE id_reserva = (SELECT MAX(id_reserva) FROM reserva);

SELECT id_pago, id_reserva, monto, metodo, estado
  FROM pago
 WHERE id_reserva = (SELECT MAX(id_reserva) FROM reserva);

PROMPT =====================================================================
PROMPT CASO 2: FALLO DE PAGO Y DEMOSTRACION DE ROLLBACK PARCIAL
PROMPT (La reserva se crea, el pago falla por monto insuficiente,
PROMPT se hace ROLLBACK TO sp_post_reserva: Reserva queda PENDIENTE y
PROMPT NO existe tupla huerfana en PAGO)
PROMPT =====================================================================
DECLARE
  v_id_reserva   NUMBER;
  v_id_pago      NUMBER;
  v_estado_final VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- INICIANDO CASO 2 (Monto $50 insuficiente para estadia) ---');

  pkg_turismouq.sp_reserva_con_pago_atomico (
    p_id_cliente     => 2,
    p_id_habitacion  => 16,
    p_fecha_checkin  => DATE '2026-11-25',
    p_fecha_checkout => DATE '2026-11-28',
    p_num_huespedes  => 2,
    p_monto_pago     => 50, -- Provoca rechazo por suficiencia
    p_metodo_pago    => 'PSE',
    p_id_reserva     => v_id_reserva,
    p_id_pago        => v_id_pago,
    p_estado_final   => v_estado_final
  );

  DBMS_OUTPUT.PUT_LINE('Resultado Caso 2:');
  DBMS_OUTPUT.PUT_LINE('  ID Reserva: ' || v_id_reserva);
  DBMS_OUTPUT.PUT_LINE('  ID Pago:    ' || NVL(TO_CHAR(v_id_pago), 'NULL (REVERSADO)'));
  DBMS_OUTPUT.PUT_LINE('  Estado:     ' || v_estado_final);
END;
/

PROMPT Verificacion en Tablas Base Caso 2 (Evidencia de Rollback Parcial):
SELECT id_reserva, id_cliente, id_alojamiento, estado, fecha_checkin, fecha_checkout
  FROM reserva
 WHERE id_reserva = (SELECT MAX(id_reserva) FROM reserva);

SELECT NVL(COUNT(*), 0) AS pagos_asociados
  FROM pago
 WHERE id_reserva = (SELECT MAX(id_reserva) FROM reserva);

PROMPT Verificacion del Log Transaccional Autonomo:
SELECT id_log, id_reserva, fecha_evento, resultado, mensaje_error
  FROM log_transaccion_reserva
 ORDER BY id_log DESC
 FETCH FIRST 2 ROWS ONLY;
