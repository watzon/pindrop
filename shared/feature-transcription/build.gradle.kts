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

    val xcframework = XCFramework("PindropSharedTranscription")

    listOf(
        macosArm64Target,
        macosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedTranscription"
            xcframework.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(project(":core"))
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
