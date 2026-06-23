SET SERVEROUTPUT ON;

-- =========================================================
-- CASO 1 - DOLPHIN CONSULTING
-- =========================================================
DECLARE
    v_existe NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_existe
    FROM user_sequences
    WHERE sequence_name = 'SQ_ERRORES';

    IF v_existe = 0 THEN
        EXECUTE IMMEDIATE 'CREATE SEQUENCE SQ_ERRORES START WITH 1 INCREMENT BY 1 NOCACHE';
    END IF;
END;
/

-- =========================================================
-- VARIABLES BIND 
-- Fecha de proceso en formato MMYYYY
-- Límite máximo de asignaciones
-- =========================================================
VARIABLE b_fecha_proceso VARCHAR2(6);
VARIABLE b_monto_limite NUMBER;

EXEC :b_fecha_proceso := '062021';
EXEC :b_monto_limite := 250000;

-- =========================================================
-- BLOQUE PRINCIPAL CASO 1
-- =========================================================
DECLARE
    -- VARRAY con porcentajes de movilización extra:
    -- 1 Santiago = 2%
    -- 2 Ñuñoa = 4%
    -- 3 La Reina = 5%
    -- 4 La Florida = 7%
    -- 5 Macul = 9%
    TYPE t_porc_movil IS VARRAY(5) OF NUMBER;
    v_porc_movil t_porc_movil := t_porc_movil(2, 4, 5, 7, 9);

    -- Registro para almacenar los cálculos del profesional procesado
    TYPE t_reg_calculo IS RECORD (
        nro_asesorias              NUMBER(4),
        monto_honorarios           NUMBER(8),
        monto_movil_extra          NUMBER(8),
        monto_asig_tipocont        NUMBER(8),
        monto_asig_profesion       NUMBER(8),
        monto_total_asignaciones   NUMBER(8)
    );

    v_calculo t_reg_calculo;

    -- Variables de proceso
    v_mes_proceso       NUMBER(2);
    v_anno_proceso      NUMBER(4);
    v_anno_mes_proceso  NUMBER(6);
    v_fecha_inicio      DATE;
    v_fecha_fin         DATE;

    -- Variables para porcentajes obtenidos desde tablas
    v_incentivo_tpcont  tipo_contrato.incentivo%TYPE;
    v_porc_profesion    porcentaje_profesion.asignacion%TYPE;

    -- Variables auxiliares
    v_comuna            VARCHAR2(50);
    v_mensaje_oracle    VARCHAR2(300);
    v_mensaje_usuario   VARCHAR2(300);

    -- Excepción definida por el usuario para controlar tope de asignación
    e_tope_superado EXCEPTION;

    -- Excepción no predefinida asociada a ORA-01400
    e_valor_nulo EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_valor_nulo, -1400);

    -- Cursor sin parámetro.
    -- Obtiene solo datos básicos del profesional.
    CURSOR cur_profesionales IS
        SELECT p.numrun_prof,
               p.dvrun_prof,
               p.appaterno,
               p.nombre,
               p.cod_profesion,
               pr.nombre_profesion,
               p.cod_comuna,
               c.nom_comuna,
               p.cod_tpcontrato,
               p.sueldo
        FROM profesional p
        JOIN profesion pr
          ON pr.cod_profesion = p.cod_profesion
        JOIN comuna c
          ON c.cod_comuna = p.cod_comuna
        ORDER BY pr.nombre_profesion,
                 p.appaterno,
                 p.nombre;

BEGIN
    -- Se obtiene mes, año y período desde la variable BIND MMYYYY
    v_mes_proceso      := TO_NUMBER(SUBSTR(:b_fecha_proceso, 1, 2));
    v_anno_proceso     := TO_NUMBER(SUBSTR(:b_fecha_proceso, 3, 4));
    v_anno_mes_proceso := TO_NUMBER(SUBSTR(:b_fecha_proceso, 3, 4) ||
                                    SUBSTR(:b_fecha_proceso, 1, 2));

    v_fecha_inicio := TO_DATE('01' || :b_fecha_proceso, 'DDMMYYYY');
    v_fecha_fin    := ADD_MONTHS(v_fecha_inicio, 1);

    -- Se limpian las tablas solicitadas para permitir varias ejecuciones
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_asignacion_mes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_mes_profesion';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE errores_proceso';

    -- Se elimina y crea nuevamente la secuencia de errores
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE sq_errores';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE != -2289 THEN
                RAISE;
            END IF;
    END;

    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_errores START WITH 1 INCREMENT BY 1 NOCACHE';

    DBMS_OUTPUT.PUT_LINE('Inicio proceso Caso 1');
    DBMS_OUTPUT.PUT_LINE('Periodo proceso: ' || :b_fecha_proceso);
    DBMS_OUTPUT.PUT_LINE('Monto limite: ' || :b_monto_limite);

    -- Se procesan todos los profesionales
    FOR reg_prof IN cur_profesionales LOOP

        -- Inicialización de variables por cada profesional
        v_calculo.nro_asesorias            := 0;
        v_calculo.monto_honorarios         := 0;
        v_calculo.monto_movil_extra        := 0;
        v_calculo.monto_asig_tipocont      := 0;
        v_calculo.monto_asig_profesion     := 0;
        v_calculo.monto_total_asignaciones := 0;

        v_incentivo_tpcont := 0;
        v_porc_profesion   := 0;
        v_comuna           := UPPER(TRIM(reg_prof.nom_comuna));

        -- SELECT separado para contar asesorías y sumar honorarios
        SELECT COUNT(*),
               NVL(SUM(honorario), 0)
        INTO v_calculo.nro_asesorias,
             v_calculo.monto_honorarios
        FROM asesoria
        WHERE numrun_prof = reg_prof.numrun_prof
          AND inicio_asesoria >= v_fecha_inicio
          AND inicio_asesoria <  v_fecha_fin;

        -- Solo se insertan profesionales con asesorías en el período
        IF v_calculo.nro_asesorias > 0 THEN

            -- Cálculo de asignación por movilización extra usando VARRAY
            IF (reg_prof.cod_comuna = 82 OR v_comuna = 'SANTIAGO')
               AND v_calculo.monto_honorarios < 350000 THEN

                v_calculo.monto_movil_extra :=
                    ROUND(v_calculo.monto_honorarios * v_porc_movil(1) / 100);

            ELSIF INSTR(v_comuna, 'U') > 0
                  AND INSTR(v_comuna, 'OA') > 0 THEN

                v_calculo.monto_movil_extra :=
                    ROUND(v_calculo.monto_honorarios * v_porc_movil(2) / 100);

            ELSIF (reg_prof.cod_comuna = 85 OR v_comuna = 'LA REINA')
                  AND v_calculo.monto_honorarios < 400000 THEN

                v_calculo.monto_movil_extra :=
                    ROUND(v_calculo.monto_honorarios * v_porc_movil(3) / 100);

            ELSIF (reg_prof.cod_comuna = 86 OR v_comuna = 'LA FLORIDA')
                  AND v_calculo.monto_honorarios < 800000 THEN

                v_calculo.monto_movil_extra :=
                    ROUND(v_calculo.monto_honorarios * v_porc_movil(4) / 100);

            ELSIF (reg_prof.cod_comuna = 89 OR v_comuna = 'MACUL')
                  AND v_calculo.monto_honorarios < 680000 THEN

                v_calculo.monto_movil_extra :=
                    ROUND(v_calculo.monto_honorarios * v_porc_movil(5) / 100);

            ELSE
                v_calculo.monto_movil_extra := 0;
            END IF;

            -- SELECT separado para obtener incentivo por tipo de contrato
            BEGIN
                SELECT incentivo
                INTO v_incentivo_tpcont
                FROM tipo_contrato
                WHERE cod_tpcontrato = reg_prof.cod_tpcontrato;

                v_calculo.monto_asig_tipocont :=
                    ROUND(v_calculo.monto_honorarios * v_incentivo_tpcont / 100);

            EXCEPTION
                WHEN OTHERS THEN
                    v_mensaje_oracle := SUBSTR(SQLERRM, 1, 300);
                    v_mensaje_usuario := SUBSTR(
                        'Error al obtener incentivo de tipo de contrato para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );

                    v_calculo.monto_asig_tipocont := 0;
            END;

            -- SELECT separado para obtener porcentaje de asignación por profesión
            -- Se controla cualquier error Oracle y se asigna cero si falla.
            BEGIN
                SELECT asignacion
                INTO v_porc_profesion
                FROM porcentaje_profesion
                WHERE cod_profesion = reg_prof.cod_profesion;

                v_calculo.monto_asig_profesion :=
                    ROUND(reg_prof.sueldo * v_porc_profesion / 100);

            EXCEPTION
                WHEN OTHERS THEN
                    v_mensaje_oracle := SUBSTR(SQLERRM, 1, 300);
                    v_mensaje_usuario := SUBSTR(
                        'Error al obtener porcentaje de asignación para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );

                    v_calculo.monto_asig_profesion := 0;
            END;

            -- Cálculo total de asignaciones
            v_calculo.monto_total_asignaciones :=
                ROUND(v_calculo.monto_movil_extra
                    + v_calculo.monto_asig_tipocont
                    + v_calculo.monto_asig_profesion);

            -- Control de tope mediante excepción definida por el usuario
            BEGIN
                IF v_calculo.monto_total_asignaciones > :b_monto_limite THEN
                    RAISE e_tope_superado;
                END IF;

            EXCEPTION
                WHEN e_tope_superado THEN
                    v_mensaje_oracle := 'TOPE_SUPERADO';
                    v_mensaje_usuario := SUBSTR(
                        'Se reemplazó el monto total de las asignaciones calculadas de '
                        || v_calculo.monto_total_asignaciones
                        || ' por el monto límite de '
                        || :b_monto_limite
                        || ' para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );

                    v_calculo.monto_total_asignaciones := :b_monto_limite;
            END;

            -- Inserción del detalle mensual
            BEGIN
                INSERT INTO detalle_asignacion_mes (
                    mes_proceso,
                    anno_proceso,
                    run_profesional,
                    nombre_profesional,
                    profesion,
                    nro_asesorias,
                    monto_honorarios,
                    monto_movil_extra,
                    monto_asig_tipocont,
                    monto_asig_profesion,
                    monto_total_asignaciones
                )
                VALUES (
                    v_mes_proceso,
                    v_anno_proceso,
                    TO_CHAR(reg_prof.numrun_prof),
                    reg_prof.appaterno || ' ' || reg_prof.nombre,
                    reg_prof.nombre_profesion,
                    v_calculo.nro_asesorias,
                    v_calculo.monto_honorarios,
                    v_calculo.monto_movil_extra,
                    v_calculo.monto_asig_tipocont,
                    v_calculo.monto_asig_profesion,
                    v_calculo.monto_total_asignaciones
                );

            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN
                    v_mensaje_oracle := SUBSTR(SQLERRM, 1, 300);
                    v_mensaje_usuario := SUBSTR(
                        'Registro duplicado en DETALLE_ASIGNACION_MES para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );

                WHEN e_valor_nulo THEN
                    v_mensaje_oracle := SUBSTR(SQLERRM, 1, 300);
                    v_mensaje_usuario := SUBSTR(
                        'Valor nulo obligatorio al insertar detalle para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );

                WHEN OTHERS THEN
                    v_mensaje_oracle := SUBSTR(SQLERRM, 1, 300);
                    v_mensaje_usuario := SUBSTR(
                        'Error al insertar detalle para el run Nro. '
                        || reg_prof.numrun_prof, 1, 300
                    );

                    INSERT INTO errores_proceso
                    VALUES (
                        sq_errores.NEXTVAL,
                        v_mensaje_oracle,
                        v_mensaje_usuario
                    );
            END;

        END IF;

    END LOOP;

    -- Generación del resumen por profesión
    FOR reg_res IN (
        SELECT profesion
        FROM detalle_asignacion_mes
        GROUP BY profesion
        ORDER BY profesion
    ) LOOP

        SELECT SUM(nro_asesorias),
               SUM(monto_honorarios),
               SUM(monto_movil_extra),
               SUM(monto_asig_tipocont),
               SUM(monto_asig_profesion),
               SUM(monto_total_asignaciones)
        INTO v_calculo.nro_asesorias,
             v_calculo.monto_honorarios,
             v_calculo.monto_movil_extra,
             v_calculo.monto_asig_tipocont,
             v_calculo.monto_asig_profesion,
             v_calculo.monto_total_asignaciones
        FROM detalle_asignacion_mes
        WHERE profesion = reg_res.profesion;

        INSERT INTO resumen_mes_profesion (
            anno_mes_proceso,
            profesion,
            total_asesorias,
            monto_total_honorarios,
            monto_total_movil_extra,
            monto_total_asig_tipocont,
            monto_total_asig_prof,
            monto_total_asignaciones
        )
        VALUES (
            v_anno_mes_proceso,
            reg_res.profesion,
            v_calculo.nro_asesorias,
            v_calculo.monto_honorarios,
            v_calculo.monto_movil_extra,
            v_calculo.monto_asig_tipocont,
            v_calculo.monto_asig_profesion,
            v_calculo.monto_total_asignaciones
        );

    END LOOP;

    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');
    DBMS_OUTPUT.PUT_LINE('Detalle, resumen y errores generados.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error crítico del proceso: ' || SQLCODE || ' - ' || SQLERRM);
END;
/

-- =========================================================
-- SELECT de Comprobación
-- =========================================================

SELECT COUNT(*) AS total_detalle
FROM detalle_asignacion_mes;

SELECT COUNT(*) AS total_resumen
FROM resumen_mes_profesion;

SELECT COUNT(*) AS total_errores
FROM errores_proceso;

SELECT *
FROM detalle_asignacion_mes
ORDER BY profesion, nombre_profesional;

SELECT *
FROM resumen_mes_profesion
ORDER BY profesion;

SELECT *
FROM errores_proceso
ORDER BY error_id;