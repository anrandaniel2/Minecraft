import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "MinecraftVulkanOverlay"
val pluginPackageName = "org.anrandaniel.minecraft.vulkanoverlay"

android {
    namespace = pluginPackageName
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        targetSdk = 35
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"$pluginName\"")

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

base {
    archivesName.set(pluginName)
}

dependencies {
    // The 4.7.1 Android library is the latest Godot API published to
    // MavenCentral; it is binary-compatible with the 4.7.2 export template.
    implementation("org.godotengine:godot:4.7.1.stable")
}
