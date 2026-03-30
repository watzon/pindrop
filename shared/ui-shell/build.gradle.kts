import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    kotlin("multiplatform")
}

val isLinuxHost = System.getProperty("os.name")?.lowercase()?.contains("linux") == true

kotlin {
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_21)
        }
    }
    val macosArm64Target = macosArm64()
    val macosX64Target = macosX64()

    val xcframework = XCFramework("PindropSharedNavigation")

    listOf(macosArm64Target, macosX64Target).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedNavigation"
            xcframework.add(this)
        }
    }

    linuxX64 {
        if (isLinuxHost) {
            compilations.getByName("main").cinterops {
                val gtk4 by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/gtk4.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.gtk4"
                }
                val libadwaita by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/libadwaita.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.libadwaita"
                }
                val appindicator by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/appindicator.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.appindicator"
                }
            }
        }

        binaries {
            executable {
                entryPoint = "tech.watzon.pindrop.shared.ui.shell.linux.main"
            }
        }
    }

    sourceSets {
        commonMain.dependencies {
        }
        linuxX64Main.dependencies {
            implementation(project(":core"))
            implementation(project(":feature-transcription"))
            implementation(project(":runtime-transcription"))
            implementation(project(":settings-schema"))
            implementation(project(":ui-localization"))
            implementation(project(":ui-settings"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
