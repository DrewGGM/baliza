# Estado de iOS

Este documento existe por honestidad: **el lado iOS está configurado pero no
compilado ni probado**, porque el desarrollo se hizo sin acceso a macOS. Aquí
queda exactamente qué está hecho, qué falta y cómo terminarlo.

---

## Lo que ya está hecho

| Elemento | Estado | Dónde |
|---|:---:|---|
| Código de dominio y aplicación | ✅ | Compartido con Android, sin cambios |
| Permisos y textos de justificación | ✅ | `ios/Runner/Info.plist` |
| Modos de segundo plano BLE + audio | ✅ | `ios/Runner/Info.plist` |
| Sesión de audio para la sirena | ✅ | `AVAudioSessionCategoryPlayback` |
| Claves de Actividades en Vivo | ✅ | `NSSupportsLiveActivities` |
| Entitlement de alertas críticas | ✅ declarado | `ios/Runner/Runner.entitlements` |

El transporte BLE usa `ble_peripheral` y `flutter_blue_plus`, que soportan iOS.
La capa nativa que habría que escribir a mano es la que se detalla abajo.

---

## Lo que falta, en orden

### 1. Enlazar el fichero de *entitlements* — 2 minutos

`Runner.entitlements` existe pero **no está referenciado** en el proyecto de
Xcode. No se enlazó desde aquí porque editar `project.pbxproj` a ciegas, sin
poder abrir Xcode para comprobarlo, es una forma habitual de romper el proyecto
entero.

En Xcode: selecciona el *target* `Runner` → **Build Settings** → busca
`Code Signing Entitlements` → escribe `Runner/Runner.entitlements`.

### 2. Solicitar el permiso de alertas críticas a Apple — días de espera

El entitlement está declarado, pero Apple **no lo concede solo**: hay que
pedirlo justificando el caso de uso en
[developer.apple.com/contact/request/notifications-critical-alerts](https://developer.apple.com/contact/request/notifications-critical-alerts).

Sin aprobación la app compila y funciona, pero el aviso «¿estás bien?» respeta
el modo silencioso — y quien duerme con el teléfono en silencio es exactamente
quien no va a responder a tiempo.

### 3. Actividades en Vivo — la pieza importante

**Es el equivalente iOS del servicio en primer plano de Android.** No es un
adorno: en iOS, una Actividad en Vivo activa mantiene viva la sesión de radio
mientras la app está en segundo plano. Sin ella, iOS suspende la app al
bloquear la pantalla y la baliza deja de emitir.

Requiere crear una **extensión de widget** en Xcode, que no se puede generar
desde fuera del IDE. Los pasos:

1. Xcode → **File › New › Target… › Widget Extension**
   - Nombre: `BalizaLiveActivity`
   - Marca **Include Live Activity**
2. Define el `ActivityAttributes` con lo que ya expone `SosController`:
   código corto de baliza, minutos emitiendo, batería y nivel de ahorro.
3. Comunica Flutter ↔ ActivityKit con un `MethodChannel`, siguiendo el mismo
   patrón que `lib/infrastructure/platform/shortcuts.dart` usa para el atajo de
   Android.
4. Arranca la actividad en `SosController.startSos()` y detenla en `stopSos()`,
   dentro del mismo bloque protegido que el resto de periféricos: si falla, la
   emisión de radio debe continuar.

> ⚠️ **Limitación conocida de iOS**: una Actividad en Vivo **no se puede
> iniciar** si la app lleva mucho tiempo en segundo plano — `Activity.request()`
> lanza `ActivityAuthorizationError.visibility`. Hay que crearla mientras la app
> está en primer plano, es decir, en el mismo momento en que la persona pulsa
> SOS. Con la detección automática de sismos esto importa: si el teléfono lleva
> horas bloqueado, la actividad no podrá crearse y habrá que degradar a una
> notificación normal.

### 4. Atajo equivalente al de Android

Android tiene el mosaico de ajustes rápidos. En iOS los equivalentes son:

- **Botón de Acción** (iPhone 15 Pro en adelante) vía App Intents
- **Atajo de Siri**: «Oye Siri, pide ayuda» — el más valioso, porque funciona
  con las manos atrapadas
- **Widget de pantalla de bloqueo** con el código de baliza, para poder
  cantarlo por radio sin desbloquear

---

## Cómo probarlo cuando haya un Mac

```bash
flutter build ios --release          # compilación
flutter build ipa --release          # paquete para distribución
```

El BLE **no funciona en el simulador de iOS**, igual que no funciona en el
emulador de Android. Hacen falta dos dispositivos físicos.

Para recorrer la interfaz sin hardware, activa **Ajustes → Modo simulación**.

---

## Diferencias de comportamiento frente a Android

| Aspecto | Android | iOS |
|---|---|---|
| Persistencia en segundo plano | Servicio en primer plano | Actividad en Vivo (pendiente) |
| Anuncio BLE en segundo plano | Completo | El UUID pasa al área de desbordamiento; **sólo lo ve quien filtra por ese UUID** |
| Permiso de ubicación | Necesario hasta Android 11 | No aplica |
| Exención de batería | Diálogo del sistema | No existe; lo resuelven los modos de segundo plano |
| Sonar en silencio | Canal de alarma | Requiere alertas críticas aprobadas por Apple |

La segunda fila explica una decisión del código que de otro modo parecería
arbitraria: `BleScanner` **siempre** filtra por el UUID de servicio. Es la única
forma de que un iPhone bloqueado siga siendo detectable.
