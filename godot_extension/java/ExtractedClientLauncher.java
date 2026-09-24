package net.minecraft.godot;

import com.mojang.blaze3d.platform.DisplayData;
import com.mojang.blaze3d.platform.NativeLibrariesBootstrap;
import net.minecraft.client.ClientBootstrap;
import net.minecraft.client.Minecraft;
import net.minecraft.client.PreferredGraphicsApi;
import net.minecraft.client.User;
import net.minecraft.SharedConstants;
import net.minecraft.WorldVersion;
import net.minecraft.client.main.GameConfig;
import net.minecraft.client.main.Main;
import net.minecraft.godot.renderpearl.GodotGpuBackend;
import net.minecraft.server.Bootstrap;

import java.io.File;
import java.net.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.OptionalInt;
import java.util.UUID;

/**
 * Starts the extracted 26.3 client. This class does not replace
 * {@link Minecraft}; the native image must contain the extracted class.
 *
 * Godot is not imported here. The graphics slot is the classpath overlay of
 * {@code PreferredGraphicsApi}, which constructs {@link GodotGpuBackend}.
 */
public final class ExtractedClientLauncher {
    /** ASCII marker embedded in the native image. Do not rename. */
    static final byte[] IMAGE_MARKER = new byte[] {
            'e', 'x', 't', 'r', 'a', 'c', 't', 'e', 'd', '-',
            'm', 'i', 'n', 'e', 'c', 'r', 'a', 'f', 't', '-',
            '2', '6', '.', '3', '-',
            'c', 'l', 'i', 'e', 'n', 't'
    };

    private static volatile Minecraft client;
    private static volatile Throwable failure;
    private static volatile boolean started;

    private ExtractedClientLauncher() {
    }

    /** Keeps the ASCII image marker reachable from the C entry point. */
    public static int imageMarkerByte(int index) {
        if (index < 0 || index >= IMAGE_MARKER.length) {
            return -1;
        }
        return IMAGE_MARKER[index] & 0xff;
    }

    /** Keeps the Godot RenderPearl backend in the native-image reachability set. */
    static Class<?> godotBackendType() {
        return GodotGpuBackend.class;
    }

    /** Keeps the extracted client entry class in the image even though startup does not call it. */
    static Class<?> extractedMainType() {
        return Main.class;
    }

    public static Minecraft client() {
        return client;
    }

    public static Throwable failure() {
        return failure;
    }

    public static boolean isRunning() {
        Minecraft current = client;
        return current != null && current.isRunning();
    }

    public static synchronized void start() {
        if (started) {
            return;
        }
        started = true;
        if (godotBackendType().getName().isEmpty() || extractedMainType().getName().isEmpty()) {
            throw new IllegalStateException("Extracted client image is missing its backend or entry class");
        }
        Thread thread = new Thread(ExtractedClientLauncher::runClient, "Render thread");
        thread.setDaemon(false);
        thread.setUncaughtExceptionHandler((ignored, error) -> remember(error));
        thread.start();
    }

    public static void stop() {
        Minecraft current = client;
        if (current == null) {
            return;
        }
        try {
            current.execute(current::stop);
        } catch (RuntimeException failure) {
            current.stop();
        }
    }

    /**
     * JVM probe used by the native-image build. It is not the Godot entry point.
     * A positive {@code minecraft.godot.probeSeconds} constructs the extracted
     * client and then requests shutdown without calling {@code Main.main}, so
     * the probe does not {@code System.exit} through the stock launcher.
     */
    public static void main(String[] args) throws InterruptedException {
        start();
        int seconds = Integer.getInteger("minecraft.godot.probeSeconds", 8);
        long deadline = System.nanoTime() + seconds * 1_000_000_000L;
        while (System.nanoTime() < deadline && client() == null && failure() == null) {
            Thread.sleep(200L);
        }
        Minecraft current = client();
        Throwable startupFailure = failure();
        if (current != null) {
            stop();
        }
        if (startupFailure != null) {
            startupFailure.printStackTrace(System.err);
            System.exit(1);
        }
        if (current == null) {
            System.err.println("Extracted Minecraft client did not construct");
            System.exit(2);
        }
        System.out.println("Extracted Minecraft client constructed");
    }

    private static void runClient() {
        try {
            configureProcess();
            try {
                NativeLibrariesBootstrap.loadLibraries();
            } catch (Throwable loadFailure) {
                System.err.println("Minecraft native library load failed; continuing with the Godot backend");
                loadFailure.printStackTrace(System.err);
            }
            Bootstrap.bootStrap();
            ClientBootstrap.bootstrap();
            Minecraft created = new Minecraft(gameConfig());
            client = created;
            created.run();
        } catch (Throwable error) {
            remember(error);
        }
    }

    private static void remember(Throwable error) {
        failure = error;
        error.printStackTrace(System.err);
    }

    private static void configureProcess() {
        String nativeDir = firstNonBlank(
                System.getProperty("minecraft.godot.nativeDir"),
                System.getenv("MINECRAFT_GODOT_NATIVE_DIR")
        );
        if (nativeDir == null) {
            Path bin = Path.of("godot_extension", "bin", "natives");
            if (!Files.isDirectory(bin)) {
                bin = Path.of("bin", "natives");
            }
            if (!Files.isDirectory(bin)) {
                bin = Path.of("godot_extension", "bin");
            }
            if (!Files.isDirectory(bin)) {
                bin = Path.of("bin");
            }
            nativeDir = bin.toAbsolutePath().toString();
        }
        System.setProperty("org.lwjgl.librarypath", nativeDir);
        System.setProperty("org.lwjgl.system.librarypath", nativeDir);
        System.setProperty("java.awt.headless", "true");
        System.setProperty("sun.net.client.defaultConnectTimeout", "2000");
        System.setProperty("sun.net.client.defaultReadTimeout", "2000");
        loadStubLibrary(nativeDir, "libSDL3.so");
    }

    private static void loadStubLibrary(String nativeDir, String libraryFile) {
        Path library = Path.of(nativeDir).resolve(libraryFile);
        if (!Files.isRegularFile(library)) {
            return;
        }
        try {
            System.load(library.toAbsolutePath().toString());
        } catch (UnsatisfiedLinkError ignored) {
            // LWJGL will report a missing SDL dependency if this stub cannot load.
        }
    }

    private static GameConfig gameConfig() {
        int width = positiveProperty("minecraft.godot.width", environmentInt("GODOT_VIEWPORT_WIDTH", 1280));
        int height = positiveProperty("minecraft.godot.height", environmentInt("GODOT_VIEWPORT_HEIGHT", 720));
        System.setProperty("minecraft.godot.width", Integer.toString(width));
        System.setProperty("minecraft.godot.height", Integer.toString(height));

        File gameDirectory = directory(firstNonBlank(
                System.getProperty("minecraft.godot.gameDir"),
                Path.of(System.getProperty("user.dir"), "minecraft-godot-run").toString()
        ));
        File resourcePackDirectory = directory(new File(gameDirectory, "resourcepacks").getPath());
        File assetDirectory = directory(firstNonBlank(
                System.getProperty("minecraft.godot.assetsDir"),
                new File(gameDirectory, "assets").getPath()
        ));
        String username = firstNonBlank(System.getProperty("minecraft.godot.username"), "Player");
        User user = new User(
                username,
                UUID.nameUUIDFromBytes(("OfflinePlayer:" + username).getBytes(StandardCharsets.UTF_8)),
                "0",
                Optional.empty(),
                Optional.empty()
        );
        return new GameConfig(
                new GameConfig.UserData(user, Proxy.NO_PROXY),
                new DisplayData(width, height, OptionalInt.empty(), OptionalInt.empty(), false),
                new GameConfig.FolderData(gameDirectory, resourcePackDirectory, assetDirectory, "34"),
                new GameConfig.GameData(
                        false,
                        "26.3",
                        "release",
                        false,
                        false,
                        false,
                        false,
                        false,
                        PreferredGraphicsApi.DEFAULT,
                        true
                ),
                new GameConfig.QuickPlayData("", GameConfig.QuickPlayVariant.DISABLED)
        );
    }

    private static File directory(String path) {
        File directory = new File(path);
        if (!directory.isDirectory() && !directory.mkdirs() && !directory.isDirectory()) {
            throw new IllegalStateException("Could not create Minecraft directory " + directory);
        }
        return directory;
    }

    private static int positiveProperty(String property, int fallback) {
        String value = System.getProperty(property);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            int parsed = Integer.parseInt(value);
            return parsed > 0 ? parsed : fallback;
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static int environmentInt(String name, int fallback) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            int parsed = Integer.parseInt(value);
            return parsed > 0 ? parsed : fallback;
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static String firstNonBlank(String first, String second) {
        if (first != null && !first.isBlank()) {
            return first;
        }
        return second;
    }
}
