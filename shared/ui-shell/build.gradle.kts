import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework
import java.io.ByteArrayOutputStream
import java.io.File

plugins {
    kotlin("multiplatform")
}

val isLinuxHost = System.getProperty("os.name")?.lowercase()?.contains("linux") == true

fun pkgConfigArgs(vararg args: String): List<String> {
    if (!isLinuxHost) return emptyList()

    val output = ByteArrayOutputStream()
    val process = ProcessBuilder(listOf("pkg-config", *args))
        .directory(File(project.projectDir.absolutePath))
        .redirectErrorStream(true)
        .start()

    process.inputStream.use { input ->
        input.copyTo(output)
    }

    check(process.waitFor() == 0) {
        "pkg-config ${args.joinToString(" ")} failed: ${output.toString().trim()}"
    }

    return output
        .toString()
        .trim()
        .split(Regex("\\s+"))
        .filter { it.isNotBlank() }
}

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
                    compilerOpts(*pkgConfigArgs("--cflags", "gtk4").toTypedArray())
                }
                val libadwaita by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/libadwaita.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.libadwaita"
                    compilerOpts(*pkgConfigArgs("--cflags", "libadwaita-1").toTypedArray())
                }
                val appindicator by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/appindicator.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.appindicator"
                    compilerOpts(*pkgConfigArgs("--cflags", "ayatana-appindicator3-0.1", "gtk+-3.0").toTypedArray())
                }
                val x11 by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/x11.def")
                    packageName = "tech.watzon.pindrop.shared.uishell.cinterop.x11"
                    compilerOpts(*pkgConfigArgs("--cflags", "x11").toTypedArray())
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
            implementation(project(":feature-transcription"))
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
