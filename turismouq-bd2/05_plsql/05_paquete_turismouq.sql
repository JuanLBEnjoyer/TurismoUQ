-- =====================================================================
-- ESPECIFICACIÓN DEL PAQUETE
-- Expone la interfaz pública de los subprogramas centrales de la plataforma.
-- =====================================================================
CREATE OR REPLACE PACKAGE pkg_turismouq IS

    -- Constantes públicas de negocio
    c_pct_comision CONSTANT NUMBER(4,2) := 0.10;

    -- 1. Función para calcular el valor total de una estadía cruzando temporadas
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER;

    -- 2. Procedimiento para validar y registrar una reserva con excepciones controladas
    PROCEDURE sp_crear_reserva (
        p_id_cliente      IN  NUMBER,
        p_id_habitacion   IN  NUMBER,
        p_fecha_checkin   IN  DATE,
        p_fecha_checkout  IN  DATE,
        p_num_huespedes   IN  NUMBER,
        p_id_reserva      OUT NUMBER
    );

    -- 3. Procedimiento de proceso masivo: liquidación mensual con cursor parametrizado
    PROCEDURE sp_liquidar_mensual (
        p_anio           IN NUMBER,
        p_mes            IN NUMBER,
        p_id_alojamiento IN NUMBER DEFAULT NULL
    );

END pkg_turismouq;
/

-- =====================================================================
-- CUERPO DEL PAQUETE (PACKAGE BODY)
-- Implementa la lógica operativa de los subprogramas declarados.
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY pkg_turismouq IS

    -- =================================================================
    -- 1. fn_valor_estadia
    -- =================================================================
    FUNCTION fn_valor_estadia (
        p_id_habitacion IN NUMBER,
        p_fecha_in      IN DATE,
        p_fecha_out     IN DATE
    ) RETURN NUMBER IS
        v_total NUMBER := 0;
    BEGIN
        IF p_fecha_out <= p_fecha_in THEN
            RETURN 0;
        END IF;

        SELECT NVL(SUM(
                   (LEAST(p_fecha_out, t.fecha_fin + 1) - GREATEST(p_fecha_in, t.fecha_inicio)) * tf.valor_noche
               ), 0)
          INTO v_total
          FROM temporada t
          JOIN tarifa tf ON tf.id_temporada = t.id_temporada
         WHERE tf.id_habitacion = p_id_habitacion
           AND t.fecha_inicio < p_fecha_out
           AND t.fecha_fin >= p_fecha_in;

        RETURN v_total;
    END fn_valor_estadia;

    -- =================================================================
    -- 2. sp_crear_reserva
    -- =================================================================
    PROCEDURE sp_crear_reserva (
        p_id_cliente      IN  NUMBER,
        p_id_habitacion   IN  NUMBER,
        p_fecha_checkin   IN  DATE,
        p_fecha_checkout  IN  DATE,
        p_num_huespedes   IN  NUMBER,
        p_id_reserva      OUT NUMBER
    ) IS
        v_id_alojamiento  habitacion.id_alojamiento%TYPE;
        v_capacidad_max   habitacion.capacidad_max%TYPE;
        v_solapamientos   NUMBER := 0;
    BEGIN
        -- Validación 1: Fechas invertidas o iguales
        IF p_fecha_checkout <= p_fecha_checkin THEN
            RAISE_APPLICATION_ERROR(-20001, 'Error: La fecha de check-out (' || 
                TO_CHAR(p_fecha_checkout, 'YYYY-MM-DD') || 
                ') debe ser estrictamente posterior al check-in (' || 
                TO_CHAR(p_fecha_checkin, 'YYYY-MM-DD') || ').');
        END IF;

        -- Validación 2: Existencia y capacidad de habitación
        BEGIN
            SELECT id_alojamiento, capacidad_max
              INTO v_id_alojamiento, v_capacidad_max
              FROM habitacion
             WHERE id_habitacion = p_id_habitacion;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20004, 'Error: La habitacion con ID ' || p_id_habitacion || ' no existe.');
        END;

        IF p_num_huespedes > v_capacidad_max THEN
            RAISE_APPLICATION_ERROR(-20002, 'Error: Capacidad excedida. La habitacion soporta maximo ' || 
                v_capacidad_max || ' huespedes y se solicitaron ' || p_num_huespedes || '.');
        END IF;

        -- Validación 3: Solapamiento de fechas con reservas activas
        SELECT COUNT(*)
          INTO v_solapamientos
          FROM reserva_habitacion rh
          JOIN reserva r ON r.id_reserva = rh.id_reserva
         WHERE rh.id_habitacion = p_id_habitacion
           AND r.estado IN ('CONFIRMADA', 'PENDIENTE', 'COMPLETADA')
           AND rh.fecha_checkin  < p_fecha_checkout
           AND rh.fecha_checkout > p_fecha_checkin;

        IF v_solapamientos > 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Error: Habitacion no disponible. Ya existe una reserva activa en ese rango de fechas.');
        END IF;

        -- Inserción de cabecera y detalle
        INSERT INTO reserva (
            id_cliente,
            id_alojamiento,
            fecha_creacion,
            fecha_checkin,
            fecha_checkout,
            estado,
            fecha_cancelacion
        ) VALUES (
            p_id_cliente,
            v_id_alojamiento,
            SYSDATE,
            p_fecha_checkin,
            p_fecha_checkout,
            'PENDIENTE',
            NULL
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

        COMMIT;
    END sp_crear_reserva;

    -- =================================================================
    -- 3. sp_liquidar_mensual
    -- =================================================================
    PROCEDURE sp_liquidar_mensual (
        p_anio           IN NUMBER,
        p_mes            IN NUMBER,
        p_id_alojamiento IN NUMBER DEFAULT NULL
    ) IS
        v_fecha_ini DATE;
        v_fecha_fin DATE;

        v_gran_total_reservas   NUMBER := 0;
        v_gran_total_noches     NUMBER := 0;
        v_gran_total_hospedaje  NUMBER := 0;
        v_gran_total_servicios  NUMBER := 0;
        v_gran_total_bruto      NUMBER := 0;
        v_gran_total_comision   NUMBER := 0;
        v_gran_total_neto       NUMBER := 0;

        v_comision NUMBER(14,2);
        v_neto     NUMBER(14,2);

        CURSOR c_liquidacion (
            cp_fecha_ini      DATE,
            cp_fecha_fin      DATE,
            cp_id_alojamiento NUMBER
        ) IS
            WITH res_completadas AS (
                SELECT r.id_reserva,
                       r.id_alojamiento
                  FROM reserva r
                 WHERE r.estado = 'COMPLETADA'
                   AND r.fecha_checkout >= cp_fecha_ini
                   AND r.fecha_checkout <  cp_fecha_fin + 1
                   AND (cp_id_alojamiento IS NULL OR r.id_alojamiento = cp_id_alojamiento)
            ),
            hospedaje_res AS (
                SELECT rc.id_alojamiento,
                       rc.id_reserva,
                       SUM(rh.fecha_checkout - rh.fecha_checkin) AS noches,
                       SUM(fn_valor_estadia(rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout)) AS valor_hospedaje
                  FROM res_completadas rc
                  JOIN reserva_habitacion rh ON rh.id_reserva = rc.id_reserva
                 GROUP BY rc.id_alojamiento, rc.id_reserva
            ),
            servicios_res AS (
                SELECT rc.id_reserva,
                       SUM(rs.cantidad * rs.precio_unitario) AS valor_servicios
                  FROM res_completadas rc
                  JOIN reserva_servicio rs ON rs.id_reserva = rc.id_reserva
                 GROUP BY rc.id_reserva
            )
            SELECT a.id_alojamiento,
                   a.nombre_comercial,
                   m.nombre AS municipio,
                   ta.nombre AS tipo_alojamiento,
                   COUNT(DISTINCT hr.id_reserva) AS total_reservas,
                   NVL(SUM(hr.noches), 0) AS total_noches,
                   NVL(SUM(hr.valor_hospedaje), 0) AS total_hospedaje,
                   NVL(SUM(sr.valor_servicios), 0) AS total_servicios,
                   NVL(SUM(hr.valor_hospedaje), 0) + NVL(SUM(sr.valor_servicios), 0) AS total_bruto
              FROM alojamiento a
              JOIN municipio m ON m.id_municipio = a.id_municipio
              JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
              JOIN hospedaje_res hr ON hr.id_alojamiento = a.id_alojamiento
              LEFT JOIN servicios_res sr ON sr.id_reserva = hr.id_reserva
             GROUP BY a.id_alojamiento, a.nombre_comercial, m.nombre, ta.nombre
             ORDER BY total_bruto DESC;

        v_reg c_liquidacion%ROWTYPE;

    BEGIN
        IF p_mes NOT BETWEEN 1 AND 12 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Error: El mes debe estar comprendido entre 1 y 12.');
        END IF;

        IF p_anio < 2024 OR p_anio > 2026 THEN
            RAISE_APPLICATION_ERROR(-20006, 'Error: El anio debe estar en el rango operativo del proyecto (2024-2026).');
        END IF;

        v_fecha_ini := TO_DATE(p_anio || '-' || LPAD(p_mes, 2, '0') || '-01', 'YYYY-MM-DD');
        v_fecha_fin := LAST_DAY(v_fecha_ini);

        DBMS_OUTPUT.PUT_LINE('================================================================================================================================');
        DBMS_OUTPUT.PUT_LINE(' TURISMOUQ - LIQUIDACION MENSUAL DE ALOJAMIENTOS | PERIODO: ' || TO_CHAR(v_fecha_ini, 'YYYY-MM'));
        DBMS_OUTPUT.PUT_LINE('================================================================================================================================');
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ID', 5) ||
            RPAD('ALOJAMIENTO', 32) ||
            RPAD('MUNICIPIO', 16) ||
            LPAD('RES', 6) ||
            LPAD('NOCHES', 8) ||
            LPAD('HOSPEDAJE', 18) ||
            LPAD('SERVICIOS', 15) ||
            LPAD('TOTAL BRUTO', 18) ||
            LPAD('COMISION(10%)', 16) ||
            LPAD('NETO ALOJ.', 18)
        );
        DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------------------------------------------------------');

        OPEN c_liquidacion(v_fecha_ini, v_fecha_fin, p_id_alojamiento);
        LOOP
            FETCH c_liquidacion INTO v_reg;
            EXIT WHEN c_liquidacion%NOTFOUND;

            v_comision := ROUND(v_reg.total_bruto * c_pct_comision, 2);
            v_neto     := v_reg.total_bruto - v_comision;

            v_gran_total_reservas  := v_gran_total_reservas  + v_reg.total_reservas;
            v_gran_total_noches    := v_gran_total_noches    + v_reg.total_noches;
            v_gran_total_hospedaje := v_gran_total_hospedaje + v_reg.total_hospedaje;
            v_gran_total_servicios := v_gran_total_servicios + v_reg.total_servicios;
            v_gran_total_bruto     := v_gran_total_bruto     + v_reg.total_bruto;
            v_gran_total_comision  := v_gran_total_comision  + v_comision;
            v_gran_total_neto      := v_gran_total_neto      + v_neto;

            DBMS_OUTPUT.PUT_LINE(
                RPAD(TO_CHAR(v_reg.id_alojamiento), 5) ||
                RPAD(SUBSTR(v_reg.nombre_comercial, 1, 30), 32) ||
                RPAD(SUBSTR(v_reg.municipio, 1, 14), 16) ||
                LPAD(TO_CHAR(v_reg.total_reservas), 6) ||
                LPAD(TO_CHAR(v_reg.total_noches), 8) ||
                LPAD(TO_CHAR(v_reg.total_hospedaje, '999,999,999'), 18) ||
                LPAD(TO_CHAR(v_reg.total_servicios, '999,999,999'), 15) ||
                LPAD(TO_CHAR(v_reg.total_bruto,     '999,999,999'), 18) ||
                LPAD(TO_CHAR(v_comision,            '999,999,999'), 16) ||
                LPAD(TO_CHAR(v_neto,                '999,999,999'), 18)
            );
        END LOOP;

        IF c_liquidacion%ROWCOUNT = 0 THEN
            DBMS_OUTPUT.PUT_LINE('No se registraron reservas completadas para liquidar en el periodo indicado.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------------------------------------------------------------------');
            DBMS_OUTPUT.PUT_LINE(
                RPAD('TOTALES (' || c_liquidacion%ROWCOUNT || ' ALOJAMIENTOS)', 53) ||
                LPAD(TO_CHAR(v_gran_total_reservas), 6) ||
                LPAD(TO_CHAR(v_gran_total_noches), 8) ||
                LPAD(TO_CHAR(v_gran_total_hospedaje, '999,999,999'), 18) ||
                LPAD(TO_CHAR(v_gran_total_servicios, '999,999,999'), 15) ||
                LPAD(TO_CHAR(v_gran_total_bruto,     '999,999,999'), 18) ||
                LPAD(TO_CHAR(v_gran_total_comision,  '999,999,999'), 16) ||
                LPAD(TO_CHAR(v_gran_total_neto,      '999,999,999'), 18)
            );
            DBMS_OUTPUT.PUT_LINE('================================================================================================================================');
        END IF;

        CLOSE c_liquidacion;

    END sp_liquidar_mensual;

END pkg_turismouq;
/



-- Pruebas

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 250;

DECLARE
    v_valor_calculado NUMBER;
    v_id_reserva_nueva NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('>>> 1. PRUEBA DE FUNCION EN PAQUETE: fn_valor_estadia <<<');
    v_valor_calculado := pkg_turismouq.fn_valor_estadia(
        p_id_habitacion => 10,
        p_fecha_in      => DATE '2025-12-10',
        p_fecha_out     => DATE '2025-12-15'
    );
    DBMS_OUTPUT.PUT_LINE('Valor calculado: $' || TO_CHAR(v_valor_calculado, '999,999,999'));

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '>>> 2. PRUEBA DE PROCEDIMIENTO EN PAQUETE: sp_crear_reserva <<<');
    pkg_turismouq.sp_crear_reserva(
        p_id_cliente     => 2,
        p_id_habitacion  => 20,
        p_fecha_checkin  => DATE '2026-11-20',
        p_fecha_checkout => DATE '2026-11-25',
        p_num_huespedes  => 2,
        p_id_reserva     => v_id_reserva_nueva
    );
    DBMS_OUTPUT.PUT_LINE('Reserva creada con exito desde el paquete. ID: ' || v_id_reserva_nueva);

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '>>> 3. PRUEBA DE LIQUIDACION MENSUAL EN PAQUETE: sp_liquidar_mensual <<<');
    pkg_turismouq.sp_liquidar_mensual(
        p_anio           => 2025,
        p_mes            => 7,
        p_id_alojamiento => 1
    );
END;
/