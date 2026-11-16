/* =====================================================================
   TP Ingeniería de Datos - "Salud Corporativa del Sur S.A."
   Script 02: carga de datos de prueba
   Ejecutar DESPUÉS del script 01.

   Por qué en este orden: se carga igual que se crearon las tablas,
   primero las que no tienen FK y después las que las referencian.
   Si se intentara cargar un Turno antes que su Paciente, la FK lo rechazaría
   (error 547: "conflicted with the FOREIGN KEY constraint").

   Los 4 primeros turnos son los mismos de la tabla 0 de la normalización.
   ===================================================================== */

USE SaludCorporativa;
GO

-- Formato de fechas: se usa 'AAAA-MM-DD' (ISO), que SQL Server interpreta
-- siempre igual sin importar el idioma de la instalación.

/* ---------------------------- ObraSocial ---------------------------- */
INSERT INTO ObraSocial (cod_obra_social, nombre, porcentaje_cobertura) VALUES
(1, 'OSDE',          80.00),
(2, 'IOMA',          60.00),
(3, 'PAMI',          90.00),
(4, 'Swiss Medical', 70.00);
GO

/* --------------------------- Especialidad --------------------------- */
INSERT INTO Especialidad (id_especialidad, nombre, valor_visita) VALUES
(1, 'Clínica Médica', 30000.00),
(2, 'Enfermería',     15000.00),
(3, 'Cardiología',    40000.00),
(4, 'Emergentología', 50000.00);
GO

/* ------------------------------ Movil ------------------------------- */
INSERT INTO Movil (patente, tipo, base) VALUES
('AB123CD', 'Auto médico',             'Base Avellaneda'),
('AC456EF', 'Ambulancia de traslado',  'Base Avellaneda'),
('AD789GH', 'Terapia intensiva móvil', 'Base Quilmes'),
('AE012IJ', 'Auto médico',             'Base Quilmes');
GO

/* ----------------------------- Hospital ----------------------------- */
INSERT INTO Hospital (cod_hospital, nombre, direccion) VALUES
(1, 'Hospital Zonal Sur',        'Av. Calchaquí 3500, Quilmes'),
(2, 'Clínica del Parque',        'Av. Belgrano 1800, Avellaneda'),
(3, 'Sanatorio Central',         'Hipólito Yrigoyen 4200, Lanús'),
(4, 'Hospital de Agudos Norte',  'Av. Pavón 900, Avellaneda');
GO

/* ----------------------------- Practica ----------------------------- */
INSERT INTO Practica (cod_practica, descripcion, precio) VALUES
('ECG01', 'Electrocardiograma',        12000.00),
('INY01', 'Aplicación de inyectable',   5000.00),
('CUR01', 'Curación',                   8000.00),
('OXI01', 'Oxigenoterapia',            10000.00),
('GLU01', 'Control de glucemia',        4000.00),
('SUT01', 'Sutura',                    15000.00);
GO

/* ----------------------------- Paciente ----------------------------- */
-- Cada paciente apunta a una obra social que ya existe (FK cod_obra_social).
INSERT INTO Paciente (dni, nombre, apellido, fecha_nacimiento, telefono, domicilio, cod_obra_social, nro_afiliado) VALUES
('30111222', 'Juan',    'Pérez',     '1983-04-12', '11-5555-0101', 'Av. Mitre 1200, Avellaneda', 1, 'OS-884512'),
('22334455', 'Roberto', 'Sánchez',   '1955-07-21', '11-5555-0104', 'Belgrano 450, Quilmes',      3, 'PA-55012'),
('28456789', 'María',   'González',  '1980-09-30', '11-5555-0102', 'Sarmiento 300, Lanús',       2, 'IO-778900'),
('35222333', 'Carla',   'Medina',    '1992-07-22', '11-5555-0103', 'Mitre 1550, Avellaneda',     4, 'SM-120034'),
('18765432', 'Elsa',    'Domínguez', '1948-02-03', '11-5555-0105', 'Rivadavia 820, Quilmes',     3, 'PA-61877'),
('40987654', 'Tomás',   'Acosta',    '1998-11-15', '11-5555-0106', 'Alsina 77, Lanús',           1, NULL);  -- sin nro. de afiliado todavía
GO

/* ---------------------------- Profesional --------------------------- */
INSERT INTO Profesional (matricula, nombre, apellido, telefono, email, id_especialidad) VALUES
(45120, 'Laura',  'Fernández', '11-4000-1001', 'lfernandez@saludsur.com.ar', 1),
(45980, 'Martín', 'Gómez',     '11-4000-1005', 'mgomez@saludsur.com.ar',     1),
(60111, 'Sofía',  'Ramírez',   '11-4000-1002', 'sramirez@saludsur.com.ar',   2),
(61234, 'Lucía',  'Benítez',   '11-4000-1006', 'lbenitez@saludsur.com.ar',   2),
(46010, 'Carlos', 'Ríos',      '11-4000-1003', 'crios@saludsur.com.ar',      3),
(48800, 'Diego',  'Suárez',    '11-4000-1004', 'dsuarez@saludsur.com.ar',    4);
GO

/* ------------------------------ Turno ------------------------------- */
-- NO se carga nro_turno: es IDENTITY y el motor lo numera solo (1, 2, 3...).
-- cod_hospital va NULL en todo lo que no es traslado (lo exige CK_Turno_hospital).
INSERT INTO Turno (fecha, hora, tipo_servicio, estado, domicilio_atencion, observaciones, dni_paciente, matricula, patente, cod_hospital) VALUES
-- 1 a 4: los turnos de la tabla 0
('2026-10-05', '09:00', 'Visita médica', 'Atendido',   'Av. Mitre 1200, Avellaneda', 'Fiebre y dolor de garganta', '30111222', 45120, 'AB123CD', NULL),
('2026-10-14', '22:30', 'Traslado',      'Atendido',   'Belgrano 450, Quilmes',      'Dolor de pecho',             '22334455', 48800, 'AD789GH', 1),
('2026-10-20', '10:00', 'Enfermería',    'Ausente',    'Sarmiento 300, Lanús',       'Paciente no estaba',         '28456789', 60111, 'AE012IJ', NULL),
('2026-11-18', '16:00', 'Visita médica', 'Programado', 'Mitre 1550, Avellaneda',     NULL,                         '35222333', 46010, 'AB123CD', NULL),
-- 5 a 12: más movimiento para que las consultas devuelvan datos interesantes
('2026-10-22', '08:30', 'Enfermería',    'Atendido',   'Rivadavia 820, Quilmes',     'Control post operatorio',    '18765432', 61234, 'AE012IJ', NULL),
('2026-10-28', '11:15', 'Visita médica', 'Atendido',   'Alsina 77, Lanús',           'Corte en la mano',           '40987654', 45980, 'AB123CD', NULL),
('2026-11-03', '19:40', 'Traslado',      'Atendido',   'Rivadavia 820, Quilmes',     'Caída en domicilio',         '18765432', 48800, 'AC456EF', 3),
('2026-11-05', '09:30', 'Visita médica', 'Cancelado',  'Belgrano 450, Quilmes',      'Canceló por teléfono',       '22334455', 46010, 'AE012IJ', NULL),
('2026-11-10', '15:00', 'Enfermería',    'Atendido',   'Sarmiento 300, Lanús',       'Aplicación de medicación',   '28456789', 60111, 'AB123CD', NULL),
('2026-11-12', '07:50', 'Visita médica', 'Atendido',   'Av. Mitre 1200, Avellaneda', 'Control de presión',         '30111222', 46010, 'AE012IJ', NULL),
('2026-11-20', '10:30', 'Enfermería',    'Programado', 'Rivadavia 820, Quilmes',     NULL,                         '18765432', 61234, 'AE012IJ', NULL),
('2026-11-21', '21:00', 'Traslado',      'Programado', 'Alsina 77, Lanús',           'Traslado para estudios',     '40987654', 48800, 'AC456EF', 2);
GO

/* --------------------------- TurnoPractica -------------------------- */
-- Solo los turnos atendidos tienen prácticas realizadas.
-- La PK (nro_turno, cod_practica) impide cargar dos veces la misma práctica en un turno.
INSERT INTO TurnoPractica (nro_turno, cod_practica, cantidad) VALUES
(1,  'INY01', 1),
(2,  'ECG01', 1),
(2,  'OXI01', 1),
(5,  'CUR01', 1),
(5,  'GLU01', 1),
(6,  'SUT01', 1),
(6,  'CUR01', 1),
(7,  'OXI01', 1),
(9,  'INY01', 2),   -- dos aplicaciones en la misma visita: se usa cantidad, no otra fila
(10, 'ECG01', 1);
GO

/* --------------------- Control: filas por tabla --------------------- */
SELECT 'ObraSocial'    AS tabla, COUNT(*) AS filas FROM ObraSocial    UNION ALL
SELECT 'Especialidad',            COUNT(*)          FROM Especialidad  UNION ALL
SELECT 'Movil',                   COUNT(*)          FROM Movil         UNION ALL
SELECT 'Hospital',                COUNT(*)          FROM Hospital      UNION ALL
SELECT 'Practica',                COUNT(*)          FROM Practica      UNION ALL
SELECT 'Paciente',                COUNT(*)          FROM Paciente      UNION ALL
SELECT 'Profesional',             COUNT(*)          FROM Profesional   UNION ALL
SELECT 'Turno',                   COUNT(*)          FROM Turno         UNION ALL
SELECT 'TurnoPractica',           COUNT(*)          FROM TurnoPractica;
GO

/* ---------------------------------------------------------------------
   Pruebas de las restricciones (opcional, para mostrar en la exposición).
   Sacar el comentario de a una y ejecutar: cada una TIENE que fallar.

   -- 1) Traslado sin hospital -> viola CK_Turno_hospital
   INSERT INTO Turno (fecha, hora, tipo_servicio, domicilio_atencion, dni_paciente, matricula, patente)
   VALUES ('2026-12-01', '10:00', 'Traslado', 'Alsina 77, Lanús', '40987654', 48800, 'AC456EF');

   -- 2) Profesional en dos lugares a la misma hora -> viola UQ_Turno_profesional_horario
   INSERT INTO Turno (fecha, hora, tipo_servicio, domicilio_atencion, dni_paciente, matricula, patente)
   VALUES ('2026-10-05', '09:00', 'Visita médica', 'Alsina 77, Lanús', '40987654', 45120, 'AE012IJ');

   -- 3) Paciente que no existe -> viola FK_Turno_Paciente
   INSERT INTO Turno (fecha, hora, tipo_servicio, domicilio_atencion, dni_paciente, matricula, patente)
   VALUES ('2026-12-01', '10:00', 'Enfermería', 'Calle Falsa 123', '99999999', 60111, 'AE012IJ');

   -- 4) Cobertura mayor a 100 % -> viola CK_ObraSocial_cobertura
   INSERT INTO ObraSocial VALUES (5, 'Galeno', 120);
   --------------------------------------------------------------------- */
