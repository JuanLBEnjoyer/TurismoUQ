-- =====================================================================
-- 12_test_planes_ejecucion.sql
-- Comparativa de Planes de Ejecución (EXPLAIN PLAN + DBMS_XPLAN)
-- Antes vs Después y Demostración del "Índice que No Ayuda"
-- =====================================================================
-- ---------------------------------------------------------------------
-- NOTA METODOLOGICA:
-- Los hints NO_INDEX/INDEX se usan para garantizar la reproducibilidad
-- del plan "antes/despues" en una sola pasada. La mejora tambien se
-- valido ejecutando el script completo en dos fases: (1) sin indices
-- creados (fase ANTES con el CBO eligiendo FTS) y (2) con los indices
-- de 12_indices_optimizacion.sql creados (fase DESPUES con el CBO
-- eligiendo INDEX RANGE SCAN). Ambos metodos producen el mismo
-- diagnostico. Los hints son un atajo pedagogico, no una simulacion.
-- ---------------------------------------------------------------------

SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF

PROMPT =====================================================================
PROMPT CASO 1: ÍNDICE COMPUESTO SOBRE RESERVA_HABITACION(id_habitacion, fechas)
PROMPT Consulta de disponibilidad de una habitación en un rango de fechas
PROMPT =====================================================================

-- 1.A. PLAN ANTES (Simulado deshabilitando o ignorando el índice)
EXPLAIN PLAN SET STATEMENT_ID = 'ANTES_COMPUESTO' FOR
SELECT /*+ NO_INDEX(rh idx_reshab_hab_fechas) */ 
       id_reserva, id_habitacion, fecha_checkin, fecha_checkout
  FROM reserva_habitacion rh
 WHERE id_habitacion = 150
   AND fecha_checkin < DATE '2026-07-20'
   AND fecha_checkout > DATE '2026-07-10';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'ANTES_COMPUESTO', 'TYPICAL'));

-- 1.B. PLAN DESPUÉS (Usando el índice compuesto)
EXPLAIN PLAN SET STATEMENT_ID = 'DESPUES_COMPUESTO' FOR
SELECT /*+ INDEX(rh idx_reshab_hab_fechas) */ 
       id_reserva, id_habitacion, fecha_checkin, fecha_checkout
  FROM reserva_habitacion rh
 WHERE id_habitacion = 150
   AND fecha_checkin < DATE '2026-07-20'
   AND fecha_checkout > DATE '2026-07-10';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DESPUES_COMPUESTO', 'TYPICAL'));


PROMPT =====================================================================
PROMPT CASO 2: ÍNDICE BASADO EN FUNCIÓN SOBRE PAGO(TRUNC(fecha_pago))
PROMPT Búsqueda de pagos registrados en un día específico omitiendo componente de hora
PROMPT =====================================================================

-- 2.A. PLAN ANTES (Sin índice funcional)
EXPLAIN PLAN SET STATEMENT_ID = 'ANTES_FUNCIONAL' FOR
SELECT /*+ NO_INDEX(p idx_pago_trunc_fecha) */ 
       id_pago, id_reserva, monto, estado
  FROM pago p
 WHERE TRUNC(fecha_pago) = DATE '2026-01-15';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'ANTES_FUNCIONAL', 'TYPICAL'));

-- 2.B. PLAN DESPUÉS (Con índice funcional activo)
EXPLAIN PLAN SET STATEMENT_ID = 'DESPUES_FUNCIONAL' FOR
SELECT /*+ INDEX(p idx_pago_trunc_fecha) */ 
       id_pago, id_reserva, monto, estado
  FROM pago p
 WHERE TRUNC(fecha_pago) = DATE '2026-01-15';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'DESPUES_FUNCIONAL', 'TYPICAL'));


PROMPT =====================================================================
PROMPT CASO 3: ÍNDICE COMPUESTO SOBRE RESERVA(id_alojamiento, estado)
PROMPT Consulta de reportes por alojamiento y estado
PROMPT =====================================================================

-- 3.A. PLAN ANTES (Simulado deshabilitando el índice)
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_ANTES' FOR
SELECT /*+ NO_INDEX(r idx_reserva_aloj_estado) */ 
       id_reserva, fecha_checkin, estado
  FROM reserva r
 WHERE id_alojamiento = 1 
   AND estado = 'PENDIENTE';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_ANTES', 'TYPICAL'));

-- 3.B. PLAN DESPUÉS (Usando el índice compuesto)
EXPLAIN PLAN SET STATEMENT_ID = 'Q3_DESPUES' FOR
SELECT /*+ INDEX(r idx_reserva_aloj_estado) */ 
       id_reserva, fecha_checkin, estado
  FROM reserva r
 WHERE id_alojamiento = 1 
   AND estado = 'PENDIENTE';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'Q3_DESPUES', 'TYPICAL'));


PROMPT =====================================================================
PROMPT CASO 4 (15%): ESCENARIO DONDE EL ÍNDICE NO AYUDA Y ES IGNORADO POR EL CBO
PROMPT =====================================================================

PROMPT ---------------------------------------------------------------------
PROMPT Escenario A: Búsqueda no anclada a la izquierda (LIKE '%texto%')
PROMPT ---------------------------------------------------------------------
-- Aunque exista el índice idx_aloj_nombre sobre nombre_comercial,
-- la presencia de un wildcard inicial impide el recorrido por el árbol B-Tree.
EXPLAIN PLAN SET STATEMENT_ID = 'NO_AYUDA_LIKE' FOR
SELECT id_alojamiento, nombre_comercial, direccion
  FROM alojamiento
 WHERE nombre_comercial LIKE '%Campestre%';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'NO_AYUDA_LIKE', 'TYPICAL'));

PROMPT ---------------------------------------------------------------------
PROMPT Escenario B: Filtro sobre columna de muy baja selectividad
PROMPT ---------------------------------------------------------------------
-- El estado 'COMPLETADA' abarca más del 65% de la tabla RESERVA (25.000 tuplas).
-- El optimizador prefiere TABLE ACCESS FULL con I/O multirregistro
-- en lugar de leer miles de hojas del índice y hacer salto individual por ROWID.
EXPLAIN PLAN SET STATEMENT_ID = 'NO_AYUDA_BAJA_SEL' FOR
SELECT id_reserva, id_cliente, estado, fecha_checkin
  FROM reserva
 WHERE estado = 'COMPLETADA';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'NO_AYUDA_BAJA_SEL', 'TYPICAL'));
