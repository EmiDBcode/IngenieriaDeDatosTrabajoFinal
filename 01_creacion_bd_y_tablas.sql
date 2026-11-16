/* =====================================================================
   TP Ingeniería de Datos
   Caso: "Salud Corporativa del Sur S.A." - empresa tercerizada de salud
   Script 01: creación de la base de datos y de las 9 tablas (modelo en 3FN)
   Motor: Microsoft SQL Server 2019 / 2022

   Cómo leer este script:
   - Cada tabla sale de la 3FN: una tabla por cada "determinante" que
     encontramos en la normalización (paciente, obra social, profesional...).
   - PK  (PRIMARY KEY): identifica cada fila; no se repite y no es NULL.
   - FK  (FOREIGN KEY): columna que apunta a la PK de otra tabla. Asegura
         que no se pueda cargar, por ejemplo, un turno de un paciente
         que no existe (integridad referencial).
   - UQ  (UNIQUE): valor que no se repite pero no es la PK (clave alternativa).
   - CK  (CHECK): regla de negocio que el motor valida en cada INSERT/UPDATE.
   - Se nombran todas las restricciones (PK_..., FK_..., CK_...) para que,
     si una falla, el mensaje de error diga claramente cuál fue.
   ===================================================================== */

-- Nos paramos en master porque no se puede borrar una base estando dentro de ella.
USE master;
GO

-- Si la base ya existe, se borra para poder ejecutar el script las veces que haga falta.
-- SINGLE_USER WITH ROLLBACK IMMEDIATE cierra las conexiones abiertas (por ejemplo,
-- otra pestaña de SSMS) que de otra forma impedirían el DROP.
IF DB_ID('SaludCorporativa') IS NOT NULL
BEGIN
    ALTER DATABASE SaludCorporativa SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SaludCorporativa;
END
GO

CREATE DATABASE SaludCorporativa;
GO

USE SaludCorporativa;
GO

/* ---------------------------------------------------------------------
   ORDEN DE CREACIÓN: primero las tablas que no dependen de nadie
   (no tienen FK) y después las que las referencian. Una FK solo se puede
   crear si la tabla a la que apunta ya existe.
     1) ObraSocial, Especialidad, Movil, Hospital, Practica  (sin FK)
     2) Paciente (-> ObraSocial), Profesional (-> Especialidad)
     3) Turno (-> Paciente, Profesional, Movil, Hospital)
     4) TurnoPractica (-> Turno, Practica)
   --------------------------------------------------------------------- */


/* =========================== TABLAS SIN FK =========================== */

-- OBRA SOCIAL: a quién le factura la empresa. Sale de la DF
-- COD_OBRA_SOCIAL -> NOMBRE, PORCENTAJE_COBERTURA (3FN).
CREATE TABLE ObraSocial (
    cod_obra_social       INT          NOT NULL,   -- código interno, lo asigna la empresa
    nombre                VARCHAR(60)  NOT NULL,
    porcentaje_cobertura  DECIMAL(5,2) NOT NULL,   -- DECIMAL y no FLOAT: los porcentajes y montos
                                                   -- tienen que ser exactos (FLOAT redondea)
    CONSTRAINT PK_ObraSocial PRIMARY KEY (cod_obra_social),
    -- No puede haber dos obras sociales con el mismo nombre (clave alternativa).
    CONSTRAINT UQ_ObraSocial_nombre UNIQUE (nombre),
    -- Un porcentaje solo tiene sentido entre 0 y 100.
    CONSTRAINT CK_ObraSocial_cobertura CHECK (porcentaje_cobertura BETWEEN 0 AND 100)
);
GO

-- ESPECIALIDAD: define el valor de la visita. Se separó de Profesional en 3FN
-- porque MATRICULA -> ID_ESPECIALIDAD -> NOMBRE, VALOR_VISITA (dependencia transitiva).
CREATE TABLE Especialidad (
    id_especialidad  INT           NOT NULL,
    nombre           VARCHAR(50)   NOT NULL,
    valor_visita     DECIMAL(10,2) NOT NULL,   -- honorario base de cada atención
    CONSTRAINT PK_Especialidad PRIMARY KEY (id_especialidad),
    CONSTRAINT UQ_Especialidad_nombre UNIQUE (nombre),
    CONSTRAINT CK_Especialidad_valor CHECK (valor_visita > 0)
);
GO

-- MÓVIL: vehículo que la empresa manda al domicilio. La patente ya es única
-- en el mundo real, por eso se usa como PK natural (no hace falta un ID inventado).
CREATE TABLE Movil (
    patente  VARCHAR(10) NOT NULL,
    tipo     VARCHAR(30) NOT NULL,   -- Auto médico, Ambulancia de traslado, Terapia intensiva móvil
    base     VARCHAR(40) NOT NULL,   -- base operativa desde donde sale
    CONSTRAINT PK_Movil PRIMARY KEY (patente)
);
GO

-- HOSPITAL: destino de los traslados. Es una tabla aparte porque
-- COD_HOSPITAL -> NOMBRE, DIRECCION (dependencia transitiva en Turno).
CREATE TABLE Hospital (
    cod_hospital  INT          NOT NULL,
    nombre        VARCHAR(80)  NOT NULL,
    direccion     VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Hospital PRIMARY KEY (cod_hospital)
);
GO

-- PRÁCTICA: catálogo de prácticas que se pueden hacer en una atención.
-- Se separó en 2FN: DESCRIPCION y PRECIO dependían solo de COD_PRACTICA,
-- no de la clave completa (NRO_TURNO, COD_PRACTICA).
CREATE TABLE Practica (
    cod_practica  VARCHAR(10)   NOT NULL,
    descripcion   VARCHAR(80)   NOT NULL,
    precio        DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_Practica PRIMARY KEY (cod_practica),
    CONSTRAINT CK_Practica_precio CHECK (precio > 0)
);
GO


/* ======================= TABLAS CON UNA FK =========================== */

-- PACIENTE: la persona que pide el servicio. Cada paciente pertenece a UNA
-- obra social (relación "afilia", 1 a N), por eso la FK está de este lado.
CREATE TABLE Paciente (
    dni               VARCHAR(10)  NOT NULL,   -- VARCHAR y no INT: no se hacen cuentas con el DNI
                                               -- y así se respetan ceros a la izquierda
    nombre            VARCHAR(50)  NOT NULL,
    apellido          VARCHAR(50)  NOT NULL,
    fecha_nacimiento  DATE         NOT NULL,   -- DATE guarda solo la fecha, sin hora
    telefono          VARCHAR(20)  NOT NULL,
    domicilio         VARCHAR(100) NOT NULL,
    cod_obra_social   INT          NOT NULL,
    nro_afiliado      VARCHAR(20)  NULL,       -- NULL: puede faltar al momento del alta
    CONSTRAINT PK_Paciente PRIMARY KEY (dni),
    CONSTRAINT FK_Paciente_ObraSocial FOREIGN KEY (cod_obra_social)
        REFERENCES ObraSocial (cod_obra_social),
    -- No se aceptan fechas de nacimiento futuras.
    CONSTRAINT CK_Paciente_nacimiento CHECK (fecha_nacimiento <= CAST(GETDATE() AS DATE))
);
GO

-- El número de afiliado no se puede repetir dentro de la misma obra social.
-- Se usa un índice ÚNICO FILTRADO (WHERE ... IS NOT NULL) porque un UNIQUE común
-- en SQL Server solo deja UN valor NULL, y puede haber varios pacientes sin número.
CREATE UNIQUE INDEX UX_Paciente_afiliado
    ON Paciente (cod_obra_social, nro_afiliado)
    WHERE nro_afiliado IS NOT NULL;
GO

-- PROFESIONAL: médico, enfermero o paramédico que hace la atención.
-- Cada profesional tiene UNA especialidad (relación "tiene", 1 a N).
CREATE TABLE Profesional (
    matricula        INT          NOT NULL,   -- matrícula profesional: única, sirve como PK natural
    nombre           VARCHAR(50)  NOT NULL,
    apellido         VARCHAR(50)  NOT NULL,
    telefono         VARCHAR(20)  NOT NULL,
    email            VARCHAR(80)  NOT NULL,
    id_especialidad  INT          NOT NULL,
    CONSTRAINT PK_Profesional PRIMARY KEY (matricula),
    CONSTRAINT UQ_Profesional_email UNIQUE (email),
    CONSTRAINT FK_Profesional_Especialidad FOREIGN KEY (id_especialidad)
        REFERENCES Especialidad (id_especialidad),
    -- Validación mínima de formato de e-mail.
    CONSTRAINT CK_Profesional_email CHECK (email LIKE '%_@_%._%')
);
GO


/* ============================ TURNO ================================= */

-- TURNO: la tabla central (el "hecho"). Cada fila es un pedido de servicio:
-- quién lo pidió, qué profesional va, en qué móvil y, si es traslado, a qué hospital.
-- Tiene 4 FK porque en el DER es el lado N de 4 relaciones 1 a N.
CREATE TABLE Turno (
    nro_turno           INT IDENTITY(1,1) NOT NULL,  -- IDENTITY: el motor genera 1, 2, 3...
                                                     -- solo; no hay que cargarlo a mano
    fecha               DATE         NOT NULL,
    hora                TIME(0)      NOT NULL,       -- TIME(0) = hh:mm:ss sin fracciones de segundo
    tipo_servicio       VARCHAR(20)  NOT NULL,
    estado              VARCHAR(12)  NOT NULL
        CONSTRAINT DF_Turno_estado DEFAULT ('Programado'), -- DEFAULT: si no se indica, arranca "Programado"
    domicilio_atencion  VARCHAR(100) NOT NULL,       -- puede ser distinto del domicilio del paciente
                                                     -- (por eso no es dato redundante)
    observaciones       VARCHAR(200) NULL,
    dni_paciente        VARCHAR(10)  NOT NULL,
    matricula           INT          NOT NULL,
    patente             VARCHAR(10)  NOT NULL,
    cod_hospital        INT          NULL,           -- NULL: solo los traslados tienen hospital

    CONSTRAINT PK_Turno PRIMARY KEY (nro_turno),

    CONSTRAINT FK_Turno_Paciente    FOREIGN KEY (dni_paciente) REFERENCES Paciente (dni),
    CONSTRAINT FK_Turno_Profesional FOREIGN KEY (matricula)    REFERENCES Profesional (matricula),
    CONSTRAINT FK_Turno_Movil       FOREIGN KEY (patente)      REFERENCES Movil (patente),
    CONSTRAINT FK_Turno_Hospital    FOREIGN KEY (cod_hospital) REFERENCES Hospital (cod_hospital),

    -- Dominio cerrado: solo estos tres servicios ofrece la empresa.
    CONSTRAINT CK_Turno_tipo CHECK (tipo_servicio IN ('Visita médica', 'Enfermería', 'Traslado')),

    -- Estados posibles del ciclo de vida de un turno.
    CONSTRAINT CK_Turno_estado CHECK (estado IN ('Programado', 'En curso', 'Atendido', 'Cancelado', 'Ausente')),

    -- Regla de negocio: un traslado TIENE que tener hospital de destino,
    -- y los otros servicios NO llevan hospital.
    CONSTRAINT CK_Turno_hospital CHECK (
        (tipo_servicio = 'Traslado'  AND cod_hospital IS NOT NULL) OR
        (tipo_servicio <> 'Traslado' AND cod_hospital IS NULL)
    ),

    -- Claves alternativas (las encontramos en la 3FN):
    -- un profesional no puede estar en dos atenciones el mismo día a la misma hora...
    CONSTRAINT UQ_Turno_profesional_horario UNIQUE (matricula, fecha, hora),
    -- ...y un móvil tampoco puede estar en dos lugares a la vez.
    CONSTRAINT UQ_Turno_movil_horario UNIQUE (patente, fecha, hora)
);
GO

-- Índices sobre las FK que más se consultan. SQL Server crea índice automático
-- para PK y UNIQUE, pero NO para las FK. Sin estos índices, buscar "todos los
-- turnos de un paciente" obliga a recorrer la tabla entera.
CREATE INDEX IX_Turno_paciente ON Turno (dni_paciente);
CREATE INDEX IX_Turno_fecha    ON Turno (fecha);
GO


/* ========================= TURNO_PRACTICA ============================ */

-- TURNO_PRACTICA: resuelve la relación N a M "incluye" entre Turno y Practica
-- (en un turno se pueden hacer varias prácticas y una práctica aparece en muchos turnos).
-- Es la tabla que nació en la 1FN al sacar el grupo repetitivo de prácticas.
CREATE TABLE TurnoPractica (
    nro_turno     INT         NOT NULL,
    cod_practica  VARCHAR(10) NOT NULL,
    cantidad      TINYINT     NOT NULL      -- TINYINT (0 a 255) alcanza y ocupa 1 byte
        CONSTRAINT DF_TurnoPractica_cantidad DEFAULT (1),

    -- PK COMPUESTA: la misma práctica no se carga dos veces en el mismo turno
    -- (si se hizo dos veces, se sube la cantidad).
    CONSTRAINT PK_TurnoPractica PRIMARY KEY (nro_turno, cod_practica),

    -- ON DELETE CASCADE: si se borra un turno, se borran solas sus prácticas
    -- (no tienen sentido sin el turno). Con Practica NO se pone cascada:
    -- no se debe poder borrar una práctica del catálogo que ya se usó.
    CONSTRAINT FK_TurnoPractica_Turno FOREIGN KEY (nro_turno)
        REFERENCES Turno (nro_turno) ON DELETE CASCADE,
    CONSTRAINT FK_TurnoPractica_Practica FOREIGN KEY (cod_practica)
        REFERENCES Practica (cod_practica),

    CONSTRAINT CK_TurnoPractica_cantidad CHECK (cantidad > 0)
);
GO

/* ---------------------------------------------------------------------
   ¿Por qué NO hay tabla Factura ni columna "importe"?
   El importe de una atención = valor_visita de la especialidad + suma de
   (precio * cantidad) de sus prácticas, y lo que paga la obra social es ese
   importe por su porcentaje de cobertura. Son DATOS DERIVADOS: si se guardaran,
   habría que actualizarlos cada vez que cambia un precio (redundancia y
   riesgo de inconsistencia, justo lo que la normalización evita).
   Se calculan con una VISTA (script 03).
   --------------------------------------------------------------------- */

-- Control final: lista las 9 tablas creadas.
SELECT name AS tabla, create_date
FROM sys.tables
ORDER BY create_date;
GO
