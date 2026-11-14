-- =====================================================================
-- 13_test_seguridad_diccionario.sql
-- Script de Verificación de Privilegios, Vistas y Restricciones
-- =====================================================================
-- NOTA IMPORTANTE:
-- Este script requiere conexión como SYSTEM o SYSDBA porque consulta
-- directamente las vistas administrativas del diccionario de datos:
-- DBA_ROLE_PRIVS, DBA_TAB_PRIVS y DBA_PROFILES.
-- =====================================================================

SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF

PROMPT =====================================================================
PROMPT 1. VERIFICACION DE ASIGNACION DE ROLES A USUARIOS (DBA_ROLE_PRIVS)
PROMPT =====================================================================
SELECT grantee AS usuario, granted_role AS rol_asignado, default_role
  FROM dba_role_privs
 WHERE grantee IN ('USR_RECEPCION_01', 'USR_ADMIN_01', 'USR_GERENTE_01', 'USR_AUDITOR_01')
 ORDER BY grantee;

PROMPT =====================================================================
PROMPT 2. VERIFICACION DE PRIVILEGIOS DE OBJETOS POR ROL (DBA_TAB_PRIVS)
PROMPT =====================================================================
SELECT grantee AS rol, table_name AS objeto, privilege AS privilegio
  FROM dba_tab_privs
 WHERE grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
 ORDER BY grantee, table_name;

PROMPT =====================================================================
PROMPT 3. DEMOSTRACION DE ACCESO EXCLUSIVO POR VISTAS PARA RECEPCION
PROMPT =====================================================================
-- A. Conexión como USR_RECEPCION_01
-- Consulta autorizada a través de la vista:
SELECT id_reserva, cliente_nombre, alojamiento, numero_habitacion, fecha_checkin, fecha_checkout, estado_reserva
  FROM v_recepcion_huespedes
 WHERE ROWNUM <= 5;

-- B. Intento de acceso a tabla base (DEBE FALLAR con ORA-00942: tabla o vista no existe)
PROMPT Intento de consulta directa a tabla base RESERVA (demostracion de bloqueo):
/*
CONNECT usr_recepcion_01/"TurismoUq2026#Recep"@localhost:1521/XEPDB1
SELECT * FROM reserva;
-- Salida: ORA-00942: table or view does not exist
*/

PROMPT =====================================================================
PROMPT 4. VERIFICACION DEL PERFIL perfil_recepcion (DBA_PROFILES)
PROMPT =====================================================================
SELECT profile, resource_name, limit
  FROM dba_profiles
 WHERE profile = 'PERFIL_RECEPCION'
   AND resource_name IN ('SESSIONS_PER_USER', 'IDLE_TIME', 'CONNECT_TIME', 
                         'FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME')
 ORDER BY resource_name;
