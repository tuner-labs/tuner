/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Main.vala
 *
 * @brief Tuner application entry point
 * 
 */
 
using GLib;
using Posix;

[CCode (cname="backtrace")]
extern int backtrace (void** buffer, int size);

[CCode (cname="backtrace_symbols_fd")]
extern void backtrace_symbols_fd (void** buffer, int size, int fd);

void print_backtrace () {
    void* buf[64];
    int n = backtrace (buf, 64);
    backtrace_symbols_fd (buf, n, 2);
}

void on_signal (int sig) {
    GLib.stderr.printf ("Tuner abending with Signal %d\n", sig);
    GLib.stderr.flush ();
    print_backtrace ();
    Posix._exit (128 + sig);
}

private void install_filtered_json_warning_handler ()
{
    GLib.Log.set_handler (
        "Json",
        GLib.LogLevelFlags.LEVEL_WARNING,
        (log_domain, log_level, message) => {
            if (message != null
                && message.contains ("Boxed type 'GDateTime' is not handled by JSON-GLib"))
            {
                return;
            }

            GLib.Log.default_handler (log_domain, log_level, message);
        }
    );
} // install_filtered_json_warning_handler

/**
 * @brief Program entry point.
 *
 * Installs the crash signal handlers and the JSON warning filter, sets the locale, initialises
 * GStreamer and runs the Application.
 *
 * @return The application exit status, or 1 if registration fails or Tuner is already running.
 */
public static int main (string[] args) 
{
    Posix.signal (Posix.Signal.SEGV, on_signal);
    Posix.signal (Posix.Signal.ABRT, on_signal);
    Posix.signal (Posix.Signal.BUS,  on_signal);

    Intl.setlocale (LocaleCategory.ALL, "");
    install_filtered_json_warning_handler ();
    Gst.init (ref args);
    var app = Tuner.Application.instance;
    try {
        app.register (null);
    } catch (Error e) {
        GLib.critical ("Failed to register application: %s", e.message);
        return 1;
    }
    if (app.is_remote) {
        GLib.critical ("Tuner is already running.");
        return 1;
    }

    foreach (var signum in new int[] { (int) Posix.Signal.TERM, (int) Posix.Signal.HUP, (int) Posix.Signal.INT }) {
        var number = signum;
        GLib.Unix.signal_add (number, () => {
            app.quit_for_signal (number);
            return GLib.Source.REMOVE;
        });
    }

    return app.run (args);
}
