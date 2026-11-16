/* =====================================================================
   TP Ingeniería de Datos - "Salud Corporativa del Sur S.A."
   Script 04: CONSULTAS CON SUBCONSULTAS (queries 4 y 5 de 10)
   Ejecutar después del script 03 (la segunda consulta usa una vista).

   Una subconsulta es un SELECT dentro de otro SELECT. Se usa cuando para
   responder la pregunta primero hay que calcular otro dato (un promedio,
   una lista de códigos) y después comparar contra ese resultado.
   ===================================================================== */

USE SaludCorporativa;
GO

/* ---------------------------------------------------------------------
   QUERY 4: Profesionales con MÁS turnos asignados que el promedio.
   Pregunta de negocio: ¿quiénes son los profesionales con más carga de
   trabajo? Sirve para repartir mejor los turnos. Se cuentan todos los
   turnos asignados (hechos y por hacer) menos los cancelados.

   Cómo funciona:
   - La consulta de afuera cuenta los turnos de cada profesional.
   - La subconsulta (en el HAVING) calcula el promedio de turnos por
     profesional. Tiene a su vez una subconsulta en el FROM (tabla derivada
     "x") porque primero hay que contar por profesional y recién después
     promediar esos conteos: no se puede hacer AVG(COUNT(*)) directo.
   - Se compara en el HAVING y no en el WHERE porque el WHERE filtra filas
     ANTES de agrupar, y el COUNT recién existe DESPUÉS del GROUP BY.
   - "* 1.0" fuerza decimales: sin eso, el promedio de enteros se trunca.
   --------------------------------------------------------------------- */
SELECT
    pr.matricula,
    pr.apellido + ', ' + pr.nombre  AS profesional,
    e.nombre                        AS especialidad,
    COUNT(*)                        AS turnos_asignados
FROM Turno t
    INNER JOIN Profesional  pr ON pr.matricula      = t.matricula
    INNER JOIN Especialidad e  ON e.id_especialidad = pr.id_especialidad
WHERE t.estado <> 'Cancelado'
GROUP BY pr.matricula, pr.apellido, pr.nombre, e.nombre
HAVING COUNT(*) > (
        SELECT AVG(x.cant * 1.0)
        FROM (  SELECT matricula, COUNT(*) AS cant
                FROM Turno
                WHERE estado <> 'Cancelado'
                GROUP BY matricula ) AS x
       )
ORDER BY turnos_asignados DESC;
GO


/* ---------------------------------------------------------------------
   QUERY 5: Atenciones cuyo importe supera el promedio de SU tipo de servicio.
   Pregunta de negocio: ¿qué atenciones salieron más caras de lo normal?
   Una visita médica no se compara contra un traslado (que siempre es más
   caro), sino contra el promedio de las otras visitas médicas.

   Cómo funciona: es una subconsulta CORRELACIONADA. La subconsulta usa
   "i.tipo_servicio" de la fila de afuera, así que el motor la vuelve a
   calcular para cada fila: para cada atención calcula el promedio de su
   propio tipo de servicio y compara.
   --------------------------------------------------------------------- */
SELECT
    i.nro_turno,
    i.fecha,
    i.tipo_servicio,
    p.apellido + ', ' + p.nombre  AS paciente,
    i.obra_social,
    i.importe_total,
    i.a_cargo_paciente,
    -- La misma subconsulta en el SELECT, para mostrar contra qué promedio se comparó.
    (SELECT CAST(AVG(i2.importe_total) AS DECIMAL(12,2))
       FROM vw_ImportePorTurno i2
      WHERE i2.tipo_servicio = i.tipo_servicio)  AS promedio_del_servicio
FROM vw_ImportePorTurno i
    INNER JOIN Paciente p ON p.dni = i.dni_paciente
WHERE i.importe_total > (
        SELECT AVG(i2.importe_total)
        FROM vw_ImportePorTurno i2
        WHERE i2.tipo_servicio = i.tipo_servicio     -- correlación con la fila de afuera
      )
ORDER BY i.tipo_servicio, i.importe_total DESC;
GO
