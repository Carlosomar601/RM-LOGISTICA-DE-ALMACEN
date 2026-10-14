# Solicitud: endpoints de órdenes y facturas para despacho (rmapiv2)

**Para:** equipo de RM API v2 · **De:** Logística de almacén (Piqueo FIFO) · **Fecha:** 2026-10-13

## Por qué

La aplicación de almacén ya importa la mercancía recibida con `RecReceiptsByDate` (gracias). Ahora necesita lo contrario:
saber qué **órdenes de clientes** y qué **facturas** hay que despachar, para preparar el piqueo FIFO por canasta.

Hoy solo existe `GetOrderDetail`, que exige conocer el número de orden; no hay forma de listar las órdenes abiertas
ni las facturas de un período.

Pedimos **dos endpoints de solo lectura**, con las mismas convenciones que `RecReceiptsByDate`:
- HTTP 200 con el error en el cuerpo (`{"success":false,"message":...,"status":...}`);
- `[]` cuando no hay datos;
- fechas `yyyy-MM-dd`, ambos días incluidos, máximo 366 días.

Ninguno escribe en la base de datos.

---

## A. `GET /cse.api.v1/OrdOpenOrders`

**Foto completa de las órdenes abiertas**: órdenes con al menos una línea pendiente (`Pendiente > 0`), una fila por línea.

| Parámetro | Obligatorio | Notas |
|---|---|---|
| `DateFrom`, `DateTo` | no | Filtran por fecha de la orden. Sin ellos: todas las órdenes abiertas. |
| `Station` | no | Código de estación (`Compania.IDCompania`), por si una base atiende varias. |

**Campos por fila**

| Campo | Origen sugerido | Notas |
|---|---|---|
| `OrderNumber` | `Ordenes.Numero` | Incluye las `O-` de Octano. |
| `OrderDate` | `Ordenes.Fecha` | `yyyy-MM-dd HH:mm:ss` |
| `Cliente`, `ClienteNombre` | `Ordenes` / `Clientes` | |
| `Vendedor` | `Ordenes.Vendedor` | 900 = Octano APP |
| `Comentario` | `Ordenes.Comentario` | |
| `Station` | | |
| `LineID` | `OrdenesDetalle` (identidad) | **Único**; identifica la línea entre una consulta y otra. |
| `ItemCode`, `Description` | `OrdenesDetalle.Referencia` / `Inventario` | |
| `QuantityOrdered`, `QuantityShipped`, `Pending` | `OrdenesDetalle` | En la misma unidad que `Unit`. |
| `Unit`, `UnitConv` | `Unidades` | `UnitConv` = unidades mínimas por unidad. |
| `IsService`, `IsFuel` | | Servicios y líneas de `Gasolina` no se despachan del almacén. |

**Por qué una foto y no "cambios desde"**: comparando una foto con la anterior detectamos órdenes nuevas, cantidades
modificadas y órdenes que desaparecen (facturadas, borradas o canceladas). Así **no hace falta ninguna columna
de "modificado" ni ningún cambio de base de datos**. El volumen de órdenes abiertas suele ser pequeño.

Ejemplo de respuesta:

```json
[
  {
    "OrderNumber": "O-261013-207-0001", "OrderDate": "2026-10-13 14:32:05",
    "Cliente": "OA20700001", "ClienteNombre": "JUAN PEREZ", "Vendedor": 900, "Comentario": "", "Station": "207",
    "LineID": 55120, "ItemCode": "12354001350", "Description": "CEMENTO GRIS 94LB",
    "QuantityOrdered": 3, "QuantityShipped": 0, "Pending": 3, "Unit": "EACH", "UnitConv": 1,
    "IsService": false, "IsFuel": false
  }
]
```

---

## B. `GET /cse.api.v1/SalesInvoicesByDate`

**Facturas de venta** de un período, una fila por línea, de `Facturas`/`FacturasDetalle` (y `FacturasHisto`/`FacturasDetalleHisto`
cuando el rango lo alcance).

| Parámetro | Obligatorio | Notas |
|---|---|---|
| `DateFrom`, `DateTo` | sí | Máximo 366 días. |
| `Cliente` | no | Código o nombre, como en otros endpoints. |

**Campos por fila**

| Campo | Notas |
|---|---|
| `InvoiceNumber`, `InvoiceDate` | |
| `Cliente`, `ClienteNombre` | |
| **`OrderNumber`** | **Número de la orden de la que salió la factura** (orden del POS u orden `O-` de Octano, `OrdenNumero`). Vacío si fue venta directa. **Ver "Requisito clave".** |
| `LineID` | Único y creciente (como en `RecReceiptsByDate`) para importar de forma incremental. |
| `ItemCode`, `Description`, `Quantity`, `Unit`, `UnitConv` | |
| `Transaccion` | Para distinguir ventas de devoluciones/anulaciones. |
| `IsService` | |

Pedimos **excluir** devoluciones y anulaciones parciales (`Transaccion` 70/71) y servicios. Si prefieren incluirlas,
basta con que `Transaccion` e `IsService` vengan en cada fila.

---

## Requisito clave: enlazar la factura con su orden

Cuando una orden se convierte en factura, el almacén **no puede despachar dos veces**:
primero la orden (ya piqueada) y después la factura de esa misma orden.

Para evitarlo, la aplicación relaciona cada factura con su orden por `OrderNumber`. Por eso necesitamos:

1. **`OrderNumber` siempre lleno** cuando la factura viene de una orden, por **todos** los caminos:
   - facturación desde el POS;
   - facturación de Octano (`ImportExternalInvoice`, `OrdenNumero`);
   - cualquier otro camino que exista.
2. Saber cómo se ve una **orden facturada en partes**. ¿Varias facturas con el mismo `OrderNumber`? ¿La orden sigue
   abierta en A con lo que queda pendiente?
3. Confirmar que, al facturarse por completo, la orden **sale de A** (deja de estar abierta). Si se borra (como hace Octano
   cuando no queda nada pendiente), también nos sirve.

Si alguno de estos puntos no es posible, avísennos. Sin el enlace factura → orden tendríamos que pedir revisión
manual de cada factura.

## Preguntas

- ¿Los nombres de campo propuestos chocan con alguna convención suya? Podemos adaptarnos a los que entreguen.
- ¿`QuantityOrdered`/`Pending` vienen en la unidad de la línea o en la unidad mínima?
- ¿Hay otros estados de orden (cotizaciones `EsQuote`, órdenes en espera) que debamos excluir? Proponemos excluir cotizaciones.
