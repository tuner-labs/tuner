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

public static int main (string[] args) 
{
    Posix.signal (Posix.Signal.SEGV, on_signal);
    Posix.signal (Posix.Signal.ABRT, on_signal);
    Posix.signal (Posix.Signal.BUS,  on_signal);

    Intl.setlocale (LocaleCategory.ALL, "");
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
    return app.run (args);
}
