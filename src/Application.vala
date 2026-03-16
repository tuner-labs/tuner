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
                            settings.save();
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

        /** @brief Player controller */
        public StarStore stars { get; construct; }
        
        /** @brief API DataProvider */
        public DataProvider.API provider { get; construct; }
        
        /** @brief Cache directory path */
        public string? cache_dir { get; construct; }
        
        /** @brief Data directory path */
        public string? data_dir { get; construct; }

        /** @brief provide a Cancellable for online processes */
        public Cancellable offline_cancel { get; construct; }

        /** @brief Are we online */
        public bool is_offline { get; private set; default = true;}   
        private bool _is_online = false;
        public bool is_online { 
            get { return _is_online; } 
            private set {   
                if ( value == _is_online ) return;     
                if ( value ) 
                { 
                    _offline_cancel.reset (); 
                }
                else 
                { 
                    _offline_cancel.cancel (); 
                }
                _is_online = value;
                is_offline = !value;
                if (events != null)
                    events.connectivity_changed_sig(_is_online );
            }
        }   

        /** @brief Run the application with the given command line arguments */
        public new int run ( string[]? argv = null)
        {
            APP_ARGV = argv;     // Keep a copy of the args for rerunning the app from the RestartManager
            return base.run (argv); 
        }

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
        private Gst.Element? _startup_jingle;
        // Coordinates playback restart behavior after online/offline transitions.
        private PlaybackRecoveryCoordinator _playback_recovery_coordinator;
        // Coordinates provider click/vote updates from player events.
        private UsageTrackingCoordinator _usage_tracking_coordinator;


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
            offline_cancel = create_offline_cancellable();
            initialize_connectivity_monitoring ();

            settings = create_settings();
            provider = create_provider();
            player = create_player();
            stars = create_star_store(starred_file);
            directory = create_directory_controller(provider, stars);
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
        * @brief Creates cancellable token used by online operations.
        *
        * @return Newly created cancellable instance.
        */
        private Cancellable create_offline_cancellable()
        {
            return new Cancellable();
        }


        /**
        * @brief Initializes connectivity monitor hooks and initial online state.
        */
        private void initialize_connectivity_monitoring()
        {
            is_online = NETMON.get_network_available ();
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
            return new RadioBrowser(null);
        }


        /**
        * @brief Creates player controller service.
        *
        * @return Newly created player controller.
        */
        private PlayerController create_player()
        {
            return new PlayerController ();
        }


        /**
        * @brief Creates star-store service for station persistence.
        *
        * @param starred_file Runtime starred data file path.
        * @return Newly created star-store instance.
        */
        private StarStore create_star_store(File starred_file)
        {
            return new StarStore(starred_file);
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
            return new DirectoryController(provider, stars);
        }


        /**
        * @brief Initializes app coordinators that consume initialized services.
        */
        private void initialize_coordinators()
        {
            _playback_recovery_coordinator = new PlaybackRecoveryCoordinator(this, events, player, settings);
            _usage_tracking_coordinator = new UsageTrackingCoordinator(settings, events, provider);
        }


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
                initialize_runtime_presentation();
                apply_runtime_preferences();
                create_main_window();
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
            window = new Window (this, player, settings, directory);
            play_startup_jingle ();
            _startup_coordinator = new StartupCoordinator(this, events, window, settings, directory);
            _startup_coordinator.start();

            // Flathub screenshot sizing
            //window.resize(1000, 625);    // Screenshot sizing - round corners 80, ds op 1

            add_window(window);
        }


        /**
        * @brief Play the startup jingle (resource-backed WAV) once per launch.
        */
        private void play_startup_jingle ()
        {
            if (_startup_jingle != null)
                return;

            var playbin = Gst.ElementFactory.make ("playbin", "startup-jingle");
            if (playbin == null)
                return;

            var uri = "resource:///io/github/tuner_labs/tuner/sounds/tuner_startup.mp3";
            playbin.set ("uri", uri);
            playbin.set ("volume", settings.volume);
            _startup_jingle = playbin;

            var bus = playbin.get_bus ();
            if (bus != null)
            {
                bus.add_signal_watch ();
                bus.message.connect ((message) => {
                    switch (message.type)
                    {
                        case Gst.MessageType.EOS:
                        case Gst.MessageType.ERROR:
                            playbin.set_state (Gst.State.NULL);
                            bus.remove_signal_watch ();
                            _startup_jingle = null;
                            break;
                        default:
                            break;
                    }
                });
            }

            playbin.set_state (Gst.State.PLAYING);
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
                    is_online = NETMON.get_network_available ();
                    _has_started = true;
                    return Source.REMOVE;
                });

                return;
            }
            // network is unavailable 
            is_online = false;
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
