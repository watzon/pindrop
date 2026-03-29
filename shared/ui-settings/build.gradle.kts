import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

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

    val xcframework = XCFramework("PindropSharedSettings")

    listOf(macosArm64Target, macosX64Target).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedSettings"
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
