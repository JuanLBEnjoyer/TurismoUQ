-- =====================================================================
-- 14_ajustes_resena.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 3 - Soporte de Calidad: Restricción de Reseña por Cliente y Alojamiento
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- =====================================================================
-- PARTE A: ELIMINACIÓN DE DUPLICADOS PREVIOS (CLIENTE, ALOJAMIENTO)
-- Conserva el id_resena máximo de cada par (cliente, alojamiento)
-- =====================================================================
DECLARE
  v_del NUMBER := 0;
BEGIN
  DELETE FROM resena
   WHERE id_resena NOT IN (
     SELECT MAX(res.id_resena)
       FROM resena res
       JOIN reserva r ON r.id_reserva = res.id_reserva
      GROUP BY r.id_cliente, r.id_alojamiento
   )
     AND id_resena IN (
       SELECT res.id_resena
         FROM resena res
         JOIN reserva r ON r.id_reserva = res.id_reserva
        GROUP BY r.id_cliente, r.id_alojamiento
       HAVING COUNT(*) > 1
     );
  v_del := SQL%ROWCOUNT;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Resenas duplicadas eliminadas: ' || v_del);
END;
/

-- =====================================================================
-- PARTE B: TRIGGER COMPOUND ANTI-TABLA MUTANTE (ORA-04091)
-- Valida que la reserva esté COMPLETADA y que no exista reseña previa
-- =====================================================================
CREATE OR REPLACE TRIGGER trg_valida_resena_unica
FOR INSERT ON resena COMPOUND TRIGGER

  TYPE t_rows IS TABLE OF resena.id_reserva%TYPE INDEX BY PLS_INTEGER;
  v_rows t_rows;
  v_idx  PLS_INTEGER := 0;

  BEFORE EACH ROW IS
    v_estado reserva.estado%TYPE;
  BEGIN
    SELECT estado INTO v_estado FROM reserva WHERE id_reserva = :NEW.id_reserva;
    IF v_estado <> 'COMPLETADA' THEN
      RAISE_APPLICATION_ERROR(-20030,
        'Solo reservas COMPLETADAS admiten resena. Estado: ' || v_estado);
    END IF;
    v_idx := v_idx + 1;
    v_rows(v_idx) := :NEW.id_reserva;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20032,
        'La reserva ' || :NEW.id_reserva || ' no existe.');
  END BEFORE EACH ROW;

  AFTER STATEMENT IS
    v_cli reserva.id_cliente%TYPE;
    v_alo reserva.id_alojamiento%TYPE;
    v_cnt NUMBER;
  BEGIN
    FOR i IN 1 .. v_rows.COUNT LOOP
      SELECT id_cliente, id_alojamiento
        INTO v_cli, v_alo
        FROM reserva WHERE id_reserva = v_rows(i);

      SELECT COUNT(*) INTO v_cnt
        FROM resena res
        JOIN reserva r ON r.id_reserva = res.id_reserva
       WHERE r.id_cliente = v_cli
         AND r.id_alojamiento = v_alo
         AND res.id_reserva <> v_rows(i);

      IF v_cnt > 0 THEN
        RAISE_APPLICATION_ERROR(-20031,
          'Cliente ' || v_cli || ' ya resenio el alojamiento ' || v_alo);
      END IF;
    END LOOP;
  END AFTER STATEMENT;

END trg_valida_resena_unica;
/
