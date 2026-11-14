/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file History.vala
 *
 * @brief Session history model for played tracks.
 */

using Gee;

namespace Tuner.Models
{
	/**
	 * @brief One played track in the current session history.
	 */
	public class HistoryEntry : GLib.Object
	{
		public Station station { get; private set; }
		public string title { get; private set; default = ""; }
		public bool hearted { get; private set; default = false; }
		public DateTime played_at { get; private set; }
		public int played_seconds { get; private set; default = 0; }
		public bool playing { get; private set; default = false; }


		/**
		 * @brief Creates an entry stamped with the current local time.
		 *
		 * @param station Station the track played on.
		 * @param title Track title, or empty when the station sent none.
		 * @param hearted Whether the track is hearted.
		 */
		public HistoryEntry(Station station, string title, bool hearted = false)
		{
			Object();
			this.station = station;
			this.title = title;
			this.hearted = hearted;
			this.played_at = new DateTime.now_local();
		} // HistoryEntry


		/**
		 * @brief Replaces the entry's title.
		 */
		public void update_title(string title)
		{
			this.title = title;
			notify_property("title");
		} // update_title


		/**
		 * @brief Sets whether the entry is hearted. Does nothing if the value is unchanged.
		 */
		public void update_hearted(bool hearted)
		{
			if (this.hearted == hearted)
				return;

			this.hearted = hearted;
			notify_property("hearted");
		} // update_hearted


		/**
		 * @brief Marks the entry as playing, so playback ticks add to its time.
		 */
		public void start_playback()
		{
			if (playing)
				return;

			playing = true;
			notify_property("playing");
		} // start_playback


		/**
		 * @brief Marks the entry as no longer playing.
		 */
		public void stop_playback()
		{
			if (!playing)
				return;

			playing = false;
			notify_property("playing");
		} // stop_playback


		/**
		 * @brief Add elapsed playback seconds to this history entry.
		 *
		 * This method is driven by the shared playback tick signal so the entry
		 * accumulates time while it remains the actively playing track.
		 *
		 * @param seconds Number of seconds to add. Ignored unless the entry is playing.
		 */
		public void tick_playback(int seconds)
		{
			if (!playing || seconds <= 0)
				return;

			played_seconds += seconds;
			notify_property("played-seconds");
		} // tick_playback


		/**
		 * @brief Seconds this entry has played.
		 */
		public int get_total_played_seconds()
		{
			return played_seconds;
		} // get_total_played_seconds


		/**
		 * @brief The title to show for this entry: the track title, or "Unknown Track" if the station sent none.
		 */
		public string get_display_title()
		{
			var shown = title.strip();
			return shown == "" ? _("Unknown Track") : shown;
		} // get_display_title
	} // HistoryEntry


	/**
	 * @brief Tracks a linear history of played station/title pairs.
	 */
	public class History : GLib.Object
	{
		public signal void entry_added_sig(HistoryEntry entry);
		public signal void entry_removed_sig(HistoryEntry entry);
		public signal void entry_changed_sig(HistoryEntry entry);
		public signal void cleared_sig();


		/**
		 * @brief Plain-text list of the entries, newest first, for the clipboard.
		 */
		public string build_clipboard_text()
		{
			var builder = new StringBuilder();
			for (int index = _entries.size - 1; index >= 0; index--)
			{
				var entry = _entries[index];
				builder.append(entry.station.name).append("\n\t");
				if (entry.hearted)
					builder.append("♥ ");
				builder.append(entry.get_display_title()).append("\n");
			}
			return builder.str;
		} // build_clipboard_text

		private Gee.List<HistoryEntry> _entries = new Gee.ArrayList<HistoryEntry>();
		private HistoryEntry _last_entry = null;

		public Gee.List<HistoryEntry> entries
		{
			get { return _entries; }
		}

		public HistoryEntry last_entry
		{
			get { return _last_entry; }
		}

		public int station_change_count
		{
			get
			{
				if (_entries.size == 0)
					return 0;

				int changes = 1;
				Station previous_station = _entries[0].station;
				for (int index = 1; index < _entries.size; index++)
				{
					var entry = _entries[index];
					if (entry.station != previous_station)
					{
						changes++;
						previous_station = entry.station;
					}
				}

				return changes;
			}
		}

		public int distinct_track_count
		{
			get
			{
				var track_keys = new Gee.HashSet<string>();
				foreach (var entry in _entries)
				{
					var title = entry.title.strip();
					if (title == "")
						continue;
					track_keys.add(create_track_key(entry.station, title));
				}

				return track_keys.size;
			}
		}

		public int hearted_track_count
		{
			get
			{
				int count = 0;
				foreach (var entry in _entries)
				{
					if (entry.hearted)
						count++;
				}
				return count;
			}
		}

		public int total_played_seconds
		{
			get
			{
				int total = 0;
				foreach (var entry in _entries)
					total += entry.get_total_played_seconds();
				return total;
			}
		}


		/**
		 * @brief Removes every entry, emitting entry_removed_sig for each.
		 */
		public void clear()
		{
			stop_last_entry_playback();

			foreach (var entry in _entries)
				entry_removed_sig(entry);

			_entries.clear();
			_last_entry = null;
			cleared_sig();
		} // clear


		/**
		 * @brief Removes every entry except the current (last) one.
		 */
		public void clear_preserving_last()
		{
			if (_entries.size <= 1)
				return;

			var current_entry = _last_entry;
			var removed_entries = new Gee.ArrayList<HistoryEntry>();
			foreach (var entry in _entries)
			{
				if (entry != current_entry)
					removed_entries.add(entry);
			}

			foreach (var entry in removed_entries)
			{
				_entries.remove(entry);
				entry_removed_sig(entry);
			}
		} // clear_preserving_last


		/**
		 * @brief Adds an entry for a station and title, making it the current entry.
		 *
		 * Does nothing if the current entry already has this station and title. If the current
		 * entry is the same station with no title, it is replaced; otherwise it stops playing.
		 *
		 * @param station Station that is playing.
		 * @param title Track title, or null or empty when the station sent none.
		 */
		public void append(Station station, string title)
		{
			var normalized_title = title != null ? title : "";
			if (_last_entry != null
				&& _last_entry.station == station
				&& _last_entry.title == normalized_title)
			{
				return;
			}

			if (_last_entry != null
				&& _last_entry.station == station
				&& _last_entry.title == "")
			{
				remove_last();
			}
			else
			{
				stop_last_entry_playback();
			}

			var entry = new HistoryEntry(station, normalized_title);
			_entries.add(entry);
			_last_entry = entry;
			entry_added_sig(entry);
		} // append


		/**
		 * @brief Apply a playback tick to the current active history entry.
		 *
		 * Only the last item that matches the active station and is still
		 * playing receives incremental play time updates.
		 */
		public void tick_playback(Station station, int seconds)
		{
			if (_last_entry == null
				|| _last_entry.station != station
				|| !_last_entry.playing)
			{
				return;
			}

			_last_entry.tick_playback(seconds);
			entry_changed_sig(_last_entry);
		} // tick_playback


		/**
		 * @brief Sets the hearted flag on the current entry if it matches the station and title.
		 *
		 * @return True if the current entry matches, false otherwise.
		 */
		public bool set_last_entry_hearted_if_matches(Station station, string title, bool hearted)
		{
			if (_last_entry == null)
				return false;

			if (_last_entry.station != station || _last_entry.title != title)
				return false;

			if (_last_entry.hearted == hearted)
				return true;

			_last_entry.update_hearted(hearted);
			entry_changed_sig(_last_entry);
			return true;
		} // set_last_entry_hearted_if_matches


		/**
		 * @brief Whether the current entry is this station and title and is hearted.
		 */
		public bool is_last_entry_hearted_for(Station station, string title)
		{
			return _last_entry != null
				&& _last_entry.station == station
				&& _last_entry.title == title
				&& _last_entry.hearted;
		} // is_last_entry_hearted_for


		/**
		 * @brief Starts or stops the current entry's playback to match the player state.
		 *
		 * Ignored unless the current entry is for this station.
		 *
		 * @param station Station the state change is for.
		 * @param state New player state. PLAYING starts the entry; any other state stops it.
		 */
		public void sync_play_state(Station station, StreamPlayer.State state)
		{
			if (_last_entry == null || _last_entry.station != station)
				return;

			switch (state)
			{
				case StreamPlayer.State.PLAYING:
					_last_entry.start_playback();
					entry_changed_sig(_last_entry);
					break;
				default:
					if (_last_entry.playing)
					{
						_last_entry.stop_playback();
						entry_changed_sig(_last_entry);
					}
					break;
			}
		} // sync_play_state


		/**
		 * @brief Titles of the hearted entries, in play order. Entries with no title are skipped.
		 */
		public Gee.List<string> get_hearted_titles()
		{
			var results = new Gee.ArrayList<string>();
			foreach (var entry in _entries)
			{
				var title = entry.title.strip();
				if (!entry.hearted || title == "")
					continue;
				results.add(title);
			}
			return results;
		} // get_hearted_titles


		/**
		 * @brief Hearted entries as "Station: Title" lines, in play order. Entries with no title are skipped.
		 */
		public Gee.List<string> get_hearted_history_lines()
		{
			var results = new Gee.ArrayList<string>();
			foreach (var entry in _entries)
			{
				var title = entry.title.strip();
				if (!entry.hearted || title == "")
					continue;
				results.add(entry.station.name + ": " + title);
			}
			return results;
		} // get_hearted_history_lines


		private string create_track_key(Station station, string title)
		{
			return station.stationuuid + "\n" + title;
		} // create_track_key


		private void remove_last()
		{
			if (_last_entry == null)
				return;

			_last_entry.stop_playback();
			_entries.remove(_last_entry);
			entry_removed_sig(_last_entry);
			_last_entry = _entries.size > 0 ? _entries.get(_entries.size - 1) : null;
		} // remove_last


		private void stop_last_entry_playback()
		{
			if (_last_entry == null || !_last_entry.playing)
				return;

			_last_entry.stop_playback();
			entry_changed_sig(_last_entry);
		} // stop_last_entry_playback
	} // History
} // Tuner.Models
