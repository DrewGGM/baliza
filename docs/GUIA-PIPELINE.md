# Guía de instalación y ejecución del pipeline

Esta guía explica cómo preparar el ambiente, qué parámetros tiene el pipeline y cómo ejecutarlo. También explica cómo hacer fallar una prueba a propósito y dónde se ve ese fallo.

Hay dos caminos y sirven igual:

| Camino | Qué se necesita | Cuándo conviene |
|---|---|---|
| **A. GitHub Actions** | Solo una cuenta de GitHub | Es el pipeline completo: pruebas, APK y publicación |
| **B. En el computador** | Git y Flutter 3.47.1 | Para correr las pruebas sin usar GitHub |

---

## 1. Qué hace el pipeline

El archivo es [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) y en GitHub aparece con el nombre **Pipeline CI/CD**. Tiene tres trabajos encadenados. Cada uno arranca solo si el anterior terminó en verde.

```
Build & Test  ──►  Build APK  ──►  Deploy a Runtime
```

| Trabajo | Qué hace | Duración típica |
|---|---|---|
| **Build & Test** | Descarga el código, instala JDK 17 y Flutter 3.47.1, resuelve dependencias, corre el análisis estático y ejecuta las **113 pruebas unitarias**. Guarda el reporte de cobertura | 1 a 2 minutos |
| **Build APK** | Compila el APK de release, uno por arquitectura | 6 a 8 minutos |
| **Deploy a Runtime** | Publica los APK en una Release de GitHub llamada `Baliza build N` | Unos 10 segundos |

Si una prueba falla, **Build & Test** queda en rojo y los otros dos trabajos no se ejecutan. Así ningún APK con pruebas fallidas llega a publicarse.

---

## 2. Camino A: ejecutarlo en GitHub Actions

### 2.1 Hacer una copia del repositorio

1. Entrar a https://github.com/DrewGGM/baliza con una cuenta de GitHub.
2. Pulsar **Fork** arriba a la derecha y luego **Create fork**.

El pipeline corre sobre la copia y deja el repositorio original intacto.

### 2.2 Habilitar Actions en la copia

GitHub deja desactivados los workflows en toda copia nueva. Hay que activarlos una vez:

1. En la copia, abrir la pestaña **Actions**.
2. Pulsar **I understand my workflows, go ahead and enable them**.

No hay secretos que configurar. El pipeline solo usa `GITHUB_TOKEN` y GitHub lo crea solo en cada ejecución. El ambiente `distribucion` que usa el despliegue también lo crea GitHub la primera vez.

### 2.3 Lanzar el pipeline

Hay dos formas:

- **A mano:** Actions → **Pipeline CI/CD** en la lista de la izquierda → botón **Run workflow** → rama `master` → **Run workflow**.
- **Con un cambio:** cualquier commit en `master` lo dispara solo. Basta editar un archivo en la web de GitHub y confirmar el cambio.

### 2.4 Dónde ver el resultado

Al abrir la ejecución aparece el diagrama de los tres trabajos.

| Qué se quiere ver | Dónde está |
|---|---|
| Cuántas pruebas pasaron | **Build & Test** → paso **Ejecutar pruebas unitarias** → última línea: `+113: All tests passed!` |
| Una prueba concreta | En ese mismo paso, la lupa del log, arriba a la derecha, buscando parte del nombre de la prueba |
| El reporte de cobertura | Al final de la página de la ejecución, artefacto **cobertura-lcov** |
| El APK compilado | Artefacto **baliza-apk**, o el paso **Compilar el APK de release** dentro de **Build APK** |
| La publicación | Pestaña **Releases** del repositorio: `Baliza build N` con tres APK |
| En qué máquina corrió | **Build & Test** → **Set up job** → línea `Image:` |

---

## 3. Parámetros del pipeline

Todo se configura dentro de `.github/workflows/ci.yml`. Para cambiar un parámetro se edita la línea indicada y se confirma el cambio. El pipeline corre de nuevo con el valor nuevo.

| Parámetro | Línea | Valor actual | Para qué sirve |
|---|---|---|---|
| Disparadores `on:` | 26 a 31 | push y pull request hacia `master` o `main`, más el botón manual `workflow_dispatch` | Decide qué eventos lanzan el pipeline. Para que corra en otra rama se agrega a la lista `branches`, por ejemplo `[master, main, dev]` |
| `concurrency` | 35 a 37 | `cancel-in-progress: true` | Si llegan dos commits seguidos cancela la ejecución vieja y deja la del último |
| `FLUTTER_VERSION` | 41 | `3.47.1` | Versión del SDK que se instala en el servidor. Debe coincidir con la que se usa en local |
| `JAVA_VERSION` | 42 | `"17"` | JDK que necesita Gradle para compilar el APK |
| `runs-on` | 51, 105 y 155 | `ubuntu-latest` | Máquina virtual de GitHub donde corre cada trabajo. Se crea limpia en cada ejecución |
| Análisis estático | 81 | `flutter analyze --fatal-infos` | Cualquier aviso del analizador detiene el pipeline |
| Pruebas | 87 | `flutter test --coverage --reporter expanded` | Ejecuta las pruebas, genera la cobertura y escribe en el log el nombre de cada prueba |
| Conservación de artefactos | 97 y 142 | `retention-days: 30` | Días que GitHub guarda la cobertura y los APK |
| `needs` | 106 y 156 | `build-and-test` y `empaquetado` | La cadena que corta el pipeline cuando un trabajo falla |
| `if:` | 107 y 157 | solo `master` o `main` | En pull requests y otras ramas solo corren las pruebas. El APK y la Release quedan para la rama principal |
| `permissions` | 159 y 160 | `contents: write` | Permiso que necesita el despliegue para crear la Release |
| `tag_name` | 177 | `build-${{ github.run_number }}` | Etiqueta de la Release. El número es el de la ejecución |

---

## 4. Camino B: ejecutarlo en el computador

Sirve en Windows, macOS y Linux. Corre los mismos comandos que el trabajo **Build & Test**.

### 4.1 Instalar Flutter 3.47.1

Necesita Git. Flutter ya trae su propio Dart, el 3.13.

```bash
git clone --depth 1 --branch 3.47.1 https://github.com/flutter/flutter.git
```

Después se agrega la carpeta `flutter/bin` al `PATH` y se comprueba:

```bash
flutter --version     # Flutter 3.47.1 • channel stable … Dart 3.13.1
```

En Windows, para la sesión actual de PowerShell:

```powershell
$env:Path = "C:\ruta\donde\quedo\flutter\bin;$env:Path"
```

Para correr las pruebas no hacen falta JDK, Android SDK ni un teléfono. Solo se necesitan si además se quiere compilar el APK.

### 4.2 Descargar el proyecto y correr el pipeline

```bash
git clone https://github.com/DrewGGM/baliza.git
cd baliza
flutter pub get                                  # dependencias
flutter analyze --fatal-infos                    # análisis estático
flutter test --coverage --reporter expanded      # pruebas unitarias
```

Resultado esperado:

```
No issues found!
...
00:08 +113: All tests passed!
```

### 4.3 Correr un archivo o una sola prueba

```bash
flutter test test/domain/power_policy_test.dart
flutter test --plain-name "por debajo del 10 % sólo queda la radio"
```

`--plain-name` busca el texto dentro del nombre. Si un pedazo del nombre coincide con varias pruebas corren todas las que coincidan.

### 4.4 Ver la cobertura del dominio

El criterio del plan de pruebas es al menos 80 % sobre `lib/domain`. Hoy da **85,2 %**.

PowerShell:

```powershell
$lf=0;$lh=0;$dom=$false; Get-Content coverage/lcov.info | ForEach-Object { if ($_ -like 'SF:*') { $dom = $_ -match 'lib[\\/]domain' } elseif ($dom -and $_ -like 'LF:*') { $lf += [int]$_.Substring(3) } elseif ($dom -and $_ -like 'LH:*') { $lh += [int]$_.Substring(3) } }; "Cobertura del dominio: {0:N1} %" -f (100*$lh/$lf)
```

macOS o Linux:

```bash
awk '/^SF:/{d=($0 ~ /lib[\\\/]domain/)} d&&/^LF:/{split($0,a,":");lf+=a[2]} d&&/^LH:/{split($0,a,":");lh+=a[2]} END{printf "Cobertura del dominio: %.1f %%\n",100*lh/lf}' coverage/lcov.info
```

### 4.5 Compilar el APK, opcional

Requiere JDK 17 y el Android SDK, que se instala con Android Studio.

```bash
flutter build apk --release --split-per-abi
```

Los APK quedan en `build/app/outputs/flutter-apk/`.

---

## 5. Hacer fallar una prueba a propósito

Cualquier prueba sirve. La regla general es cambiar el valor esperado dentro de su `expect(...)`. Estas tres ya están ensayadas y se sabe exactamente qué muestran:

| Archivo y línea | Cambio | Lo que aparece en el log |
|---|---|---|
| `test/domain/sos_payload_codec_test.dart`, línea 36 | `0x29B1` por `0x29B2` | `el vector canónico del estándar da 0x29B1 [E]` con `Expected: <10674>` y `Actual: <10673>`. El log muestra los números en decimal |
| `test/domain/power_policy_test.dart`, línea 30 | `PowerTier.critical` por `PowerTier.saving` | `por debajo del 10 % sólo queda la radio [E]` con `Expected: PowerTier.saving` y `Actual: PowerTier.critical` |
| `test/domain/triage_test.dart`, línea 102 | `severe.beaconId` por `mild.beaconId` | `por gravedad, el perfil más grave va primero [E]` con `Expected: <3003>` y `Actual: <2730>` |

También se puede dañar el código en vez de la prueba. En `lib/domain/services/power_policy.dart`, línea 52, cambiar `minBattery: 10` por `minBattery: 0` hace fallar `por debajo del 10 % sólo queda la radio` con `Expected: PowerTier.critical` y `Actual: PowerTier.low`. Es la prueba haciendo su trabajo: detecta que la regla de negocio cambió.

### 5.1 En GitHub

1. En la copia, abrir el archivo de la prueba y pulsar el lápiz **Edit this file**.
2. Hacer el cambio y pulsar **Commit changes** sobre `master`.
3. El pipeline arranca solo. En Actions, **Build & Test** queda en rojo en uno o dos minutos.
4. **Build APK** y **Deploy a Runtime** aparecen como omitidos y no se publica ninguna Release.
5. En **Build & Test** → **Ejecutar pruebas unitarias** se ve la prueba marcada con `[E]`, los valores `Expected` y `Actual` y al final `Some tests failed.`

Para volver a verde se deshace el cambio con otro commit. Si se suben dos commits seguidos el pipeline cancela la ejecución vieja, así que conviene esperar a ver el rojo antes de corregir.

### 5.2 En el computador

```bash
# hacer el cambio y guardar
flutter test --reporter expanded       # termina en "Some tests failed."
git checkout -- test/ lib/             # deshace el cambio
flutter test                           # vuelve a "+113: All tests passed!"
```

---

## 6. Las pruebas del plan y dónde están

El plan de pruebas eligió estas 20 para el pipeline, al menos una por regla de negocio. Todas están en `test/domain/`.

| # | Caso | Prueba | Archivo y línea |
|---|---|---|---|
| 1 | CP-01 | el vector canónico del estándar da 0x29B1 | `sos_payload_codec_test.dart:35` |
| 2 | CP-01 | la entrada vacía da el valor inicial 0xFFFF | `sos_payload_codec_test.dart:39` |
| 3 | CP-02 | la trama mide exactamente 16 bytes | `sos_payload_codec_test.dart:53` |
| 4 | CP-02 | un CRC alterado hace que tryDecode devuelva null | `sos_payload_codec_test.dart:201` |
| 5 | CP-02 | una versión desconocida se rechaza aunque el CRC cuadre | `sos_payload_codec_test.dart:216` |
| 6 | CP-02 | los minutos y las personas saturan en 255 en vez de desbordar | `sos_payload_codec_test.dart:166` |
| 7 | CP-03 | el RSSI de referencia corresponde a un metro | `distance_estimator_test.dart:16` |
| 8 | CP-03 | clasifica cada distancia en su banda | `distance_estimator_test.dart:41` |
| 9 | CP-03 | la media recortada absorbe una lectura atípica | `distance_estimator_test.dart:71` |
| 10 | CP-04 | reconoce que el rescatista se acerca | `distance_estimator_test.dart:78` |
| 11 | CP-05 | con barómetro exige tres sensores | `disaster_detector_test.dart:24` |
| 12 | CP-05 | una anomalía vieja no cuenta como simultánea | `disaster_detector_test.dart:82` |
| 13 | CP-05 | suprime las réplicas y vuelve a detectar al enfriarse | `disaster_detector_test.dart:185` |
| 14 | CP-06 | por debajo del 10 % sólo queda la radio | `power_policy_test.dart:29` |
| 15 | CP-06 | sin lectura de batería se asume el mejor caso | `power_policy_test.dart:34` |
| 16 | CP-06 | el nivel crítico retira todo lo auxiliar y nada más | `power_policy_test.dart:42` |
| 17 | CP-06 | una batería que fluctúa en el umbral no oscila de nivel | `power_policy_test.dart:63` |
| 18 | CP-07 | no rota aunque pasen horas, y al terminar fuerza uno nuevo | `beacon_identity_test.dart:44` |
| 19 | CP-08 | por gravedad, el perfil más grave va primero | `triage_test.dart:84` |
| 20 | CP-08 | ordenar no pierde ni duplica balizas | `triage_test.dart:172` |

Los demás casos del plan también tienen sus pruebas y corren en el mismo pipeline:

| Caso | Qué verifica | Dónde |
|---|---|---|
| CP-09 | La confirmación de 2 minutos tras detectar un sismo | `test/application/detection_controller_test.dart` |
| CP-10 | La ficha médica convertida a códigos y de vuelta | `test/domain/medical_profile_test.dart` |
| CP-11 | El registro de supervivientes | `test/domain/survivor_registry_test.dart` |
| CP-12 | La entidad de la señal de auxilio | `test/domain/sos_signal_test.dart` |
| CP-13 | El reloj simulado de las pruebas | `test/domain/clock_test.dart` |

---

## 7. Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| En la copia no aparece el botón **Run workflow** | Actions no está habilitado en la copia, ver el punto 2.2. O la página abierta no es la del workflow: hay que elegir **Pipeline CI/CD** en la lista de la izquierda |
| Un commit no lanzó el pipeline | El commit no fue a `master` ni a `main`. Se agrega la rama en la línea 28 o se usa **Run workflow** |
| **Build & Test** sale en rojo sin que se haya tocado ninguna prueba | Abrir el paso que falló. Si es **Instalar Flutter** o **Instalar dependencias** fue un problema de red del servidor y basta **Re-run jobs** |
| En local el análisis o las pruebas dan resultados distintos | Revisar con `flutter --version` que sea la 3.47.1. Otra versión puede traer reglas de análisis distintas |
| `flutter` no se reconoce como comando | La carpeta `flutter/bin` no está en el `PATH` de esa terminal |
| `flutter build apk` falla en local | Falta JDK 17 o el Android SDK. Para correr las pruebas no hacen falta |
