-- =====================================================================
-- 03_carga_reservas.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 1 - Carga de datos: reservas y movimiento
--
--
-- Carga:
--   RESERVA 25.000 (2024-2026)  | RESERVA_HABITACION >= 25.000
--   RESERVA_SERVICIO >= 40.000  | PAGO >= 25.000 | RESENA >= 40 % de las
--   reservas COMPLETADAS
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON

-- =====================================================================
-- BLOQUE 1. RESERVAS, LINEAS DE HABITACION Y SERVICIOS CONTRATADOS
-- =====================================================================
DECLARE
  c_semilla CONSTANT PLS_INTEGER := 10261023;  
  c_total   CONSTANT PLS_INTEGER := 25000;      -- reservas a generar
  c_min_srv CONSTANT PLS_INTEGER := 40000;      -- minimo de lineas de servicio
  c_hoy     CONSTANT DATE := DATE '2026-10-01'; -- "hoy" fijo del dataset
  c_ini     CONSTANT DATE := DATE '2024-01-01'; -- primer dia del calendario
  c_ndias   CONSTANT PLS_INTEGER := 1096;       -- 2024-01-01 .. 2026-12-31

  TYPE t_int  IS TABLE OF PLS_INTEGER  INDEX BY PLS_INTEGER;
  TYPE t_num  IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  TYPE t_bool IS TABLE OF BOOLEAN      INDEX BY PLS_INTEGER;
  TYPE t_cat  IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER;

  -- Alojamientos: ids, rango de habitaciones/servicios, popularidad
  a_id t_int;  a_idx t_int;  a_first t_int;  a_cnt t_int;
  a_sfirst t_int;  a_scnt t_int;  a_pop t_num;  a_cum t_num;
  -- Habitaciones, servicios, clientes
  h_id t_int;  h_cap t_int;
  s_id t_int;  s_precio t_num;
  cli_id t_int;
  -- Calendario: categoria de temporada y peso acumulado por dia
  d_cat t_cat;  d_cum t_num;
  -- Mapa de ocupacion: clave = indice_habitacion * 2000 + dia
  occ t_bool;
  -- Reservas generadas (para completar servicios al final)
  r_id t_int;  r_a t_int;
  -- Lineas de la reserva en construccion
  l_h t_int;  l_d1 t_int;  l_d2 t_int;  l_g t_int;
  -- Servicios elegidos para la reserva en construccion
  sel t_int;

  v_na PLS_INTEGER := 0;  v_nh PLS_INTEGER := 0;  v_ns PLS_INTEGER := 0;
  v_ncli PLS_INTEGER := 0;  v_i PLS_INTEGER;
  v_peso NUMBER;  v_peso_tot NUMBER := 0;
  v_w NUMBER;  v_cum_tot NUMBER := 0;

  v_ok PLS_INTEGER := 0;  v_intentos PLS_INTEGER := 0;  v_nlin PLS_INTEGER := 0;
  v_a PLS_INTEGER;  v_d1 PLS_INTEGER;  v_d2 PLS_INTEGER;  v_n PLS_INTEGER;
  v_ci DATE;  v_co DATE;  v_cre DATE;  v_canc DATE;
  v_estado VARCHAR2(12);  v_r NUMBER;  v_dias PLS_INTEGER;
  v_k PLS_INTEGER;  v_nl PLS_INTEGER;  v_tries PLS_INTEGER;
  v_h PLS_INTEGER;  v_l1 PLS_INTEGER;  v_l2 PLS_INTEGER;  v_dup BOOLEAN;
  v_c PLS_INTEGER;  v_res NUMBER;
  v_nsv PLS_INTEGER;  v_nsel PLS_INTEGER;  v_s PLS_INTEGER;  v_cant PLS_INTEGER;

  -- Dia (0..1095) con probabilidad proporcional al peso de temporada
  FUNCTION pick_dia RETURN PLS_INTEGER IS
    v_x  NUMBER := DBMS_RANDOM.VALUE(0, v_cum_tot);
    v_lo PLS_INTEGER := 0;
    v_hi PLS_INTEGER := c_ndias - 1;
    v_md PLS_INTEGER;
  BEGIN
    WHILE v_lo < v_hi LOOP
      v_md := TRUNC((v_lo + v_hi) / 2);
      IF d_cum(v_md) >= v_x THEN v_hi := v_md; ELSE v_lo := v_md + 1; END IF;
    END LOOP;
    RETURN v_lo;
  END;

  -- Alojamiento (indice 1..v_na) con probabilidad proporcional a su peso
  FUNCTION pick_aloj RETURN PLS_INTEGER IS
    v_x NUMBER := DBMS_RANDOM.VALUE(0, v_peso_tot);
  BEGIN
    FOR i IN 1 .. v_na LOOP
      IF a_cum(i) >= v_x THEN RETURN i; END IF;
    END LOOP;
    RETURN v_na;
  END;

  FUNCTION pick_noches RETURN PLS_INTEGER IS
    v_x NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    RETURN CASE WHEN v_x < 0.10 THEN 1 WHEN v_x < 0.40 THEN 2 WHEN v_x < 0.65 THEN 3
                WHEN v_x < 0.80 THEN 4 WHEN v_x < 0.88 THEN 5 WHEN v_x < 0.93 THEN 6
                ELSE 7 END;
  END;

  FUNCTION pick_nrooms RETURN PLS_INTEGER IS
    v_x NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    RETURN CASE WHEN v_x < 0.84 THEN 1 WHEN v_x < 0.94 THEN 2 WHEN v_x < 0.98 THEN 3 ELSE 4 END;
  END;

  -- TRUE si la habitacion (indice) esta libre las noches [d1, d2)
  FUNCTION libre(p_h PLS_INTEGER, p_d1 PLS_INTEGER, p_d2 PLS_INTEGER) RETURN BOOLEAN IS
  BEGIN
    FOR d IN p_d1 .. p_d2 - 1 LOOP
      IF occ.EXISTS(p_h * 2000 + d) THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN TRUE;
  END;

  PROCEDURE ocupar(p_h PLS_INTEGER, p_d1 PLS_INTEGER, p_d2 PLS_INTEGER) IS
  BEGIN
    FOR d IN p_d1 .. p_d2 - 1 LOOP
      occ(p_h * 2000 + d) := TRUE;
    END LOOP;
  END;
BEGIN
  DBMS_RANDOM.SEED(c_semilla);

  -- ---------- Cargar alojamientos y su popularidad por municipio ----------
  FOR a IN (SELECT al.id_alojamiento, m.nombre AS muni
              FROM alojamiento al JOIN municipio m ON m.id_municipio = al.id_municipio
             ORDER BY al.id_alojamiento) LOOP
    v_na := v_na + 1;
    a_id(v_na) := a.id_alojamiento;
    a_idx(a.id_alojamiento) := v_na;
    a_cnt(v_na) := 0;  a_scnt(v_na) := 0;
    a_pop(v_na) := CASE WHEN a.muni = 'Armenia' THEN 1.25
                        WHEN a.muni = 'Salento' THEN 1.5
                        WHEN a.muni = 'Montenegro' THEN 1.2
                        WHEN a.muni = 'Quimbaya' THEN 1.1
                        WHEN a.muni = 'Filandia' THEN 1.15
                        WHEN a.muni LIKE 'Calarc%' THEN 1.0
                        WHEN a.muni IN ('La Tebaida', 'Circasia') THEN 0.9
                        WHEN a.muni = 'Pijao' THEN 0.8
                        ELSE 0.6 END;
  END LOOP;

  -- ---------- Habitaciones (contiguas por alojamiento) ----------
  FOR h IN (SELECT id_alojamiento, id_habitacion, capacidad_max
              FROM habitacion ORDER BY id_alojamiento, id_habitacion) LOOP
    v_nh := v_nh + 1;
    h_id(v_nh) := h.id_habitacion;  h_cap(v_nh) := h.capacidad_max;
    v_i := a_idx(h.id_alojamiento);
    IF a_cnt(v_i) = 0 THEN a_first(v_i) := v_nh; END IF;
    a_cnt(v_i) := a_cnt(v_i) + 1;
  END LOOP;

  -- ---------- Servicios ----------
  FOR s IN (SELECT id_alojamiento, id_servicio, precio
              FROM servicio ORDER BY id_alojamiento, id_servicio) LOOP
    v_ns := v_ns + 1;
    s_id(v_ns) := s.id_servicio;  s_precio(v_ns) := s.precio;
    v_i := a_idx(s.id_alojamiento);
    IF a_scnt(v_i) = 0 THEN a_sfirst(v_i) := v_ns; END IF;
    a_scnt(v_i) := a_scnt(v_i) + 1;
  END LOOP;

  -- ---------- Clientes ----------
  SELECT id_cliente BULK COLLECT INTO cli_id FROM cliente ORDER BY id_cliente;
  v_ncli := cli_id.COUNT;
  IF v_na = 0 OR v_nh = 0 OR v_ncli = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Ejecute primero 02_carga_catalogos.sql');
  END IF;

  -- ---------- Peso de cada alojamiento ----------
  -- habitaciones^0.75 x factor del municipio x factor aleatorio -> muy desigual
  FOR i IN 1 .. v_na LOOP
    v_peso := POWER(a_cnt(i), 0.75) * a_pop(i) * DBMS_RANDOM.VALUE(0.4, 1.8);
    v_peso_tot := v_peso_tot + v_peso;
    a_cum(i) := v_peso_tot;
  END LOOP;

  -- ---------- Calendario: categoria por dia y peso acumulado ----------
  FOR d IN 0 .. c_ndias - 1 LOOP d_cat(d) := 'BAJA'; END LOOP;
  FOR t IN (SELECT categoria, fecha_inicio, fecha_fin FROM temporada) LOOP
    FOR d IN (t.fecha_inicio - c_ini) .. (t.fecha_fin - c_ini) LOOP
      d_cat(d) := t.categoria;
    END LOOP;
  END LOOP;
  FOR d IN 0 .. c_ndias - 1 LOOP
    v_w := CASE d_cat(d) WHEN 'ALTA' THEN 5 WHEN 'MEDIA' THEN 2.2 ELSE 1 END;
    -- fin de semana: dia 0 = lunes (2024-01-01) -> 3 jueves, 4 viernes, 5 sabado
    v_w := v_w * CASE MOD(d, 7) WHEN 3 THEN 1.2 WHEN 4 THEN 1.7 WHEN 5 THEN 1.7 ELSE 1 END;
    -- crecimiento anual del negocio
    v_w := v_w * CASE EXTRACT(YEAR FROM (c_ini + d)) WHEN 2024 THEN 0.75 WHEN 2025 THEN 1 ELSE 1.15 END;
    -- fechas futuras: pocas reservas anticipadas
    IF c_ini + d > c_hoy THEN v_w := v_w * 0.3; END IF;
    -- el ultimo dia no puede ser check-in (no habria noche)
    IF d = c_ndias - 1 THEN v_w := 0; END IF;
    v_cum_tot := v_cum_tot + v_w;
    d_cum(d) := v_cum_tot;
  END LOOP;

  -- =================== GENERACION DE RESERVAS ===================
  WHILE v_ok < c_total AND v_intentos < c_total * 30 LOOP
    v_intentos := v_intentos + 1;
    v_a  := pick_aloj;
    v_d1 := pick_dia;
    v_n  := pick_noches;
    IF v_d1 + v_n > c_ndias - 1 THEN v_n := c_ndias - 1 - v_d1; END IF;
    CONTINUE WHEN v_n < 1;
    v_d2 := v_d1 + v_n;
    v_ci := c_ini + v_d1;
    v_co := c_ini + v_d2;

    -- ---- Estado segun la posicion de la estadia respecto a "hoy" ----
    v_r := DBMS_RANDOM.VALUE;
    IF v_co <= c_hoy THEN
      v_estado := CASE WHEN v_r < 0.87 THEN 'COMPLETADA' ELSE 'CANCELADA' END;
    ELSIF v_ci <= c_hoy THEN
      v_estado := CASE WHEN v_r < 0.93 THEN 'CONFIRMADA' ELSE 'CANCELADA' END;
    ELSE
      v_estado := CASE WHEN v_r < 0.70 THEN 'CONFIRMADA' WHEN v_r < 0.90 THEN 'PENDIENTE'
                       ELSE 'CANCELADA' END;
    END IF;

    -- ---- Habitaciones de la reserva  ----
    v_k := pick_nrooms;
    IF v_k > a_cnt(v_a) THEN v_k := a_cnt(v_a); END IF;
    v_nl := 0;  v_tries := 0;
    WHILE v_nl < v_k AND v_tries < 12 LOOP
      v_tries := v_tries + 1;
      v_h := a_first(v_a) + TRUNC(DBMS_RANDOM.VALUE(0, a_cnt(v_a)));
      v_dup := FALSE;
      FOR j IN 1 .. v_nl LOOP
        IF l_h(j) = v_h THEN v_dup := TRUE; END IF;
      END LOOP;
      IF NOT v_dup THEN
        -- La primera linea cubre todo el rango; las demas pueden llegar un dia
        -- despues o salir un dia antes.
        v_l1 := v_d1;  v_l2 := v_d2;
        IF v_nl > 0 AND v_n >= 2 THEN
          IF DBMS_RANDOM.VALUE < 0.20 THEN v_l1 := v_d1 + 1; END IF;
          IF DBMS_RANDOM.VALUE < 0.15 THEN v_l2 := v_d2 - 1; END IF;
          IF v_l2 <= v_l1 THEN v_l2 := v_l1 + 1; END IF;
        END IF;
        -- Las canceladas no ocupan la habitacion: no se valida disponibilidad
        IF v_estado = 'CANCELADA' OR libre(v_h, v_l1, v_l2) THEN
          v_nl := v_nl + 1;
          l_h(v_nl) := v_h;  l_d1(v_nl) := v_l1;  l_d2(v_nl) := v_l2;
          l_g(v_nl) := 1 + TRUNC(DBMS_RANDOM.VALUE(0, h_cap(v_h))); 
        END IF;
      END IF;
    END LOOP;
    CONTINUE WHEN v_nl = 0;     

    IF v_estado <> 'CANCELADA' THEN
      FOR j IN 1 .. v_nl LOOP ocupar(l_h(j), l_d1(j), l_d2(j)); END LOOP;
    END IF;

    -- ---- Fechas de creacion y cancelacion ----
    v_cre := v_ci - (1 + TRUNC(POWER(DBMS_RANDOM.VALUE, 2) * 90));
    IF v_cre > c_hoy THEN v_cre := c_hoy - TRUNC(DBMS_RANDOM.VALUE(0, 20)); END IF;
    v_canc := NULL;
    IF v_estado = 'CANCELADA' THEN
      IF DBMS_RANDOM.VALUE < 0.60 THEN
        v_dias := 6 + TRUNC(DBMS_RANDOM.VALUE(0, 35));  
      ELSE
        v_dias := TRUNC(DBMS_RANDOM.VALUE(0, 5));        
      END IF;
      v_canc := LEAST(GREATEST(v_cre, v_ci - v_dias), c_hoy);
    END IF;

    -- ---- Cliente: distribucion sesgada ----
    v_c := 1 + TRUNC(v_ncli * POWER(DBMS_RANDOM.VALUE, 1.3));

    INSERT INTO reserva (id_cliente, id_alojamiento, fecha_creacion, fecha_checkin,
                         fecha_checkout, estado, fecha_cancelacion)
    VALUES (cli_id(v_c), a_id(v_a), v_cre, v_ci, v_co, v_estado, v_canc)
    RETURNING id_reserva INTO v_res;

    FOR j IN 1 .. v_nl LOOP
      INSERT INTO reserva_habitacion (id_reserva, id_habitacion, fecha_checkin,
                                      fecha_checkout, num_huespedes)
      VALUES (v_res, h_id(l_h(j)), c_ini + l_d1(j), c_ini + l_d2(j), l_g(j));
    END LOOP;

    -- ---- Servicios contratados ----
    v_r := DBMS_RANDOM.VALUE;
    v_nsv := CASE WHEN v_r < 0.12 THEN 0 WHEN v_r < 0.40 THEN 1 WHEN v_r < 0.68 THEN 2
                  WHEN v_r < 0.86 THEN 3 ELSE 4 END;
    IF v_estado = 'CANCELADA' AND DBMS_RANDOM.VALUE < 0.5 THEN v_nsv := 0; END IF;
    IF v_nsv > a_scnt(v_a) THEN v_nsv := a_scnt(v_a); END IF;
    v_nsel := 0;
    WHILE v_nsel < v_nsv LOOP
      v_s := a_sfirst(v_a) + TRUNC(DBMS_RANDOM.VALUE(0, a_scnt(v_a)));
      v_dup := FALSE;
      FOR j IN 1 .. v_nsel LOOP
        IF sel(j) = v_s THEN v_dup := TRUE; END IF;
      END LOOP;
      IF NOT v_dup THEN
        v_nsel := v_nsel + 1;
        sel(v_nsel) := v_s;
        v_cant := 1 + TRUNC(POWER(DBMS_RANDOM.VALUE, 2) * 4);   
        INSERT INTO reserva_servicio (id_reserva, id_servicio, cantidad, precio_unitario)
        VALUES (v_res, s_id(v_s), v_cant, s_precio(v_s));
        v_nlin := v_nlin + 1;
      END IF;
    END LOOP;

    v_ok := v_ok + 1;
    r_id(v_ok) := v_res;
    r_a(v_ok)  := v_a;
  END LOOP;

  IF v_ok < c_total THEN
    DBMS_OUTPUT.PUT_LINE('ADVERTENCIA: solo se generaron ' || v_ok || ' reservas (ocupacion saturada).');
  END IF;

  -- ---- Completar hasta el minimo de lineas de servicio  ----
  WHILE v_nlin < c_min_srv LOOP
    v_i := 1 + TRUNC(DBMS_RANDOM.VALUE(0, v_ok));           -- reserva al azar
    v_a := r_a(v_i);
    v_s := a_sfirst(v_a) + TRUNC(DBMS_RANDOM.VALUE(0, a_scnt(v_a)));
    BEGIN
      INSERT INTO reserva_servicio (id_reserva, id_servicio, cantidad, precio_unitario)
      VALUES (r_id(v_i), s_id(v_s), 1 + TRUNC(DBMS_RANDOM.VALUE(0, 3)), s_precio(v_s));
      v_nlin := v_nlin + 1;
    EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN NULL;                      
    END;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Reservas generadas: ' || v_ok || ' (intentos: ' || v_intentos || ')');
  DBMS_OUTPUT.PUT_LINE('Lineas de servicio:  ' || v_nlin);
END;
/

-- =====================================================================
-- BLOQUE 2. PAGOS
-- El valor de cada reserva se calcula noche por noche:
--
--   COMPLETADA : 68 % pago unico; 32 % anticipo (30-50 %) + saldo al llegar.
--                6 % tienen ademas un intento previo FALLIDO.
--   CONFIRMADA : 50 % pago unico; 50 % anticipo + saldo (PENDIENTE si aun no llega).
--   PENDIENTE  : 55 % con un anticipo en estado PENDIENTE; el resto sin pagos.
--   CANCELADA  : 75 % con anticipo EXITOSO; si cancelo con MAS de 5 dias se agrega
--                una fila REEMBOLSADO por el 80 % del anticipo.
-- =====================================================================
DECLARE
  c_semilla CONSTANT PLS_INTEGER := 203255323;
  c_hoy     CONSTANT DATE := DATE '2026-10-01';

  CURSOR c_res IS
    WITH est AS (
      SELECT rh.id_reserva,
             SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1)
                  - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.valor_noche) AS valor
        FROM reserva_habitacion rh
        JOIN temporada t  ON t.fecha_inicio < rh.fecha_checkout
                         AND t.fecha_fin   >= rh.fecha_checkin
        JOIN tarifa tf    ON tf.id_habitacion = rh.id_habitacion
                         AND tf.id_temporada  = t.id_temporada
       GROUP BY rh.id_reserva
    ),
    srv AS (
      SELECT id_reserva, SUM(cantidad * precio_unitario) AS valor
        FROM reserva_servicio
       GROUP BY id_reserva
    )
    SELECT r.id_reserva, r.estado, r.fecha_creacion, r.fecha_checkin,
           r.fecha_cancelacion, NVL(e.valor, 0) + NVL(s.valor, 0) AS total
      FROM reserva r
      LEFT JOIN est e ON e.id_reserva = r.id_reserva
      LEFT JOIN srv s ON s.id_reserva = r.id_reserva
     ORDER BY r.id_reserva;

  v_ant  NUMBER;
  v_fec  DATE;
  v_npag PLS_INTEGER := 0;

  -- Metodo de pago: en linea o al llegar
  FUNCTION metodo(p_llegada BOOLEAN DEFAULT FALSE) RETURN VARCHAR2 IS
    v_x NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    IF p_llegada THEN
      RETURN CASE WHEN v_x < 0.30 THEN 'TARJETA_CREDITO' WHEN v_x < 0.50 THEN 'TARJETA_DEBITO'
                  WHEN v_x < 0.60 THEN 'PSE' WHEN v_x < 0.70 THEN 'TRANSFERENCIA' ELSE 'EFECTIVO' END;
    END IF;
    RETURN CASE WHEN v_x < 0.38 THEN 'TARJETA_CREDITO' WHEN v_x < 0.52 THEN 'TARJETA_DEBITO'
                WHEN v_x < 0.80 THEN 'PSE' WHEN v_x < 0.93 THEN 'TRANSFERENCIA' ELSE 'EFECTIVO' END;
  END;

  PROCEDURE pagar(p_res NUMBER, p_fecha DATE, p_monto NUMBER, p_metodo VARCHAR2, p_estado VARCHAR2) IS
  BEGIN
    INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado)
    VALUES (p_res, p_fecha, p_monto, p_metodo, p_estado);
    v_npag := v_npag + 1;
  END;
BEGIN
  DBMS_RANDOM.SEED(c_semilla);

  FOR r IN c_res LOOP
    v_ant := ROUND(r.total * DBMS_RANDOM.VALUE(0.30, 0.50));   

    IF r.estado = 'COMPLETADA' THEN
      IF DBMS_RANDOM.VALUE < 0.06 THEN
        pagar(r.id_reserva, r.fecha_creacion, v_ant, metodo, 'FALLIDO');
      END IF;
      IF DBMS_RANDOM.VALUE < 0.68 THEN
        v_fec := r.fecha_creacion + TRUNC(DBMS_RANDOM.VALUE(0, r.fecha_checkin - r.fecha_creacion + 1));
        pagar(r.id_reserva, v_fec, r.total, metodo, 'EXITOSO');
      ELSE
        pagar(r.id_reserva, r.fecha_creacion, v_ant, metodo, 'EXITOSO');
        pagar(r.id_reserva, r.fecha_checkin, r.total - v_ant, metodo(TRUE), 'EXITOSO');
      END IF;

    ELSIF r.estado = 'CONFIRMADA' THEN
      IF DBMS_RANDOM.VALUE < 0.50 THEN
        pagar(r.id_reserva, r.fecha_creacion, r.total, metodo, 'EXITOSO');
      ELSE
        pagar(r.id_reserva, r.fecha_creacion, v_ant, metodo, 'EXITOSO');
        pagar(r.id_reserva, r.fecha_checkin, r.total - v_ant, metodo(TRUE),
              CASE WHEN r.fecha_checkin <= c_hoy THEN 'EXITOSO' ELSE 'PENDIENTE' END);
      END IF;

    ELSIF r.estado = 'PENDIENTE' THEN
      IF DBMS_RANDOM.VALUE < 0.55 THEN
        pagar(r.id_reserva, r.fecha_creacion, v_ant, metodo, 'PENDIENTE');
      END IF;

    ELSE   -- CANCELADA
      IF DBMS_RANDOM.VALUE < 0.75 THEN
        v_ant := ROUND(r.total * DBMS_RANDOM.VALUE(0.30, 0.60));
        pagar(r.id_reserva, r.fecha_creacion, v_ant, metodo, 'EXITOSO');
        -- Regla de reembolso: mas de 5 dias de anticipacion -> devuelve el 80 %
        IF r.fecha_checkin - r.fecha_cancelacion > 5 THEN
          pagar(r.id_reserva, r.fecha_cancelacion, ROUND(v_ant * 0.8), metodo, 'REEMBOLSADO');
        END IF;
      END IF;
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Pagos generados: ' || v_npag);
END;
/

-- =====================================================================
-- BLOQUE 3. RESENAS
-- Solo de reservas COMPLETADAS (regla RN2), maximo una por reserva. Se resena
-- ~52 % de las completadas. Cada alojamiento tiene una "calidad base" ligada
-- a sus estrellas mas ruido; la calificacion = calidad + variacion normal,
-- acotada entre 1 y 5, de modo que hay alojamientos bien y mal calificados.
-- =====================================================================
DECLARE
  c_semilla CONSTANT PLS_INTEGER := 2022441223;  
  c_hoy     CONSTANT DATE := DATE '2026-10-01';

  TYPE t_num IS TABLE OF NUMBER        INDEX BY PLS_INTEGER;
  TYPE t_vc  IS TABLE OF VARCHAR2(200) INDEX BY PLS_INTEGER;
  v_q    t_num;
  v_pos  t_vc;  v_neu t_vc;  v_neg t_vc;
  v_cal  PLS_INTEGER;
  v_com  VARCHAR2(500);
  v_nres PLS_INTEGER := 0;

  PROCEDURE llenar(p_lista IN VARCHAR2, p_tab IN OUT NOCOPY t_vc) IS
    v_i PLS_INTEGER := 1;
    v_x VARCHAR2(200);
  BEGIN
    LOOP
      v_x := REGEXP_SUBSTR(p_lista, '[^|]+', 1, v_i);
      EXIT WHEN v_x IS NULL;
      p_tab(v_i) := TRIM(v_x);
      v_i := v_i + 1;
    END LOOP;
  END;
BEGIN
  DBMS_RANDOM.SEED(c_semilla);

  llenar('Excelente atencion y ubicacion, volveremos|El cafe de la finca es increible|'
      || 'Habitaciones limpias y muy comodas|Paisaje espectacular y personal amable|'
      || 'Muy buena relacion calidad-precio|Todo salio perfecto, super recomendado', v_pos);
  llenar('Buen lugar, pero el wifi fallaba|Cumple lo basico, nada especial|'
      || 'La habitacion estaba bien aunque algo ruidosa|Buena ubicacion, atencion regular', v_neu);
  llenar('No coincidia con las fotos publicadas|Demoraron mucho el check-in|'
      || 'Habitacion con humedad y mucho ruido|El servicio dejo mucho que desear', v_neg);

  -- Calidad base de cada alojamiento: depende de sus estrellas (autoasignadas)
  FOR a IN (SELECT id_alojamiento, estrellas FROM alojamiento) LOOP
    v_q(a.id_alojamiento) := LEAST(4.9, GREATEST(2.5,
                               2.4 + a.estrellas * 0.4 + DBMS_RANDOM.NORMAL * 0.35));
  END LOOP;

  FOR r IN (SELECT id_reserva, id_alojamiento, fecha_checkout
              FROM reserva WHERE estado = 'COMPLETADA' ORDER BY id_reserva) LOOP
    IF DBMS_RANDOM.VALUE < 0.52 THEN
      v_cal := ROUND(v_q(r.id_alojamiento) + DBMS_RANDOM.NORMAL * 0.9);
      IF v_cal < 1 THEN v_cal := 1; END IF;
      IF v_cal > 5 THEN v_cal := 5; END IF;

      v_com := NULL;                                -- el comentario es opcional (60 %)
      IF DBMS_RANDOM.VALUE < 0.60 THEN
        IF v_cal >= 4 THEN
          v_com := v_pos(1 + TRUNC(DBMS_RANDOM.VALUE(0, v_pos.COUNT)));
        ELSIF v_cal = 3 THEN
          v_com := v_neu(1 + TRUNC(DBMS_RANDOM.VALUE(0, v_neu.COUNT)));
        ELSE
          v_com := v_neg(1 + TRUNC(DBMS_RANDOM.VALUE(0, v_neg.COUNT)));
        END IF;
      END IF;

      INSERT INTO resena (id_reserva, calificacion, comentario, fecha_resena)
      VALUES (r.id_reserva, v_cal, v_com,
              LEAST(r.fecha_checkout + TRUNC(DBMS_RANDOM.VALUE(0, 15)), c_hoy));
      v_nres := v_nres + 1;
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Resenas generadas: ' || v_nres);
END;
/

-- Estadisticas del optimizador (utiles para los planes de ejecucion posteriores)
BEGIN
  DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

-- =====================================================================
-- VERIFICACION DE LA CARGA COMPLETA
-- =====================================================================

-- 1. Volumen frente al minimo exigido
SELECT 'MUNICIPIO' AS tabla, (SELECT COUNT(*) FROM municipio) AS filas, 12 AS minimo FROM dual
UNION ALL SELECT 'TIPO_ALOJAMIENTO',    (SELECT COUNT(*) FROM tipo_alojamiento), 4     FROM dual
UNION ALL SELECT 'ALOJAMIENTO',         (SELECT COUNT(*) FROM alojamiento), 60    FROM dual
UNION ALL SELECT 'HABITACION',          (SELECT COUNT(*) FROM habitacion), 400   FROM dual
UNION ALL SELECT 'TEMPORADA',           (SELECT COUNT(*) FROM temporada), 6     FROM dual
UNION ALL SELECT 'TARIFA (cruce)',      (SELECT COUNT(*) FROM tarifa),
                                        (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada) FROM dual
UNION ALL SELECT 'CLIENTE',             (SELECT COUNT(*) FROM cliente), 3000  FROM dual
UNION ALL SELECT 'RESERVA',             (SELECT COUNT(*) FROM reserva), 25000 FROM dual
UNION ALL SELECT 'RESERVA_HABITACION',  (SELECT COUNT(*) FROM reserva_habitacion), 25000 FROM dual
UNION ALL SELECT 'PAGO',                (SELECT COUNT(*) FROM pago), 25000 FROM dual
UNION ALL SELECT 'SERVICIO',            (SELECT COUNT(*) FROM servicio), 30    FROM dual
UNION ALL SELECT 'RESERVA_SERVICIO',    (SELECT COUNT(*) FROM reserva_servicio), 40000 FROM dual
UNION ALL SELECT 'RESENA',              (SELECT COUNT(*) FROM resena), 0     FROM dual
UNION ALL SELECT 'USUARIO_SISTEMA',     (SELECT COUNT(*) FROM usuario_sistema), 10    FROM dual;
-- 2. Porcentaje de reservas COMPLETADAS con resena 
SELECT COUNT(*) AS completadas, COUNT(re.id_resena) AS con_resena,
       ROUND(100 * COUNT(re.id_resena) / COUNT(*), 1) AS porcentaje
  FROM reserva r LEFT JOIN resena re ON re.id_reserva = r.id_reserva
 WHERE r.estado = 'COMPLETADA';

-- 3. Solapes entre reservas NO canceladas de la misma habitacion 
SELECT COUNT(*) AS solapes
  FROM reserva_habitacion a
  JOIN reserva ra ON ra.id_reserva = a.id_reserva AND ra.estado <> 'CANCELADA'
  JOIN reserva_habitacion b ON b.id_habitacion = a.id_habitacion
                           AND b.id_reserva_hab > a.id_reserva_hab
                           AND a.fecha_checkin  < b.fecha_checkout
                           AND a.fecha_checkout > b.fecha_checkin
  JOIN reserva rb ON rb.id_reserva = b.id_reserva AND rb.estado <> 'CANCELADA';

-- 4. Lineas cuyas noches no estan 100 % cubiertas por alguna tarifa 
SELECT COUNT(*) AS lineas_sin_tarifa_completa
  FROM (SELECT rh.id_reserva_hab,
               rh.fecha_checkout - rh.fecha_checkin AS noches,
               SUM(LEAST(rh.fecha_checkout, t.fecha_fin + 1)
                   - GREATEST(rh.fecha_checkin, t.fecha_inicio)) AS noches_cubiertas
          FROM reserva_habitacion rh
          JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout
                          AND t.fecha_fin   >= rh.fecha_checkin
         GROUP BY rh.id_reserva_hab, rh.fecha_checkout, rh.fecha_checkin)
 WHERE noches <> noches_cubiertas;

-- 5. Lineas fuera del rango de su reserva o con huespedes sobre la capacidad 
SELECT COUNT(*) AS lineas_invalidas
  FROM reserva_habitacion rh
  JOIN reserva r     ON r.id_reserva = rh.id_reserva
  JOIN habitacion h  ON h.id_habitacion = rh.id_habitacion
 WHERE rh.fecha_checkin < r.fecha_checkin OR rh.fecha_checkout > r.fecha_checkout
    OR rh.num_huespedes > h.capacidad_max
    OR h.id_alojamiento <> r.id_alojamiento;

-- 6. Estados de las reservas
SELECT estado, COUNT(*) AS reservas, ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
  FROM reserva GROUP BY estado ORDER BY reservas DESC;

-- 7. Estacionalidad: reservas por mes de check-in (debe verse alta en dic-ene, jun-jul, abril)
SELECT TO_CHAR(fecha_checkin, 'YYYY-MM') AS mes, COUNT(*) AS reservas
  FROM reserva GROUP BY TO_CHAR(fecha_checkin, 'YYYY-MM') ORDER BY mes;

-- 8. Asimetria: reservas por municipio
SELECT m.nombre AS municipio, COUNT(*) AS reservas
  FROM reserva r
  JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
  JOIN municipio m   ON m.id_municipio = a.id_municipio
 GROUP BY m.nombre ORDER BY reservas DESC;

-- 9. Reservas con mas de una habitacion y con mas de un pago
SELECT (SELECT COUNT(*) FROM (SELECT id_reserva FROM reserva_habitacion GROUP BY id_reserva HAVING COUNT(*) > 1)) AS reservas_multihabitacion,
       (SELECT COUNT(*) FROM (SELECT id_reserva FROM pago GROUP BY id_reserva HAVING COUNT(*) > 1)) AS reservas_multipago
  FROM dual;
