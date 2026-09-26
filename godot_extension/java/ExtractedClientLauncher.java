package net.minecraft.godot;

import com.mojang.blaze3d.platform.DisplayData;
import com.mojang.blaze3d.platform.NativeLibrariesBootstrap;
import net.minecraft.client.ClientBootstrap;
import net.minecraft.client.Minecraft;
import net.minecraft.client.PreferredGraphicsApi;
import net.minecraft.client.User;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.client.gui.screens.worldselection.WorldOpenFlows;
import net.minecraft.world.Difficulty;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.LevelSettings;
import net.minecraft.world.level.WorldDataConfiguration;
import net.minecraft.world.level.levelgen.WorldOptions;
import net.minecraft.world.level.levelgen.presets.WorldPresets;
import net.minecraft.SharedConstants;
import net.minecraft.WorldVersion;
import net.minecraft.client.main.GameConfig;
import net.minecraft.client.main.Main;
import net.minecraft.godot.renderpearl.GodotGpuBackend;
import net.minecraft.server.Bootstrap;
import net.minecraft.server.packs.VanillaPackResourcesBuilder;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.net.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.OptionalInt;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

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
    private static volatile String nativeLibraryFailure;
    private static volatile boolean started;
    private static final AtomicBoolean worldEntryRequested = new AtomicBoolean();
    private static final AtomicBoolean onboardingDismissed = new AtomicBoolean();
    private static final AtomicReference<Runnable> renderThreadTask = new AtomicReference<>();
    /** Set by the Godot host from the process environment before the isolate starts. */
    private static volatile boolean enterWorldFromHost;
    private static volatile Path gameDirectoryPath;
    private static final AtomicInteger vanillaPackApplications = new AtomicInteger();
    private static final StringBuilder capturedErrors = new StringBuilder();
    private static PrintStream originalErr;
    /** True while {@code runTick} is on the stack, so encoder hooks leave the task queued. */
    private static volatile boolean insideClientTick;
    private static long nextWorldAttemptNanos;
    private static long nextWorldScreenLogNanos;

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
        Thread watchdog = new Thread(ExtractedClientLauncher::watchClient, "minecraft-godot-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();
    }

    public static void stop() {
        Minecraft current = client;
        if (current == null) {
            return;
        }
        // 26.3 has no Minecraft.execute. stop() is safe to call from the caller.
        current.stop();
    }

    /**
     * JVM probe used by the native-image build. It is not the Godot entry point.
     * A positive {@code minecraft.godot.probeSeconds} constructs the extracted
     * client and then requests shutdown without calling {@code Main.main}, so
     * the probe does not {@code System.exit} through the stock launcher.
     */
    public static void main(String[] args) throws InterruptedException {
        if (Boolean.getBoolean("minecraft.godot.jniProbeOnly")) {
            configureProcess();
            loadNativeLibraries();
            if (nativeLibraryFailure != null) {
                System.err.println("JNI_PROBE_FAIL " + nativeLibraryFailure);
                System.exit(1);
            }
            System.out.println("JNI_PROBE_OK");
            return;
        }
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

    /**
     * The viewport proof only sees frames the render thread submits. If that
     * thread blocks inside resource reload, {@code submit()} never logs the
     * screen again, so this daemon prints the stuck stack and reload counters.
     */
    private static void watchClient() {
        try {
            Thread.sleep(8_000L);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
            return;
        }
        while (!Thread.currentThread().isInterrupted()) {
            try {
                logReloadProgress();
                logStuckStacks();
            } catch (Throwable error) {
                System.err.println("MINECRAFT_GD_STACK watchdog " + error.getClass().getSimpleName());
            }
            try {
                Thread.sleep(10_000L);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }

    private static void logReloadProgress() {
        try {
            Minecraft current = client;
            if (current == null) {
                System.err.println("MINECRAFT_GD_RELOAD client none");
                return;
            }
            Object gui = declaredMember(current, "gui");
            Object overlay = gui == null ? null : invokeNoArgs(gui, "overlay");
            if (overlay == null) {
                System.err.println("MINECRAFT_GD_RELOAD overlay none");
                return;
            }
            Object reload = declaredMember(overlay, "reload");
            StringBuilder line = new StringBuilder("MINECRAFT_GD_RELOAD");
            Object progress = declaredMember(overlay, "currentProgress");
            if (progress != null) {
                line.append(" progress ").append(progress);
            }
            if (reload == null) {
                line.append(" reload none");
            } else {
                line.append(" type ").append(reload.getClass().getSimpleName());
                Object done = invokeNoArgs(reload, "isDone");
                line.append(" done ").append(done);
                appendReloadCounters(reload, line, 0);
            }
            System.err.println(clip(line.toString(), 220));
        } catch (Throwable error) {
            System.err.println("MINECRAFT_GD_RELOAD unreadable " + error.getClass().getSimpleName());
        }
    }

    private static void appendReloadCounters(Object owner, StringBuilder line, int depth) {
        if (owner == null || depth > 2) {
            return;
        }
        Class<?> type = owner.getClass();
        while (type != null && type != Object.class) {
            for (Field field : type.getDeclaredFields()) {
                if (Modifier.isStatic(field.getModifiers())) {
                    continue;
                }
                Object value;
                try {
                    field.setAccessible(true);
                    value = field.get(owner);
                } catch (Throwable ignored) {
                    continue;
                }
                String name = field.getName();
                if ("listenerCount".equals(name) && value instanceof Integer count) {
                    line.append(" listeners=").append(count);
                } else if (value instanceof AtomicInteger counter
                        && (name.contains("Task") || name.contains("Reload"))) {
                    line.append(' ').append(name).append('=').append(counter.get());
                } else if (value instanceof Collection<?> pending && name.contains("prepar")) {
                    line.append(' ').append(name).append('=').append(pending.size());
                    int shown = 0;
                    for (Object listener : pending.toArray()) {
                        if (shown++ >= 3) {
                            break;
                        }
                        line.append(' ').append(listenerName(listener));
                    }
                }
            }
            type = type.getSuperclass();
        }
    }

    private static String listenerName(Object listener) {
        if (listener == null) {
            return "null";
        }
        try {
            Object name = listener.getClass().getMethod("getName").invoke(listener);
            if (name != null) {
                return name.toString();
            }
        } catch (ReflectiveOperationException ignored) {
            // Class name is enough to identify a stuck listener.
        }
        return listener.getClass().getSimpleName();
    }

    private static void logStuckStacks() {
        Map<Thread, StackTraceElement[]> traces = Thread.getAllStackTraces();
        Thread render = null;
        for (Thread thread : traces.keySet()) {
            if ("Render thread".equals(thread.getName())) {
                render = thread;
                break;
            }
        }
        if (render == null) {
            System.err.println("MINECRAFT_GD_STACK render-thread missing");
        } else {
            System.err.println(clip("MINECRAFT_GD_STACK " + summarize(render, traces.get(render)), 220));
        }
        int extra = 0;
        for (Map.Entry<Thread, StackTraceElement[]> entry : traces.entrySet()) {
            if (entry.getKey() == render || extra >= 3) {
                continue;
            }
            String summary = summarize(entry.getKey(), entry.getValue());
            if (!stuckThread(summary)) {
                continue;
            }
            System.err.println(clip("MINECRAFT_GD_STACK " + summary, 220));
            extra++;
        }
    }

    private static boolean stuckThread(String summary) {
        String lower = summary.toLowerCase();
        return lower.contains("openal")
                || lower.contains("alc")
                || lower.contains("sound")
                || lower.contains("reload")
                || lower.contains("future")
                || lower.contains("park")
                || lower.contains("socket")
                || lower.contains("audio");
    }

    private static String summarize(Thread thread, StackTraceElement[] stack) {
        StringBuilder line = new StringBuilder();
        line.append(thread.getName()).append(' ').append(thread.getState());
        int shown = 0;
        if (stack != null) {
            for (StackTraceElement frame : stack) {
                // getAllStackTraces freezes threads in the Graal safepoint.
                // Those frames hid the Minecraft method that is not returning.
                if (infrastructure(frame)) {
                    continue;
                }
                String type = frame.getClassName();
                int dot = type.lastIndexOf('.');
                line.append(" <- ")
                        .append(dot >= 0 ? type.substring(dot + 1) : type)
                        .append('.')
                        .append(frame.getMethodName());
                if (++shown >= 8) {
                    break;
                }
            }
        }
        if (shown == 0 && stack != null && stack.length > 0) {
            line.append(" <- ").append(stack[0].getMethodName());
        }
        return line.toString();
    }

    private static boolean infrastructure(StackTraceElement frame) {
        String type = frame.getClassName();
        return type.startsWith("com.oracle.")
                || type.startsWith("jdk.internal.")
                || type.startsWith("sun.")
                || type.startsWith("java.lang.Thread")
                || type.startsWith("java.lang.ref.")
                || type.contains("Safepoint");
    }

    private static Object declaredMember(Object owner, String name) {
        Class<?> type = owner.getClass();
        while (type != null && type != Object.class) {
            try {
                Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                return field.get(owner);
            } catch (ReflectiveOperationException ignored) {
                type = type.getSuperclass();
            }
        }
        return null;
    }

    private static Object invokeNoArgs(Object owner, String name) {
        try {
            return owner.getClass().getMethod(name).invoke(owner);
        } catch (ReflectiveOperationException ignored) {
            return null;
        }
    }

    private static String clip(String text, int limit) {
        return text.length() <= limit ? text : text.substring(0, limit);
    }

    private static void runClient() {
        try {
            // Minecraft.run catches render failures and calls System.exit(-1),
            // which is process status 255 and skips this method's catch. The
            // hook still runs for exit(); halt() is covered by the CI file scan.
            Runtime.getRuntime().addShutdownHook(new Thread(
                    ExtractedClientLauncher::printCrashReports, "minecraft-crash-report"));
            System.err.println("MINECRAFT_GD_USER_DIR " + System.getProperty("user.dir"));
            installErrorTap();
            configureProcess();
            loadNativeLibraries();
            SharedConstants.tryDetectVersion();
            WorldVersion detected = SharedConstants.getCurrentVersion();
            if (detected == null || detected.name() == null || detected.name().isBlank()) {
                throw new IllegalStateException("extracted client could not read /version.json");
            }
            System.err.println("Detected Minecraft " + detected.id() + " (" + detected.name() + ")");
            Bootstrap.bootStrap();
            ClientBootstrap.bootstrap();
            // Main.main registers this thread before constructing Minecraft.
            // Window.setMode rejects the call otherwise.
            com.mojang.blaze3d.systems.RenderSystem.initRenderThread();
            // Native-image classpath URLs are not file: or jar:, so the built-in
            // pack lists nothing. Point both pack types at the extracted tree.
            exposeExtractedVanillaPack();
            Minecraft created = new Minecraft(gameConfig());
            client = created;
            System.err.println("MINECRAFT_GD_WORLD requested " + enterWorldRequested()
                    + " env " + System.getenv("MINECRAFT_ENTER_WORLD")
                    + " host " + enterWorldFromHost);
            System.err.println("MINECRAFT_GD_RUN_ENTER");
            if (enterWorldRequested()) {
                // createFreshLevel blocks in renderFrame. Minecraft.run() has
                // no hook between ticks, and 26.3 has no Minecraft.execute.
                runBetweenTicks(created);
            } else {
                created.run();
            }
            System.err.println("MINECRAFT_GD_RUN_RETURN");
        } catch (Throwable error) {
            remember(error);
        }
    }

    /** Prints the saved crash report. Minecraft exits before our catch can see it. */
    private static void printCrashReports() {
        System.err.println("MINECRAFT_GD_CRASH hook");
        Path[] roots = {
                Path.of(System.getProperty("user.dir", "."), "minecraft-godot-run", "crash-reports"),
                Path.of("minecraft-godot-run", "crash-reports"),
                Path.of("godot_extension", "minecraft-godot-run", "crash-reports"),
                Path.of("crash-reports")
        };
        for (Path root : roots) {
            if (!Files.isDirectory(root)) {
                continue;
            }
            try (Stream<Path> listing = Files.list(root)) {
                Optional<Path> newest = listing
                        .filter(path -> path.getFileName().toString().endsWith(".txt"))
                        .max(Comparator.comparingLong(ExtractedClientLauncher::lastModified));
                if (newest.isEmpty()) {
                    continue;
                }
                System.err.println("MINECRAFT_GD_CRASH file " + newest.get());
                List<String> lines = Files.readAllLines(newest.get());
                int printed = 0;
                for (String line : lines) {
                    String trimmed = line.strip();
                    if (!crashLine(trimmed)) {
                        continue;
                    }
                    System.err.println("MINECRAFT_GD_CRASH " + trimmed);
                    printed++;
                    if (printed >= 24) {
                        break;
                    }
                }
            } catch (IOException failure) {
                System.err.println("MINECRAFT_GD_CRASH unreadable " + failure.getMessage());
            }
        }
    }

    private static long lastModified(Path path) {
        try {
            return Files.getLastModifiedTime(path).toMillis();
        } catch (IOException ignored) {
            return 0L;
        }
    }

    private static boolean crashLine(String line) {
        if (line.isEmpty()) {
            return false;
        }
        return line.startsWith("Description:")
                || line.startsWith("Caused by")
                || line.startsWith("java.")
                || line.startsWith("at net.minecraft.godot")
                || line.startsWith("at net.minecraft.client.Minecraft")
                || line.contains("Exception")
                || line.contains("Game crashed")
                || line.contains("submission failed")
                || line.contains("Unsupported");
    }

    private static void remember(Throwable error) {
        String detail = describe(error);
        if (nativeLibraryFailure != null) {
            detail = detail + " | native libraries: " + nativeLibraryFailure;
        }
        failure = new IllegalStateException(detail, error);
        error.printStackTrace(System.err);
        System.err.println("BOOT_DETAIL " + detail);
    }

    private static String describe(Throwable error) {
        StringBuilder builder = new StringBuilder();
        Throwable current = error;
        int depth = 0;
        while (current != null && depth < 8) {
            if (depth > 0) {
                builder.append(" caused by ");
            }
            builder.append(current.getClass().getName());
            String message = current.getMessage();
            if (message != null && !message.isBlank()) {
                builder.append(": ").append(message.replace('\n', ' ').replace('\r', ' '));
            }
            current = current.getCause();
            depth++;
        }
        return builder.toString();
    }

    /**
     * Loads LWJGL before bootstrap. A failed OpenAL load must not be the first
     * touch of {@code org.lwjgl.system.JNI}: that poisons the class and hides
     * the original link error from the later SDL viewport path.
     */
    private static void loadNativeLibraries() {
        System.setProperty("org.lwjgl.util.Debug", "true");
        System.setProperty("org.lwjgl.util.DebugLoader", "true");
        // The viewport stub exports the SDL calls boot uses, not every symbol
        // LWJGL looks up while binding the library.
        System.setProperty("org.lwjgl.util.NoFunctionChecks", "true");
        System.setProperty("org.lwjgl.system.allocator", "system");
        String nativeDir = firstNonBlank(
                System.getProperty("org.lwjgl.librarypath"),
                System.getenv("MINECRAFT_GODOT_NATIVE_DIR")
        );
        String listing = nativeDir == null ? "unset" : listNativeDirectory(nativeDir);
        System.err.println("LWJGL natives " + nativeDir + " [" + listing + "]");
        if (nativeDir != null) {
            Path lwjgl = Path.of(nativeDir).resolve("liblwjgl.so");
            if (Files.isRegularFile(lwjgl)) {
                System.setProperty("org.lwjgl.libname", lwjgl.toAbsolutePath().toString());
            }
        }
        try {
            org.lwjgl.system.Library.initialize();
            // Initialize JNI here so a later OpenAL miss cannot hide the first
            // link error behind "Could not initialize class".
            Class.forName("org.lwjgl.system.JNI");
            System.err.println("LWJGL_INIT ok");
        } catch (Throwable error) {
            nativeLibraryFailure = describe(error) + " natives=[" + listing + "]";
            System.err.println("LWJGL_INIT_FAIL " + nativeLibraryFailure);
            error.printStackTrace(System.err);
            return;
        }
        try {
            NativeLibrariesBootstrap.loadLibraries();
        } catch (Throwable loadFailure) {
            // Audio and optional loaders are not the viewport. Do not let a
            // missing OpenAL device abort the extracted client.
            System.err.println("Minecraft native library load failed; continuing with the Godot backend: " + describe(loadFailure));
            loadFailure.printStackTrace(System.err);
        }
    }

    private static String listNativeDirectory(String nativeDir) {
        Path directory = Path.of(nativeDir);
        if (!Files.isDirectory(directory)) {
            return "missing-directory";
        }
        StringBuilder names = new StringBuilder();
        try (Stream<Path> listing = Files.list(directory)) {
            listing.map(path -> path.getFileName().toString()).sorted().forEach(name -> {
                if (!names.isEmpty()) {
                    names.append(',');
                }
                names.append(name);
            });
        } catch (IOException failure) {
            return "unreadable:" + failure.getMessage();
        }
        return names.isEmpty() ? "empty" : names.toString();
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
        gameDirectoryPath = gameDirectory.toPath();
        writeAllowedSymlinks(gameDirectory);
        if (enterWorldRequested()) {
            writeWorldOptions(gameDirectory);
        }
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

    /** Called from the Godot host before {@link #start()}. The isolate may not see getenv. */
    public static void setEnterWorldFromHost(boolean enabled) {
        enterWorldFromHost = enabled;
    }

    private static boolean enterWorldRequested() {
        return enterWorldFromHost
                || "1".equals(System.getenv("MINECRAFT_ENTER_WORLD"))
                || Boolean.parseBoolean(System.getProperty("minecraft.godot.enterWorld", "false"));
    }

    /**
     * Native image cannot turn classpath resources into a file or jar path, so
     * {@code pushJarResources} lists an empty vanilla pack and world creation
     * bails back to the title screen. A direct write stays visible to analysis;
     * a reflective write can be constant-folded back to the no-op consumer.
     */
    private static void exposeExtractedVanillaPack() {
        Path root = extractedRoot();
        if (root == null) {
            System.err.println("MINECRAFT_GD_WORLD pack missing dir " + System.getProperty("user.dir"));
            return;
        }
        VanillaPackResourcesBuilder.developmentConfig = builder -> {
            builder.pushUniversalPath(root);
            int applied = vanillaPackApplications.incrementAndGet();
            System.err.println("MINECRAFT_GD_WORLD pack-applied " + applied + " " + root);
        };
        System.err.println("MINECRAFT_GD_WORLD pack " + root);
    }

    private static Path extractedRoot() {
        String configured = firstNonBlank(
                System.getProperty("minecraft.godot.extractedDir"),
                System.getenv("MINECRAFT_EXTRACTED_DIR"));
        Path cwd = Path.of(System.getProperty("user.dir", ".")).toAbsolutePath();
        Path[] candidates = new Path[] {
                configured == null || configured.isBlank() ? null : Path.of(configured),
                cwd.resolve("extracted"),
                cwd.resolve("../extracted"),
                cwd.getParent() == null ? null : cwd.getParent().resolve("extracted")
        };
        for (Path candidate : candidates) {
            if (candidate != null
                    && Files.isDirectory(candidate.resolve("data/minecraft"))
                    && Files.isDirectory(candidate.resolve("assets/minecraft"))) {
                return candidate.toAbsolutePath().normalize();
            }
        }
        Path cursor = cwd;
        for (int i = 0; i < 4 && cursor != null; i++) {
            Path candidate = cursor.resolve("extracted");
            if (Files.isDirectory(candidate.resolve("data/minecraft"))
                    && Files.isDirectory(candidate.resolve("assets/minecraft"))) {
                return candidate.toAbsolutePath().normalize();
            }
            cursor = cursor.getParent();
        }
        return null;
    }

    /** Runners often check out through a symlink. An empty allow-list rejects the save. */
    private static void writeAllowedSymlinks(File gameDirectory) {
        Path file = gameDirectory.toPath().resolve("allowed_symlinks.txt");
        if (Files.isRegularFile(file)) {
            return;
        }
        try {
            Files.writeString(file, "# headless viewport\n[prefix]/\n[/]\n");
        } catch (IOException failure) {
            System.err.println("MINECRAFT_GD_WORLD symlinks " + failure.getClass().getSimpleName());
        }
    }

    private static void installErrorTap() {
        if (originalErr != null) {
            return;
        }
        originalErr = System.err;
        System.setErr(new PrintStream(new OutputStream() {
            private final ByteArrayOutputStream line = new ByteArrayOutputStream();

            @Override
            public void write(int value) {
                originalErr.write(value);
                if (value == '\n') {
                    rememberErrorLine(line.toString(StandardCharsets.UTF_8));
                    line.reset();
                } else if (value != '\r') {
                    line.write(value);
                }
            }

            @Override
            public void write(byte[] buffer, int offset, int length) {
                originalErr.write(buffer, offset, length);
                for (int index = offset; index < offset + length; index++) {
                    int value = buffer[index] & 0xff;
                    if (value == '\n') {
                        rememberErrorLine(line.toString(StandardCharsets.UTF_8));
                        line.reset();
                    } else if (value != '\r') {
                        line.write(value);
                    }
                }
            }
        }, true, StandardCharsets.UTF_8));
    }

    private static void rememberErrorLine(String line) {
        String lower = line.toLowerCase();
        if (!(lower.contains("fail") || lower.contains("exception") || lower.contains("error")
                || lower.contains("datapack") || lower.contains("symlink") || lower.contains("warn")
                || lower.contains("couldn't") || lower.contains("could not"))) {
            return;
        }
        if (line.contains("MINECRAFT_GD_")) {
            return;
        }
        synchronized (capturedErrors) {
            if (capturedErrors.length() > 4000) {
                capturedErrors.delete(0, capturedErrors.length() - 2500);
            }
            if (capturedErrors.length() > 0) {
                capturedErrors.append(" || ");
            }
            capturedErrors.append(line);
        }
    }

    private static void printCapturedErrors() {
        String text;
        synchronized (capturedErrors) {
            text = capturedErrors.toString();
        }
        System.err.println("MINECRAFT_GD_WORLD fail " + (text.isBlank() ? "no-captured-error" : clip(text, 700)));
    }

    /** A failed create can leave the level folder behind and make the retry fail differently. */
    private static void deletePartialWorld() {
        Path directory = gameDirectoryPath;
        if (directory == null) {
            return;
        }
        Path world = directory.resolve("saves").resolve("godot");
        if (!Files.exists(world)) {
            return;
        }
        try (Stream<Path> walk = Files.walk(world)) {
            walk.sorted(Comparator.reverseOrder()).forEach(path -> {
                try {
                    Files.deleteIfExists(path);
                } catch (IOException ignored) {
                    // The next create reports the leftover if it still matters.
                }
            });
        } catch (IOException failure) {
            System.err.println("MINECRAFT_GD_WORLD cleanup " + failure.getClass().getSimpleName());
        }
    }

    private static void printWorldLogTail() {
        Path directory = gameDirectoryPath;
        Path log = directory == null ? null : directory.resolve("logs").resolve("latest.log");
        if (log == null || !Files.isRegularFile(log)) {
            System.err.println("MINECRAFT_GD_WORLD log missing");
            return;
        }
        try {
            List<String> lines = Files.readAllLines(log);
            StringBuilder kept = new StringBuilder();
            for (int i = Math.max(0, lines.size() - 80); i < lines.size(); i++) {
                String line = lines.get(i);
                String lower = line.toLowerCase();
                if (!(lower.contains("fail") || lower.contains("exception") || lower.contains("error")
                        || lower.contains("datapack") || lower.contains("symlink") || lower.contains("warn"))) {
                    continue;
                }
                if (kept.length() > 0) {
                    kept.append(" || ");
                }
                kept.append(line);
            }
            System.err.println("MINECRAFT_GD_WORLD log " + clip(kept.toString(), 700));
        } catch (IOException failure) {
            System.err.println("MINECRAFT_GD_WORLD log " + failure.getClass().getSimpleName());
        }
    }

    /**
     * A two-chunk view finishes meshing inside the viewport gate. Pause-on-focus
     * would freeze a headless run before the first terrain pass.
     */
    private static void writeWorldOptions(File gameDirectory) {
        Path options = gameDirectory.toPath().resolve("options.txt");
        if (Files.isRegularFile(options)) {
            return;
        }
        try {
            Files.writeString(options, String.join("\n",
                    "renderDistance:2",
                    "simulationDistance:2",
                    "pauseOnLostFocus:false",
                    "guiScale:2",
                    "onboardAccessibility:false",
                    "onboardingAccessibilityFinished:true"
            ) + "\n", StandardCharsets.UTF_8);
        } catch (IOException failure) {
            System.err.println("MINECRAFT_GD_WORLD options " + failure.getClass().getSimpleName());
        }
    }

    private static volatile boolean loggedWorldLoaded;

    private static void maybeEnterWorld(Minecraft minecraft) {
        if (!enterWorldRequested()) {
            return;
        }
        if (readMember(minecraft, "level") != null) {
            if (!loggedWorldLoaded) {
                loggedWorldLoaded = true;
                System.err.println("MINECRAFT_GD_WORLD loaded");
            }
            return;
        }
        long now = System.nanoTime();
        Object gui = declaredMember(minecraft, "gui");
        if (gui != null && invokeNoArgs(gui, "overlay") != null) {
            return;
        }
        Object screen = gui == null ? null : invokeNoArgs(gui, "screen");
        String screenName = screen == null ? "none" : screen.getClass().getSimpleName();
        if (now >= nextWorldScreenLogNanos) {
            nextWorldScreenLogNanos = now + 10_000_000_000L;
            System.err.println("MINECRAFT_GD_WORLD screen " + screenName);
        }
        if (screen != null && screen.getClass().getName().endsWith("AccessibilityOnboardingScreen")) {
            if (onboardingDismissed.compareAndSet(false, true)) {
                dismissOnboarding(minecraft);
            }
            return;
        }
        if (screen != null && screen.getClass().getSimpleName().contains("Confirm")
                && acceptBooleanCallback(screen)) {
            System.err.println("MINECRAFT_GD_WORLD confirmed " + screenName);
            return;
        }
        // createFreshLevel returns before the client joins. A null level is the
        // loading screen, not a failure. Retry only after we are back on the title.
        if (worldEntryRequested.get()) {
            if (!screenName.equals("TitleScreen") || now < nextWorldAttemptNanos) {
                return;
            }
            worldEntryRequested.set(false);
            System.err.println("MINECRAFT_GD_WORLD retry");
        }
        if (screen == null || !screen.getClass().getName().endsWith("TitleScreen")
                || !worldEntryRequested.compareAndSet(false, true)) {
            return;
        }
        nextWorldAttemptNanos = now + 20_000_000_000L;
        System.err.println("MINECRAFT_GD_WORLD title");
        tuneHeadlessOptions(minecraft);
        createFreshWorld(minecraft);
    }

    private static boolean acceptBooleanCallback(Object screen) {
        Class<?> type = screen.getClass();
        while (type != null && type != Object.class) {
            try {
                Field field = type.getDeclaredField("callback");
                field.setAccessible(true);
                Object callback = field.get(screen);
                if (callback == null) {
                    return false;
                }
                callback.getClass().getMethod("accept", boolean.class).invoke(callback, Boolean.TRUE);
                return true;
            } catch (NoSuchFieldException ignored) {
                type = type.getSuperclass();
            } catch (ReflectiveOperationException failure) {
                System.err.println("MINECRAFT_GD_WORLD confirm " + failure.getClass().getSimpleName());
                return false;
            }
        }
        return false;
    }

    private static void tuneHeadlessOptions(Minecraft minecraft) {
        Object options = declaredMember(minecraft, "options");
        if (options == null) {
            return;
        }
        setBooleanField(options, "pauseOnLostFocus", false);
        setBooleanField(options, "onboardAccessibility", false);
        setBooleanField(options, "onboardingAccessibilityFinished", true);
        setOptionValue(options, "renderDistance", 2);
        setOptionValue(options, "simulationDistance", 2);
    }

    private static void setOptionValue(Object options, String name, int value) {
        Object option = declaredMember(options, name);
        if (option == null) {
            return;
        }
        try {
            option.getClass().getMethod("set", Object.class).invoke(option, Integer.valueOf(value));
        } catch (ReflectiveOperationException failure) {
            System.err.println("MINECRAFT_GD_WORLD option " + name + " " + failure.getClass().getSimpleName());
        }
    }

    private static void createFreshWorld(Minecraft minecraft) {
        try {
            if (readMember(minecraft, "level") != null) {
                System.err.println("MINECRAFT_GD_WORLD already");
                return;
            }
            WorldOpenFlows flows = minecraft.createWorldOpenFlows();
            Object gui = declaredMember(minecraft, "gui");
            Screen returnScreen = gui == null ? null : invokeNoArgs(gui, "screen") instanceof Screen screen ? screen : null;
            LevelSettings settings = new LevelSettings(
                    "Godot",
                    GameType.SURVIVAL,
                    new LevelSettings.DifficultySettings(Difficulty.EASY, false, false),
                    false,
                    WorldDataConfiguration.DEFAULT
            );
            deletePartialWorld();
            flows.createFreshLevel(
                    "godot",
                    settings,
                    WorldOptions.defaultWithRandomSeed(),
                    WorldPresets::createNormalWorldDimensions,
                    returnScreen
            );
            boolean joined = readMember(minecraft, "level") != null;
            System.err.println("MINECRAFT_GD_WORLD create level " + joined
                    + " applied " + vanillaPackApplications.get()
                    + " dir " + gameDirectoryPath);
            if (!joined) {
                printWorldLogTail();
                printCapturedErrors();
            }
        } catch (Throwable failure) {
            worldEntryRequested.set(false);
            nextWorldAttemptNanos = System.nanoTime() + 5_000_000_000L;
            System.err.println("MINECRAFT_GD_WORLD create-failed " + failure.getClass().getSimpleName()
                    + " " + failure.getMessage());
            failure.printStackTrace(System.err);
        }
    }

    /**
     * Runs queued world entry, then one client tick. {@code createFreshLevel}
     * calls {@code renderFrame} while the integrated server starts, so the task
     * has to run here rather than inside an open command encoder.
     */
    private static void runBetweenTicks(Minecraft minecraft) throws ReflectiveOperationException {
        try {
            Field gameThread = Minecraft.class.getDeclaredField("gameThread");
            gameThread.setAccessible(true);
            gameThread.set(minecraft, Thread.currentThread());
        } catch (ReflectiveOperationException failure) {
            System.err.println("MINECRAFT_GD_WORLD thread " + failure.getClass().getSimpleName());
        }
        Method runTick = Minecraft.class.getDeclaredMethod("runTick", boolean.class);
        runTick.setAccessible(true);
        Field events = null;
        try {
            events = Minecraft.class.getDeclaredField("sdlEventHandler");
            events.setAccessible(true);
        } catch (ReflectiveOperationException ignored) {
            events = null;
        }
        while (minecraft.isRunning()) {
            insideClientTick = false;
            // Loading can outlast a background deadline. Enter only between ticks,
            // and keep checking until the client stops.
            maybeEnterWorld(minecraft);
            runPendingRenderTask();
            insideClientTick = true;
            try {
                if (events != null) {
                    Object handler = events.get(minecraft);
                    if (handler != null) {
                        com.mojang.blaze3d.systems.RenderSystem.pollEvents(
                                (com.mojang.blaze3d.platform.SDLEventHandler) handler);
                    }
                }
                runTick.invoke(minecraft, Boolean.TRUE);
            } catch (InvocationTargetException wrapped) {
                Throwable cause = wrapped.getCause() == null ? wrapped : wrapped.getCause();
                System.err.println("MINECRAFT_GD_WORLD tick " + cause.getClass().getSimpleName()
                        + " " + cause.getMessage());
                cause.printStackTrace(System.err);
                if (cause instanceof OutOfMemoryError) {
                    System.gc();
                    continue;
                }
                break;
            } finally {
                insideClientTick = false;
            }
        }
    }

    /**
     * Runs a queued world-entry task on the render thread. Encoder hooks call
     * this only when {@code Minecraft.run} is the loop; the between-tick loop
     * leaves the task queued until {@code runTick} returns.
     */
    public static void runPendingRenderTask() {
        if (insideClientTick) {
            return;
        }
        Runnable task = renderThreadTask.getAndSet(null);
        if (task != null) {
            task.run();
        }
    }

    private static void scheduleOnRenderThread(Runnable task) {
        renderThreadTask.set(task);
    }

    private static void dismissOnboarding(Minecraft minecraft) {
        markOnboardingFinished(minecraft);
        Object gui = declaredMember(minecraft, "gui");
        if (gui == null) {
            return;
        }
        try {
            gui.getClass().getMethod("setScreen", Screen.class).invoke(gui, new TitleScreen());
            System.err.println("MINECRAFT_GD_WORLD skipped-onboarding");
        } catch (ReflectiveOperationException failure) {
            System.err.println("MINECRAFT_GD_WORLD onboarding " + failure.getClass().getSimpleName());
        }
    }

    private static void markOnboardingFinished(Minecraft minecraft) {
        Object options = readMember(minecraft, "options");
        if (options == null) {
            return;
        }
        setBooleanField(options, "onboardAccessibility", false);
        setBooleanField(options, "onboardingAccessibilityFinished", true);
    }

    private static void setBooleanField(Object owner, String name, boolean value) {
        Class<?> type = owner.getClass();
        while (type != null && type != Object.class) {
            try {
                Field field = type.getDeclaredField(name);
                field.setAccessible(true);
                field.setBoolean(owner, value);
                return;
            } catch (ReflectiveOperationException ignored) {
                type = type.getSuperclass();
            }
        }
    }

    private static Object readMember(Object owner, String name) {
        if (owner == null) {
            return null;
        }
        try {
            return owner.getClass().getMethod(name).invoke(owner);
        } catch (ReflectiveOperationException ignored) {
            return declaredMember(owner, name);
        }
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
