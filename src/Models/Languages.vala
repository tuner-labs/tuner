/*
 * SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file Languages.vala
 *
 * @brief Language names for various language codes related to available translations
 * 
 */

using Gee;

/*
    Language names for various language codes related to available translations. 

    ISO 3166-1 alpha-2 codes are two-letter country codes defined in ISO 3166-1, 
    part of the ISO 3166 standard[1] published by the International Organization for Standardization (ISO), 
    to represent countries, dependent territories, and special areas of geographical interest.

    BCP 47 language tags are a standardized code used to identify human languages. 
    They are defined by the Internet Engineering Task Force (IETF) in RFC 5646,

    Language code look up references:
        https://stringcatalog.com/languages/es/es-419

*/
namespace Tuner.Models {

    /**
     * @brief The Languages class provides a mapping of language codes to their translated names, 
     *        and methods to retrieve language names based on codes and the current locale.
     */
    public class Languages 
    {
        
        private static string? current_locale = null;

        private static SortedMap<string,string>? _cached_translated_map = null;

        private static SortedMap<string, string> _reference_map = null;

        // The map property initializes and returns a mapping of language codes to their translated names.
        public static Map<string, string> map 
        {
            get {
                if (_reference_map == null) {
                    _reference_map = new TreeMap<string, string> ();

                    // Language code we have translations for which have a different name than the default one.

                    _reference_map["es_419"] = NC_("Languages","Spanish (Latin America)");
                    _reference_map["nb_NO"] = NC_("Languages","Norwegian (Bokmal)");
                    _reference_map["pt_BR"] = NC_("Languages","Portuguese (Brazil)");
                    _reference_map["zh_Hant"] = NC_("Languages","Traditional Chinese");

                    // Populate the reference map with language codes and their corresponding translated names, 
                    // which we may or may not have translations for, but we want to have a reference for the default name.
                    _reference_map["aa"] = NC_("Languages","Afar");
                    _reference_map["ab"] = NC_("Languages","Abkhazian");
                    _reference_map["ae"] = NC_("Languages","Avestan");
                    _reference_map["af"] = NC_("Languages","Afrikaans");
                    _reference_map["ak"] = NC_("Languages","Akan");
                    _reference_map["am"] = NC_("Languages","Amharic");
                    _reference_map["an"] = NC_("Languages","Aragonese");
                    _reference_map["ar"] = NC_("Languages","Arabic");
                    _reference_map["as"] = NC_("Languages","Assamese");
                    _reference_map["av"] = NC_("Languages","Avaric");
                    _reference_map["ay"] = NC_("Languages","Aymara");
                    _reference_map["az"] = NC_("Languages","Azerbaijani");

                    _reference_map["ba"] = NC_("Languages","Bashkir");
                    _reference_map["be"] = NC_("Languages","Belarusian");
                    _reference_map["bg"] = NC_("Languages","Bulgarian");
                    _reference_map["bh"] = NC_("Languages","Bihari");
                    _reference_map["bi"] = NC_("Languages","Bislama");
                    _reference_map["bm"] = NC_("Languages","Bambara");
                    _reference_map["bn"] = NC_("Languages","Bengali");
                    _reference_map["bo"] = NC_("Languages","Tibetan");
                    _reference_map["br"] = NC_("Languages","Breton");
                    _reference_map["bs"] = NC_("Languages","Bosnian");

                    _reference_map["ca"] = NC_("Languages","Catalan");
                    _reference_map["ce"] = NC_("Languages","Chechen");
                    _reference_map["ch"] = NC_("Languages","Chamorro");
                    _reference_map["co"] = NC_("Languages","Corsican");
                    _reference_map["cr"] = NC_("Languages","Cree");
                    _reference_map["cs"] = NC_("Languages","Czech");
                    _reference_map["cu"] = NC_("Languages","Church Slavic");
                    _reference_map["cv"] = NC_("Languages","Chuvash");
                    _reference_map["cy"] = NC_("Languages","Welsh");

                    _reference_map["da"] = NC_("Languages","Danish");
                    _reference_map["de"] = NC_("Languages","German");
                    _reference_map["dv"] = NC_("Languages","Divehi");
                    _reference_map["dz"] = NC_("Languages","Dzongkha");

                    _reference_map["ee"] = NC_("Languages","Ewe");
                    _reference_map["el"] = NC_("Languages","Greek");
                    _reference_map["en"] = NC_("Languages","English");
                    _reference_map["eo"] = NC_("Languages","Esperanto");
                    _reference_map["es"] = NC_("Languages","Spanish");
                    _reference_map["et"] = NC_("Languages","Estonian");
                    _reference_map["eu"] = NC_("Languages","Basque");

                    _reference_map["fa"] = NC_("Languages","Persian");
                    _reference_map["ff"] = NC_("Languages","Fulah");
                    _reference_map["fi"] = NC_("Languages","Finnish");
                    _reference_map["fj"] = NC_("Languages","Fijian");
                    _reference_map["fo"] = NC_("Languages","Faroese");
                    _reference_map["fr"] = NC_("Languages","French");
                    _reference_map["fy"] = NC_("Languages","Western Frisian");

                    _reference_map["ga"] = NC_("Languages","Irish");
                    _reference_map["gd"] = NC_("Languages","Scottish Gaelic");
                    _reference_map["gl"] = NC_("Languages","Galician");
                    _reference_map["gn"] = NC_("Languages","Guarani");
                    _reference_map["gu"] = NC_("Languages","Gujarati");
                    _reference_map["gv"] = NC_("Languages","Manx");

                    _reference_map["ha"] = NC_("Languages","Hausa");
                    _reference_map["he"] = NC_("Languages","Hebrew");
                    _reference_map["hi"] = NC_("Languages","Hindi");
                    _reference_map["ho"] = NC_("Languages","Hiri Motu");
                    _reference_map["hr"] = NC_("Languages","Croatian");
                    _reference_map["ht"] = NC_("Languages","Haitian");
                    _reference_map["hu"] = NC_("Languages","Hungarian");
                    _reference_map["hy"] = NC_("Languages","Armenian");
                    _reference_map["hz"] = NC_("Languages","Herero");

                    _reference_map["ia"] = NC_("Languages","Interlingua");
                    _reference_map["id"] = NC_("Languages","Indonesian");
                    _reference_map["ie"] = NC_("Languages","Interlingue");
                    _reference_map["ig"] = NC_("Languages","Igbo");
                    _reference_map["ii"] = NC_("Languages","Sichuan Yi");
                    _reference_map["ik"] = NC_("Languages","Inupiaq");
                    _reference_map["io"] = NC_("Languages","Ido");
                    _reference_map["is"] = NC_("Languages","Icelandic");
                    _reference_map["it"] = NC_("Languages","Italian");
                    _reference_map["iu"] = NC_("Languages","Inuktitut");

                    _reference_map["ja"] = NC_("Languages","Japanese");
                    _reference_map["jv"] = NC_("Languages","Javanese");

                    _reference_map["ka"] = NC_("Languages","Georgian");
                    _reference_map["kg"] = NC_("Languages","Kongo");
                    _reference_map["ki"] = NC_("Languages","Kikuyu");
                    _reference_map["kj"] = NC_("Languages","Kwanyama");
                    _reference_map["kk"] = NC_("Languages","Kazakh");
                    _reference_map["kl"] = NC_("Languages","Kalaallisut");
                    _reference_map["km"] = NC_("Languages","Khmer");
                    _reference_map["kn"] = NC_("Languages","Kannada");
                    _reference_map["ko"] = NC_("Languages","Korean");
                    _reference_map["kr"] = NC_("Languages","Kanuri");
                    _reference_map["ks"] = NC_("Languages","Kashmiri");
                    _reference_map["ku"] = NC_("Languages","Kurdish");
                    _reference_map["kv"] = NC_("Languages","Komi");
                    _reference_map["kw"] = NC_("Languages","Cornish");
                    _reference_map["ky"] = NC_("Languages","Kirghiz");

                    _reference_map["la"] = NC_("Languages","Latin");
                    _reference_map["lb"] = NC_("Languages","Luxembourgish");
                    _reference_map["lg"] = NC_("Languages","Ganda");
                    _reference_map["li"] = NC_("Languages","Limburgish");
                    _reference_map["ln"] = NC_("Languages","Lingala");
                    _reference_map["lo"] = NC_("Languages","Lao");
                    _reference_map["lt"] = NC_("Languages","Lithuanian");
                    _reference_map["lv"] = NC_("Languages","Latvian");

                    _reference_map["mg"] = NC_("Languages","Malagasy");
                    _reference_map["mh"] = NC_("Languages","Marshallese");
                    _reference_map["mi"] = NC_("Languages","Maori");
                    _reference_map["mk"] = NC_("Languages","Macedonian");
                    _reference_map["ml"] = NC_("Languages","Malayalam");
                    _reference_map["mn"] = NC_("Languages","Mongolian");
                    _reference_map["mr"] = NC_("Languages","Marathi");
                    _reference_map["ms"] = NC_("Languages","Malay");
                    _reference_map["mt"] = NC_("Languages","Maltese");
                    _reference_map["my"] = NC_("Languages","Burmese");

                    _reference_map["na"] = NC_("Languages","Nauru");
                    _reference_map["nb"] = NC_("Languages","Norwegian Bokmal");
                    _reference_map["nd"] = NC_("Languages","North Ndebele");
                    _reference_map["ne"] = NC_("Languages","Nepali");
                    _reference_map["ng"] = NC_("Languages","Ndonga");
                    _reference_map["nl"] = NC_("Languages","Dutch");
                    _reference_map["nn"] = NC_("Languages","Norwegian Nynorsk");
                    _reference_map["no"] = NC_("Languages","Norwegian");
                    _reference_map["nr"] = NC_("Languages","South Ndebele");
                    _reference_map["nv"] = NC_("Languages","Navajo");
                    _reference_map["ny"] = NC_("Languages","Chichewa");

                    _reference_map["oc"] = NC_("Languages","Occitan");
                    _reference_map["oj"] = NC_("Languages","Ojibwa");
                    _reference_map["om"] = NC_("Languages","Oromo");
                    _reference_map["or"] = NC_("Languages","Oriya");
                    _reference_map["os"] = NC_("Languages","Ossetian");

                    _reference_map["pa"] = NC_("Languages","Punjabi");
                    _reference_map["pi"] = NC_("Languages","Pali");
                    _reference_map["pl"] = NC_("Languages","Polish");
                    _reference_map["ps"] = NC_("Languages","Pashto");
                    _reference_map["pt"] = NC_("Languages","Portuguese");

                    _reference_map["qu"] = NC_("Languages","Quechua");

                    _reference_map["rm"] = NC_("Languages","Romansh");
                    _reference_map["rn"] = NC_("Languages","Rundi");
                    _reference_map["ro"] = NC_("Languages","Romanian");
                    _reference_map["ru"] = NC_("Languages","Russian");
                    _reference_map["rw"] = NC_("Languages","Kinyarwanda");

                    _reference_map["sa"] = NC_("Languages","Sanskrit");
                    _reference_map["sc"] = NC_("Languages","Sardinian");
                    _reference_map["sd"] = NC_("Languages","Sindhi");
                    _reference_map["se"] = NC_("Languages","Northern Sami");
                    _reference_map["sg"] = NC_("Languages","Sango");
                    _reference_map["si"] = NC_("Languages","Sinhala");
                    _reference_map["sk"] = NC_("Languages","Slovak");
                    _reference_map["sl"] = NC_("Languages","Slovenian");
                    _reference_map["sm"] = NC_("Languages","Samoan");
                    _reference_map["sn"] = NC_("Languages","Shona");
                    _reference_map["so"] = NC_("Languages","Somali");
                    _reference_map["sq"] = NC_("Languages","Albanian");
                    _reference_map["sr"] = NC_("Languages","Serbian");
                    _reference_map["ss"] = NC_("Languages","Swati");
                    _reference_map["st"] = NC_("Languages","Southern Sotho");
                    _reference_map["su"] = NC_("Languages","Sundanese");
                    _reference_map["sv"] = NC_("Languages","Swedish");
                    _reference_map["sw"] = NC_("Languages","Swahili");

                    _reference_map["ta"] = NC_("Languages","Tamil");
                    _reference_map["te"] = NC_("Languages","Telugu");
                    _reference_map["tg"] = NC_("Languages","Tajik");
                    _reference_map["th"] = NC_("Languages","Thai");
                    _reference_map["ti"] = NC_("Languages","Tigrinya");
                    _reference_map["tk"] = NC_("Languages","Turkmen");
                    _reference_map["tl"] = NC_("Languages","Tagalog");
                    _reference_map["tn"] = NC_("Languages","Tswana");
                    _reference_map["to"] = NC_("Languages","Tonga");
                    _reference_map["tr"] = NC_("Languages","Turkish");
                    _reference_map["ts"] = NC_("Languages","Tsonga");
                    _reference_map["tt"] = NC_("Languages","Tatar");
                    _reference_map["tw"] = NC_("Languages","Twi");
                    _reference_map["ty"] = NC_("Languages","Tahitian");

                    _reference_map["ug"] = NC_("Languages","Uighur");
                    _reference_map["uk"] = NC_("Languages","Ukrainian");
                    _reference_map["ur"] = NC_("Languages","Urdu");
                    _reference_map["uz"] = NC_("Languages","Uzbek");

                    _reference_map["ve"] = NC_("Languages","Venda");
                    _reference_map["vi"] = NC_("Languages","Vietnamese");
                    _reference_map["vo"] = NC_("Languages","Volapuk");

                    _reference_map["wa"] = NC_("Languages","Walloon");
                    _reference_map["wo"] = NC_("Languages","Wolof");

                    _reference_map["xh"] = NC_("Languages","Xhosa");

                    _reference_map["yi"] = NC_("Languages","Yiddish");
                    _reference_map["yo"] = NC_("Languages","Yoruba");

                    _reference_map["za"] = NC_("Languages","Zhuang");
                    _reference_map["zh"] = NC_("Languages","Chinese");
                    _reference_map["zu"] = NC_("Languages","Zulu");

                } // if

                return _reference_map;

            } // get
        } // map


        /**
         * @brief Returns the translated name for a given language code.
         * @param code The language code to look up.
         * @param fallback The fallback string if the code is not found.
         * @return The translated name of the language or the fallback string.
         */
        public static string get_by_code(string code, string fallback = "") 
        {
            var my_code = code.strip ();
            if (my_code == "") return fallback;
            if (map.has_key (my_code)) return dpgettext2(null, "Languages", map.get(my_code));
            if (map.has_key (my_code.down())) return dpgettext2(null, "Languages", map.get(my_code.down()));
            return my_code;
        } // get_by_code


        /**
         * @brief Returns a map of language codes to their translated names.
         * @return Map of language codes to translated names.
         */
        public static Map<string,string> get_language_map () 
        {
            ensure_locale ();
            return _cached_translated_map;
        } // get_language_map

        
        /**
         * @brief Returns the language code for the current environment locale.
         * @return The language code corresponding to the current environment locale.
         */
        public static unowned string get_environment_code () 
        {   
            unowned string result = "";
            foreach ( string lang in Intl.get_language_names_with_category (Application.ENV_LANG))
            {
                if ( map.has_key (lang) && lang.length > result.length) result = lang;
            }

            return result;
        } // get_environment_code  


        /**
        * @brief Ensures that the language map is built for the current locale, 
        * rebuilding it if the locale has changed.
         */
        private static void ensure_locale () 
        {
            string loc = get_environment_code () ; // Get the current locale (language code)

            if (current_locale == loc && _cached_translated_map != null)
                return;

            current_locale = loc;
            rebuild_language_cache ();

        } // ensure_locale


        /**
        * @brief Rebuilds the cached map of language codes to their translated names based on the current locale.
         */
        private static void rebuild_language_cache () 
        {
            _cached_translated_map = new TreeMap<string,string> ();

            foreach (string id in Application.LOCALES_FOUND) {
                string? name = map.get (id);
                if (name == null || name == "")
                    name = id;
                _cached_translated_map[id] = dpgettext2 (null, "Languages", name);
            } // foreach
            
        } // rebuild_language_cache

   } // Languages
} // Tuner.Model
