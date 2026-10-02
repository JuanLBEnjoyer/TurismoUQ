-- =====================================================================
-- 04_consultas_analisis.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 1 - Siete consultas de analisis para la gerencia
-- =====================================================================
SET LINESIZE 250
SET PAGESIZE 200
SET SQLBLANKLINES ON
SET DEFINE OFF
SET VERIFY OFF

-- =====================================================================
-- CONSULTA 1. OCUPACION POR MUNICIPIO Y MES (PIVOT)
-- Pregunta: cual es la ocupacion de cada municipio mes a mes en 2025?
-- Tecnica: PIVOT sobre el numero de mes -> una fila por municipio y una
-- columna por mes. Para otro anio, cambiar DATE '2025-01-01' en CTE "meses".
-- =====================================================================
WITH meses AS (
  SELECT ADD_MONTHS(DATE '2025-01-01', LEVEL - 1) AS ini,
         ADD_MONTHS(DATE '2025-01-01', LEVEL)     AS fin
    FROM dual
 CONNECT BY LEVEL <= 12
),
hab_mun AS (
  SELECT a.id_municipio, COUNT(*) AS habitaciones
    FROM habitacion h
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   GROUP BY a.id_municipio
),
noches AS (
  SELECT a.id_municipio, m.ini,
         SUM(LEAST(rh.fecha_checkout, m.fin) - GREATEST(rh.fecha_checkin, m.ini)) AS noches_ocupadas
    FROM meses m
    JOIN reserva_habitacion rh ON rh.fecha_checkin < m.fin AND rh.fecha_checkout > m.ini
    JOIN reserva r      ON r.id_reserva = rh.id_reserva AND r.estado <> 'CANCELADA'
    JOIN habitacion h   ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a  ON a.id_alojamiento = h.id_alojamiento
   GROUP BY a.id_municipio, m.ini
)
SELECT *
  FROM (
        SELECT mu.nombre AS municipio,
               EXTRACT(MONTH FROM m.ini) AS mes,
               ROUND(100 * NVL(n.noches_ocupadas, 0) / (hm.habitaciones * (m.fin - m.ini)), 1) AS ocupacion_pct
          FROM municipio mu
          JOIN hab_mun hm ON hm.id_municipio = mu.id_municipio
         CROSS JOIN meses m
          LEFT JOIN noches n ON n.id_municipio = mu.id_municipio AND n.ini = m.ini
       )
 PIVOT (MAX(ocupacion_pct)
        FOR mes IN (1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr, 5 AS may, 6 AS jun,
                    7 AS jul, 8 AS ago, 9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
 ORDER BY municipio;

-- =====================================================================
-- CONSULTA 2. INGRESOS POR MUNICIPIO, TIPO DE ALOJAMIENTO Y TEMPORADA (CUBE)
-- Pregunta: cuanto ingresa cada municipio, cada tipo de alojamiento y cada
-- categoria de temporada, con todos sus subtotales y el total general?
-- Tecnica: CUBE genera los subtotales de TODAS las combinaciones de las tres
-- dimensiones. GROUPING(col) = 1 indica que esa columna esta "totalizada"
-- (fila de subtotal), lo que permite distinguirla de un valor NULL real y
-- rotularla como '** TODOS **'.
-- =====================================================================
WITH ingreso_linea AS (
  SELECT a.id_municipio, a.id_tipo, t.categoria,
         (LEAST(rh.fecha_checkout, t.fecha_fin + 1)
          - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.valor_noche AS valor
    FROM reserva r
    JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
    JOIN habitacion h          ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a         ON a.id_alojamiento = h.id_alojamiento
    JOIN temporada t           ON t.fecha_inicio < rh.fecha_checkout
                              AND t.fecha_fin   >= rh.fecha_checkin
    JOIN tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                              AND tf.id_temporada  = t.id_temporada
   WHERE r.estado = 'COMPLETADA'
)
SELECT CASE GROUPING(mu.nombre) WHEN 1 THEN '** TODOS **' ELSE mu.nombre END AS municipio,
       CASE GROUPING(ta.nombre) WHEN 1 THEN '** TODOS **' ELSE ta.nombre END AS tipo_alojamiento,
       CASE GROUPING(il.categoria) WHEN 1 THEN '** TODAS **' ELSE il.categoria END AS temporada,
       GROUPING(mu.nombre)    AS g_municipio,
       GROUPING(ta.nombre)    AS g_tipo,
       GROUPING(il.categoria) AS g_temporada,
       SUM(il.valor)          AS ingreso
  FROM ingreso_linea il
  JOIN municipio mu        ON mu.id_municipio = il.id_municipio
  JOIN tipo_alojamiento ta ON ta.id_tipo = il.id_tipo
 GROUP BY CUBE (mu.nombre, ta.nombre, il.categoria)
 ORDER BY GROUPING(mu.nombre), mu.nombre,
          GROUPING(ta.nombre), ta.nombre,
          GROUPING(il.categoria), il.categoria;

-- =====================================================================
-- CONSULTA 3. LOS 3 ALOJAMIENTOS DE MAYOR INGRESO EN CADA MUNICIPIO (RANK)
-- Pregunta: cuales son los alojamientos mas rentables dentro de cada municipio?
-- Tecnica: RANK() OVER (PARTITION BY municipio ORDER BY ingreso DESC).
-- RANK deja huecos y repite puesto ante empates; los municipios con menos de
-- 3 alojamientos con ingresos muestran los que tienen.
-- =====================================================================
WITH ingreso_linea AS (
  SELECT h.id_alojamiento,
         (LEAST(rh.fecha_checkout, t.fecha_fin + 1)
          - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.valor_noche AS valor
    FROM reserva r
    JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
    JOIN habitacion h          ON h.id_habitacion = rh.id_habitacion
    JOIN temporada t           ON t.fecha_inicio < rh.fecha_checkout
                              AND t.fecha_fin   >= rh.fecha_checkin
    JOIN tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                              AND tf.id_temporada  = t.id_temporada
   WHERE r.estado = 'COMPLETADA'
),
ingreso_aloj AS (
  SELECT id_alojamiento, SUM(valor) AS ingreso
    FROM ingreso_linea
   GROUP BY id_alojamiento
),
ranking AS (
  SELECT mu.nombre AS municipio,
         a.nombre_comercial AS alojamiento,
         ta.nombre AS tipo,
         ia.ingreso,
         RANK() OVER (PARTITION BY a.id_municipio ORDER BY ia.ingreso DESC) AS puesto
    FROM ingreso_aloj ia
    JOIN alojamiento a       ON a.id_alojamiento = ia.id_alojamiento
    JOIN municipio mu        ON mu.id_municipio = a.id_municipio
    JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
)
SELECT municipio, puesto, alojamiento, tipo, ingreso
  FROM ranking
 WHERE puesto <= 3
 ORDER BY municipio, puesto;

-- =====================================================================
-- CONSULTA 4. VARIACION DE INGRESOS MES CONTRA MES (LAG)
-- Pregunta: como varian los ingresos de la plataforma de un mes a otro, y
-- frente al mismo mes del anio anterior (por la estacionalidad)?
-- Tecnica: LAG(ingreso) trae el mes anterior; LAG(ingreso, 12) el mismo mes
-- del anio previo. El ingreso se reconoce en el mes del check-out (cuando la
-- estadia se completa). La primera fila no tiene mes previo -> variacion NULL.
-- =====================================================================
WITH ingreso_reserva AS (
  SELECT r.id_reserva,
         TRUNC(r.fecha_checkout, 'MM') AS mes,
         SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1)
              - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.valor_noche) AS valor
    FROM reserva r
    JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
    JOIN temporada t           ON t.fecha_inicio < rh.fecha_checkout
                              AND t.fecha_fin   >= rh.fecha_checkin
    JOIN tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                              AND tf.id_temporada  = t.id_temporada
   WHERE r.estado = 'COMPLETADA'
   GROUP BY r.id_reserva, TRUNC(r.fecha_checkout, 'MM')
),
mensual AS (
  SELECT mes, COUNT(*) AS reservas, SUM(valor) AS ingreso
    FROM ingreso_reserva
   GROUP BY mes
)
SELECT TO_CHAR(mes, 'YYYY-MM') AS mes,
       reservas,
       ingreso,
       LAG(ingreso) OVER (ORDER BY mes) AS ingreso_mes_anterior,
       ingreso - LAG(ingreso) OVER (ORDER BY mes) AS variacion_abs,
       ROUND(100 * (ingreso - LAG(ingreso) OVER (ORDER BY mes))
             / NULLIF(LAG(ingreso) OVER (ORDER BY mes), 0), 1) AS variacion_pct,
       LAG(ingreso, 12) OVER (ORDER BY mes) AS ingreso_mismo_mes_anio_ant,
       ROUND(100 * (ingreso - LAG(ingreso, 12) OVER (ORDER BY mes))
             / NULLIF(LAG(ingreso, 12) OVER (ORDER BY mes), 0), 1) AS variacion_anual_pct
  FROM mensual
 ORDER BY mes;

-- =====================================================================
-- CONSULTA 5. CONSULTA PARAMETRIZADA CON VARIABLES DE ENLACE
-- Pregunta: dado un rango de fechas (y opcionalmente un municipio), cuanto
-- vendio cada alojamiento? (reservas no canceladas con check-in en el rango)
-- Variables de enlace: :v_desde, :v_hasta (texto 'YYYY-MM-DD') y :v_municipio
-- (NULL = todos los municipios). Los valores se pasan por bind, no concatenados:
-- el plan se reutiliza y se evita la inyeccion de SQL.
-- =====================================================================
VARIABLE v_desde     VARCHAR2(10)
VARIABLE v_hasta     VARCHAR2(10)
VARIABLE v_municipio VARCHAR2(60)
EXEC :v_desde := '2025-12-01'
EXEC :v_hasta := '2026-01-31'
EXEC :v_municipio := NULL

WITH rango AS (
  SELECT r.id_reserva, r.id_alojamiento
    FROM reserva r
   WHERE r.estado <> 'CANCELADA'
     AND r.fecha_checkin >= TO_DATE(:v_desde, 'YYYY-MM-DD')
     AND r.fecha_checkin <  TO_DATE(:v_hasta, 'YYYY-MM-DD') + 1
),
noches AS (
  SELECT rh.id_reserva, SUM(rh.fecha_checkout - rh.fecha_checkin) AS noches
    FROM reserva_habitacion rh
    JOIN rango rg ON rg.id_reserva = rh.id_reserva
   GROUP BY rh.id_reserva
),
hospedaje AS (
  SELECT rh.id_reserva,
         SUM((LEAST(rh.fecha_checkout, t.fecha_fin + 1)
              - GREATEST(rh.fecha_checkin, t.fecha_inicio)) * tf.valor_noche) AS valor
    FROM reserva_habitacion rh
    JOIN rango rg    ON rg.id_reserva = rh.id_reserva
    JOIN temporada t ON t.fecha_inicio < rh.fecha_checkout AND t.fecha_fin >= rh.fecha_checkin
    JOIN tarifa tf   ON tf.id_habitacion = rh.id_habitacion AND tf.id_temporada = t.id_temporada
   GROUP BY rh.id_reserva
),
servicios AS (
  SELECT rs.id_reserva, SUM(rs.cantidad * rs.precio_unitario) AS valor
    FROM reserva_servicio rs
    JOIN rango rg ON rg.id_reserva = rs.id_reserva
   GROUP BY rs.id_reserva
)
SELECT mu.nombre AS municipio,
       a.nombre_comercial AS alojamiento,
       COUNT(*) AS reservas,
       SUM(n.noches) AS noches_vendidas,
       SUM(h.valor) AS valor_hospedaje,
       SUM(NVL(s.valor, 0)) AS valor_servicios,
       SUM(h.valor + NVL(s.valor, 0)) AS valor_total
  FROM rango rg
  JOIN alojamiento a ON a.id_alojamiento = rg.id_alojamiento
  JOIN municipio mu  ON mu.id_municipio = a.id_municipio
  JOIN noches n      ON n.id_reserva = rg.id_reserva
  JOIN hospedaje h   ON h.id_reserva = rg.id_reserva
  LEFT JOIN servicios s ON s.id_reserva = rg.id_reserva
 WHERE (:v_municipio IS NULL OR mu.nombre = :v_municipio)
 GROUP BY mu.nombre, a.nombre_comercial
 ORDER BY valor_total DESC
 FETCH FIRST 20 ROWS ONLY;

-- =====================================================================
-- CONSULTA 6. UNPIVOT: TARIFA PROMEDIO POR TIPO DE ALOJAMIENTO Y TEMPORADA
-- Pregunta: cual es la tarifa promedio por noche de cada tipo de alojamiento
-- en temporada alta, media y baja? (formato "largo", listo para graficar)
-- Tecnica: la consulta interna produce una columna por categoria (formato
-- ancho: alta, media, baja); UNPIVOT las convierte en filas
-- (tipo, temporada, tarifa_promedio).
-- =====================================================================
SELECT tipo_alojamiento, temporada, tarifa_promedio
  FROM (
        SELECT ta.nombre AS tipo_alojamiento,
               ROUND(AVG(CASE WHEN t.categoria = 'ALTA'  THEN tf.valor_noche END)) AS alta,
               ROUND(AVG(CASE WHEN t.categoria = 'MEDIA' THEN tf.valor_noche END)) AS media,
               ROUND(AVG(CASE WHEN t.categoria = 'BAJA'  THEN tf.valor_noche END)) AS baja
          FROM tarifa tf
          JOIN temporada t         ON t.id_temporada = tf.id_temporada
          JOIN habitacion h        ON h.id_habitacion = tf.id_habitacion
          JOIN alojamiento a       ON a.id_alojamiento = h.id_alojamiento
          JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
         GROUP BY ta.nombre
       )
UNPIVOT (tarifa_promedio FOR temporada IN (alta AS 'ALTA', media AS 'MEDIA', baja AS 'BAJA'))
 ORDER BY tipo_alojamiento, DECODE(temporada, 'ALTA', 1, 'MEDIA', 2, 3);

-- =====================================================================
-- CONSULTA 7 (LIBRE). BRECHA ENTRE ESTRELLAS AUTOASIGNADAS Y RESENAS
-- Pregunta de negocio: que alojamientos se autoasignan mas estrellas de las
-- que sus clientes reconocen en las resenas?.
-- Metodo: se compara ESTRELLAS (autoasignadas) con el promedio de las
-- calificaciones de RESENA (clientes). brecha = estrellas - promedio.
--   brecha >= 1     -> 'Sobrevalorado'  (se anuncia mejor de lo que es)
--   brecha <= -0.5  -> 'Subvalorado'    (los clientes lo califican mejor)
--   en otro caso    -> 'Coherente'
-- Solo alojamientos con al menos 10 resenas (promedios confiables). RANK
-- ordena la brecha dentro de cada tipo de alojamiento.
-- =====================================================================
SELECT a.nombre_comercial AS alojamiento,
       mu.nombre AS municipio,
       ta.nombre AS tipo_alojamiento,
       a.estrellas AS estrellas_autoasignadas,
       COUNT(re.id_resena) AS num_resenas,
       ROUND(AVG(re.calificacion), 2) AS calificacion_promedio,
       ROUND(a.estrellas - AVG(re.calificacion), 2) AS brecha,
       CASE WHEN a.estrellas - AVG(re.calificacion) >= 1    THEN 'Sobrevalorado'
            WHEN a.estrellas - AVG(re.calificacion) <= -0.5 THEN 'Subvalorado'
            ELSE 'Coherente' END AS diagnostico,
       RANK() OVER (PARTITION BY ta.nombre
                    ORDER BY a.estrellas - AVG(re.calificacion) DESC) AS puesto_en_tipo
  FROM resena re
  JOIN reserva r           ON r.id_reserva = re.id_reserva
  JOIN alojamiento a       ON a.id_alojamiento = r.id_alojamiento
  JOIN municipio mu        ON mu.id_municipio = a.id_municipio
  JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
 GROUP BY a.id_alojamiento, a.nombre_comercial, mu.nombre, ta.nombre, a.estrellas
HAVING COUNT(re.id_resena) >= 10
 ORDER BY brecha DESC, alojamiento;
