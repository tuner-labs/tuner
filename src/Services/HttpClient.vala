/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HttpClient.vala
 * @author technosf
 * @date 2024-10-01
 * @since 1.5.4
 * @brief HTTP client implementation using Soup library
 */

using Gee;

/**
 * @class Tuner.HttpClient
 * @brief HTTP functions abstracting Soup library
 *
 * This class provides static methods for making HTTP requests using the Soup library.
 * It includes a singleton Soup.Session instance for efficient request handling.
 */
public class Tuner.Services.HttpClient : Object
{

    /**
     * @brief Singleton instance of Soup.Session
     *
     * This private static variable holds the single instance of Soup.Session
     * used for all HTTP requests in the application. It is initialized lazily
     * in the getSession() method.
     */
    private static Soup.Session _session;

    /** @brief The state of the network: no request is sent while offline, and they are cancelled when it goes */
    private static NetworkState? _network = null;

    /**
     * @brief Tells the client which network state to follow. Call once, before the first request.
     */
    public static void use_network (NetworkState network)
    {
        _network = network;
    } // use_network

    /** @brief Whether the network is known to be unusable */
    private static bool offline ()
    {
        return _network != null && _network.is_offline;
    } // offline

    /** @brief The cancellable that ends requests when the network goes, null if there is none */
    private static Cancellable? cancellable ()
    {
        return _network != null ? _network.cancellable : null;
    } // cancellable

    /** @brief Whether the network has gone away, cancelling requests */
    private static bool cancelled ()
    {
        return _network != null && _network.cancellable.is_cancelled ();
    } // cancelled

    /** @brief Soup session timeout in seconds, normally (also quoted in diagnostics) */
    private const int SESSION_TIMEOUT_S = 3;

    /** @brief Seconds added to the session timeout for each failed attempt to reach the provider */
    private const int PATIENCE_STEP_S = 3;

    /** @brief The longest the session timeout is stretched to */
    private const int MAX_SESSION_TIMEOUT_S = 12;

    /** @brief The timeout the current session is made with */
    private static int _session_timeout_s = SESSION_TIMEOUT_S;


    /**
     * @brief Milliseconds elapsed on a timer, for diagnostics.
     */
    private static uint elapsed_ms(Timer timer)
    {
        return (uint)(timer.elapsed() * 1000.0);
    } // elapsed_ms


    /**
     * @brief Describe an error as domain:code and message, for diagnostics.
     *
     * The domain/code pair distinguishes a timeout, a refused connection,
     * a DNS failure, a TLS failure or a cancellation.
     */
    private static string describe_error(Error e)
    {
        return @"$(e.domain.to_string()) code=$(e.code) '$(e.message)'";
    } // describe_error


    /**
     * @brief Get the singleton Soup.Session instance
     *
     * This method returns the singleton Soup.Session instance, creating it
     * if it doesn't already exist. The session is configured with a custom
     * user agent string and a timeout of 2 seconds, maximum 30 connections
     * with only one connection per host.
     * 
     *
     * @return The singleton Soup.Session instance
     */
    private static Soup.Session getSession()
    {
        if (_session == null)
        {
            _session = new Soup.Session.with_options(
               "max-conns", 50,
                "max-conns-per-host", 2 ,
                "timeout", _session_timeout_s,
                "user_agent", Tuner.user_agent ()
            );
        }
        return _session;
    } // getSession


    /**
     * @brief Throws away the HTTP session and starts a fresh one with the next request.
     *
     * A fresh session has new connections and no memory of earlier failures. Requests still waiting on the
     * old session are cancelled. Each failure stretches the time-out of the new session a little, so a
     * slow network or a slow server gets more time, up to a limit.
     *
     * @param failures How many times in a row the provider could not be reached; 0 for the normal time-out
     */
    public static void use_fresh_session (int failures)
    {
        if (_session != null)
            _session.abort ();
        _session = null;
        _session_timeout_s = int.min (SESSION_TIMEOUT_S + failures * PATIENCE_STEP_S, MAX_SESSION_TIMEOUT_S);
    } // use_fresh_session


    /**
     * @brief Perform an asynchronous GET request to the specified URL
     *
     * @param url_string The URL to send the GET request to
     * @param status_code Output parameter for the HTTP status code of the response
     * @return InputStream containing the response body, or null if the request failed
     */
    public static async InputStream? GETasync(Uri? uri, int priority, out uint status_code) 
    {
        return yield GETasync_tries(uri, priority, 3, out status_code);
    } // GETasync


    /**
     * @brief Whether a failed request is worth sending again.
     *
     * No response at all (0), a timeout (408), rate limiting (429) and server-side errors (5xx) can
     * clear up. Other client errors, such as a missing file (404), fail the same way every time.
     */
    private static bool worth_retrying(uint status_code)
    {
        return status_code == 0 || status_code == 408 || status_code == 429 || status_code >= 500;
    } // worth_retrying


    /**
     * @brief Describe how one attempt ended, for diagnostics.
     *
     * @param msg The request message, holding the HTTP status when a response arrived
     * @param e The error if no response arrived, otherwise null
     */
    private static string describe_outcome(Soup.Message msg, Error? e)
    {
        if (e != null)
            return @"no response ($(describe_error(e)); session timeout $(_session_timeout_s)s; cancelled=$(cancelled()))";
        return @"got HTTP $(msg.status_code) '$(msg.reason_phrase ?? "")'";   // reason is null when no response line was parsed
    } // describe_outcome


    /**
     * @brief The outcome of one GET attempt
     */
    private class Attempt : GLib.Object
    {
        /** @brief The response body, when a response arrived */
        public InputStream? stream = null;
        /** @brief The HTTP status, 0 if no response arrived */
        public uint status = 0;
        /** @brief Why no response arrived, otherwise null */
        public Error? error = null;

        /** @brief Whether a 2xx response arrived */
        public bool succeeded
        {
            get { return error == null && status >= 200 && status < 300; }
        }
    } // Attempt


    /**
     * @brief Sends one GET request and reports how it went.
     *
     * @param attempt Which attempt this is, for the diagnostics
     * @param max_tries How many attempts there may be, for the diagnostics
     */
    private static async Attempt get_once(Uri uri, int priority, int attempt, int max_tries)
    {
        var result = new Attempt();
        var msg = new Soup.Message.from_uri("GET", uri);

        // Ignore all TLS certificate errors
        msg.accept_certificate.connect ((m, cert, errors) => {
            return true;
        });

        var timer = new Timer();   // Diagnostics: time taken by this attempt
        try
        {
            result.stream = yield getSession().send_async(msg, priority, cancellable());
            result.status = msg.status_code;
        } catch (Error e)
        {
            result.error = e;
        }

        if (Tuner.debug_enabled ())
            debug(@"GETasync - Try $(attempt)/$(max_tries) $(describe_outcome(msg, result.error)) after $(elapsed_ms(timer))ms: $(uri.to_string())");
        return result;
    } // get_once


    /**
     * @brief GETasync() with a choice of how many attempts are made
     *
     * A new message is sent for each attempt. Only failures that can clear up are retried (see
     * worth_retrying()), after a short pause that grows with each attempt, and retrying stops at once
     * if the app goes offline.
     *
     * @param max_tries Attempts before giving up; use 1 to fail fast, e.g. when the caller has another
     *                  server to move on to
     * @param status_code Output parameter for the HTTP status code of the last attempt, 0 if no response
     * @return InputStream containing the response body, or null if the request failed
     */
    public static async InputStream? GETasync_tries(Uri? uri, int priority, int max_tries, out uint status_code) 
    {
        status_code = 0;

        if (offline())
            return null;

        if (uri == null)
        {
            warning("GETasync - Invalid URI (null)");
            return null;
        }

        for (int attempt = 1; attempt <= max_tries; attempt++)
        {
            var result = yield get_once(uri, priority, attempt, max_tries);
            status_code = result.status;

            if (result.succeeded)
                return result.stream;

            if (cancelled() || !worth_retrying(result.status))
                break;      // Gone offline, or this would only fail the same way again

            if (attempt < max_tries)
                yield nap(200 * attempt);
        }

        if (Tuner.debug_enabled ())
            debug(@"GETasync - gave up after $(max_tries) tries at most, last http_status=$(status_code): $(uri.to_string())");
        return null;
    } // GETasync_tries
}
