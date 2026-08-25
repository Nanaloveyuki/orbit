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
  val moonWorkspace = rootDir.resolve("moon.work")
  val ownsMoonWorkspace = !moonWorkspace.exists()
  if (ownsMoonWorkspace) {
    moonWorkspace.writeText("members = [\".\", \"../../..\"]\n")
    gradle.buildFinished {
      moonWorkspace.delete()
    }
  }
  includeBuild(file(waseeAndroidDir)) {
    dependencySubstitution {
      substitute(module("dev.nanaloveyuki.wasee:host"))
        .using(project(":host"))
    }
  }
}

rootProject.name = "orbit-react-memo-android"
include(":app")
