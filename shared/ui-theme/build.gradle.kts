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

    val xcframework = XCFramework("PindropSharedUITheme")

    listOf(
        macosArm64Target,
        macosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedUITheme"
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
