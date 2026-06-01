SET DEFINE OFF;
SET SERVEROUTPUT ON;
SET VERIFY OFF;
SET FEEDBACK ON;

-- ============================================================
-- CASO 1
-- Proceso masivo de mailing y categorizacion de clientes
-- Empresa: LOGi y CARG
-- ============================================================


-- LIMPIEZA PREVIA DE LA TABLA RESULTANTE

TRUNCATE TABLE DETALLE_DE_CLIENTES;

-- ============================================================
-- VARIABLES BIND
-- ============================================================

VAR b_periodo_proceso VARCHAR2(6);
VAR b_mes_proceso     VARCHAR2(2);

EXEC :b_periodo_proceso := TO_CHAR(SYSDATE, 'MMYYYY');
EXEC :b_mes_proceso     := TO_CHAR(SYSDATE, 'MM');

-- ============================================================
-- BLOQUE PL/SQL ANONIMO
-- ============================================================

DECLARE

    -- --------------------------------------------------------
    -- Variables escalares
    -- --------------------------------------------------------
    v_total_clientes       NUMBER := 0;
    v_total_procesados     NUMBER := 0;
    v_total_insertados     NUMBER := 0;
    v_edad                 NUMBER := 0;
    v_anno_proceso         NUMBER(4);
    v_dia_nacimiento       VARCHAR2(2);

    -- --------------------------------------------------------
    -- Variables con %TYPE
    -- --------------------------------------------------------
    v_puntaje              DETALLE_DE_CLIENTES.puntaje%TYPE := 0;
    v_nombre_cliente       DETALLE_DE_CLIENTES.cliente%TYPE;
    v_correo_corp          DETALLE_DE_CLIENTES.correo_corp%TYPE;
    v_porcentaje_tramo     TRAMO_EDAD.porcentaje%TYPE := 0;

BEGIN

    DBMS_OUTPUT.PUT_LINE('PROCESANDO CLIENTES ...');

    -- ========================================================
    -- SENTENCIA SQL DOCUMENTADA
    -- ========================================================
    SELECT COUNT(*)
    INTO v_total_clientes
    FROM CLIENTE;

    -- Obtener el año del proceso desde el periodo MMYYYY
    v_anno_proceso := TO_NUMBER(SUBSTR(:b_periodo_proceso, 3, 4));


    FOR reg_cliente IN (
        SELECT c.id_cli,
               c.numrun_cli,
               c.dvrun_cli,
               c.appaterno_cli,
               c.apmaterno_cli,
               c.pnombre_cli,
               c.snombre_cli,
               c.renta,
               c.fecha_nac_cli,
               NVL(co.nombre_comuna, 'SIN COMUNA') AS nombre_comuna,
               tc.nombre_tipo_cli
        FROM CLIENTE c
        LEFT JOIN COMUNA co
            ON c.id_comuna = co.id_comuna
        JOIN TIPO_CLIENTE tc
            ON c.id_tipo_cli = tc.id_tipo_cli
        ORDER BY c.id_cli
    ) LOOP

        -- Reiniciar variables por cada cliente
        v_puntaje := 0;
        v_porcentaje_tramo := 0;

        -- Calcular edad en años completos
        IF reg_cliente.fecha_nac_cli IS NOT NULL THEN
            v_edad := TRUNC(MONTHS_BETWEEN(SYSDATE, reg_cliente.fecha_nac_cli) / 12);
            v_dia_nacimiento := TO_CHAR(reg_cliente.fecha_nac_cli, 'DD');
        ELSE
            v_edad := 0;
            v_dia_nacimiento := '00';
        END IF;


        v_nombre_cliente := INITCAP(
            TRIM(
                reg_cliente.appaterno_cli || ' ' ||
                NVL(reg_cliente.apmaterno_cli, '') || ' ' ||
                reg_cliente.pnombre_cli || ' ' ||
                NVL(reg_cliente.snombre_cli, '')
            )
        );

        IF reg_cliente.renta > 800000
           AND UPPER(TRIM(reg_cliente.nombre_comuna)) NOT IN
               ('LA REINA', 'LAS CONDES', 'VITACURA') THEN

            v_puntaje := ROUND(reg_cliente.renta * 0.03);

        ELSIF UPPER(TRIM(reg_cliente.nombre_tipo_cli)) IN
              ('VIP', 'INTERNACIONAL', 'EXTRANJERO') THEN

            v_puntaje := ROUND(v_edad * 30);

        END IF;

    
        IF v_puntaje = 0 THEN

            BEGIN

                SELECT porcentaje
                INTO v_porcentaje_tramo
                FROM TRAMO_EDAD
                WHERE anno_vig = v_anno_proceso
                  AND v_edad BETWEEN tramo_inf AND tramo_sup;

                v_puntaje := ROUND(reg_cliente.renta * v_porcentaje_tramo / 100);

            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_puntaje := 0;
            END;

        END IF;

        v_correo_corp :=
            LOWER(reg_cliente.appaterno_cli) ||
            v_edad ||
            '*' ||
            UPPER(SUBSTR(reg_cliente.pnombre_cli, 1, 1)) ||
            v_dia_nacimiento ||
            :b_mes_proceso ||
            '@LogiCarg.cl';

        -- ====================================================
        -- SENTENCIA DML DOCUMENTADA
        -- ====================================================
        INSERT INTO DETALLE_DE_CLIENTES
        (
            IDC,
            RUT,
            CLIENTE,
            EDAD,
            PUNTAJE,
            CORREO_CORP,
            PERIODO
        )
        VALUES
        (
            reg_cliente.id_cli,
            reg_cliente.numrun_cli,
            v_nombre_cliente,
            v_edad,
            v_puntaje,
            v_correo_corp,
            :b_periodo_proceso
        );

        -- Contadores para validar el proceso
        v_total_procesados := v_total_procesados + 1;
        v_total_insertados := v_total_insertados + SQL%ROWCOUNT;

    END LOOP;

    -- ========================================================
    -- VALIDACION FINAL DEL PROCESO
    -- ========================================================
    IF v_total_procesados = v_total_clientes
       AND v_total_insertados = v_total_clientes THEN

        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado Exitosamente');
        DBMS_OUTPUT.PUT_LINE('Se Procesaron : ' || v_total_procesados || ' CLIENTES');

    ELSE

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado con Errores');
        DBMS_OUTPUT.PUT_LINE('Clientes existentes : ' || v_total_clientes);
        DBMS_OUTPUT.PUT_LINE('Clientes procesados : ' || v_total_procesados);
        DBMS_OUTPUT.PUT_LINE('Se realiza ROLLBACK para no afectar la BBDD');

    END IF;

EXCEPTION

    WHEN OTHERS THEN

        ROLLBACK;

        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado con Errores');
        DBMS_OUTPUT.PUT_LINE('Detalle del error: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Se realiza ROLLBACK para no afectar la BBDD');

END;
/

-- ============================================================
-- CONSULTA DE VALIDACION DEL RESULTADO
-- ============================================================

SELECT IDC,
       RUT,
       CLIENTE,
       EDAD,
       PUNTAJE,
       CORREO_CORP,
       PERIODO
FROM DETALLE_DE_CLIENTES
ORDER BY IDC;