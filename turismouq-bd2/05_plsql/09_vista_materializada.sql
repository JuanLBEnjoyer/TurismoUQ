-- =====================================================================
-- 1. CREACIÓN DE LA VISTA MATERIALIZADA: mv_ocupacion_mensual
-- Precalcula la tasa de ocupación mensual de cada municipio del Quindío
-- para todo el horizonte temporal del proyecto (2024-2026 = 36 meses).
-- =====================================================================
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
WITH meses AS (
    -- Generación de los 36 meses del periodo 2024-2026
    SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS mes_ini,
           ADD_MONTHS(DATE '2024-01-01', LEVEL)     AS mes_fin,
           EXTRACT(YEAR FROM ADD_MONTHS(DATE '2024-01-01', LEVEL - 1))  AS anio,
           EXTRACT(MONTH FROM ADD_MONTHS(DATE '2024-01-01', LEVEL - 1)) AS mes,
           TO_CHAR(ADD_MONTHS(DATE '2024-01-01', LEVEL - 1), 'YYYY-MM') AS periodo
      FROM dual
   CONNECT BY LEVEL <= 36
),
hab_mun AS (
    -- Capacidad instalada fija por municipio (habitaciones y alojamientos)
    SELECT a.id_municipio,
           COUNT(DISTINCT a.id_alojamiento) AS total_alojamientos,
           COUNT(h.id_habitacion)           AS total_habitaciones
      FROM alojamiento a
      JOIN habitacion h ON h.id_alojamiento = a.id_alojamiento
     GROUP BY a.id_municipio
),
ocupacion AS (
    -- Intersección exacta de noches reservadas no canceladas por mes
    SELECT a.id_municipio,
           m.periodo,
           COUNT(DISTINCT r.id_reserva) AS total_reservas,
           SUM(LEAST(rh.fecha_checkout, m.mes_fin) - GREATEST(rh.fecha_checkin, m.mes_ini)) AS noches_ocupadas
      FROM meses m
      JOIN reserva_habitacion rh ON rh.fecha_checkin < m.mes_fin 
                                AND rh.fecha_checkout > m.mes_ini
      JOIN reserva r ON r.id_reserva = rh.id_reserva 
                    AND r.estado <> 'CANCELADA'
      JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
      JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
     GROUP BY a.id_municipio, m.periodo
)
SELECT mu.id_municipio,
       mu.nombre AS municipio,
       m.anio,
       m.mes,
       m.periodo,
       hm.total_alojamientos,
       hm.total_habitaciones,
       (m.mes_fin - m.mes_ini) AS dias_mes,
       (hm.total_habitaciones * (m.mes_fin - m.mes_ini)) AS noches_disponibles,
       NVL(o.total_reservas, 0) AS total_reservas,
       NVL(o.noches_ocupadas, 0) AS noches_ocupadas,
       ROUND(100 * NVL(o.noches_ocupadas, 0) / (hm.total_habitaciones * (m.mes_fin - m.mes_ini)), 2) AS tasa_ocupacion_pct
  FROM municipio mu
  JOIN hab_mun hm ON hm.id_municipio = mu.id_municipio
 CROSS JOIN meses m
  LEFT JOIN ocupacion o ON o.id_municipio = mu.id_municipio 
                       AND o.periodo = m.periodo
 ORDER BY m.periodo, mu.nombre;

-- Comentario descriptivo en el diccionario de datos
COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS 'Resumen precalculado de ocupacion mensual por municipio (2024-2026).';

-- =====================================================================
-- 2. ÍNDICES DE RENDIMIENTO SOBRE LA VISTA MATERIALIZADA
-- Permiten que los filtros por municipio, año o periodo resuelvan en O(log n).
-- =====================================================================
CREATE INDEX idx_mv_ocup_periodo ON mv_ocupacion_mensual (periodo);
CREATE INDEX idx_mv_ocup_muni    ON mv_ocupacion_mensual (id_municipio, anio, mes);


-- Pruebas

-- Verificar el registro de la vista en el diccionario de datos

SELECT mview_name,
       refresh_mode,
       refresh_method,
       build_mode,
       last_refresh_type,
       TO_CHAR(last_refresh_date, 'YYYY-MM-DD HH24:MI:SS') AS ultimo_refresco
  FROM user_mviews
 WHERE mview_name = 'MV_OCUPACION_MENSUAL';
 
-- Demostración del refresco manual bajo demanda

BEGIN
    -- Ejecución formal del refresco completo
    DBMS_MVIEW.REFRESH(
        list   => 'MV_OCUPACION_MENSUAL',
        method => 'C' -- C = Complete Refresh
    );
END;
/

-- Consulta directa sobre la vista

-- Muestra la ocupación de temporada alta (julio de 2025) en los municipios del Quindío
SELECT municipio,
       periodo,
       total_alojamientos,
       total_habitaciones,
       noches_disponibles,
       noches_ocupadas,
       tasa_ocupacion_pct || '%' AS ocupacion
  FROM mv_ocupacion_mensual
 WHERE periodo = '2025-07'
 ORDER BY tasa_ocupacion_pct DESC;
 
-- Demostración del PIVOT de C1 consumiendo directamente la Vista Materializada

SELECT *
  FROM (
        SELECT municipio,
               mes,
               tasa_ocupacion_pct
          FROM mv_ocupacion_mensual
         WHERE anio = 2025
       )
 PIVOT (
     MAX(tasa_ocupacion_pct)
     FOR mes IN (1 AS ene, 2 AS feb, 3 AS mar, 4 AS abr, 5 AS may, 6 AS jun,
                 7 AS jul, 8 AS ago, 9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic)
 )
 ORDER BY municipio;