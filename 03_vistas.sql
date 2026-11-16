/* =====================================================================
   TP Ingeniería de Datos - "Salud Corporativa del Sur S.A."
   Script 03: VISTAS (queries 1, 2 y 3 de 10)
   Ejecutar después de los scripts 01 y 02.

   ¿Qué es una vista?
   Es un SELECT guardado con nombre. No guarda datos: cada vez que se
   consulta, el motor vuelve a ejecutar el SELECT con los datos actuales.
   Sirve para:
     - esconder JOINs complicados (el usuario consulta la vista como si
       fuera una tabla),
     - calcular datos derivados sin guardarlos (el importe de cada atención),
     - dar acceso a ciertas columnas sin mostrar la tabla completa.
   ===================================================================== */

USE SaludCorporativa;
GO

/* ---------------------------------------------------------------------
   VISTA 1: vw_AgendaTurnos
   Para qué: la operadora necesita ver cada turno "completo" (paciente,
   obra social, profesional, especialidad, móvil y hospital) sin escribir
   6 JOINs cada vez. Es la tabla 0 "reconstruida" a partir de las tablas
   normalizadas: muestra que normalizar no pierde información.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_AgendaTurnos
AS
SELECT
    t.nro_turno,
    t.fecha,
    t.hora,
    t.tipo_servicio,
    t.estado,
    t.domicilio_atencion,
    p.apellido + ', ' + p.nombre        AS paciente,     -- se concatena para mostrar, no se guarda junto
    p.dni,
    os.nombre                           AS obra_social,
    pr.apellido + ', ' + pr.nombre      AS profesional,
    e.nombre                            AS especialidad,
    m.patente + ' (' + m.tipo + ')'     AS movil,
    -- ISNULL: si no es traslado, cod_hospital es NULL y se muestra un guion.
    ISNULL(h.nombre, '-')               AS hospital_destino
FROM Turno t
    INNER JOIN Paciente     p  ON p.dni              = t.dni_paciente
    INNER JOIN ObraSocial   os ON os.cod_obra_social = p.cod_obra_social
    INNER JOIN Profesional  pr ON pr.matricula       = t.matricula
    INNER JOIN Especialidad e  ON e.id_especialidad  = pr.id_especialidad
    INNER JOIN Movil        m  ON m.patente          = t.patente
    -- LEFT JOIN y no INNER: con INNER se perderían todos los turnos
    -- sin hospital (visitas y enfermería), porque no tienen pareja en Hospital.
    LEFT  JOIN Hospital     h  ON h.cod_hospital     = t.cod_hospital;
GO

-- Uso: agenda de los turnos que todavía no se hicieron, ordenada por fecha.
SELECT nro_turno, fecha, hora, tipo_servicio, paciente, profesional, movil, hospital_destino
FROM vw_AgendaTurnos
WHERE estado = 'Programado'
ORDER BY fecha, hora;
GO


/* ---------------------------------------------------------------------
   VISTA 2: vw_ImportePorTurno
   Para qué: calcular cuánto vale cada atención y cómo se reparte entre la
   obra social y el paciente. Es el dato derivado que decidimos NO guardar
   en una tabla (ver la nota al final del script 01).

     importe_visita    = valor_visita de la especialidad del profesional
     importe_practicas = suma de (precio * cantidad) de las prácticas del turno
     importe_total     = importe_visita + importe_practicas
     a_cargo_obra_social = importe_total * porcentaje_cobertura / 100
     a_cargo_paciente    = importe_total - a_cargo_obra_social

   Solo cuentan los turnos 'Atendido': un turno cancelado o ausente no se cobra.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_ImportePorTurno
AS
SELECT
    t.nro_turno,
    t.fecha,
    t.tipo_servicio,
    t.dni_paciente,
    os.cod_obra_social,
    os.nombre                    AS obra_social,
    os.porcentaje_cobertura,
    e.valor_visita               AS importe_visita,
    -- ISNULL(..., 0): un turno sin prácticas da NULL en el LEFT JOIN, y
    -- NULL + número = NULL. Con ISNULL lo convertimos en 0.
    ISNULL(SUM(pa.precio * tp.cantidad), 0)                     AS importe_practicas,
    e.valor_visita + ISNULL(SUM(pa.precio * tp.cantidad), 0)    AS importe_total,
    CAST((e.valor_visita + ISNULL(SUM(pa.precio * tp.cantidad), 0))
         * os.porcentaje_cobertura / 100 AS DECIMAL(12,2))      AS a_cargo_obra_social,
    CAST((e.valor_visita + ISNULL(SUM(pa.precio * tp.cantidad), 0))
         * (100 - os.porcentaje_cobertura) / 100 AS DECIMAL(12,2)) AS a_cargo_paciente
FROM Turno t
    INNER JOIN Paciente      p  ON p.dni              = t.dni_paciente
    INNER JOIN ObraSocial    os ON os.cod_obra_social = p.cod_obra_social
    INNER JOIN Profesional   pr ON pr.matricula       = t.matricula
    INNER JOIN Especialidad  e  ON e.id_especialidad  = pr.id_especialidad
    -- LEFT JOIN: hay atenciones sin prácticas (solo la visita) y también se cobran.
    LEFT  JOIN TurnoPractica tp ON tp.nro_turno       = t.nro_turno
    LEFT  JOIN Practica      pa ON pa.cod_practica    = tp.cod_practica
WHERE t.estado = 'Atendido'
-- GROUP BY: se agrupa por turno para sumar todas sus prácticas en una sola fila.
-- Todas las columnas del SELECT que no están dentro de SUM tienen que estar acá.
GROUP BY t.nro_turno, t.fecha, t.tipo_servicio, t.dni_paciente,
         os.cod_obra_social, os.nombre, os.porcentaje_cobertura, e.valor_visita;
GO

-- Uso: detalle del importe de cada atención realizada.
SELECT nro_turno, fecha, tipo_servicio, obra_social, importe_visita,
       importe_practicas, importe_total, a_cargo_obra_social, a_cargo_paciente
FROM vw_ImportePorTurno
ORDER BY nro_turno;
GO


/* ---------------------------------------------------------------------
   VISTA 3: vw_FacturacionObraSocial
   Para qué: es la "factura" mensual que la empresa le pasa a cada obra
   social. Se arma ENCIMA de la vista 2 (una vista puede usar otra vista),
   así la fórmula del importe está escrita en un solo lugar: si cambia,
   se corrige en vw_ImportePorTurno y esta vista se actualiza sola.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_FacturacionObraSocial
AS
SELECT
    cod_obra_social,
    obra_social,
    YEAR(fecha)                  AS anio,
    MONTH(fecha)                 AS mes,
    COUNT(*)                     AS cantidad_atenciones,
    SUM(importe_total)           AS importe_total,
    SUM(a_cargo_obra_social)     AS total_a_facturar,     -- lo que paga la obra social
    SUM(a_cargo_paciente)        AS total_copagos         -- lo que pagan los pacientes
FROM vw_ImportePorTurno
GROUP BY cod_obra_social, obra_social, YEAR(fecha), MONTH(fecha);
GO

-- Uso: cuánto hay que facturarle a cada obra social en octubre de 2026.
SELECT obra_social, cantidad_atenciones, importe_total, total_a_facturar, total_copagos
FROM vw_FacturacionObraSocial
WHERE anio = 2026 AND mes = 10
ORDER BY total_a_facturar DESC;
GO
