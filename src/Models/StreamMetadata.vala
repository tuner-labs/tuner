/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file PlayerController.vala
 */

using Gst;

/**
 * @class Metadata
 *
 * @brief Stream Metadata transform
 *
 */
public class Tuner.Models.Metadata : GLib.Object
{
    private static string[,] METADATA_TITLES =
    // Ordered array of tags and descriptions
    {
        {"title",                       N_("Title")	                },
        {"artist",                      N_("Artist")	            },
        {"album",                       N_("Album")	                },
        {"image",                       N_("Image")	                },
        {"genre",                       N_("Genre")	                },
        {"homepage",                    N_("Homepage")	            },
        {"organization",                N_("Organization")	        },
        {"location",                    N_("Location")	            },
        {"extended-comment",            N_("Extended Comment")	    },
        {"bitrate",                     N_("Bitrate")	            },
        {"audio-codec",                 N_("Audio Codec")	        },
        {"channel-mode",                N_("Channel Mode")	        },
        {"track-number",                N_("Track Number")	        },
        {"track-count",                 N_("Track Count")	        },
        {"nominal-bitrate",             N_("Nominal Bitrate")	    },
        {"minimum-bitrate",             N_("Minimum Bitrate")	    },
        {"maximum-bitrate",             N_("Maximum Bitrate")	    },
        {"has-crc",                     N_("Has CRC")	            },
        {"container-format",            N_("Container Format")	    },
        {"container-specific-track-id", N_("Track Id")	            },
        {"application-name",            N_("Application Name")	    },
        {"encoder",                     N_("Encoder")	            },
        {"encoder-version",             N_("Encoder Version")	    },
        {"encoded-by",                  N_("Encoded by")	        },
        {"private-data",                N_("Private Data")	        },
        {"private-id3v2-frame",         N_("ID3 Private")	        },
        {"GstSample",                   N_("GStreamer Sample")	    },
        {"GstDateTime",                 N_("GStreamer Date Time")	},
        {"datetime",                    N_("Date Time")	            },
    };


    private static Gee.List<string> METADATA_TAGS =  new Gee.ArrayList<string> ();

    static construct  {

        uint8 tag_index = 0;
        foreach ( var tag in METADATA_TITLES )
        // Replicating the order in METADATA_TITLES
        {
            if ((tag_index++)%2 == 0)
                METADATA_TAGS.insert (tag_index/2, tag );
        }
    }

    public string all_tags { get; private set; default = ""; }
    public string title { get; private set; default = ""; }
    public string artist { get; private set; default = ""; }
    public string image { get; private set; default = ""; }
    public string genre { get; private set; default = ""; }
    public string homepage { get; private set; default = ""; }
    public string audio_info { get; private set; default = ""; }
    public string org_loc { get; private set; default = ""; }
    public string track { get; private set; default = ""; }
    public string pretty_print { get; private set; default = ""; }

    private Gee.Map<string,string> _metadata_values = new Gee.HashMap<string,string>();  // Hope it come out in order

    
    /**
    * Extracts the metadata from the media stream.
    *
    * @param media_info The media information stream
    * @return true if the metadata has changed
    */
    internal bool process_media_info_update (PlayerMediaInfo media_info) 
    {
        var streamlist = media_info.get_stream_list ().copy ();

        reset_fields ();

        foreach (var stream in streamlist)     // Hopefully just one metadata stream
        {
            var? tags = stream.get_tags (); // Get the raw tags

            if (tags == null)
                break;                                              // No tags, break on this metadata stream

            if (all_tags == tags.to_string ())
                return false;                                                                    // Compare to all tags and if no change return false

            all_tags = tags.to_string ();
            debug(@"All Tags: $all_tags");

            string? s = null;
            bool    b = false;
            uint    u = 0;

            tags.foreach ((list, tag) =>
            {
                var index = METADATA_TAGS.index_of (tag);

                if (index == -1)
                {
                    warning(@"New meta tag: $tag");
                    return;
                }

                var type = (list.get_value_index(tag, 0)).type();

                switch (type)
                {
                    case  GLib.Type.STRING:
                        list.get_string(tag, out s);
                        _metadata_values.set ( tag,  s);
                        break;
                    case  GLib.Type.UINT:
                        list.get_uint(tag, out u);
                        if ( u > 1000)
                            _metadata_values.set ( tag,  @"$(u/1000)K");
                        else
                            _metadata_values.set ( tag,  u.to_string ());
                        break;
                    case  GLib.Type.BOOLEAN:
                        list.get_boolean (tag, out b);
                        _metadata_values.set ( tag,  b.to_string ());
                        break;
                    default:
                        warning(@"New Tag type: $(type.name())");
                        break;
                }
            }); // tags.foreach

            update_from_metadata_values ();
        }     // foreach

        return true;
    }   // process_media_info_update

    /**
    * Extracts the metadata from a tag table.
    *
    * @param tags The tag table from the stream.
    * @return true if the metadata has changed
    */
    internal bool process_tag_table (GLib.HashTable<string, string> tags)
    {
        reset_fields ();

        var keys = new Gee.ArrayList<string> ();
        tags.foreach ((key, value) => {
            keys.add (key);
        });
        keys.sort ((a, b) => { return strcmp (a, b); });

        StringBuilder sb = new StringBuilder ();
        foreach (var key in keys)
        {
            string? value = tags.lookup (key);
            if (value == null)
                continue;
            sb.append (key).append ("=").append (value).append (";");
        }

        if (all_tags == sb.str)
            return false;
        all_tags = sb.str;

        foreach (var key in keys)
        {
            string? value = tags.lookup (key);
            if (value == null)
                continue;

            var index = METADATA_TAGS.index_of (key);
            if (index == -1)
            {
                warning(@"New meta tag: $key");
                continue;
            }

            _metadata_values.set (key, value);
        }

        update_from_metadata_values ();
        return true;
    }

    private void reset_fields ()
    {
        title        = "";
        artist       = "";
        image        = "";
        genre        = "";
        homepage     = "";
        audio_info   = "";
        org_loc      = "";
        track        = "";
        pretty_print = "";
    }

    private void update_from_metadata_values ()
    {
        _title = extract ("title");
        _artist = extract ("artist");
        _image = extract ("image");
        _genre = extract ("genre");
        _homepage = extract ("homepage");

        _audio_info = extract ("audio_codec ");
        _audio_info += extract ("bitrate ");
        _audio_info += extract ("channel_mode");
        if (_audio_info != null && _audio_info.length > 0)
            _audio_info = safestrip(_audio_info);

        _org_loc = extract("organization ");
        _org_loc += extract ("location");
        if (_org_loc != null && _org_loc.length > 0)
            org_loc = safestrip(_org_loc);

        _track = extract("track-number");    
        _track += extract("track-count");    
        _track += extract("container-specific-track-id");
        _track += extract ("extended-comment");
        if (_track != null && _track.length > 0)
            track = safestrip(_track);

        StringBuilder sb = new StringBuilder ();
        foreach ( var tag in METADATA_TAGS )
        // Pretty print
        {
            if (_metadata_values.has_key(tag))
            {
                sb.append ( _(METADATA_TITLES[METADATA_TAGS.index_of (tag),1]))
                .append(" : ")
                .append( _metadata_values.get (tag))
                .append("\n");
            }
        }

        if (sb.len > 0)
            pretty_print = sb.truncate (sb.len-1).str;
        else
            pretty_print = "";
    }


    /** */
    private string extract( string key)
    {
        if (_metadata_values.has_key (key ))
            return _metadata_values.get (key);   
        return "";
    } // extract

}     // Metadata
