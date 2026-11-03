# Solicitud: categoría y nivel de precio del cliente en órdenes y facturas (rmapiv2)

**Para:** equipo de RM API v2 · **De:** Logística de almacén (Piqueo FIFO) · **Fecha:** 2026-11-03
**Continúa:** [SOLICITUD_API_ORDENES.md](SOLICITUD_API_ORDENES.md) (`OrdOpenOrders` y `SalesInvoicesByDate`, ya entregados en 1.12/1.13)

> **Estado: entregado en RM API 1.14.0** (2026-11-03), con los nombres de campos propuestos. Respuesta del equipo:
> `DESPACHO_RESPUESTA_CATEGORIA_NIVEL.md`. El punto de `Activo` se corrigió en la 1.14.1.
> Verificado en la estación con la API instalada: los cuatro campos llegan en órdenes y facturas.

## Qué pedimos

Agregar **cuatro columnas de solo lectura** a cada fila de `OrdOpenOrders` y de `SalesInvoicesByDate`:

| Campo | Tipo JSON | Origen | Si falta |
|---|---|---|---|
| `ClienteCategoriaID` | int o `null` | `Clientes.Categoria` | `null` |
| `ClienteCategoria` | texto o `null` | `CategoriasClientes.Descripcion` | `null` |
| `ClientePriceLevelID` | int o `null` | `Clientes.PriceLevel` | `null` (también si es `0`, el valor por defecto) |
| `ClientePriceLevel` | texto o `null` | `PriceLevels.Nombre` | `null` |

Usamos los datos para filtrar la lista de órdenes del almacén por tipo de cliente (Cliente General, Ruta, mayoristas, etc.).

## Por qué

En el almacén se quiere separar las órdenes por tipo de cliente; por ejemplo, preparar primero las de ruta o las de mayoristas. En POSDPS ese dato está en dos lugares:
- `Clientes.Categoria` → `CategoriasClientes`: hoy tiene 1 Cliente General, 999 Ruta - Vendedor y 1000 Cuentas Incobrables.
- `Clientes.PriceLevel` → `PriceLevels`: aquí está «Por Mayor».

Pedimos los dos en este mismo cambio para no volver a molestarlos si el almacén decide filtrar por nivel de precio.

## Reglas

1. **En vivo.** El dato se lee con un JOIN en la misma consulta: es la categoría y el nivel que el cliente tiene **hoy**, no los del momento de la orden o factura. Si alguien cambia la categoría de un cliente, la siguiente llamada ya lo refleja. En facturas, el JOIN va en el SELECT final, después del CTE, igual que hoy `ClienteNombre`.
2. **Sin cambios de base de datos.** Son solo LEFT JOIN a tablas que ya existen. No hay columnas, tablas ni índices nuevos, ni script para aplicar. `CategoriasClientes.IdNumero` y `PriceLevels.ID` son PK, así que el JOIN no duplica filas.
3. **Nunca se pierde una fila.** Cliente inexistente (`Ordenes.Cliente` y `FacturasHisto.Cliente` no tienen FK), `Facturas.Cliente` NULL, cliente sin categoría o categoría o nivel huérfano: la fila sale igual, con los campos en `null`.
4. **Aditivo.** No cambia ningún campo ni parámetro actual. La app vieja ignora los campos nuevos, y la app nueva funciona con una API que todavía no los envía.
5. Los IDs son **los de la base de cada compañía**. La app no los compara entre compañías, así que no hace falta normalizarlos.

## SQL sugerido

Las líneas son de nuestra copia de 1.13.0, solo como referencia. Por favor, confírmenlas contra su código vigente.

`Controllers/DispatchController.cs`, **OrdOpenOrders** (SELECT en ~:68-93): agregar después de `C.Nombre AS ClienteNombre,`

```sql
C.Categoria AS ClienteCategoriaID,
CC.Descripcion AS ClienteCategoria,
NULLIF(C.PriceLevel, 0) AS ClientePriceLevelID,
PL.Nombre AS ClientePriceLevel,
```
y después de `LEFT JOIN Clientes C ON C.Numero = O.Cliente`:
```sql
LEFT JOIN CategoriasClientes CC ON CC.IdNumero = C.Categoria
LEFT JOIN PriceLevels PL ON PL.ID = C.PriceLevel
```

**SalesInvoicesByDate** (SELECT final, ~:170-191): las mismas cuatro columnas después de `COALESCE(C.Nombre, L.Nombre) AS ClienteNombre,`, y los mismos dos LEFT JOIN después de `LEFT JOIN Clientes C ON C.Numero = L.Cliente`.

`ClientsController` ya usa estos dos JOIN (`:47`, `:92`, `:95`).

## Pruebas de aceptación sugeridas

Contra `POSDPS_TEST` (nunca producción), en `Dispatch/Integration/DispatchScratchDbTests.cs`:

1. Cliente con categoría y nivel: los cuatro campos coinciden con un `SELECT` directo a `Clientes`, `CategoriasClientes` y `PriceLevels`.
2. Cliente con `Categoria NULL` y `PriceLevel 0`: los cuatro campos son `null` y la orden sigue saliendo.
3. Orden cuyo `Cliente` no existe en `Clientes`: la orden sale, y `ClienteNombre` y los cuatro campos son `null`.
4. Factura histórica de un cliente borrado, y factura con `Cliente NULL`: la línea sale.
5. **En vivo:** dentro de una transacción, `UPDATE Clientes SET Categoria = 999` en el cliente de prueba `SCRTEST01`, llamar al endpoint, verificar que trae 999 y hacer rollback.
6. El número de filas no cambia respecto de 1.13 con los mismos parámetros.

## Versión y despliegue

- Sugerimos publicarlo como 1.14.0, con la nota «sin cambios de base de datos».
- Se puede instalar estación por estación, en cualquier orden respecto de la app.
- Reversa: reinstalar 1.13.0.

## Preguntas

1. ¿Los nombres de los campos les parecen bien? Podemos adaptarnos.
2. ¿`PriceLevel = 0` significa siempre «sin nivel» en todas las compañías? (`PriceLevels.ID` es IDENTITY y empieza en 1.)
3. Algo que vimos de paso y que no pedimos en esta solicitud: `ClientsController` escribe `Activo` como `'1'`/`'0'` y lo lee con `= '1'`, mientras que el POS usa `'S'`/`'N'`. Por eso los clientes del POS aparecen inactivos en `Clients` (también lo anota `ORDERS_1.10.0_SPEC.md`). Lo mencionamos por si les sirve.
