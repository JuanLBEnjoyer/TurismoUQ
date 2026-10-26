-- =====================================================================
-- 02_carga_catalogos.sql
-- Proyecto Integrador TurismoUQ - Bases de Datos II (Univ. del Quindio)
-- Entrega 1 - Carga de datos : catalogos y oferta
-- =====================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- =====================================================================
-- BLOQUE A. TEMPORADAS
-- Cobertura continua del 2024-01-01 al 2026-12-31.
-- Se definen explicitamente los periodos ALTA; los tramos intermedios se
-- llenan alternando MEDIA y BAJA.
-- =====================================================================
DECLARE
  TYPE t_alta  IS RECORD (nombre VARCHAR2(80), ini DATE, fin DATE);
  TYPE t_altas IS TABLE OF t_alta INDEX BY PLS_INTEGER;
  v_altas t_altas;
  v_n     PLS_INTEGER := 0;
  v_cur   DATE := DATE '2024-01-01';
  c_fin   CONSTANT DATE := DATE '2026-12-31';
  v_gap   PLS_INTEGER := 0;

  PROCEDURE alta(p_nombre VARCHAR2, p_ini DATE, p_fin DATE) IS
  BEGIN
    v_n := v_n + 1;
    v_altas(v_n).nombre := p_nombre;
    v_altas(v_n).ini    := p_ini;
    v_altas(v_n).fin    := p_fin;
  END;

  PROCEDURE ins(p_nombre VARCHAR2, p_cat VARCHAR2, p_ini DATE, p_fin DATE) IS
  BEGIN
    INSERT INTO temporada (nombre, categoria, fecha_inicio, fecha_fin, anio)
    VALUES (p_nombre, p_cat, p_ini, p_fin, EXTRACT(YEAR FROM p_ini));
  END;

  PROCEDURE hueco(p_ini DATE, p_fin DATE) IS
    v_cat VARCHAR2(10);
  BEGIN
    v_gap := v_gap + 1;
    v_cat := CASE MOD(v_gap, 2) WHEN 1 THEN 'MEDIA' ELSE 'BAJA' END;
    ins('Temporada ' || INITCAP(v_cat) || ' ' || TO_CHAR(p_ini, 'YYYY-MM-DD'),
        v_cat, p_ini, p_fin);
  END;
BEGIN
  alta('Diciembre-enero 2023-2024',       DATE '2024-01-01', DATE '2024-01-10');
  alta('Semana Santa 2024',               DATE '2024-03-24', DATE '2024-03-31');
  alta('Puente festivo mayo 2024',        DATE '2024-05-11', DATE '2024-05-13');
  alta('Mitad de anio 2024',              DATE '2024-06-15', DATE '2024-07-14');
  alta('Puente festivo agosto 2024',      DATE '2024-08-17', DATE '2024-08-19');
  alta('Puente festivo octubre 2024',     DATE '2024-10-12', DATE '2024-10-14');
  alta('Puente festivo noviembre 2024',   DATE '2024-11-02', DATE '2024-11-04');
  alta('Diciembre-enero 2024-2025',       DATE '2024-12-14', DATE '2025-01-12');
  alta('Puente festivo San Jose 2025',    DATE '2025-03-22', DATE '2025-03-24');
  alta('Semana Santa 2025',               DATE '2025-04-13', DATE '2025-04-20');
  alta('Mitad de anio 2025',              DATE '2025-06-14', DATE '2025-07-13');
  alta('Puente festivo agosto 2025',      DATE '2025-08-16', DATE '2025-08-18');
  alta('Puente festivo octubre 2025',     DATE '2025-10-11', DATE '2025-10-13');
  alta('Puente festivo noviembre 2025',   DATE '2025-11-01', DATE '2025-11-03');
  alta('Diciembre-enero 2025-2026',       DATE '2025-12-13', DATE '2026-01-11');
  alta('Puente festivo San Jose 2026',    DATE '2026-03-21', DATE '2026-03-23');
  alta('Semana Santa 2026',               DATE '2026-03-29', DATE '2026-04-05');
  alta('Mitad de anio 2026',              DATE '2026-06-13', DATE '2026-07-12');
  alta('Puente festivo agosto 2026',      DATE '2026-08-15', DATE '2026-08-17');
  alta('Puente festivo octubre 2026',     DATE '2026-10-10', DATE '2026-10-12');
  alta('Puente festivo noviembre 2026',   DATE '2026-10-31', DATE '2026-11-02');
  alta('Diciembre-enero 2026-2027',       DATE '2026-12-12', DATE '2026-12-31');

  FOR i IN 1 .. v_n LOOP
    IF v_altas(i).ini > v_cur THEN
      hueco(v_cur, v_altas(i).ini - 1);
    END IF;
    ins(v_altas(i).nombre, 'ALTA', v_altas(i).ini, v_altas(i).fin);
    v_cur := v_altas(i).fin + 1;
  END LOOP;
  IF v_cur <= c_fin THEN
    hueco(v_cur, c_fin);
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Temporadas cargadas: ' || (v_n + v_gap)
                       || ' (' || v_n || ' altas + ' || v_gap || ' media/baja)');
END;
/

-- =====================================================================
-- BLOQUE B. CLIENTES (3.000)
-- Ciudades de origen variadas con pesos desiguales.
-- Documento y correo unicos por construccion.
-- =====================================================================
-- =====================================================================
-- BLOQUE B. CLIENTES (3.000)
-- =====================================================================
DECLARE
  c_semilla  CONSTANT PLS_INTEGER := 20330930;   
  c_clientes CONSTANT PLS_INTEGER := 3000;

  TYPE t_vc  IS TABLE OF VARCHAR2(80) INDEX BY PLS_INTEGER;
  TYPE t_num IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  v_nom t_vc;  v_ape t_vc;  v_dom t_vc;  v_ciu t_vc;
  v_peso t_num;
  v_peso_tot NUMBER := 0;
  v_n1 VARCHAR2(60); v_n2 VARCHAR2(60); v_a1 VARCHAR2(60); v_a2 VARCHAR2(60);
  v_nombre VARCHAR2(120);
  v_ciudad VARCHAR2(80);
  v_correo VARCHAR2(100);
  v_tel    VARCHAR2(20);

  FUNCTION rnd(p_lo PLS_INTEGER, p_hi PLS_INTEGER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
  END;

  PROCEDURE llenar(p_lista IN VARCHAR2, p_tab IN OUT NOCOPY t_vc) IS
    v_i PLS_INTEGER := 1;
    v_x VARCHAR2(80);
  BEGIN
    LOOP
      v_x := REGEXP_SUBSTR(p_lista, '[^,]+', 1, v_i);
      EXIT WHEN v_x IS NULL;
      p_tab(v_i) := TRIM(v_x);
      v_i := v_i + 1;
    END LOOP;
  END;

  PROCEDURE ciudad(p_nombre IN VARCHAR2, p_peso IN NUMBER) IS
    v_k PLS_INTEGER := v_ciu.COUNT + 1;
  BEGIN
    v_ciu(v_k)  := p_nombre;
    v_peso(v_k) := p_peso;
    v_peso_tot  := v_peso_tot + p_peso;
  END;

  FUNCTION pick_ciudad RETURN VARCHAR2 IS
    v_r    NUMBER := DBMS_RANDOM.VALUE(0, v_peso_tot);
    v_acum NUMBER := 0;
  BEGIN
    FOR i IN 1 .. v_ciu.COUNT LOOP
      v_acum := v_acum + v_peso(i);
      IF v_r < v_acum THEN RETURN v_ciu(i); END IF;
    END LOOP;
    RETURN v_ciu(v_ciu.COUNT);
  END;
BEGIN
  DBMS_RANDOM.SEED(c_semilla);

  llenar('Maria,Juan,Carlos,Luis,Ana,Sofia,Camila,Andres,Daniela,Jorge,Laura,Diego,'
      || 'Valentina,Santiago,Paula,Felipe,Natalia,Sebastian,Carolina,Alejandro,Juliana,'
      || 'David,Mariana,Nicolas,Luisa,Miguel,Andrea,Cristian,Manuela,Esteban,Gloria,'
      || 'Fernando,Claudia,Ricardo,Liliana,Hernan,Patricia,Oscar,Viviana,Mauricio', v_nom);
  llenar('Garcia,Rodriguez,Martinez,Lopez,Gonzalez,Perez,Sanchez,Ramirez,Torres,Florez,'
      || 'Duque,Ocampo,Arias,Cardona,Giraldo,Henao,Marin,Osorio,Quintero,Salazar,Valencia,'
      || 'Zapata,Restrepo,Gomez,Vargas,Castro,Moreno,Jimenez,Rojas,Herrera,Medina,Ortiz,'
      || 'Ramos,Suarez,Mejia,Londono,Bedoya,Parra,Cano,Agudelo', v_ape);
  llenar('gmail.com,gmail.com,gmail.com,hotmail.com,outlook.com,yahoo.com,uqvirtual.edu.co', v_dom);

  ciudad('Bogota', 22);         ciudad('Medellin', 12);
  ciudad('Cali', 9);            ciudad('Armenia', 12);
  ciudad('Pereira', 7);         ciudad('Manizales', 5);
  ciudad('Ibague', 4);          ciudad('Barranquilla', 3);
  ciudad('Bucaramanga', 3);     ciudad('Cartagena', 3);
  ciudad('Cucuta', 2);          ciudad('Neiva', 2);
  ciudad('Villavicencio', 2);   ciudad('Santa Marta', 2);
  ciudad('Popayan', 1);         ciudad('Pasto', 1);
  ciudad('Tulua', 2);           ciudad('Calarca', 2);
  ciudad('Montenegro', 1);      ciudad('La Tebaida', 1);
  ciudad('Miami (EE. UU.)', 1); ciudad('Madrid (Espana)', 1);
  ciudad('Buenos Aires (Argentina)', 1);

  FOR i IN 1 .. c_clientes LOOP
    v_n1 := v_nom(rnd(1, v_nom.COUNT));
    v_n2 := v_nom(rnd(1, v_nom.COUNT));
    v_a1 := v_ape(rnd(1, v_ape.COUNT));
    v_a2 := v_ape(rnd(1, v_ape.COUNT));
    v_nombre := v_n1 || CASE WHEN DBMS_RANDOM.VALUE < 0.35 THEN ' ' || v_n2 END
                     || ' ' || v_a1 || ' ' || v_a2;

    -- Evaluar TODO antes del INSERT --
    v_ciudad := pick_ciudad;
    v_correo := LOWER(v_n1 || '.' || v_a1 || i) || '@' || v_dom(rnd(1, v_dom.COUNT));
    v_tel    := '3' || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 1000000000))), 9, '0');

    INSERT INTO cliente (nombre, documento, correo, telefono, ciudad_origen)
    VALUES (
      v_nombre,
      TO_CHAR(1000000000 + i * 7919 + TRUNC(DBMS_RANDOM.VALUE(0, 7000))),
      v_correo,
      v_tel,
      v_ciudad
    );
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Clientes cargados: ' || c_clientes);
END;
/

-- =====================================================================
-- BLOQUE C. CATALOGOS, ALOJAMIENTOS, HABITACIONES, TARIFAS, SERVICIOS
--           Y USUARIOS INTERNOS
--
-- Reparto de alojamientos por municipio y tipo (orden:
-- Hotel, Hostal, Finca cafetera, Glamping, Casa campestre)
-- =====================================================================
DECLARE
  c_semilla CONSTANT PLS_INTEGER := 20345931;  

  TYPE t_vc  IS TABLE OF VARCHAR2(300) INDEX BY PLS_INTEGER;
  TYPE t_num IS TABLE OF NUMBER        INDEX BY PLS_INTEGER;

  v_mun_nom t_vc;  v_mun_comp t_vc;  v_mun_id t_num;
  v_tipo_nom t_vc; v_tipo_pref t_vc; v_tipo_id t_num; v_tipo_base t_num;
  v_pool t_vc;  v_vereda t_vc;  v_feat t_vc;  v_pers t_vc;
  v_svc_nom t_vc;  v_svc_desc t_vc;  v_svc_precio t_num;
  v_perm t_num;

  v_idx   PLS_INTEGER := 0;
  v_hotel PLS_INTEGER := 0;
  v_aloj  NUMBER;  v_hab NUMBER;
  v_nombre VARCHAR2(120);  v_slug VARCHAR2(120);  v_dir VARCHAR2(200);
  v_estr  PLS_INTEGER;  v_nhab PLS_INTEGER;  v_nsvc PLS_INTEGER;
  v_tipo_hab VARCHAR2(15);  v_cap PLS_INTEGER;  v_num VARCHAR2(10);
  v_fa NUMBER;  v_fm NUMBER;  v_fb NUMBER;
  v_base NUMBER;  v_rf NUMBER;  v_r NUMBER;
  v_j PLS_INTEGER;  v_tmp NUMBER;
  v_f1 PLS_INTEGER;  v_f2 PLS_INTEGER;
  v_rol_admin NUMBER;  v_rol_enc NUMBER;
  v_desc VARCHAR2(300);

  FUNCTION rnd(p_lo PLS_INTEGER, p_hi PLS_INTEGER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN TRUNC(DBMS_RANDOM.VALUE(p_lo, p_hi + 1));
  END;

  PROCEDURE llenar(p_lista IN VARCHAR2, p_tab IN OUT NOCOPY t_vc) IS
    v_i PLS_INTEGER := 1;
    v_x VARCHAR2(300);
  BEGIN
    LOOP
      v_x := REGEXP_SUBSTR(p_lista, '[^,]+', 1, v_i);
      EXIT WHEN v_x IS NULL;
      p_tab(v_i) := TRIM(v_x);
      v_i := v_i + 1;
    END LOOP;
  END;

  PROCEDURE servicio_cat(p_n PLS_INTEGER, p_nom VARCHAR2, p_desc VARCHAR2, p_precio NUMBER) IS
  BEGIN
    v_svc_nom(p_n) := p_nom;  v_svc_desc(p_n) := p_desc;  v_svc_precio(p_n) := p_precio;
  END;
BEGIN
  DBMS_RANDOM.SEED(c_semilla);

  -- ---------------- Catalogo de tipos de alojamiento ----------------
  v_tipo_nom(1) := 'Hotel';           v_tipo_pref(1) := 'Hotel';     v_tipo_base(1) := 130000;
  v_tipo_nom(2) := 'Hostal';          v_tipo_pref(2) := 'Hostal';    v_tipo_base(2) := 70000;
  v_tipo_nom(3) := 'Finca cafetera';  v_tipo_pref(3) := 'Finca';     v_tipo_base(3) := 140000;
  v_tipo_nom(4) := 'Glamping';        v_tipo_pref(4) := 'Glamping';  v_tipo_base(4) := 260000;
  v_tipo_nom(5) := 'Casa campestre';  v_tipo_pref(5) := 'Casa';      v_tipo_base(5) := 180000;
  FOR k IN 1 .. 5 LOOP
    INSERT INTO tipo_alojamiento (nombre) VALUES (v_tipo_nom(k))
    RETURNING id_tipo INTO v_tipo_id(k);
  END LOOP;

  -- ---------------- Catalogo de roles ----------------
  INSERT INTO rol (nombre, descripcion)
  VALUES ('ADMINISTRADOR', 'Administra la plataforma: catalogos, usuarios, temporadas y reportes')
  RETURNING id_rol INTO v_rol_admin;
  INSERT INTO rol (nombre, descripcion)
  VALUES ('ENCARGADO', 'Gestiona habitaciones, tarifas y reservas de su propio alojamiento')
  RETURNING id_rol INTO v_rol_enc;

  -- ---------------- Los 12 municipios del Quindio ----------------
  v_mun_nom(1)  := 'Armenia';           v_mun_comp(1)  := '6,3,1,1,1';
  v_mun_nom(2)  := 'Salento';           v_mun_comp(2)  := '1,2,4,3,0';
  v_mun_nom(3)  := 'Montenegro';        v_mun_comp(3)  := '2,1,3,1,1';
  v_mun_nom(4)  := 'Calarca';           v_mun_comp(4)  := '2,1,2,0,1';
  v_mun_nom(5)  := 'Quimbaya';          v_mun_comp(5)  := '2,0,3,1,0';
  v_mun_nom(6)  := 'Filandia';          v_mun_comp(6)  := '1,1,2,1,0';
  v_mun_nom(7)  := 'La Tebaida';        v_mun_comp(7)  := '2,0,1,0,1';
  v_mun_nom(8)  := 'Circasia';          v_mun_comp(8)  := '0,1,2,0,0';
  v_mun_nom(9)  := 'Pijao';             v_mun_comp(9)  := '0,0,1,1,0';
  v_mun_nom(10) := 'Cordoba';           v_mun_comp(10) := '0,1,1,0,0';
  v_mun_nom(11) := 'Genova';            v_mun_comp(11) := '0,0,1,0,0';
  v_mun_nom(12) := 'Buenavista';        v_mun_comp(12) := '0,0,1,0,0';
  FOR m IN 1 .. 12 LOOP
    INSERT INTO municipio (nombre) VALUES (v_mun_nom(m))
    RETURNING id_municipio INTO v_mun_id(m);
  END LOOP;

  -- ---------------- Listas de apoyo ----------------
  llenar('El Cafetal,La Esperanza,Villa Maria,El Mirador,La Palma,Buenavista,Los Naranjos,'
      || 'El Descanso,La Aurora,Las Acacias,El Paraiso,Monte Verde,La Cumbre,Los Guaduales,'
      || 'El Saman,La Primavera,El Roble,San Isidro,Las Palmas,El Bosque,La Cascada,Los Andes,'
      || 'El Recuerdo,La Pradera,El Encanto,Los Arrieros,El Carriel,La Mula,Rancho Grande,'
      || 'Alto Bonito,Sol Naciente,Aguas Claras,La Floresta,Los Cafetos,Tierra Linda,El Tesoro,'
      || 'Cielo Abierto,La Orquidea,Los Colibries,El Yarumo,La Guadua,San Alberto,'
      || 'Brisas del Quindio,Los Pinos,La Divisa,El Eden,El Retiro,Casa del Arriero,El Bambu,'
      || 'Rio Verde,La Tranquera,Hoja Verde,Cafe Dorado,Alma Cafetera,La Montana,'
      || 'Mirador del Valle,Villa Cocora,Las Camelias,El Girasol,Los Heliconios,La Pachamama,'
      || 'Colina Verde,Altos del Quindio,Vista Hermosa', v_pool);
  llenar('La Julia,Pueblo Tapao,El Rosario,La Montana,Barcelona,Pavas,Cocora,El Caimo,'
      || 'La Mariela,Santa Rita', v_vereda);
  llenar('vista a las montanas,balcon privado,ventilador,terraza,bano con agua caliente,'
      || 'vista al cafetal,zona de estar,jacuzzi', v_feat);
  llenar('Andres Felipe Ocampo,Luisa Fernanda Duque,Camilo Henao,Paola Andrea Marin,'
      || 'Julian Osorio,Natalia Quintero,Sebastian Salazar,Diana Marcela Valencia,'
      || 'Mateo Zapata,Valentina Restrepo,Oscar Arias,Sandra Cardona', v_pers);

  -- Catalogo de 12 servicios posibles; cada alojamiento ofrece un subconjunto
  servicio_cat(1,  'Desayuno tipico cafetero', 'Desayuno con arepa, huevos, chocolate y cafe de la region', 18000);
  servicio_cat(2,  'Tour guiado cafetero', 'Recorrido por cultivo y beneficio de cafe con degustacion', 85000);
  servicio_cat(3,  'Transporte al aeropuerto', 'Traslado ida o vuelta al Aeropuerto El Eden', 70000);
  servicio_cat(4,  'Alquiler de bicicletas', 'Bicicleta de montana por dia con casco', 30000);
  servicio_cat(5,  'Spa y masajes', 'Sesion de masaje relajante de 60 minutos', 120000);
  servicio_cat(6,  'Cena romantica', 'Cena para dos con decoracion y musica', 95000);
  servicio_cat(7,  'Cabalgata', 'Paseo a caballo guiado de dos horas', 60000);
  servicio_cat(8,  'Lavanderia', 'Servicio de lavado y planchado de ropa', 25000);
  servicio_cat(9,  'Tour Valle de Cocora', 'Excursion guiada con transporte al Valle de Cocora', 90000);
  servicio_cat(10, 'Caminata ecologica guiada', 'Caminata por senderos con guia local', 40000);
  servicio_cat(11, 'Almuerzo tipico', 'Bandeja paisa o trucha con bebida', 35000);
  servicio_cat(12, 'Decoracion para celebraciones', 'Decoracion de la habitacion para cumpleanos o aniversarios', 80000);

  -- ================= ALOJAMIENTOS (por municipio y tipo) =================
  FOR m IN 1 .. 12 LOOP
    FOR k IN 1 .. 5 LOOP
      FOR j IN 1 .. TO_NUMBER(TRIM(REGEXP_SUBSTR(v_mun_comp(m), '[^,]+', 1, k))) LOOP
        v_idx := v_idx + 1;
        IF k = 1 THEN v_hotel := v_hotel + 1; END IF;

        v_nombre := v_tipo_pref(k) || ' ' || v_pool(MOD(v_idx - 1, v_pool.COUNT) + 1);
        IF v_idx > v_pool.COUNT THEN v_nombre := v_nombre || ' ' || v_idx; END IF;
        v_slug := LOWER(REPLACE(v_pool(MOD(v_idx - 1, v_pool.COUNT) + 1), ' ', ''));

        v_estr := CASE k WHEN 1 THEN rnd(3, 5) WHEN 2 THEN rnd(1, 4) WHEN 3 THEN rnd(2, 5)
                         WHEN 4 THEN rnd(3, 5) ELSE rnd(2, 4) END;

        IF k IN (1, 2) THEN
          v_dir := CASE WHEN DBMS_RANDOM.VALUE < 0.5 THEN 'Carrera ' ELSE 'Calle ' END
                   || rnd(1, 30) || ' # ' || rnd(1, 60) || '-' || rnd(1, 99);
        ELSE
          v_dir := 'Vereda ' || v_vereda(rnd(1, v_vereda.COUNT)) || ', km ' || rnd(1, 15);
        END IF;

        INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, direccion,
                                 estrellas, telefono, correo_contacto)
        VALUES (v_mun_id(m), v_tipo_id(k), v_nombre, v_dir, v_estr,
                '3' || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE(0, 1000000000))), 9, '0'),
                'info@' || v_slug || '.com')
        RETURNING id_alojamiento INTO v_aloj;

        IF k = 1 THEN
          v_nhab := CASE WHEN v_hotel <= 4 THEN rnd(30, 40) ELSE rnd(10, 16) END;
        ELSIF k = 2 THEN v_nhab := rnd(8, 14);
        ELSIF k = 3 THEN v_nhab := rnd(3, 5);
        ELSIF k = 4 THEN v_nhab := rnd(4, 8);
        ELSE v_nhab := rnd(3, 5);
        END IF;

        v_fa := DBMS_RANDOM.VALUE(1.10, 1.65);
        v_fm := DBMS_RANDOM.VALUE(1.00, 1.15);
        v_fb := DBMS_RANDOM.VALUE(0.78, 0.95);

        -- ================= HABITACIONES + TARIFAS =================
        FOR i IN 1 .. v_nhab LOOP
          v_r := DBMS_RANDOM.VALUE;
          IF k = 1 THEN
            v_tipo_hab := CASE WHEN v_r < 0.30 THEN 'SENCILLA' WHEN v_r < 0.75 THEN 'DOBLE' ELSE 'SUITE' END;
          ELSIF k = 2 THEN
            v_tipo_hab := CASE WHEN v_r < 0.40 THEN 'SENCILLA' WHEN v_r < 0.90 THEN 'DOBLE' ELSE 'SUITE' END;
          ELSIF k = 3 THEN
            v_tipo_hab := CASE WHEN v_r < 0.40 THEN 'DOBLE' WHEN v_r < 0.80 THEN 'CABANA' ELSE 'SUITE' END;
          ELSIF k = 4 THEN
            v_tipo_hab := CASE WHEN v_r < 0.20 THEN 'DOBLE' WHEN v_r < 0.70 THEN 'CABANA' ELSE 'SUITE' END;
          ELSE
            v_tipo_hab := CASE WHEN v_r < 0.50 THEN 'CABANA' WHEN v_r < 0.80 THEN 'DOBLE' ELSE 'SUITE' END;
          END IF;

          IF v_tipo_hab = 'SENCILLA' THEN
            v_cap := rnd(1, 2);  v_rf := 1.0;  v_desc := 'Habitacion sencilla';
          ELSIF v_tipo_hab = 'DOBLE' THEN
            v_cap := rnd(2, 3);  v_rf := 1.4;  v_desc := 'Habitacion doble';
          ELSIF v_tipo_hab = 'SUITE' THEN
            v_cap := rnd(3, 5);  v_rf := 2.2;  v_desc := 'Suite';
          ELSE
            v_cap := rnd(3, 6);  v_rf := 1.8;  v_desc := 'Cabana independiente';
          END IF;
          v_f1 := rnd(1, v_feat.COUNT);
          v_f2 := MOD(v_f1 + rnd(1, v_feat.COUNT - 1) - 1, v_feat.COUNT) + 1;
          v_desc := v_desc || ' con ' || v_feat(v_f1) || ' y ' || v_feat(v_f2);

          IF k IN (1, 2) THEN
            v_num := TO_CHAR((TRUNC((i - 1) / 10) + 1) * 100 + MOD(i - 1, 10) + 1);
          ELSE
            v_num := CASE k WHEN 3 THEN 'H' WHEN 4 THEN 'G' ELSE 'C' END || i;
          END IF;

          INSERT INTO habitacion (id_alojamiento, numero, capacidad_max, tipo, descripcion)
          VALUES (v_aloj, v_num, v_cap, v_tipo_hab, v_desc)
          RETURNING id_habitacion INTO v_hab;

          v_base := ROUND(v_tipo_base(k) * v_rf * (0.70 + 0.15 * v_estr)
                          * DBMS_RANDOM.VALUE(0.90, 1.10), -3);

          INSERT INTO tarifa (id_habitacion, id_temporada, valor_noche)
          SELECT v_hab, t.id_temporada,
                 ROUND(v_base
                       * CASE t.categoria WHEN 'ALTA' THEN v_fa WHEN 'MEDIA' THEN v_fm ELSE v_fb END
                       * CASE WHEN t.nombre LIKE 'Semana Santa%' OR t.nombre LIKE 'Diciembre%'
                              THEN 1.08 ELSE 1 END
                       * DBMS_RANDOM.VALUE(0.96, 1.04), -3)
            FROM temporada t;
        END LOOP;

        -- ================= SERVICIOS del alojamiento =================
        v_nsvc := CASE k WHEN 1 THEN rnd(5, 7) WHEN 2 THEN rnd(3, 4) WHEN 3 THEN rnd(3, 5)
                         WHEN 4 THEN rnd(4, 6) ELSE rnd(3, 4) END;
        FOR s IN 1 .. 12 LOOP v_perm(s) := s; END LOOP;
        FOR s IN 1 .. v_nsvc LOOP
          v_j := rnd(s, 12);
          v_tmp := v_perm(s);  v_perm(s) := v_perm(v_j);  v_perm(v_j) := v_tmp;
          INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio)
          VALUES (v_aloj, v_svc_nom(v_perm(s)), v_svc_desc(v_perm(s)),
                  ROUND(v_svc_precio(v_perm(s)) * DBMS_RANDOM.VALUE(0.8, 1.3) / 500) * 500);
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  -- ================= USUARIOS INTERNOS =================
  -- 2 administradores y 10 encargados 
  FOR p IN 1 .. 2 LOOP
    INSERT INTO usuario_sistema (id_rol, id_alojamiento, nombre, correo)
    VALUES (v_rol_admin, NULL, v_pers(p),
            LOWER(REPLACE(v_pers(p), ' ', '.')) || '@turismouq.com');
  END LOOP;
  FOR p IN 3 .. 12 LOOP
    IF p <= 7 THEN
      SELECT id_alojamiento INTO v_aloj
        FROM alojamiento WHERE id_tipo = v_tipo_id(p - 2)
       ORDER BY DBMS_RANDOM.VALUE FETCH FIRST 1 ROW ONLY;
    ELSE
      SELECT id_alojamiento INTO v_aloj
        FROM alojamiento ORDER BY DBMS_RANDOM.VALUE FETCH FIRST 1 ROW ONLY;
    END IF;
    INSERT INTO usuario_sistema (id_rol, id_alojamiento, nombre, correo)
    VALUES (v_rol_enc, v_aloj, v_pers(p),
            LOWER(REPLACE(v_pers(p), ' ', '.')) || '@turismouq.com');
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Alojamientos cargados: ' || v_idx);
END;
/

-- =====================================================================
-- RESUMEN DE LA CARGA 
-- =====================================================================
SELECT 'MUNICIPIO' AS tabla, (SELECT COUNT(*) FROM municipio) AS filas, 12 AS minimo FROM dual
UNION ALL SELECT 'TIPO_ALOJAMIENTO', (SELECT COUNT(*) FROM tipo_alojamiento), 4 FROM dual
UNION ALL SELECT 'ROL',              (SELECT COUNT(*) FROM rol), 2 FROM dual
UNION ALL SELECT 'TEMPORADA',        (SELECT COUNT(*) FROM temporada), 6 FROM dual
UNION ALL SELECT 'CLIENTE',          (SELECT COUNT(*) FROM cliente), 3000 FROM dual
UNION ALL SELECT 'ALOJAMIENTO',      (SELECT COUNT(*) FROM alojamiento), 60 FROM dual
UNION ALL SELECT 'HABITACION',       (SELECT COUNT(*) FROM habitacion), 400 FROM dual
UNION ALL SELECT 'TARIFA',           (SELECT COUNT(*) FROM tarifa),
                                     (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada) FROM dual
UNION ALL SELECT 'SERVICIO',         (SELECT COUNT(*) FROM servicio), 30 FROM dual
UNION ALL SELECT 'USUARIO_SISTEMA',  (SELECT COUNT(*) FROM usuario_sistema), 10 FROM dual;

-- Asimetria: alojamientos y habitaciones por municipio
SELECT m.nombre AS municipio, COUNT(DISTINCT a.id_alojamiento) AS alojamientos,
       COUNT(h.id_habitacion) AS habitaciones
  FROM municipio m
  LEFT JOIN alojamiento a ON a.id_municipio = m.id_municipio
  LEFT JOIN habitacion h  ON h.id_alojamiento = a.id_alojamiento
 GROUP BY m.nombre
 ORDER BY habitaciones DESC;

-- Cobertura de temporadas: debe dar 1096 dias y 0 traslapes
SELECT SUM(fecha_fin - fecha_inicio + 1) AS dias_cubiertos FROM temporada;

SELECT COUNT(*) AS traslapes_temporada
  FROM temporada a JOIN temporada b
    ON a.id_temporada < b.id_temporada
   AND a.fecha_inicio <= b.fecha_fin AND a.fecha_fin >= b.fecha_inicio;