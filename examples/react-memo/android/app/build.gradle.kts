import org.jetbrains.kotlin.gradle.dsl.JvmTarget

val configuredNdkPath = providers.environmentVariable("ANDROID_NDK_HOME").orNull
val ajniRoot = rootProject.layout.projectDirectory.dir(".mooncakes/Nanaloveyuki/ajni")

plugins {
  id("com.android.application")
  id("org.jetbrains.kotlin.android")
}

android {
  namespace = "dev.orbit.reactmemo"
  compileSdk = 35
  buildToolsVersion = "36.1.0"
  if (configuredNdkPath != null) {
    ndkPath = configuredNdkPath
  }
  ndkVersion = "29.0.14206865"

  defaultConfig {
    applicationId = "dev.orbit.reactmemo"
    minSdk = 24
    targetSdk = 35
    versionCode = 1
    versionName = "0.1.0"

    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    externalNativeBuild {
      cmake {
        cFlags += listOf("-std=c11")
      }
    }
    ndk {
      abiFilters += listOf("arm64-v8a", "x86_64")
    }
  }

  buildTypes {
    release {
      isMinifyEnabled = false
    }
  }

  sourceSets.getByName("main").java.srcDir(
    ajniRoot.dir("android/host/src/main/java"),
  )

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }

  externalNativeBuild {
    cmake {
      path = file("src/main/cpp/CMakeLists.txt")
      version = "4.1.2"
    }
  }
}

kotlin {
  compilerOptions {
    jvmTarget.set(JvmTarget.JVM_17)
  }
}

dependencies {
  implementation("androidx.activity:activity-ktx:1.9.3")
  implementation("androidx.webkit:webkit:1.12.1")
  androidTestImplementation("androidx.test.ext:junit:1.2.1")
  androidTestImplementation("androidx.test:core:1.6.1")
  androidTestImplementation("androidx.test:runner:1.6.2")
}
