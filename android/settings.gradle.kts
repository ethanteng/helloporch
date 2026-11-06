pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // LiveKit's Android SDK depends on its fork of Twilio's audioswitch, published only on JitPack. Nothing else
        // may come from there.
        exclusiveContent {
            forRepository { maven("https://jitpack.io") }
            filter { includeModule("com.github.davidliu", "audioswitch") }
        }
    }
}

rootProject.name = "Porch"
include(":core", ":app")
