cd ~/Documentos/TrabajoPracticoDeIngDeDatos/IngenieriaDeDatosTrabajoFinal
cat > README.md << 'EOF'
# TP Final – Ingeniería de Datos
## Salud Corporativa del Sur S.A. (empresa tercerizada de salud)

Modelo de datos para una empresa que brinda servicios de salud tercerizados (visitas médicas a domicilio, enfermería y traslados a hospitales) y factura a las obras sociales según su cobertura.

## Contenido
| Punto | Entregable |
|---|---|
| Enunciado | Caso, entidades y reglas de negocio |
| 1 | DER conceptual (notación de Chen) |
| 2 | DER lógico (9 tablas) |
| 3 | Tabla 0 |
| 4 | 1FN y 2FN |
| 5 | 3FN y modelo en SQL Server |
| 6 | 10 queries: 3 vistas, 2 subconsultas y 5 stored procedures (4 con transacción y TRY/CATCH) |

## Documento
📄 [Tabla 0 y normalización](https://docs.google.com/document/d/1xnjOty_Xo46aH1K7Oes34zym3AtisM_7/edit)

## Cómo ejecutar los scripts (SQL Server / SSMS)
Correr en este orden:
1. `01_creacion_bd_y_tablas.sql`: crea la base `SaludCorporativa` y las tablas
2. `02_insercion_datos.sql`: carga los datos de ejemplo
3. `03_vistas.sql`
4. `04_subconsultas.sql`
5. `05_procedimientos.sql`

## Entidades
ObraSocial · Paciente · Especialidad · Profesional · Movil · Hospital · Turno · Practica · TurnoPractica (resuelve la N:M)
EOF
git add README.md
git commit -m "README con descripción del TP y link al documento"
git push
