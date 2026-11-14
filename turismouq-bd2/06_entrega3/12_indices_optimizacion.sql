-- =====================================================================
-- 12_indices_optimizacion.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 3 - Subpunto 2.3: Índices y Optimización (25% + 15%)
-- =====================================================================
-- DECISIÓN ARQUITECTURAL:
-- 1. Se identifican 3 consultas críticas de la Entrega 1:
--    - Consulta Candidata 1 (E1 #1 / #3): Filtros y JOINs masivos sobre
--      RESERVA_HABITACION por id_habitacion y rango de fechas.
--    - Consulta Candidata 2 (E1 #4 / Pagos diarios): Agrupaciones por fecha de pago
--      aplicando TRUNC(fecha_pago) sobre 25.000 tuplas.
--    - Consulta Candidata 3 (E1 #2 / #3): JOIN recurrente entre RESERVA y ALOJAMIENTO
--      por estado y clave foránea id_alojamiento.
--
-- 2. ÍNDICE COMPUESTO:
--    idx_reshab_hab_fechas ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout)
--    Convierte un Full Table Scan (FTS) costoso sobre 25.000 filas en un INDEX RANGE SCAN
--    con acceso directo a las columnas del predicado sin necesidad de table lookup.
--
-- 3. ÍNDICE BASADO EN FUNCIÓN:
--    Se verifica columna defensivamente: la columna en PAGO es 'fecha_pago'.
--    idx_pago_trunc_fecha ON pago (TRUNC(fecha_pago))
--    Permite al optimizador de costos (CBO) resolver cláusulas WHERE TRUNC(fecha_pago) = :d
--    mediante INDEX RANGE SCAN, eliminando la degradación de evaluar la función por fila.
--
-- 4. ÍNDICE COMPUESTO DE ESTADO Y ALOJAMIENTO:
--    idx_reserva_aloj_estado ON reserva (id_alojamiento, estado)
--
-- 5. CASO DONDE EL ÍNDICE NO AYUDA (15%):
--    Se crea el índice idx_alojamiento_nombre ON alojamiento (nombre_comercial).
--    Escenario A: Búsqueda con comodín a la izquierda WHERE nombre_comercial LIKE '%Cabaña%'.
--                 El árbol B-tree requiere conocer el prefijo para navegar la raíz y ramas;
--                 al empezar en '%', el optimizador descarta el índice y hace FTS.
--    Escenario B: Filtro sobre columna de baja selectividad WHERE estado = 'COMPLETADA'
--                 en RESERVA (~68% de las filas tienen este valor). El CBO determina que leer
--                 vía índice + table access by index rowid cuesta mucho más que un FTS con multiblock read.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- 1. LIMPIEZA PREVENTIVA DE ÍNDICES DE LA ENTREGA 3
-- ---------------------------------------------------------------------
BEGIN
  FOR idx IN (SELECT index_name FROM user_indexes 
               WHERE index_name IN ('IDX_RESHAB_HAB_FECHAS', 
                                    'IDX_PAGO_TRUNC_FECHA', 
                                    'IDX_RESERVA_ALOJ_ESTADO', 
                                    'IDX_ALOJ_NOMBRE', 
                                    'IDX_RESERVA_ESTADO_BAJA_SEL')) LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || idx.index_name;
  END LOOP;
END;
/

-- ---------------------------------------------------------------------
-- 2. CREACIÓN DEL ÍNDICE COMPUESTO
-- Resuelve consultas de disponibilidad y solapes de habitaciones
-- ---------------------------------------------------------------------
CREATE INDEX idx_reshab_hab_fechas 
    ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout);

-- ---------------------------------------------------------------------
-- 3. CREACIÓN DEL ÍNDICE BASADO EN FUNCIÓN
-- Optimiza reportes y filtros agrupados por fecha contable sin hora
-- ---------------------------------------------------------------------
CREATE INDEX idx_pago_trunc_fecha 
    ON pago (TRUNC(fecha_pago));

-- ---------------------------------------------------------------------
-- 4. CREACIÓN DE ÍNDICE COMPUESTO ADICIONAL (FK + ESTADO)
-- Acelera los cruces de liquidación y los reportes gerenciales por alojamiento
-- ---------------------------------------------------------------------
CREATE INDEX idx_reserva_aloj_estado 
    ON reserva (id_alojamiento, estado);

-- ---------------------------------------------------------------------
-- 5. ÍNDICES PARA EL EXPERIMENTO DEL CASO "EL ÍNDICE NO AYUDA"
-- ---------------------------------------------------------------------
-- Índice sobre nombre comercial para evaluar el operador LIKE '%...'
CREATE INDEX idx_aloj_nombre 
    ON alojamiento (nombre_comercial);

-- Índice sobre columna de bajísima selectividad (dominada por pocos estados)
CREATE INDEX idx_reserva_estado_baja_sel 
    ON reserva (estado);

-- ---------------------------------------------------------------------
-- 6. RECOLECCIÓN DE ESTADÍSTICAS PARA EL OPTIMIZADOR BASADO EN COSTOS (CBO)
-- Garantiza que DBMS_XPLAN refleje planes basados en datos reales
-- ---------------------------------------------------------------------
BEGIN
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION', cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO',               cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA',            cascade => TRUE);
  DBMS_STATS.GATHER_TABLE_STATS(USER, 'ALOJAMIENTO',        cascade => TRUE);
END;
/
