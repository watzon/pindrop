pluginManagement {
    repositories {
        google()
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "pindrop-shared"

include(":core")
include(":feature-transcription")
include(":runtime-transcription")
include(":ui-shell")
include(":ui-settings")
include(":ui-theme")
include(":ui-workspace")
