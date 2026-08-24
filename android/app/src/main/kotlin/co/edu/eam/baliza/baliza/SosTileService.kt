package co.edu.eam.baliza.baliza

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Atajo de "pedir ayuda" en el panel de ajustes rápidos.
 *
 * ## Por qué existe
 *
 * Para usar la app hay que desbloquear el teléfono, encontrar el icono y
 * abrirla. Son tres pasos que asumen una mano libre, la pantalla intacta y la
 * cabeza despejada. Bajo una losa puede no darse ninguna de las tres.
 *
 * El panel de ajustes rápidos se despliega **sin desbloquear**, de un gesto,
 * desde cualquier pantalla. Es el camino más corto que ofrece Android para
 * llegar a una acción, y por eso vive aquí el botón de auxilio.
 *
 * ## Por qué abre la app en vez de emitir directamente
 *
 * Sería tentador iniciar la emisión desde aquí sin abrir nada. No se hace por
 * dos razones:
 *
 * 1. La baliza vive en el aislado de Flutter. Emitir desde el servicio del
 *    atajo exigiría duplicar la pila BLE en Kotlin, y dos implementaciones del
 *    mismo protocolo acaban divergiendo.
 * 2. Quien pide auxilio necesita **ver** que la señal salió. Un atajo que
 *    emite en silencio deja a la persona sin saber si funcionó, que es la peor
 *    incertidumbre posible en ese momento.
 */
@RequiresApi(Build.VERSION_CODES.N)
class SosTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = getString(R.string.tile_sos_label)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = getString(R.string.tile_sos_subtitle)
            }
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            // La app lee este extra al arrancar y activa la emisión sola.
            putExtra(EXTRA_ACTION, ACTION_START_SOS)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14 dejó de permitir `startActivityAndCollapse(Intent)` y
            // exige un PendingIntent. Llamar a la versión antigua lanza
            // UnsupportedOperationException y el atajo no haría nada.
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    companion object {
        const val EXTRA_ACTION = "baliza_action"
        const val ACTION_START_SOS = "start_sos"
    }
}
