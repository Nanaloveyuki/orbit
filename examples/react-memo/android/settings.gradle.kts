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
  }
}

val waseeAndroidDir = providers.gradleProperty("waseeAndroidDir").orNull
if (waseeAndroidDir != null) {
  includeBuild(file(waseeAndroidDir)) {
    dependencySubstitution {
      substitute(module("dev.nanaloveyuki.wasee:host"))
        .using(project(":host"))
    }
  }
}

rootProject.name = "orbit-react-memo-android"
include(":app")
