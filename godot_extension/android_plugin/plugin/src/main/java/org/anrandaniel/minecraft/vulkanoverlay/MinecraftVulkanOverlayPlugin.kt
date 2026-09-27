package org.anrandaniel.minecraft.vulkanoverlay

import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.widget.FrameLayout
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/**
 * A very small Android composition bridge for an unmodified Minecraft client.
 *
 * The client owns Vulkan and presents into this SurfaceView. Godot remains the
 * host activity and can keep its scene tree, input and HUD alive underneath it.
 * No Godot RenderingDevice or Minecraft RenderPearl classes are referenced
 * here. The optional native bridge forwards the Android ANativeWindow to a
 * VulkanMod/Pojav-style client bridge when one is present in the process.
 *
 * This class intentionally does not bundle VulkanMod. VulkanMod is a Fabric
 * client renderer and must be installed in the Minecraft runtime/profile that
 * is launched beside this surface. The plugin only solves Android surface
 * ownership and composition.
 */
class MinecraftVulkanOverlayPlugin(godot: Godot) : GodotPlugin(godot) {
    companion object {
        private const val TAG = "MinecraftVulkanOverlay"

        init {
            try {
                System.loadLibrary("minecraft_vulkanmod_bridge")
            } catch (error: UnsatisfiedLinkError) {
                Log.w(TAG, "Native surface bridge is not packaged", error)
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var surfaceView: MinecraftSurfaceView? = null
    private var overlayVisible = false
    private var surfaceReady = false
    private var clientBridgeAttached = false
    private var surfaceWidth = 0
    private var surfaceHeight = 0
    private var surfaceGeneration = 0L

    override fun getPluginName(): String = "MinecraftVulkanOverlay"

    /**
     * Adds the client surface to the activity's content root. It is added last
     * and uses an on-top SurfaceView so VulkanMod's swapchain is composited
     * above Godot rather than competing for Godot's Vulkan device.
     */
    @UsedByGodot
    fun showMinecraftOverlay(): Boolean {
        runOnHostThread {
            val view = ensureSurfaceView()
            view.visibility = View.VISIBLE
            overlayVisible = true
        }
        return true
    }

    @UsedByGodot
    fun hideMinecraftOverlay() {
        runOnHostThread {
            surfaceView?.visibility = View.GONE
            overlayVisible = false
        }
    }

    @UsedByGodot
    fun setMinecraftOverlayBounds(left: Int, top: Int, width: Int, height: Int) {
        runOnHostThread {
            val view = ensureSurfaceView()
            val params = view.layoutParams as? FrameLayout.LayoutParams
                ?: FrameLayout.LayoutParams(width, height)
            params.width = width.coerceAtLeast(1)
            params.height = height.coerceAtLeast(1)
            params.leftMargin = left
            params.topMargin = top
            params.gravity = Gravity.TOP or Gravity.START
            view.layoutParams = params
        }
    }

    /** Enables/disables the client profile's Vulkan path before it is started. */
    @UsedByGodot
    fun setVulkanModEnabled(enabled: Boolean) {
        // This property is read by the small launcher/client adapter, not by
        // Godot. It avoids changing Minecraft's renderer or RenderPearl code.
        System.setProperty("minecraft.vulkanmod.enabled", enabled.toString())
    }

    @UsedByGodot
    fun isMinecraftSurfaceReady(): Boolean = surfaceReady

    /** True only when the Android window reached the optional client bridge. */
    @UsedByGodot
    fun isVulkanModSurfaceAttached(): Boolean = clientBridgeAttached

    @UsedByGodot
    fun getMinecraftSurfaceWidth(): Int = surfaceWidth

    @UsedByGodot
    fun getMinecraftSurfaceHeight(): Int = surfaceHeight

    @UsedByGodot
    fun getMinecraftSurfaceGeneration(): Long = surfaceGeneration

    /** Lets GDScript fail clearly instead of silently showing a black surface. */
    @UsedByGodot
    fun getVulkanModStatus(): String = when {
        !overlayVisible -> "hidden"
        !surfaceReady -> "waiting_for_android_surface"
        !clientBridgeAttached -> "surface_ready_client_bridge_missing"
        else -> "vulkanmod_surface_attached"
    }

    private fun ensureSurfaceView(): MinecraftSurfaceView {
        surfaceView?.let { return it }
        val host = activity
        val content = host.findViewById<FrameLayout>(android.R.id.content)
            ?: error("Godot activity has no FrameLayout content root")
        val view = MinecraftSurfaceView(host, object : SurfaceEvents {
            override fun created(surface: Surface, width: Int, height: Int) {
                surfaceReady = true
                surfaceWidth = width
                surfaceHeight = height
                surfaceGeneration += 1
                clientBridgeAttached = try {
                    nativeSurfaceAvailable(surface, width, height)
                } catch (error: UnsatisfiedLinkError) {
                    Log.w(TAG, "VulkanMod native bridge unavailable", error)
                    false
                }
            }

            override fun changed(width: Int, height: Int) {
                surfaceWidth = width
                surfaceHeight = height
                try {
                    nativeSurfaceSizeChanged(width, height)
                } catch (error: UnsatisfiedLinkError) {
                    clientBridgeAttached = false
                }
            }

            override fun destroyed() {
                surfaceReady = false
                clientBridgeAttached = false
                surfaceWidth = 0
                surfaceHeight = 0
                try {
                    nativeSurfaceDestroyed()
                } catch (error: UnsatisfiedLinkError) {
                    // The Java surface lifecycle remains valid without JNI.
                }
            }
        })
        view.visibility = View.GONE
        view.setBackgroundColor(Color.TRANSPARENT)
        view.setZOrderOnTop(true)
        view.holder.setFormat(PixelFormat.RGBA_8888)
        content.addView(
            view,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.TOP or Gravity.START,
            ),
        )
        surfaceView = view
        return view
    }

    private external fun nativeSurfaceAvailable(surface: Surface, width: Int, height: Int): Boolean
    private external fun nativeSurfaceSizeChanged(width: Int, height: Int)
    private external fun nativeSurfaceDestroyed()

    private interface SurfaceEvents {
        fun created(surface: Surface, width: Int, height: Int)
        fun changed(width: Int, height: Int)
        fun destroyed()
    }

    private class MinecraftSurfaceView(
        context: android.content.Context,
        private val events: SurfaceEvents,
    ) : SurfaceView(context), SurfaceHolder.Callback {
        init {
            holder.addCallback(this)
            isFocusable = true
            isFocusableInTouchMode = true
        }

        override fun surfaceCreated(holder: SurfaceHolder) {
            events.created(holder.surface, width.coerceAtLeast(1), height.coerceAtLeast(1))
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            events.changed(width, height)
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            events.destroyed()
        }
    }
}
