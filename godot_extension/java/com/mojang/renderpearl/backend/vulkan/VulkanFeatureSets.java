package com.mojang.renderpearl.backend.vulkan;

import com.mojang.renderpearl.backend.vulkan.init.FeatureSet;
import com.mojang.renderpearl.backend.vulkan.init.VulkanPNextStruct;

import java.util.Set;

/**
 * Classpath overlay for the extracted Vulkan feature table.
 *
 * {@code ClientBootstrap.bootstrap()} initializes the real class before a device
 * exists. That initializer reflects on LWJGL Vulkan structs, which this native
 * image does not expose. The Godot backend never queries these sets; Vulkan is
 * only kept linkable as a fallback and is not the viewport renderer.
 */
public final class VulkanFeatureSets {
    public static final VulkanPNextStruct VK10_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct VK11_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct VK12_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct SYNC2_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct DYNAMIC_RENDERING_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct VERTEX_ATTRIB_DIVISOR_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct PORTABILITY_SUBSET_FEATURES_STRUCT = null;
    public static final VulkanPNextStruct MULTI_DRAW_FEATURES_STRUCT = null;

    public static final FeatureSet REQUIRED_FEATURESET = featureSet("godot-required");
    public static final FeatureSet PORTABILITY_SUBSET_FEATURESET = featureSet("godot-portability");
    public static final FeatureSet MULTI_DRAW_FEATURESET = featureSet("godot-multidraw");
    public static final FeatureSet AMD_BUFFER_MARKER_FEATURESET = featureSet("godot-amd-buffer-marker");
    public static final FeatureSet NV_DIAGNOSTIC_CHECKPOINT_FEATURESET = featureSet("godot-nv-checkpoint");
    public static final FeatureSet WIREFRAME_FEATURESET = featureSet("godot-wireframe");
    public static final FeatureSet CALIBRATED_TIMESTAMP_FEATURESET = featureSet("godot-timestamps");

    private VulkanFeatureSets() {
    }

    /** The extracted method is empty. Class initialization is the side effect. */
    public static void bootstrap() {
    }

    public static Set<FeatureSet> requiredFeatureSets() {
        return Set.of();
    }

    public static Set<FeatureSet> requiredIfExtensionsAvailableFeatureSets() {
        return Set.of();
    }

    public static Set<FeatureSet> optionalFeatureSets() {
        return Set.of();
    }

    private static FeatureSet featureSet(String name) {
        return new FeatureSet(name, Set.of(), Set.of());
    }
}
