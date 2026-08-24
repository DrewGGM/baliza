package co.edu.eam.baliza.baliza

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Actividad principal.
 *
 * Su única responsabilidad añadida es transportar hasta Flutter la orden que
 * llega desde el atajo de ajustes rápidos. Se conserva en un campo y no se
 * entrega de inmediato porque el atajo puede arrancar la app desde cero: en
 * ese caso el canal todavía no existe cuando llega el intent, y entregarlo
 * entonces lo perdería en el vacío.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Flutter pregunta al arrancar si hay una orden esperando.
                    "consumePendingAction" -> {
                        result.success(pendingAction)
                        pendingAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        readAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readAction(intent)
        // Con la app ya viva, la orden se entrega en el acto.
        pendingAction?.let {
            channel?.invokeMethod("onAction", it)
            pendingAction = null
        }
    }

    private fun readAction(intent: Intent?) {
        val action = intent?.getStringExtra(SosTileService.EXTRA_ACTION)
        if (action != null) pendingAction = action
    }

    companion object {
        const val CHANNEL = "co.edu.eam.baliza/shortcuts"
    }
}
