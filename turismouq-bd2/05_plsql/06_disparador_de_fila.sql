CREATE OR REPLACE TRIGGER trg_no_solape_habitacion
FOR INSERT OR UPDATE OF id_habitacion, fecha_checkin, fecha_checkout ON reserva_habitacion
COMPOUND TRIGGER

    -- Colección en memoria para registrar las filas procesadas en la sentencia
    TYPE r_linea IS RECORD (
        id_reserva     reserva_habitacion.id_reserva%TYPE,
        id_habitacion  reserva_habitacion.id_habitacion%TYPE,
        fecha_checkin  reserva_habitacion.fecha_checkin%TYPE,
        fecha_checkout reserva_habitacion.fecha_checkout%TYPE
    );
    TYPE t_lineas IS TABLE OF r_linea INDEX BY PLS_INTEGER;
    v_lineas t_lineas;

    -- =================================================================
    -- FASE 1: A NIVEL DE FILA
    -- Captura los valores de cada tupla ingresada o modificada.
    -- =================================================================
    BEFORE EACH ROW IS
    BEGIN
        v_lineas(v_lineas.COUNT + 1).id_reserva     := :NEW.id_reserva;
        v_lineas(v_lineas.COUNT).id_habitacion      := :NEW.id_habitacion;
        v_lineas(v_lineas.COUNT).fecha_checkin      := :NEW.fecha_checkin;
        v_lineas(v_lineas.COUNT).fecha_checkout     := :NEW.fecha_checkout;
    END BEFORE EACH ROW;

    -- =================================================================
    -- FASE 2: VALIDACIÓN DE DISPONIBILIDAD 
    -- Se ejecuta tras procesar las filas, evitando el error de tabla mutante (ORA-04091).
    -- =================================================================
    AFTER STATEMENT IS
        v_solapes NUMBER;
        v_estado  reserva.estado%TYPE;
    BEGIN
        FOR i IN 1 .. v_lineas.COUNT LOOP
            -- Se verifica el estado de la reserva padre
            BEGIN
                SELECT estado
                  INTO v_estado
                  FROM reserva
                 WHERE id_reserva = v_lineas(i).id_reserva;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_estado := 'PENDIENTE';
            END;

            -- Solo las reservas activas (no canceladas) comprometen disponibilidad
            IF v_estado <> 'CANCELADA' THEN
                SELECT COUNT(*)
                  INTO v_solapes
                  FROM reserva_habitacion rh
                  JOIN reserva r ON r.id_reserva = rh.id_reserva
                 WHERE rh.id_habitacion = v_lineas(i).id_habitacion
                   AND rh.id_reserva   <> v_lineas(i).id_reserva
                   AND r.estado        IN ('CONFIRMADA', 'PENDIENTE', 'COMPLETADA')
                   AND rh.fecha_checkin  < v_lineas(i).fecha_checkout
                   AND rh.fecha_checkout > v_lineas(i).fecha_checkin;

                IF v_solapes > 0 THEN
                    RAISE_APPLICATION_ERROR(-20003,
                        'Error: Solapamiento detectado por el disparador. La habitación ' ||
                        v_lineas(i).id_habitacion || ' ya se encuentra ocupada entre el ' ||
                        TO_CHAR(v_lineas(i).fecha_checkin, 'YYYY-MM-DD') || ' y el ' ||
                        TO_CHAR(v_lineas(i).fecha_checkout, 'YYYY-MM-DD') || '.');
                END IF;
            END IF;
        END LOOP;
    END AFTER STATEMENT;

END trg_no_solape_habitacion;
/

-- Pruebas

SET SERVEROUTPUT ON;

-- 1. Crear una reserva base limpia para la prueba (Habitación 30, del 1 al 5 de Diciembre de 2026)
INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin, fecha_checkout, estado)
VALUES (1, 1, SYSDATE, DATE '2026-12-01', DATE '2026-12-05', 'CONFIRMADA');

INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, num_huespedes)
VALUES ((SELECT MAX(id_reserva) FROM reserva), 30, DATE '2026-12-01', DATE '2026-12-05', 2);

COMMIT;
DBMS_OUTPUT.PUT_LINE('Paso 1: Reserva base registrada exitosamente.');

-- 2. CASO DE PRUEBA: Intento de solapamiento directo (debe saltar el Trigger ORA-20003)
-- Se crea una nueva reserva que intenta tomar la misma Habitación 30 del 3 al 7 de Diciembre (se cruza el 3 y 4)
INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin, fecha_checkout, estado)
VALUES (2, 1, SYSDATE, DATE '2026-12-03', DATE '2026-12-07', 'PENDIENTE');

-- Esta sentencia dispara el trigger trg_no_solape_habitacion y falla
INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, num_huespedes)
VALUES ((SELECT MAX(id_reserva) FROM reserva), 30, DATE '2026-12-03', DATE '2026-12-07', 2);

-- Salida esperada en consola:
-- ORA-20003: Error: Solapamiento detectado por el disparador. La habitación 30 ya se encuentra ocupada entre el 2026-12-03 y el 2026-12-07.

-- 3. CASO EXITOSO: Mismo cuarto en fechas posteriores no conflictivas (del 10 al 15 de Diciembre de 2026)
INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin, fecha_checkout, estado)
VALUES (3, 1, SYSDATE, DATE '2026-12-10', DATE '2026-12-15', 'CONFIRMADA');

INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin, fecha_checkout, num_huespedes)
VALUES ((SELECT MAX(id_reserva) FROM reserva), 30, DATE '2026-12-10', DATE '2026-12-15', 2);

COMMIT;
dbms_output.put_line('Paso 3: Reserva consecutiva registrada sin conflictos.');