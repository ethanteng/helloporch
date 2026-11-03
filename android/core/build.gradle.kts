import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The PorchCore port: plain Kotlin, so its tests run on the JVM without a device.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    api(libs.kotlinx.serialization.json)
    implementation(libs.libphonenumber)
    testImplementation(libs.kotlin.test.junit)
}

// The server's saved responses (tests/fixtures/), which ContractFixtureTest decodes. A changed fixture reruns the tests.
val contractFixtures = rootProject.layout.projectDirectory.dir("../tests/fixtures")
tasks.test {
    inputs.dir(contractFixtures).withPropertyName("contractFixtures")
    systemProperty("porch.fixtures", contractFixtures.asFile.absolutePath)
}
