import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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
    linuxX64 {
        if (isLinuxHost) {
            compilations.getByName("main").cinterops {
                val libsecret by creating {
                    definitionFile = project.file("src/linuxX64Main/cinterop/libsecret.def")
                    packageName = "tech.watzon.pindrop.shared.core.cinterop.libsecret"
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
        commonMain.dependencies {
            implementation(project(":settings-schema"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
