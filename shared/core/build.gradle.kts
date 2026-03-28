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
    val iosArm64Target = iosArm64()
    val iosSimulatorArm64Target = iosSimulatorArm64()
    val iosX64Target = iosX64()

    val xcframework = XCFramework("PindropSharedCore")

    listOf(
        macosArm64Target,
        macosX64Target,
        iosArm64Target,
        iosSimulatorArm64Target,
        iosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedCore"
            xcframework.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}
