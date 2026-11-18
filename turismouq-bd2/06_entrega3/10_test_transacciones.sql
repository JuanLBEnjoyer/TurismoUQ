-- =====================================================================
-- 10_test_transacciones.sql
-- Script de prueba con evidencia de Rollback Parcial y Atomicidad
-- (Versión corregida: limpieza previa, verificación con IDs reales)
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 50

PROMPT =====================================================================
PROMPT LIMPIEZA PREVIA DE DATOS DE PRUEBA (HAB 15 Y 16)
PROMPT =====================================================================
BEGIN
  -- Eliminar pagos asociados a reservas de prueba en hab 15 y 16
  DELETE FROM pago
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion IN (15, 16)
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.id_habitacion = 15 AND rh.fecha_checkin < DATE '2026-11-23' AND rh.fecha_checkout > DATE '2026-11-20')
           OR (rh.id_habitacion = 16 AND rh.fecha_checkin < DATE '2026-11-28' AND rh.fecha_checkout > DATE '2026-11-25') )
   );

  -- Eliminar detalle de reserva_habitacion
  DELETE FROM reserva_habitacion
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion IN (15, 16)
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.id_habitacion = 15 AND rh.fecha_checkin < DATE '2026-11-23' AND rh.fecha_checkout > DATE '2026-11-20')
           OR (rh.id_habitacion = 16 AND rh.fecha_checkin < DATE '2026-11-28' AND rh.fecha_checkout > DATE '2026-11-25') )
   );

  -- Eliminar cabecera de reserva
  DELETE FROM reserva
   WHERE id_reserva IN (
     SELECT r.id_reserva
       FROM reserva r
       JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
      WHERE rh.id_habitacion IN (15, 16)
        AND r.estado IN ('CONFIRMADA','PENDIENTE','COMPLETADA')
        AND ( (rh.id_habitacion = 15 AND rh.fecha_checkin < DATE '2026-11-23' AND rh.fecha_checkout > DATE '2026-11-20')
           OR (rh.id_habitacion = 16 AND rh.fecha_checkin < DATE '2026-11-28' AND rh.fecha_checkout > DATE '2026-11-25') )
   );
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Limpieza de datos de prueba completada.');
END;
/

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
  v_estado       VARCHAR2(20);
  v_monto        NUMBER;
  v_metodo       VARCHAR2(20);
  v_pago_estado  VARCHAR2(20);
BEGIN
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

  -- Verificación en tablas base
  SELECT estado INTO v_estado FROM reserva WHERE id_reserva = v_id_reserva;
  DBMS_OUTPUT.PUT_LINE('  Verificacion RESERVA: estado=' || v_estado);

  SELECT monto, metodo, estado INTO v_monto, v_metodo, v_pago_estado
    FROM pago WHERE id_pago = v_id_pago;
  DBMS_OUTPUT.PUT_LINE('  Verificacion PAGO: monto=' || v_monto || ', metodo=' || v_metodo || ', estado=' || v_pago_estado);
END;
/

PROMPT =====================================================================
PROMPT CASO 2: FALLO DE PAGO Y DEMOSTRACION DE ROLLBACK PARCIAL
PROMPT =====================================================================
DECLARE
  v_id_reserva   NUMBER;
  v_id_pago      NUMBER;
  v_estado_final VARCHAR2(20);
  v_estado       VARCHAR2(20);
  v_pagos        NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('--- INICIANDO CASO 2 (Monto $50 insuficiente para estadia) ---');

  pkg_turismouq.sp_reserva_con_pago_atomico (
    p_id_cliente     => 2,
    p_id_habitacion  => 16,
    p_fecha_checkin  => DATE '2026-11-25',
    p_fecha_checkout => DATE '2026-11-28',
    p_num_huespedes  => 2,
    p_monto_pago     => 50,
    p_metodo_pago    => 'PSE',
    p_id_reserva     => v_id_reserva,
    p_id_pago        => v_id_pago,
    p_estado_final   => v_estado_final
  );

  DBMS_OUTPUT.PUT_LINE('Resultado Caso 2:');
  DBMS_OUTPUT.PUT_LINE('  ID Reserva: ' || v_id_reserva);
  DBMS_OUTPUT.PUT_LINE('  ID Pago:    ' || NVL(TO_CHAR(v_id_pago), 'NULL (REVERSADO)'));
  DBMS_OUTPUT.PUT_LINE('  Estado:     ' || v_estado_final);

  -- Verificación en tablas base
  SELECT estado INTO v_estado FROM reserva WHERE id_reserva = v_id_reserva;
  DBMS_OUTPUT.PUT_LINE('  Verificacion RESERVA: estado=' || v_estado);

  SELECT COUNT(*) INTO v_pagos FROM pago WHERE id_reserva = v_id_reserva;
  DBMS_OUTPUT.PUT_LINE('  Verificacion PAGO: pagos_asociados=' || v_pagos);
END;
/

PROMPT =====================================================================
PROMPT VERIFICACION FINAL DEL LOG TRANSACCIONAL AUTONOMO
PROMPT =====================================================================
SELECT id_log, id_reserva, fecha_evento, resultado, mensaje_error
  FROM log_transaccion_reserva
 ORDER BY id_log DESC
 FETCH FIRST 2 ROWS ONLY;