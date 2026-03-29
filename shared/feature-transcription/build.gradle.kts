import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform")
}

kotlin {
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_21)
        }
    }
    val macosArm64Target = macosArm64()
    val macosX64Target = macosX64()
    linuxX64()

    val xcframework = XCFramework("PindropSharedTranscription")

    listOf(
        macosArm64Target,
        macosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedTranscription"
            export(project(":runtime-transcription"))
            export(project(":core"))
            transitiveExport = true
            xcframework.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            api(project(":runtime-transcription"))
            api(project(":core"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
        }
    }
}
