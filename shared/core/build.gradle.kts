import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.ByteArrayOutputStream

plugins {
    kotlin("multiplatform")
}

val isLinuxHost = System.getProperty("os.name")?.lowercase()?.contains("linux") == true

fun pkgConfigArgs(vararg args: String): List<String> {
    if (!isLinuxHost) return emptyList()

    val output = ByteArrayOutputStream()
    project.exec {
        commandLine("pkg-config", *args)
        standardOutput = output
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
    linuxX64 {
        if (isLinuxHost) {
            compilations.getByName("main").cinterops {
                val libsecret by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/libsecret.def")
                    packageName = "tech.watzon.pindrop.shared.core.cinterop.libsecret"
                    compilerOpts(*pkgConfigArgs("--cflags", "libsecret-1").toTypedArray())
                    linkerOpts(*pkgConfigArgs("--libs", "libsecret-1").toTypedArray())
                }
            }
        }
    }
    mingwX64()

    val xcframework = XCFramework("PindropSharedCore")

    listOf(
        macosArm64Target,
        macosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedCore"
            xcframework.add(this)
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(project(":settings-schema"))
            }
        }

        val macosMain by creating {
            dependsOn(commonMain)
        }

        getByName("macosArm64Main").dependsOn(macosMain)
        getByName("macosX64Main").dependsOn(macosMain)

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
