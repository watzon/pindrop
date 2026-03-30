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
    mingwX64()

    val xcframework = XCFramework("PindropSharedRuntimeTranscription")

    listOf(
        macosArm64Target,
        macosX64Target,
    ).forEach { target ->
        target.binaries.framework {
            baseName = "PindropSharedRuntimeTranscription"
            export(project(":core"))
            transitiveExport = true
            xcframework.add(this)
        }
    }

    sourceSets {
        val desktopMain by creating {
            dependsOn(commonMain.get())
            dependencies {
                implementation("io.ktor:ktor-client-core:3.4.1")
            }
        }

        commonMain.dependencies {
            api(project(":core"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2")
            implementation("com.squareup.okio:okio:3.9.0")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
            implementation("io.ktor:ktor-client-mock:3.4.1")
            implementation("com.squareup.okio:okio-fakefilesystem:3.9.0")
        }

        jvmMain.get().dependsOn(desktopMain)
        linuxX64Main.get().dependsOn(desktopMain)
        linuxX64Main.dependencies {
            implementation("io.ktor:ktor-client-curl:3.4.1")
        }
        mingwX64Main.get().dependsOn(desktopMain)
    }
}
