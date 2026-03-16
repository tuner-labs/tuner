/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Favicon.vala
 *
 * @brief Favicon index, loading and caching
 * 
 */

using Gee;
using Tuner.Services;

/**
 * @class Favicon
 * @brief Favicon location and loading.
 */
public abstract class Tuner.Models.Favicon : Object
{
    public signal void favicon_sig();  // Station favicon loaded

    // ----------------------------------------------------------
    // statics
    // ----------------------------------------------------------

    // Stations with Favicons that failed to load
    private static Set<string> FAILING_FAVICON = new HashSet<string>();

    private const int FADE_MS = 400;


    // ----------------------------------------------------------
    // Properties
    // ----------------------------------------------------------


    /** @property {string} favicon - Favicon URL of the station. */
    private string _favicon;

    public string favicon {
        get { return _favicon; }
        protected set {
            if ( value == null || value.length == 0 || _favicon == value ) return;            
            _favicon = value;	
            try	            
            {
                _favicon_uri = Uri.parse(value, NONE);
            } catch (GLib.UriError e)
            {
                FAILING_FAVICON.add(value);
            }
        }
    } // favicon


    // ----------------------------------------------------------
    // Privates
    // ----------------------------------------------------------
    
    private Uri _favicon_uri;
    private int _favicon_loaded = 0;  // Indicates the number of load attempts the favicon from cache or internet
    private Gdk.Pixbuf _favicon_pixbuf; // Favicon for this station


    // ----------------------------------------------------------
    // Methods
    // ----------------------------------------------------------

    /**
     * @brief Abstract method to get the file path of the favicon cache.
     *
     * This method should be implemented by subclasses to provide the specific
     * file path where the favicon cache is stored.
     *
     * @return A string representing the file path of the favicon cache.
     */
    protected abstract string favicon_cache_file();

    
    /**
     * @brief Has favicon been loaded.
     *
     * @return An integer indicating the status of the favicon loading process.
     */
    public int favicon_loaded()
    { 
        return _favicon_loaded;
    }


    /**
     * @brief Asynchronously sets the given image to the station favicon, if available.
     *
     * Load the known icons first, and if reload, go around after trying the favicon url
     *
     * @param {Image} favicon_image - The favicon image to be updated.
     * @param {bool} reload - Whether to force reload the favicon from source.
     * @return {bool} True if the favicon was available and the image updated.
     */
    public async bool update_favicon_image( Gtk.Image favicon_image, bool reload = false, string default_icon = "")
    {
        bool reloading = false;
        do {           
            try{
                if ( _favicon_pixbuf == null || FAILING_FAVICON.contains(_favicon)) 
                {
                    yield fade_image(favicon_image, FADE_MS, false);
                    favicon_image.set_from_icon_name(default_icon,Gtk.IconSize.DIALOG);
                    yield fade_image(favicon_image, FADE_MS, true);
                }
                else{

                    yield fade_image(favicon_image, FADE_MS, false);
                    favicon_image.set_from_pixbuf(_favicon_pixbuf);
                    yield fade_image(favicon_image, FADE_MS, true);
                }
            } finally {
                favicon_image.opacity = 1;
                reloading = false;
            }
            
            if ( reload && _favicon_loaded < 2 ) 
            /*
                Reload requested, and favicon has not had reload requested before
            */
            { 
                FAILING_FAVICON.remove(_favicon);    // Give possible 2nd chance
                yield load_favicon_async(true); // Wait for load_favicon_async to complete
                reloading = true;
                reload = false;
            }
        } while ( reloading );
        return true;
    } // update_favicon_image

    
    /**
     * @brief Asynchronously loads the favicon for the station.
     *
     * Loads from cache is not requesting reload and cache exists
     * Otherwise async calls to the website to download the favicon,
     * then stores it in the cache and replaces the Station favicon
     *
     * @param {bool} reload - Whether to force reload the favicon.
     */
    protected async void load_favicon_async( bool reload = false )
    {
        if ( _favicon_uri == null || ( !reload && _favicon_loaded > 0 )) return;

        /*  
            Get favicon from cache file if file is in cache AND
            Not requesting reload Or favicon is currently failing
        */
        if (    ( !reload || FAILING_FAVICON.contains(_favicon) )
            &&  FileUtils.test(favicon_cache_file(), FileTest.EXISTS)) 
            {
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale(favicon_cache_file(), 48, 48, true);
                _favicon_pixbuf = pixbuf;              
                _favicon_loaded++;
                favicon_sig();
                return;
            } catch (Error e) {
                info(@"$(_favicon) - Failed to load cached favicon: $(e.message)");
            }
        }

		if (_favicon_uri == null)
			return;                                              // First load or reload requested and favicon is not failing

        uint status_code;

        InputStream? stream = yield HttpClient.GETasync(_favicon_uri, Priority.LOW, out status_code); // Will automatically try several times

        if ( stream != null && status_code == 200 ) 
        /*
            Input stream OK
        */
        {
            try {
                var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(stream, 48, 48, true,null);
                pixbuf.save(favicon_cache_file(), "png");
                _favicon_pixbuf = pixbuf;
                 _favicon_loaded++;
                favicon_sig();
                return;

            } catch (Error e) {
                debug(@"$(_favicon) - Failed to process favicon $(_favicon_uri.to_string()) - $(e.message)");
            }
        }
        info(@"$(_favicon) - Failed to load favicon $(_favicon_uri.to_string()) - Status code: $(status_code)");
        FAILING_FAVICON.add(_favicon);
    } // load_favicon_async
} // Station
