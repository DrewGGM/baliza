# Protocolo Baliza v1

Especificación del formato de anuncio que Baliza emite y reconoce por Bluetooth
de baja energía.

Este documento es normativo: cualquier implementación que lo siga es
interoperable con Baliza, y eso es deliberado. Una herramienta de rescate cuyo
formato sólo entiende una app es una herramienta a medias — el objetivo es que
un equipo de bomberos pueda escribir su propio receptor si lo necesita.

---

## 1. Presupuesto de bytes

Un anuncio BLE *legacy* transporta **31 bytes** de datos. El reparto de Baliza:

| Estructura AD | Bytes | Contenido |
|---|---:|---|
| Flags | 3 | `02 01 06` — LE General Discoverable, sin BR/EDR |
| Complete List of 16-bit Service UUIDs | 4 | UUID de servicio `0xB4A1` |
| Manufacturer Specific Data | 22 | Cabecera (4) + firma (2) + trama (16) |
| **Total** | **29** | quedan 2 bytes de margen |

Los datos de fabricante viajan en la **respuesta de escaneo** (`scan response`),
no en el anuncio principal, para que el UUID de servicio quepa holgadamente en
la trama primaria — que es por donde filtra el receptor.

### Identificador de fabricante

Se usa **`0xFFFF`**, reservado por la especificación Bluetooth para pruebas y
desarrollo. Es lo correcto mientras el proyecto no tenga un identificador propio
asignado por el Bluetooth SIG; usar el de otra empresa sería incorrecto y haría
que sus dispositivos interpretaran mal estas tramas.

Como `0xFFFF` lo puede usar cualquiera, la trama **no se identifica sólo por ese
número**. Lleva además una firma y un CRC.

### Firma

Los dos primeros bytes de los datos de fabricante son `0x42 0x5A` — los
caracteres ASCII `BZ`. Es el filtro más barato y descarta de inmediato el ruido
de otros dispositivos que también usan `0xFFFF`.

---

## 2. Mapa de la trama

16 bytes. Todos los enteros multibyte en **big-endian** (orden de red).

```
 Offset  Tam  Campo
 ──────  ───  ─────────────────────────────────────────────────────────
 0       1    versión (4 bits altos) | tipo de mensaje (4 bits bajos)
 1       1    indicadores de situación (máscara de bits)
 2       4    identificador de baliza (uint32)
 6       1    batería 0..100   (0xFF = desconocida)
 7       1    minutos emitiendo 0..254   (0xFF = 254 o más)
 8       1    grupo sanguíneo (4 bits altos) | franja etaria (4 bits bajos)
 9       1    condiciones médicas (máscara de bits)
 10      1    alergias (máscara de bits)
 11      1    personas en el punto 0..254   (0xFF = 254 o más)
 12      2    reservado — debe ser 0x0000 en v1
 14      2    CRC-16/CCITT-FALSE sobre los bytes 0..13
```

### 2.1 Byte 0 — versión y tipo

`versión` vale `1` en esta especificación. Un receptor **debe descartar** toda
trama cuya versión no reconozca: es preferible ignorar una baliza que
interpretar mal una ficha médica.

| Tipo | Valor | Significado |
|---|---:|---|
| `SOS` | 1 | Solicitud de auxilio activa |
| `SAFE` | 2 | «Estoy bien» — permite descartar a alguien de la búsqueda |
| `RESPONDER` | 3 | Presencia de un equipo de rescate |

### 2.2 Byte 1 — indicadores

| Bit | Nombre | Significado |
|---:|---|---|
| 0 | `manual` | La persona pulsó el botón deliberadamente |
| 1 | `autoDetected` | Se activó sola tras detectar un sismo |
| 2 | `medicalPresent` | La trama incluye ficha médica diligenciada |
| 3 | `trapped` | Declara estar atrapada o inmovilizada |
| 4 | `mobilityImpaired` | Movilidad reducida |
| 5 | `lowBattery` | Batería en el umbral crítico o por debajo (≤ 15 %) |
| 6 | `minorsPresent` | Hay menores de edad en el mismo punto |
| 7 | — | Reservado |

Los bits `medicalPresent` y `lowBattery` son **derivados**: el emisor los calcula
a partir del estado real y no acepta el valor que le pasen. Así no pueden quedar
desincronizados del contenido de la trama.

### 2.3 Bytes 2–5 — identificador

Entero de 32 bits **seudónimo**. No se deriva de ningún dato del dispositivo ni
de la persona: se sortea con un generador criptográfico. Los valores `0x00000000`
y `0xFFFFFFFF` están reservados y nunca se emiten.

**Política de rotación:** el identificador cambia cada **15 minutos** en reposo.
Mientras hay una emisión de auxilio activa queda **congelado**, porque el equipo
de rescate necesita seguir la misma señal mientras se acerca. Al terminar la
emergencia se fuerza uno nuevo de inmediato.

### 2.4 Byte 8 — grupo sanguíneo y edad

| Grupo | Código | | Franja | Código |
|---|---:|---|---|---:|
| Desconocido | 0 | | Desconocida | 0 |
| O− | 1 | | 0–2 años | 1 |
| O+ | 2 | | 3–11 años | 2 |
| A− | 3 | | 12–17 años | 3 |
| A+ | 4 | | 18–39 años | 4 |
| B− | 5 | | 40–59 años | 5 |
| B+ | 6 | | 60–74 años | 6 |
| AB− | 7 | | 75+ años | 7 |
| AB+ | 8 | | | |

La edad viaja **en franjas y no exacta**: basta para priorizar el triaje y reduce
la identificabilidad de la persona.

### 2.5 Bytes 9 y 10 — máscaras médicas

**Condiciones** (byte 9):

| Bit | Condición | | Bit | Condición |
|---:|---|---|---:|---|
| 0 | Diabetes | | 4 | Embarazo |
| 1 | Cardiopatía | | 5 | Anticoagulantes |
| 2 | Enf. respiratoria | | 6 | Enfermedad renal |
| 3 | Epilepsia | | 7 | Inmunosupresión |

**Alergias** (byte 10):

| Bit | Alergia | | Bit | Alergia |
|---:|---|---|---:|---|
| 0 | Penicilina | | 4 | Yodo / contraste |
| 1 | Sulfas | | 5 | Anestésicos |
| 2 | AINEs | | 6 | Mariscos |
| 3 | Látex | | 7 | Otra |

### 2.6 Bytes 14–15 — CRC

**CRC-16/CCITT-FALSE**: polinomio `0x1021`, valor inicial `0xFFFF`, sin reflexión
de entrada ni de salida, sin XOR final. Se calcula sobre los bytes `0..13`.

Vector de comprobación: `CRC("123456789") = 0x29B1`.

Se eligió por ser el estándar de facto en enlaces de radio cortos y por detectar
de forma fiable las ráfagas de error típicas de un canal 2,4 GHz saturado, que es
exactamente el escenario tras un sismo urbano.

---

## 3. Reglas de recepción

Un receptor conforme debe rechazar la trama, en este orden:

1. El identificador de fabricante no es `0xFFFF`
2. Los datos de fabricante miden menos de 18 bytes
3. Los dos primeros bytes no son `0x42 0x5A`
4. El CRC calculado no coincide con el transmitido
5. La versión no es `1`
6. El tipo de mensaje no está en el catálogo

El orden va del filtro más barato al más caro a propósito: en un entorno urbano
llegan cientos de anuncios BLE por minuto y casi ninguno es una Baliza.

**Nunca se debe entregar una ficha médica que no haya superado el CRC.** Un dato
equivocado sobre alergias puede matar; es preferible descartar la trama entera.

---

## 4. Cadencia de emisión

| Parámetro | Valor | Motivo |
|---|---|---|
| Intervalo de anuncio | ~900 ms | Compromiso entre latencia de detección y batería |
| Refresco de contenido | 30 s | Actualiza minutos transcurridos y batería |
| Ventana de escaneo | continua, baja latencia | Durante un rescate se compra latencia |

El anuncio BLE no admite cambiar la carga útil en caliente: refrescar exige
detener y reiniciar el anuncio. El corte dura milisegundos y ocurre cada 30
segundos, así que el receptor no lo percibe.

---

## 5. Consideraciones por plataforma

### Android

La emisión continúa mientras el proceso viva. Es imprescindible un **servicio en
primer plano** con notificación persistente; sin él, el sistema mata el proceso
al apagar la pantalla y la señal desaparece.

Desde Android 12 se usan `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE` y
`BLUETOOTH_CONNECT`. El escaneo se declara con el flag **`neverForLocation`**,
que es cierto: Baliza sólo mide potencia de señal y no deduce ubicación.

### iOS

En segundo plano el sistema **degrada el anuncio**: el UUID de servicio se
traslada al área de desbordamiento de la trama y deja de ser visible para
escáneres que no lo busquen de forma explícita.

Por eso el escáner **debe filtrar siempre por el UUID de servicio `0xB4A1`**. Es
la única forma de que un iPhone bloqueado siga siendo detectable.

Requiere declarar los modos de segundo plano `bluetooth-central`,
`bluetooth-peripheral` y `audio`.

---

## 6. Estimación de distancia

El receptor traduce la potencia recibida (RSSI, en dBm) a distancia mediante el
modelo log-distancia de pérdida de trayecto:

```
d = 10 ^ ((P₁ₘ − RSSI) / (10 · n))
```

- `P₁ₘ` — RSSI de referencia a un metro. Por defecto **−59 dBm**, el valor que
  usan como referencia las implementaciones iBeacon.
- `n` — exponente de pérdida del medio:

| Entorno | `n` |
|---|---:|
| Campo abierto, línea de vista | 2,0 |
| Interior convencional | 2,8 |
| **Estructura colapsada** | **3,5** |

### El modelo es malo, y hay que decirlo

Todos los modelos RSSI lo son: la orientación del cuerpo, el modelo de teléfono,
la humedad y una pared cambian la lectura varios decibelios.

Se usa igual porque la alternativa —no dar ninguna pista de distancia— es peor, y
porque el rescatista no necesita la distancia: **necesita saber si se está
acercando**.

Por eso una implementación conforme:

- Aplica **media recortada** sobre las últimas ~8 lecturas, descartando los
  extremos, antes de estimar.
- Presenta el resultado en **bandas anchas** (`< 2 m`, `2–5 m`, `5–15 m`,
  `> 15 m`), nunca como una cifra con decimales.
- Muestra una **tendencia** comparando la mitad reciente de la serie contra la
  anterior, con un umbral de 3 dB para no confundir ruido con movimiento.
- Expone la **confianza** de la estimación al usuario. Un rescatista que sabe que
  la medición es débil busca con más criterio propio.

---

## 7. Cambios futuros

Los bytes 12–13 están reservados y deben transmitirse a cero. Un receptor v1 los
ignora, de modo que una futura v2 puede usarlos sin romper la compatibilidad
hacia atrás, siempre que incremente el campo de versión.

**Nunca se debe reordenar ni reutilizar un código de catálogo existente.** Una
baliza emitida por una versión previa de la app debe seguir siendo interpretable.
