-- =====================================================================
-- 13_seguridad_roles_perfil.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 3 - Subpunto 2.4: Seguridad, Roles, Perfiles y Vistas (25%)
-- =====================================================================
-- DECISIÓN ARQUITECTURAL:
-- 1. Se crean los 4 roles diferenciados a nivel de base de datos en Oracle:
--    - ROL_RECEPCION: Opera exclusivamente a través de VISTAS; NUNCA accede a tablas base.
--    - ROL_ADMIN_ALOJAMIENTO: DML y gestión sobre su alojamiento, habitaciones y tarifas.
--    - ROL_GERENTE: Lectura analítica consolidada, vistas materializadas y reportes gerenciales.
--    - ROL_AUDITOR: Lectura de tablas de auditoría, logs transaccionales y reservas.
--
-- 2. VISTAS DEDICADAS PARA RECEPCIÓN:
--    - v_recepcion_huespedes: Agenda operativa diaria con datos de cliente y habitación.
--    - v_recepcion_habitaciones: Consulta de habitaciones sin exponer tarifas internas.
--    - v_recepcion_estado_cuenta: Vista consolidada sin duplicación para pagos agregados.
--
-- 3. PERFIL perfil_recepcion:
--    - SESSIONS_PER_USER = 2 (evita uso simultáneo no autorizado en múltiples terminales)
--    - IDLE_TIME = 15 (cierre automático tras 15 minutos de inactividad)
--    - CONNECT_TIME = 480 (máximo 8 horas por turno operativo)
--    - FAILED_LOGIN_ATTEMPTS = 3 (bloqueo preventivo ante fuerza bruta)
--    - PASSWORD_LOCK_TIME = 1 (bloqueo por 1 día si falla intentos)
--
-- 4. USUARIOS DE PRUEBA ASIGNADOS A SUS RESPECTIVOS ROLES.
-- =====================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ---------------------------------------------------------------------
-- 0. VERIFICACIÓN DEFENSIVA DE PRIVILEGIOS DE EJECUCIÓN (SYSTEM / SYSDBA)
-- ---------------------------------------------------------------------
DECLARE
  v_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_n FROM user_role_privs WHERE granted_role IN ('DBA','SYSDBA');
  IF v_n = 0 THEN
    RAISE_APPLICATION_ERROR(-20100, 'Este script DEBE ejecutarse como SYSTEM o SYSDBA.');
  END IF;
END;
/

-- ---------------------------------------------------------------------
-- 1. LIMPIEZA PREVENTIVA DE SEGURIDAD (ROLES, USUARIOS, VISTAS, PERFIL)
-- ---------------------------------------------------------------------
BEGIN
  -- Eliminar usuarios de prueba si existen
  FOR u IN (SELECT username FROM all_users 
             WHERE username IN ('USR_RECEPCION_01', 'USR_ADMIN_01', 'USR_GERENTE_01', 'USR_AUDITOR_01')) LOOP
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;

  -- Eliminar roles si existen
  FOR r IN (SELECT role FROM dba_roles 
             WHERE role IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')) LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;

  -- Eliminar perfil si existe
  FOR p IN (SELECT profile FROM dba_profiles WHERE profile = 'PERFIL_RECEPCION' AND ROWNUM = 1) LOOP
    EXECUTE IMMEDIATE 'DROP PROFILE PERFIL_RECEPCION CASCADE';
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
/

-- ---------------------------------------------------------------------
-- 2. CREACIÓN DEL PERFIL CON LÍMITES DE RECURSOS Y CONTRASEÑA
-- ---------------------------------------------------------------------
CREATE PROFILE perfil_recepcion LIMIT
    SESSIONS_PER_USER          2
    IDLE_TIME                  15
    CONNECT_TIME               480
    FAILED_LOGIN_ATTEMPTS      3
    PASSWORD_LIFE_TIME         60
    PASSWORD_LOCK_TIME         1;

-- ---------------------------------------------------------------------
-- 3. CREACIÓN DE LOS 4 ROLES
-- ---------------------------------------------------------------------
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

-- ---------------------------------------------------------------------
-- 4. CREACIÓN DE VISTAS DEDICADAS PARA RECEPCIÓN (ACCESO INDIRECTO)
-- ---------------------------------------------------------------------
-- Vista 1: Flujo operativo diario de huéspedes para Check-in y Check-out
CREATE OR REPLACE VIEW v_recepcion_huespedes AS
SELECT 
    r.id_reserva,
    c.id_cliente,
    c.nombre             AS cliente_nombre,
    c.documento          AS cliente_documento,
    c.telefono           AS cliente_telefono,
    a.nombre_comercial   AS alojamiento,
    h.numero             AS numero_habitacion,
    h.tipo               AS tipo_habitacion,
    rh.fecha_checkin,
    rh.fecha_checkout,
    rh.num_huespedes,
    r.estado             AS estado_reserva
FROM reserva r
JOIN cliente c ON c.id_cliente = r.id_cliente
JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
JOIN habitacion h ON h.id_habitacion = rh.id_habitacion;

-- Vista 2: Habitaciones y capacidades operativas
CREATE OR REPLACE VIEW v_recepcion_habitaciones AS
SELECT 
    h.id_habitacion,
    a.nombre_comercial AS alojamiento,
    h.numero,
    h.tipo,
    h.capacidad_max,
    h.descripcion
FROM habitacion h
JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
WHERE a.estado = 'ACTIVO';

-- Vista 3: Estado consolidado de cuenta por reserva
CREATE OR REPLACE VIEW v_recepcion_estado_cuenta AS
SELECT r.id_reserva,
       r.id_cliente,
       r.estado AS estado_reserva,
       NVL(SUM(p.monto), 0) AS monto_pagado,
       LISTAGG(DISTINCT p.metodo, ',') WITHIN GROUP (ORDER BY p.metodo) AS metodos,
       CASE WHEN SUM(CASE WHEN p.estado = 'EXITOSO' THEN 1 ELSE 0 END) > 0
            THEN 'PAGADO' ELSE 'SIN_PAGO' END AS estado_pago
  FROM reserva r
  LEFT JOIN pago p ON p.id_reserva = r.id_reserva
 GROUP BY r.id_reserva, r.id_cliente, r.estado;

-- ---------------------------------------------------------------------
-- 5. ASIGNACIÓN DE PRIVILEGIOS A LOS ROLES
-- ---------------------------------------------------------------------

-- A. ROL_RECEPCION: Accede ÚNICAMENTE a través de vistas y ejecución de reservas
GRANT CREATE SESSION TO rol_recepcion;
GRANT SELECT ON v_recepcion_huespedes     TO rol_recepcion;
GRANT SELECT ON v_recepcion_habitaciones  TO rol_recepcion;
GRANT SELECT ON v_recepcion_estado_cuenta TO rol_recepcion;
GRANT EXECUTE ON pkg_turismouq            TO rol_recepcion;

-- B. ROL_ADMIN_ALOJAMIENTO: Gestión de inventario de habitaciones y tarifas
GRANT CREATE SESSION TO rol_admin_alojamiento;
GRANT SELECT, UPDATE ON alojamiento   TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON habitacion    TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON tarifa        TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON servicio      TO rol_admin_alojamiento;
GRANT SELECT ON reserva             TO rol_admin_alojamiento;
GRANT SELECT ON reserva_habitacion  TO rol_admin_alojamiento;

-- C. ROL_GERENTE: Inteligencia de negocios, reportes, vistas materializadas y consultas
GRANT CREATE SESSION TO rol_gerente;
GRANT SELECT ON municipio            TO rol_gerente;
GRANT SELECT ON tipo_alojamiento     TO rol_gerente;
GRANT SELECT ON alojamiento          TO rol_gerente;
GRANT SELECT ON reserva              TO rol_gerente;
GRANT SELECT ON reserva_habitacion   TO rol_gerente;
GRANT SELECT ON pago                 TO rol_gerente;
GRANT SELECT ON resena               TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;
GRANT EXECUTE ON pkg_turismouq       TO rol_gerente;

-- D. ROL_AUDITOR: Auditoría de seguridad y trazabilidad contable
GRANT CREATE SESSION TO rol_auditor;
GRANT SELECT ON auditoria_tarifa        TO rol_auditor;
GRANT SELECT ON log_transaccion_reserva TO rol_auditor;
GRANT SELECT ON reserva_historico       TO rol_auditor;
GRANT SELECT ON pago                    TO rol_auditor;
GRANT SELECT ON reserva                 TO rol_auditor;

-- ---------------------------------------------------------------------
-- 6. CREACIÓN DE USUARIOS DE PRUEBA Y ASIGNACIÓN DE PERFILES Y ROLES
-- ---------------------------------------------------------------------
-- Usuario de Recepción con perfil restringido
CREATE USER usr_recepcion_01 IDENTIFIED BY "TurismoUq2026#Recep"
    PROFILE perfil_recepcion
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;

GRANT rol_recepcion TO usr_recepcion_01;
ALTER USER usr_recepcion_01 DEFAULT ROLE rol_recepcion;

-- Usuario Administrador de Alojamiento
CREATE USER usr_admin_01 IDENTIFIED BY "TurismoUq2026#Admin"
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;

GRANT rol_admin_alojamiento TO usr_admin_01;
ALTER USER usr_admin_01 DEFAULT ROLE rol_admin_alojamiento;

-- Usuario Gerente
CREATE USER usr_gerente_01 IDENTIFIED BY "TurismoUq2026#Gerente"
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;

GRANT rol_gerente TO usr_gerente_01;
ALTER USER usr_gerente_01 DEFAULT ROLE rol_gerente;

-- Usuario Auditor
CREATE USER usr_auditor_01 IDENTIFIED BY "TurismoUq2026#Auditor"
    DEFAULT TABLESPACE users
    TEMPORARY TABLESPACE temp;

GRANT rol_auditor TO usr_auditor_01;
ALTER USER usr_auditor_01 DEFAULT ROLE rol_auditor;

-- ---------------------------------------------------------------------
-- 7. NOTA SOBRE UNICIDAD DE RESENA
-- La unicidad de resena por cliente + alojamiento se garantiza mediante
-- el trigger TRG_VALIDA_RESENA_UNICA definido en 14_ajustes_resena.sql.
-- No se implementa con un UNIQUE constraint porque id_cliente vive en
-- RESERVA (tabla separada de RESENA) y un UK no puede abarcar un JOIN.
-- ---------------------------------------------------------------------
