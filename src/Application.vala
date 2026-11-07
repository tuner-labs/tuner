/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Application.vala
 *
 * @brief Main application class and namespace assets for the Tuner radio application
 */

 using GLib;
 using Gst;
 using Tuner.Coordinators;
 using Tuner.Controllers;
 using Tuner.Events;
 using Tuner.Models;
 using Tuner.Providers;
 using Tuner.Services;
 using Tuner.Widgets;
/**
 * @namespace Tuner
 * @brief Main namespace for the Tuner application
 */
namespace Tuner {


    /*
        Namespace Assets and Methods
    */
    private static Application _instance;

    private static string[] APP_ARGV; 


    /**
    * @brief Getter for the singleton instance
    *
    * @return The Application instance
    */
    public static Application app() {
            return _instance;
    } // app


    //-------------------------------------

    /*
    
        Application

    */

    /**
    * @class Application
    * @brief Main application class implementing core functionality
    * @ingroup Tuner
    * 
    * The Application class serves as the primary entry point and controller for the Tuner
    * application. It manages:
    * - Window creation and presentation
    * - Settings management
    * - Player control
    * - Directory structure
    * - DBus initialization
    * 
    * @note This class follows the singleton pattern, accessible via Application.instance
    */
    public class Application : Gtk.Application 
    {
        private delegate void StringActionHandler(string value);

        public static string ENV_LANG = "LANGUAGE";

        /** @brief Application version */
        public const string APP_VERSION = VERSION;
        
        /** @brief Application ID */
        public const string APP_ID = "io.github.tuner_labs.tuner";
        
        /** @brief Unicode character for starred items ★ */
        public const string STAR_CHAR = "\u2605 ";

        /** @brief Unicode character for unstarred items ☆ */ 
        public const string UNSTAR_CHAR = "\u2606 ";

        /** @brief Unicode character for out-of-date items ⚠ */ 
        public const string EXCLAIM_CHAR = "\u26A0 ";
    
        /** @brief File name for starred station sore */
        public const string STARRED = "starred.json";

        public static Gee.Collection<string> LOCALES_FOUND = new Gee.TreeSet<string>();

        /** @brief Connectivity monitoring*/
        private static NetworkMonitor NETMON = NetworkMonitor.get_default ();

        private static Gtk.CssProvider CSSPROVIDER = new Gtk.CssProvider();

        private static Gtk.Settings GTK_SETTINGS;


        private static string GTK_SYSTEM_THEME = "unset";

        /**
         * @brief The system GTK theme name, saved before Tuner applies its own theme; "unset" until it is read.
         */
        public static string SYSTEM_THEME() { return GTK_SYSTEM_THEME; }

        static construct 
        {
            // Internationalization
            Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
            Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
            Intl.textdomain (GETTEXT_PACKAGE);
            LOCALES_FOUND.add("en"); // English is always available as default
            try {   
                // Add translations
                var dir = File.new_for_path(LOCALEDIR);
                var enumerator = dir.enumerate_children("standard::*", FileQueryInfoFlags.NONE);
                FileInfo info;
                while ((info = enumerator.next_file()) != null) 
                {
                    if (info.get_file_type() == FileType.DIRECTORY && info.get_name() != "C") 
                    {
                        var lang_dir = dir.get_child(info.get_name());
                        var mo_file = lang_dir.get_child("LC_MESSAGES").get_child(GETTEXT_PACKAGE + ".mo");
                        if (mo_file.query_exists()) 
                        {
                            LOCALES_FOUND.add(info.get_name());
                        }
                    }
                } //  while
            } catch (Error e) {
                warning(@"Error reading locale path: $(e.message)");
            }            
        } // static construct

        // -------------------------------------

        public string language { 
            get { return GLib.Environment.get_variable(ENV_LANG); }
            //get { return Model.Languages.get_environment_code(); }
            set { 
                if ( GLib.Environment.get_variable(ENV_LANG) == value 
                || ( value != "" && !LOCALES_FOUND.contains(value )) ) return;

                if ( settings.language != value ) 
                {
                    settings.language = value;

                    // Defer save and restart to give the WM/compositor a short
                    // moment to finalize the resize/move. We still flush
                    // pending GTK events right before saving inside the
                    // timeout callback.
                    Idle.add(() => {
                        // Start a fade-out using the shared fade constant and
                        // hide the window after the fade so opacity doesn't revert.
                        uint fade_ms = WINDOW_FADE_MS;
                        fade_window.begin(window, fade_ms, false, () => { });

                        GLib.Timeout.add((uint) (fade_ms + 80), () => {
                            while (Gtk.events_pending()) Gtk.main_iteration();
                            settings.save(window);
                            window.hide();
                            // Stop GTK main loop cleanly
                            spawn_restart();
                            quit();
                            return false; // one-shot
                        });
                        return Source.REMOVE;
                    });
                }

                GLib.Environment.set_variable(ENV_LANG, value, true);
            }
        }

        public string theme_name { 
            get { return settings.theme_mode; }
            set { 
                if ( settings.theme_mode == value ) return;
                settings.theme_mode = value;
                apply_theme_name(value);
            }
        }

        /** @brief Application settings */
        public Settings settings { get; construct; }  

        /** @brief Cross-component event hub */
        public AppEventBus events { get; construct; }
        
        /** @brief Player controller */
        public PlayerController player { get; construct; }  

        /** @brief Player controller */
        public DirectoryController directory { get; construct; }

        /** @brief Jukebox controller */
        public JukeboxController jukebox { get; construct; }

        /** @brief Tape counter controller */
        public TapeCounterController tape_counter { get; construct; }

        /** @brief Player controller */
        public StarStore stars { get; construct; }

        /** @brief Shared session playback history */
        public History history { get; private set; }

        /** @brief Hearted tracks kept for All Time across sessions */
        public HeartedArchive all_time { get; private set; }

        /** @brief Stations that failed to play this session - jukebox skips these */
        public StationSession session { get; private set; }
        
        /** @brief API DataProvider */
        public DataProvider.API provider { get; construct; }
        
        /** @brief Cache directory path */
        public string? cache_dir { get; construct; }
        
        /** @brief Data directory path */
        public string? data_dir { get; construct; }

        /** @brief The state of the network, and the Cancellable that ends online work when it goes */
        public NetworkState network { get; private set; }

        /** @brief provide a Cancellable for online processes (cancelled while offline) */
        public Cancellable offline_cancel { get { return network.cancellable; } }

#if DEBUG_LOCAL
        /** @brief Development-only: force the online state, to show the offline look in screenshots. */
        public void debug_set_online (bool online)
        {
            network.set_online (online);
        }
#endif

        /** @brief The network is not usable (see network) */
        public bool is_offline { get { return network.is_offline; } }

        /** @brief The network is usable (see network) */
        public bool is_online { get { return network.is_online; } }

        /** @brief Run the application with the given command line arguments */
        public new int run ( string[]? argv = null)
        {
            APP_ARGV = argv;     // Keep a copy of the args for rerunning the app from the RestartManager
            return base.run (argv); 
        }

        /**
         * @brief Cleanly quits the application in response to a termination signal.
         *
         * @param signum The signal number received.
         */
        public void quit_for_signal (int signum)
        {
            quit_cleanly (@"received signal $signum");
        } // quit_for_signal


        /**
         * @brief Stops playback, saves state and quits, whatever the "keep playing" setting is.
         *
         * @param reason Why the application is quitting, for the log.
         */
        public void quit_cleanly (string reason)
        {
            message ("Quitting: %s", reason);
            if (player != null)
                player.stop ();
            all_time.flush ();
            settings.save (window);
            quit ();
        } // quit_cleanly

        /** @brief Main application window */
        public Window window { get; private set; }


        /** @brief Action entries for the application */
        private const ActionEntry[] ACTION_ENTRIES = {
            { "resume-window", on_resume_window }
        };

        private uint _monitor_changed_id = 0;
        private bool _has_started = false;
        // Coordinates startup-only cross-component flows (e.g., deferred autoplay).
        private StartupCoordinator _startup_coordinator;
        // Works out whether the network and a radio-browser server are usable.
        public ConnectionCoordinator connection { get; private set; }
        // Coordinates playback restart behavior after online/offline transitions.
        private PlaybackRecoveryCoordinator _playback_recovery_coordinator;
        // Coordinates provider click/vote updates from player events.
        private UsageTrackingCoordinator _usage_tracking_coordinator;
        // Cookie of the active suspend inhibitor, or 0 when none is held.
        private uint _sleep_inhibit_cookie = 0;
        private bool _is_playing = false;


        /**
        * @brief Constructor for the Application
        */
        private Application () {
            GLib.Object (
                application_id: APP_ID,
                flags: ApplicationFlags.FLAGS_NONE
            );
        }


        /**
        * @brief Construct block for initializing the application
        */
        construct 
        {           
            cache_dir = stat_dir(Environment.get_user_cache_dir ());
            data_dir = stat_dir(Environment.get_user_data_dir ());

            var starred_file = setup_runtime_storage ();

            events = create_event_bus();
            network = create_network_state();
            initialize_connectivity_monitoring ();

            settings = create_settings();
            provider = create_provider();
            session = new StationSession();
            player = create_player();
            stars = create_star_store(starred_file);
            directory = create_directory_controller(provider, stars);
            history = new History();
            all_time = new HeartedArchive(settings, history);
            jukebox = create_jukebox_controller();
            tape_counter = create_tape_counter_controller();
            initialize_coordinators();

            register_application_actions ();
        } // construct


        /**
        * @brief Prepares the starred data file path under runtime data storage.
        *
        * Requires `data_dir` to already be initialized in the construct block.
        * Also attempts one-time migration from the legacy favorites file.
        *
        * @return The target starred data file handle.
        */
        private File setup_runtime_storage ()
        {
            var favorites_file = File.new_build_filename(data_dir, "favorites.json");
            var starred_file   = File.new_build_filename(data_dir, Application.STARRED);
            migrate_legacy_favorites(favorites_file, starred_file);

            return starred_file;
        }


        /**
        * @brief Attempts migration from the legacy favorites file to starred file.
        *
        * @param favorites_file Legacy file path from older versions.
        * @param starred_file Current starred file path.
        */
        private void migrate_legacy_favorites(File favorites_file, File starred_file)
        {
            try {
                favorites_file.open_readwrite().close ();
                starred_file.create(NONE);
                favorites_file.copy(starred_file, FileCopyFlags.NONE);
                warning(@"Migrated v1 Favorites to v2 Starred");
            }
            catch (Error e) {
                // Preconditions not met, no migration needed.
            }
        }


        /**
        * @brief Creates the application event bus instance.
        *
        * @return Newly created app event bus.
        */
        private AppEventBus create_event_bus()
        {
            return new AppEventBus();
        }


        /**
        * @brief Creates the network state, and has the event bus and the HTTP client follow it.
        *
        * @return Newly created network state.
        */
        private NetworkState create_network_state()
        {
            var state = new NetworkState();
            state.changed.connect ((online) => {
                events.connectivity_changed_sig (online);
            });
            HttpClient.use_network (state);
            return state;
        }


        /**
        * @brief Initializes connectivity monitor hooks and initial online state.
        */
        private void initialize_connectivity_monitoring()
        {
            network.set_online (NETMON.get_network_available ());
            NETMON.network_changed.connect((monitor) => {
                check_online_status();
            });
        }


        /**
        * @brief Creates application settings service.
        *
        * @return Newly created settings instance.
        */
        private Settings create_settings()
        {
            return new Settings ();
        }


        /**
        * @brief Creates radio-provider service.
        *
        * @return Newly created provider API implementation.
        */
        private DataProvider.API create_provider()
        {
            return new RadioBrowser(null, network);
        }


        /**
        * @brief Creates player controller service.
        *
        * @return Newly created player controller.
        */
        private PlayerController create_player()
        {
            return new PlayerController (events, settings, session, network);
        }


        /**
        * @brief Creates star-store service for station persistence.
        *
        * @param starred_file Runtime starred data file path.
        * @return Newly created star-store instance.
        */
        private StarStore create_star_store(File starred_file)
        {
            return new StarStore(starred_file, events, provider);
        }


        /**
        * @brief Creates directory controller service.
        *
        * @param provider Provider API instance.
        * @param stars Star-store instance.
        * @return Newly created directory controller.
        */
        private DirectoryController create_directory_controller(DataProvider.API provider, StarStore stars)
        {
            return new DirectoryController(provider, stars, network);
        }


        /**
        * @brief Creates the jukebox controller service.
        *
        * @return Newly created jukebox controller.
        */
        private JukeboxController create_jukebox_controller()
        {
            return new JukeboxController(this, directory);
        }


        /**
        * @brief Creates the tape-counter controller service.
        *
        * @return Newly created tape-counter controller.
        */
        private TapeCounterController create_tape_counter_controller()
        {
            return new TapeCounterController(events, history, session);
        }


        /**
        * @brief Initializes app coordinators that consume initialized services.
        */
        private void initialize_coordinators()
        {
            connection = new ConnectionCoordinator(this, events, provider);
            _playback_recovery_coordinator = new PlaybackRecoveryCoordinator(this, events, player, settings);
            _usage_tracking_coordinator = new UsageTrackingCoordinator(settings, events, provider, session);

            // Stop the computer suspending while a station plays, if the user wants that
            events.player_state_changed_sig.connect ((station, state) =>
            {
                _is_playing = state == StreamPlayer.State.PLAYING || state == StreamPlayer.State.BUFFERING;
                update_sleep_inhibit ();
            });
            settings.notify["inhibit-sleep"].connect (() => { update_sleep_inhibit (); });
        }


        /**
        * @brief Holds a suspend inhibitor while a station is playing and the preference is on.
        *
        * Only suspend is inhibited, so the screen can still blank and lock. The inhibitor is
        * released when playback pauses, stops or fails, or when the preference is turned off.
        * Under Flatpak the request goes through the desktop portal.
        */
        private void update_sleep_inhibit ()
        {
            var wanted = _is_playing && settings.inhibit_sleep;

            if (wanted && _sleep_inhibit_cookie == 0)
            {
                _sleep_inhibit_cookie = inhibit (window, Gtk.ApplicationInhibitFlags.SUSPEND, _("Playing radio"));
                if (Tuner.debug_enabled ())
                    debug (@"Suspend inhibitor requested, cookie $_sleep_inhibit_cookie");
            }
            else if (!wanted && _sleep_inhibit_cookie != 0)
            {
                uninhibit (_sleep_inhibit_cookie);
                if (Tuner.debug_enabled ())
                    debug (@"Suspend inhibitor released, cookie $_sleep_inhibit_cookie");
                _sleep_inhibit_cookie = 0;
            }
        } // update_sleep_inhibit


        /**
        * @brief Registers app-level actions used by UI and preferences widgets.
        */
        private void register_application_actions()
        {
            add_action_entries(ACTION_ENTRIES, this);
            add_string_action("set-theme-name", (value) => { theme_name = value; });
            add_string_action("set-language", (value) => { language = value; });
        }


        /**
        * @brief Adds a string-parameter action and binds it to a typed handler.
        *
        * @param action_name Action name to register.
        * @param handler Callback that receives the string payload.
        */
        private void add_string_action(string action_name, StringActionHandler handler)
        {
            var action = new SimpleAction(action_name, VariantType.STRING);
            action.activate.connect((parameter) => {
                if (parameter != null)
                    handler(parameter.get_string());
            });
            add_action(action);
        }


        /**
        * @brief Getter for the singleton instance
        *
        * @return The Application instance
        */
        public static Application instance 
        {
            get {
                    if (Tuner._instance == null) {  
                    Tuner._instance = new Application ();  
                }
                return Tuner._instance;
            }
        } // instance


        /**
        * @brief Activates the application
        *
        * This method is called when the application is activated. It creates
        * or presents the main window and initializes the DBus connection.
        */
        protected override void activate() 
        {
            if (window == null) { 
                var began = GLib.get_monotonic_time();
                connection.start();     // Starts choosing a server while the window is built
                initialize_runtime_presentation();
                var presented = GLib.get_monotonic_time();
                apply_runtime_preferences();
                create_main_window();
                if (Tuner.debug_enabled ())
                    debug(@"[startup] activate: DBus/CSS $((presented - began) / 1000)ms, window $((GLib.get_monotonic_time() - presented) / 1000)ms");
            } else {
                window.present ();
            }
        } // activate
        
        
        /**
        * @brief Resumes the window
        *
        * This method is called to bring the main window to the foreground.
        */
        private void on_resume_window() {
            if (window != null)
                window.present();
        }


        /**
        * @brief Initializes runtime services required for visual presentation.
        *
        * Sets up DBus media integration, caches system GTK theme, and installs
        * the application CSS provider on the default screen.
        */
        private void initialize_runtime_presentation()
        {
            Services.DBus.initialize (this);

            GTK_SETTINGS = Gtk.Settings.get_default();
            GTK_SYSTEM_THEME = GTK_SETTINGS.gtk_theme_name;
            CSSPROVIDER.load_from_resource ("/io/github/tuner_labs/tuner/css/Tuner-system.css");
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                CSSPROVIDER,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }


        /**
        * @brief Applies persisted runtime preferences before creating widgets.
        *
        * Theme and language are applied early so the first rendered window
        * reflects the user's configured preferences.
        */
        private void apply_runtime_preferences()
        {
            apply_theme_name(settings.theme_mode);
            language = settings.language;
        }


        /**
        * @brief Creates and registers the main application window.
        *
        * Also starts startup-only orchestration and applies screenshot sizing.
        */
        private void create_main_window()
        {
#if DEBUG_LOCAL
            // Development-only: set up the screenshot state before the window is built
            ScreenshotMode.prepare ();
#endif
            window = new Window (this, player, settings, directory);

            _startup_coordinator = new StartupCoordinator(this, events, window, settings, directory);
            _startup_coordinator.start();

#if DEBUG_LOCAL
            // Development-only: apply the screenshot steps from TUNER_SCREENSHOT, if set.
            // See Services/ScreenshotMode.vala and scripts/screenshots.sh. Flathub wants about 1000x625.
            if (ScreenshotMode.is_active ())
                ScreenshotMode.apply.begin (window);
#endif

            add_window(window);
        }


        /**
        * @brief Create directory structure quietly
        *
        */
        private string? stat_dir (string dir)
        {
            var _dir = File.new_build_filename (dir, application_id);
            try {
                _dir.make_directory_with_parents ();
            } catch (IOError.EXISTS e) {
            } catch (Error e) {
                warning(@"Stat Directory failed $(e.message)");
                return null;
            }
            return _dir.get_path ();

        } // stat_dir


        /**
        * @brief Set the network availability
        *
        * If going offline, set immediately.
        * Going online - wait a second to allow network to stabilize
        * This method removes any existing timeout and sets a new one 
        * reduces network state bounciness
        */
        private void check_online_status()
        {
            bool network_available = NETMON.get_network_available ();

            // Clean up the prior network monitor task
            if( _monitor_changed_id > 0) 
            {
                Source.remove(_monitor_changed_id);
                _monitor_changed_id = 0;
            }

            /*
                If change to online from offline state
                wait 1 seconds before setting to online status
                to whatever the state is at that time
            */
            if ( network_available )
            {
                if (is_online)
                    return;

                _monitor_changed_id = Timeout.add_seconds( (uint)_has_started+1, () => 
                {           
                    _monitor_changed_id = 0; // Reset timeout ID after scheduling  
                    network.set_online (NETMON.get_network_available ());
                    _has_started = true;
                    return Source.REMOVE;
                });

                return;
            }
            // network is unavailable 
            network.set_online (false);
        } // check_online_status


        /** @brief Spawns a new instance of the application */
        private void spawn_restart() 
        {
            try {
                Pid pid;

                string[] argv = build_restart_argv();

                Process.spawn_async(
                    null,
                    argv,
                    null, // inherit environment (LANGUAGE already set)
                    SpawnFlags.SEARCH_PATH,
                    null,
                    out pid
                );

            } catch (SpawnError e) {
                warning(@"Restart failed: $(e.message)");
            }
        } // spawn_restart


        /** @brief Build the correct argv for restarting the application, handling Flatpak and Meson cases */   
        private string[] build_restart_argv() 
        {
            string exe = Environment.get_prgname();

            // Prefer stored argv (Meson, Flatpak, debugging correctness)
            if (APP_ARGV != null && APP_ARGV.length > 0)
                exe = APP_ARGV[0];

            // Flatpak requires host spawn
            if (FileUtils.test("/run/.flatpak-info", FileTest.EXISTS) ) 
            // Is a flatpak
            {
                return { "flatpak-spawn", "--host", exe };
            }

            return { exe };
        } // build_restart_argv
    } // Application
} // namespace Tuner
