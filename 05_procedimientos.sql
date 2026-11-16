/* =====================================================================
   TP Ingeniería de Datos - "Salud Corporativa del Sur S.A."
   Script 05: STORED PROCEDURES (queries 6 a 10 de 10)
   Ejecutar después de los scripts 01 y 02 (el SP 5 usa la vista del script 03).

   ¿Qué es un stored procedure (SP)?
   Un bloque de código T-SQL guardado en la base, con nombre y parámetros.
   Se ejecuta con EXEC. A diferencia de una vista, puede MODIFICAR datos,
   validar reglas y devolver errores propios.

   Control de transacciones y errores (SP 1 a 4):
   - BEGIN TRAN ... COMMIT: todo lo que está en el medio se confirma junto.
     Si algo falla, ROLLBACK deshace TODO lo que se hizo desde el BEGIN TRAN.
     Es la "A" de ACID (atomicidad): o se hace todo, o no se hace nada.
   - BEGIN TRY ... END TRY / BEGIN CATCH ... END CATCH: si cualquier
     instrucción del TRY da error, la ejecución salta al CATCH.
   - En el CATCH: si quedó una transacción abierta (@@TRANCOUNT > 0) se hace
     ROLLBACK, y después THROW vuelve a lanzar el error para que quien llamó
     al SP se entere de qué pasó (si no, el error quedaría "tapado").
   - SET XACT_ABORT ON: ante errores graves la transacción se marca para
     deshacer sí o sí; es la práctica recomendada junto con TRY/CATCH.
   - SET NOCOUNT ON: no muestra el mensaje "(1 row affected)" de cada
     instrucción; deja la salida más limpia.
   - THROW 5xxxx: errores propios del negocio. Los números desde 50000
     están reservados para el usuario.

   Resumen:
     SP 6  sp_RegistrarTurno          -> transacción + TRY/CATCH
     SP 7  sp_RegistrarPractica       -> transacción + TRY/CATCH
     SP 8  sp_CancelarTurno           -> transacción + TRY/CATCH
     SP 9  sp_ActualizarAranceles     -> transacción + TRY/CATCH
     SP 10 sp_HistorialPaciente       -> solo consulta (no modifica datos,
                                         por eso no necesita transacción)
   ===================================================================== */

USE SaludCorporativa;
GO


/* ---------------------------------------------------------------------
   SP 6: sp_RegistrarTurno
   Para qué: la operadora carga un pedido de servicio. El SP valida las
   reglas ANTES de insertar, para devolver un mensaje claro en lugar del
   error técnico de una restricción.
   Validaciones:
     - el paciente y el profesional existen,
     - la fecha no es pasada,
     - un traslado trae hospital y los demás servicios no,
     - el profesional y el móvil están libres en ese día y hora.
   Devuelve: el nro_turno generado (parámetro OUTPUT).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE sp_RegistrarTurno
    @fecha               DATE,
    @hora                TIME(0),
    @tipo_servicio       VARCHAR(20),
    @dni_paciente        VARCHAR(10),
    @matricula           INT,
    @patente             VARCHAR(10),
    @cod_hospital        INT          = NULL,  -- "= NULL": parámetro opcional
    @domicilio_atencion  VARCHAR(100) = NULL,  -- si no se informa, se usa el del paciente
    @observaciones       VARCHAR(200) = NULL,
    @nro_turno           INT OUTPUT            -- OUTPUT: el SP le devuelve el valor a quien lo llama
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF NOT EXISTS (SELECT 1 FROM Paciente WHERE dni = @dni_paciente)
            THROW 50001, 'El paciente no existe.', 1;

        IF NOT EXISTS (SELECT 1 FROM Profesional WHERE matricula = @matricula)
            THROW 50002, 'El profesional no existe.', 1;

        IF @fecha < CAST(GETDATE() AS DATE)
            THROW 50003, 'No se pueden registrar turnos en fechas pasadas.', 1;

        IF @tipo_servicio = 'Traslado' AND @cod_hospital IS NULL
            THROW 50004, 'Un traslado necesita un hospital de destino.', 1;

        IF @tipo_servicio <> 'Traslado' AND @cod_hospital IS NOT NULL
            THROW 50005, 'Solo los traslados llevan hospital de destino.', 1;

        -- Se controla también contra turnos cancelados porque las restricciones
        -- UNIQUE de la tabla (matricula, fecha, hora) y (patente, fecha, hora)
        -- tampoco dejan reusar ese horario.
        -- WITH (UPDLOCK, HOLDLOCK): bloquea ese horario mientras dura la
        -- transacción. Así, si dos operadoras cargan el mismo profesional a la
        -- misma hora al mismo tiempo, la segunda espera y después ve el turno
        -- de la primera (evita la "condición de carrera").
        IF EXISTS (SELECT 1 FROM Turno WITH (UPDLOCK, HOLDLOCK)
                   WHERE matricula = @matricula AND fecha = @fecha AND hora = @hora)
            THROW 50006, 'El profesional ya tiene un turno en ese horario.', 1;

        IF EXISTS (SELECT 1 FROM Turno WITH (UPDLOCK, HOLDLOCK)
                   WHERE patente = @patente AND fecha = @fecha AND hora = @hora)
            THROW 50007, 'El móvil ya está asignado en ese horario.', 1;

        -- Si no se informó domicilio de atención, se toma el del paciente.
        IF @domicilio_atencion IS NULL
            SELECT @domicilio_atencion = domicilio FROM Paciente WHERE dni = @dni_paciente;

        INSERT INTO Turno (fecha, hora, tipo_servicio, estado, domicilio_atencion,
                           observaciones, dni_paciente, matricula, patente, cod_hospital)
        VALUES (@fecha, @hora, @tipo_servicio, 'Programado', @domicilio_atencion,
                @observaciones, @dni_paciente, @matricula, @patente, @cod_hospital);

        -- SCOPE_IDENTITY(): último IDENTITY generado en ESTE bloque.
        -- Se prefiere a @@IDENTITY, que podría devolver uno generado por un trigger.
        SET @nro_turno = SCOPE_IDENTITY();

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;   -- relanza el error original (número y mensaje)
    END CATCH
END;
GO


/* ---------------------------------------------------------------------
   SP 7: sp_RegistrarPractica
   Para qué: el profesional informa una práctica que hizo en la atención.
   Toca DOS tablas: agrega la práctica en TurnoPractica y pasa el turno a
   'Atendido'. Por eso necesita transacción: si una de las dos operaciones
   falla, no puede quedar la práctica cargada en un turno que sigue
   'Programado' (o al revés).
   Si la práctica ya estaba cargada en ese turno, suma la cantidad en vez
   de insertar otra fila (la PK compuesta no lo permitiría).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE sp_RegistrarPractica
    @nro_turno     INT,
    @cod_practica  VARCHAR(10),
    @cantidad      TINYINT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado VARCHAR(12);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @estado = estado FROM Turno WITH (UPDLOCK) WHERE nro_turno = @nro_turno;

        IF @estado IS NULL
            THROW 50011, 'El turno no existe.', 1;

        IF @estado IN ('Cancelado', 'Ausente')
            THROW 50012, 'No se pueden cargar prácticas en un turno cancelado o ausente.', 1;

        IF NOT EXISTS (SELECT 1 FROM Practica WHERE cod_practica = @cod_practica)
            THROW 50013, 'La práctica no existe.', 1;

        IF @cantidad < 1
            THROW 50014, 'La cantidad tiene que ser mayor a cero.', 1;

        -- Operación 1: agrega la práctica o suma la cantidad.
        IF EXISTS (SELECT 1 FROM TurnoPractica
                   WHERE nro_turno = @nro_turno AND cod_practica = @cod_practica)
            UPDATE TurnoPractica
               SET cantidad = cantidad + @cantidad
             WHERE nro_turno = @nro_turno AND cod_practica = @cod_practica;
        ELSE
            INSERT INTO TurnoPractica (nro_turno, cod_practica, cantidad)
            VALUES (@nro_turno, @cod_practica, @cantidad);

        -- Operación 2: si se hizo una práctica, la atención se realizó.
        UPDATE Turno SET estado = 'Atendido' WHERE nro_turno = @nro_turno;

        COMMIT;

        -- Muestra cómo quedó el turno.
        SELECT tp.nro_turno, pa.cod_practica, pa.descripcion, tp.cantidad,
               pa.precio * tp.cantidad AS subtotal
        FROM TurnoPractica tp
            INNER JOIN Practica pa ON pa.cod_practica = tp.cod_practica
        WHERE tp.nro_turno = @nro_turno;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------
   SP 8: sp_CancelarTurno
   Para qué: el paciente llama para cancelar. Solo se puede cancelar un
   turno 'Programado' (uno ya atendido no se puede "des-atender").
   No se borra la fila (DELETE): se cambia el estado. Así queda el historial
   y se puede medir cuántos turnos se cancelan ("borrado lógico").
   Se deja el motivo en observaciones, sin perder lo que ya tenía.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE sp_CancelarTurno
    @nro_turno  INT,
    @motivo     VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @estado VARCHAR(12);

    BEGIN TRY
        BEGIN TRAN;

        SELECT @estado = estado FROM Turno WITH (UPDLOCK) WHERE nro_turno = @nro_turno;

        IF @estado IS NULL
            THROW 50021, 'El turno no existe.', 1;

        IF @estado <> 'Programado'
            THROW 50022, 'Solo se pueden cancelar turnos en estado Programado.', 1;

        IF LTRIM(RTRIM(ISNULL(@motivo, ''))) = ''
            THROW 50023, 'Hay que indicar el motivo de la cancelación.', 1;

        UPDATE Turno
           SET estado = 'Cancelado',
               -- LEFT(..., 200): recorta para no pasarse del largo de la columna.
               observaciones = LEFT(ISNULL(observaciones + ' | ', '') + 'Cancelado: ' + @motivo, 200)
         WHERE nro_turno = @nro_turno;

        COMMIT;

        SELECT nro_turno, fecha, hora, estado, observaciones
        FROM Turno WHERE nro_turno = @nro_turno;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------
   SP 9: sp_ActualizarAranceles
   Para qué: por la inflación, la empresa aumenta sus valores un porcentaje.
   Actualiza DOS tablas (Especialidad y Practica). La transacción garantiza
   que no quede la mitad de los precios aumentados y la otra mitad no.
   Como los importes NO están guardados (se calculan en la vista), con
   cambiar los precios alcanza: no hay que recalcular nada más. Esta es
   una ventaja directa de haber normalizado.
   OJO: el aumento también cambia el importe de las atenciones viejas al
   consultar la vista (el modelo guarda el precio actual, no un histórico).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE sp_ActualizarAranceles
    @porcentaje  DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        IF @porcentaje <= 0 OR @porcentaje > 100
            THROW 50031, 'El porcentaje tiene que estar entre 0 y 100.', 1;

        BEGIN TRAN;

        UPDATE Especialidad
           SET valor_visita = ROUND(valor_visita * (1 + @porcentaje / 100), 2);

        UPDATE Practica
           SET precio = ROUND(precio * (1 + @porcentaje / 100), 2);

        COMMIT;

        SELECT 'Especialidad' AS tabla, nombre AS item, valor_visita AS nuevo_valor FROM Especialidad
        UNION ALL
        SELECT 'Practica', descripcion, precio FROM Practica;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO


/* ---------------------------------------------------------------------
   SP 10: sp_HistorialPaciente
   Para qué: ver todos los turnos de un paciente con su importe.
   Es solo un SELECT con parámetro: no modifica datos, por eso no lleva
   transacción. La ventaja frente a una vista es que recibe parámetros
   (el DNI y, opcionalmente, un rango de fechas).
   LEFT JOIN con la vista de importes: los turnos no atendidos no tienen
   importe y aparecen con 0.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE sp_HistorialPaciente
    @dni    VARCHAR(10),
    @desde  DATE = NULL,
    @hasta  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.nro_turno, a.fecha, a.hora, a.tipo_servicio, a.estado,
           a.profesional, a.especialidad, a.hospital_destino,
           ISNULL(i.importe_total, 0)     AS importe_total,
           ISNULL(i.a_cargo_paciente, 0)  AS a_cargo_paciente
    FROM vw_AgendaTurnos a
        LEFT JOIN vw_ImportePorTurno i ON i.nro_turno = a.nro_turno
    WHERE a.dni = @dni
      -- Si el parámetro viene NULL, la condición da verdadero y no filtra.
      AND (@desde IS NULL OR a.fecha >= @desde)
      AND (@hasta IS NULL OR a.fecha <= @hasta)
    ORDER BY a.fecha, a.hora;
END;
GO


/* =====================================================================
   PRUEBAS (ejecutar de a un bloque y mirar el resultado)
   ===================================================================== */

-- SP 6, caso OK: traslado de Elsa Domínguez al Hospital Zonal Sur.
DECLARE @nuevo INT;
EXEC sp_RegistrarTurno
     @fecha = '2026-12-01', @hora = '10:00', @tipo_servicio = 'Traslado',
     @dni_paciente = '18765432', @matricula = 48800, @patente = 'AC456EF',
     @cod_hospital = 1, @observaciones = 'Traslado para diálisis',
     @nro_turno = @nuevo OUTPUT;
SELECT @nuevo AS turno_generado;
GO

-- SP 6, caso con error: el mismo profesional a la misma hora -> error 50006.
-- El TRY/CATCH hace ROLLBACK y el turno NO se inserta.
DECLARE @nuevo INT;
BEGIN TRY
    EXEC sp_RegistrarTurno
         @fecha = '2026-12-01', @hora = '10:00', @tipo_servicio = 'Visita médica',
         @dni_paciente = '30111222', @matricula = 48800, @patente = 'AB123CD',
         @nro_turno = @nuevo OUTPUT;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH
GO

-- SP 7: al turno 10 (Juan Pérez, cardiología) se le agrega un control de glucemia.
EXEC sp_RegistrarPractica @nro_turno = 10, @cod_practica = 'GLU01';
GO

-- SP 7, caso con error: práctica en un turno cancelado (el 8) -> error 50012.
BEGIN TRY
    EXEC sp_RegistrarPractica @nro_turno = 8, @cod_practica = 'ECG01';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH
GO

-- SP 8: Tomás Acosta cancela el traslado del turno 12.
EXEC sp_CancelarTurno @nro_turno = 12, @motivo = 'Se reprogramó el estudio';
GO

-- SP 8, caso con error: cancelar un turno ya atendido -> error 50022.
BEGIN TRY
    EXEC sp_CancelarTurno @nro_turno = 1, @motivo = 'Prueba';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS nro_error, ERROR_MESSAGE() AS mensaje;
END CATCH
GO

-- SP 9: aumento del 10 %. Se envuelve en una transacción de prueba y se
-- deshace al final para no alterar los datos del resto de las consultas.
BEGIN TRAN;
    EXEC sp_ActualizarAranceles @porcentaje = 10;
ROLLBACK;
GO

-- SP 10: historial de Elsa Domínguez (todos sus turnos).
EXEC sp_HistorialPaciente @dni = '18765432';
GO
