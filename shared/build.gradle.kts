import org.gradle.api.GradleException

plugins {
    kotlin("multiplatform") version "2.3.10" apply false
}

tasks.register("desktopWindowsStub") {
    group = "verification"
    description = "Fails fast to document that Windows support has not been implemented yet."
    doLast {
        throw GradleException("mingwX64 is a stub only. Windows support is not implemented yet.")
    }
}
