allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// ---------------------------------------------------------------------------
// Unificación de compileSdk entre plugins.
//
// Varios plugins de la comunidad declaran compileSdk 37, que Gradle resuelve
// contra el identificador `android-37`. El SDK sólo publica hoy la plataforma
// `android-37.0`, cuyo identificador NO coincide, y la compilación falla con
// "Failed to find target with hash string 'android-37'".
//
// Se fuerza a todos los subproyectos Android a compilar contra la 36, que es
// una plataforma estable y publicada. Esto sólo afecta a la API contra la que
// se compila, no a `minSdk` ni a `targetSdk`, así que el comportamiento en el
// dispositivo no cambia.
//
// El enganche va por `plugins.withId`, que reacciona en cuanto el plugin de
// Android se aplica. Un `afterEvaluate` aquí llegaría tarde: el bloque
// `evaluationDependsOn(":app")` de más abajo ya habría evaluado el proyecto.
//
// Retirar cuando `platforms;android-37` esté disponible en el repositorio.
// ---------------------------------------------------------------------------
val unifiedCompileSdk = 36

subprojects {
    listOf("com.android.application", "com.android.library").forEach { pluginId ->
        plugins.withId(pluginId) {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileSdkVersion(unifiedCompileSdk)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
