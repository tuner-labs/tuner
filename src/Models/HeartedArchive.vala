/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file HeartedArchive.vala
 *
 * @brief Persistent "All Time" store of hearted tracks.
 */

using Gee;

namespace Tuner.Models
{
	/**
	 * @brief One hearted track kept in the All Time store.
	 *
	 * Plain data (no Station object) so it can be saved to and restored from settings.
	 */
	public class ArchivedTrack : GLib.Object
	{
		public string station_uuid { get; set; default = ""; }
		public string station_name { get; set; default = ""; }
		public string title { get; set; default = ""; }

		/** @brief When the track started playing, seconds since the Unix epoch. */
		public int64 played_at { get; set; default = 0; }

		/** @brief Seconds the track played. */
		public int played_seconds { get; set; default = 0; }


		/**
		 * @brief The play date and time in local time, e.g. "2026-11-05 22:50".
		 */
		public string format_played_at()
		{
			var stamp = new DateTime.from_unix_local(played_at);
			return stamp != null ? stamp.format("%Y-%m-%d %H:%M") : "";
		} // format_played_at
	} // ArchivedTrack


	/**
	 * @brief Collects every hearted track across sessions and keeps it in settings.
	 *
	 * While the "Save all Hearted tracks for All Time" preference is on, a track that is hearted
	 * in the session History is added here, its play time follows the History entry, and
	 * un-hearting it removes it again. Clearing the session History does not touch this store.
	 *
	 * Stored in the settings key `all-time-hearted` as `a(sssxi)`:
	 * station uuid, station name, title, played-at (Unix seconds), played seconds.
	 */
	public class HeartedArchive : GLib.Object
	{
		/** @brief Oldest tracks are dropped beyond this many, to keep the settings store small. */
		public const int MAX_TRACKS = 2000;

		private const string SETTINGS_KEY = "all-time-hearted";
		private const string VARIANT_TYPE = "a(sssxi)";
		private const string ROW_TYPE = "(sssxi)";

		/** @brief Emitted when tracks are added, removed or cleared (not for play-time ticks). */
		public signal void changed_sig();

		private Tuner.Settings _settings;
		private Gee.ArrayList<ArchivedTrack> _tracks = new Gee.ArrayList<ArchivedTrack>();

		// Stored track for each History entry hearted this session, so later edits follow the entry.
		private Gee.HashMap<HistoryEntry, ArchivedTrack> _live = new Gee.HashMap<HistoryEntry, ArchivedTrack>();
		private bool _dirty = false;

		// Session entries whose stored track the user deleted: not re-added while they stay hearted.
		private Gee.HashSet<HistoryEntry> _suppressed = new Gee.HashSet<HistoryEntry>();


		/**
		 * @brief Loads the stored tracks and starts following the session History.
		 */
		public HeartedArchive(Tuner.Settings settings, History history)
		{
			Object();
			_settings = settings;
			load();

			history.entry_changed_sig.connect(sync_entry);
			history.entry_removed_sig.connect(on_entry_removed);
		} // HeartedArchive


		/** @brief Stored tracks, oldest first. */
		public Gee.List<ArchivedTrack> tracks
		{
			get { return _tracks; }
		}

		/** @brief Number of stored tracks. */
		public int count
		{
			get { return _tracks.size; }
		}

		/** @brief Play time of all stored tracks, in seconds. */
		public int total_played_seconds
		{
			get
			{
				int total = 0;
				foreach (var track in _tracks)
					total += track.played_seconds;
				return total;
			}
		}


		/**
		 * @brief Removes every stored track.
		 */
		public void clear()
		{
			_tracks.clear();
			_live.clear();
			persist();
			changed_sig();
		} // clear


		/**
		 * @brief Removes one stored track.
		 */
		public void remove(ArchivedTrack track)
		{
			if (!_tracks.remove(track))
				return;

			// If a session entry is feeding this track, stop it adding the track back.
			HistoryEntry? owner = null;
			foreach (var item in _live.entries)
			{
				if (item.value == track)
				{
					owner = item.key;
					break;
				}
			}
			if (owner != null)
			{
				_live.unset(owner);
				_suppressed.add(owner);
			}

			persist();
			changed_sig();
		} // remove


		/**
		 * @brief Writes any pending play-time changes to settings. Call before quitting.
		 */
		public void flush()
		{
			if (_dirty)
				persist();
		} // flush


		/**
		 * @brief Plain-text list of the stored tracks, oldest first, for the clipboard.
		 */
		public string build_clipboard_text()
		{
			var builder = new StringBuilder();
			foreach (var track in _tracks)
			{
				builder.append(track.format_played_at()).append("  ")
					.append(track.station_name).append("\n\t♥ ")
					.append(track.title).append("  (")
					.append(format_duration(track.played_seconds)).append(")\n");
			}
			return builder.str;
		} // build_clipboard_text


		/**
		 * @brief Formats seconds as H:MM:SS or M:SS.
		 */
		public static string format_duration(int total_seconds)
		{
			int hours = total_seconds / 3600;
			int minutes = (total_seconds % 3600) / 60;
			int seconds = total_seconds % 60;

			if (hours > 0)
				return "%d:%02d:%02d".printf(hours, minutes, seconds);

			return "%d:%02d".printf(minutes, seconds);
		} // format_duration


		/**
		 * @brief Follows a session History entry: adds it when hearted, removes it when un-hearted.
		 */
		private void sync_entry(HistoryEntry entry)
		{
			var stored = _live.get(entry);

			if (!entry.hearted)
			{
				_suppressed.remove(entry);
				if (stored == null)
					return;

				_tracks.remove(stored);
				_live.unset(entry);
				persist();
				changed_sig();
				return;
			}

			var title = entry.title.strip();
			if (title == "" || _suppressed.contains(entry))
				return;

			if (stored == null)
			{
				if (!_settings.save_all_time_hearted)
					return;

				stored = new ArchivedTrack() {
					station_uuid = entry.station.stationuuid,
					station_name = entry.station.name,
					title = title,
					played_at = entry.played_at.to_unix(),
					played_seconds = entry.get_total_played_seconds()
				};
				_tracks.add(stored);
				_live.set(entry, stored);
				while (_tracks.size > MAX_TRACKS)
					_tracks.remove_at(0);

				persist();
				changed_sig();
				return;
			}

			// Already stored: follow the entry's title and play time. Ticks only mark the store
			// dirty; it is written when the entry stops playing, is dropped, or the app quits.
			stored.title = title;
			stored.played_seconds = entry.get_total_played_seconds();
			if (entry.playing)
				_dirty = true;
			else
				persist();
		} // sync_entry


		/**
		 * @brief Saves a dropped History entry's final play time and stops following it.
		 */
		private void on_entry_removed(HistoryEntry entry)
		{
			_suppressed.remove(entry);
			var stored = _live.get(entry);
			if (stored == null)
				return;

			stored.played_seconds = entry.get_total_played_seconds();
			_live.unset(entry);
			persist();
		} // on_entry_removed


		/**
		 * @brief Reads the stored tracks from settings.
		 */
		private void load()
		{
			var stored = _settings.get_value(SETTINGS_KEY);
			var count = stored.n_children();
			for (size_t index = 0; index < count; index++)
			{
				var row = stored.get_child_value(index);
				_tracks.add(new ArchivedTrack() {
					station_uuid = row.get_child_value(0).get_string(),
					station_name = row.get_child_value(1).get_string(),
					title = row.get_child_value(2).get_string(),
					played_at = row.get_child_value(3).get_int64(),
					played_seconds = row.get_child_value(4).get_int32()
				});
			}
		} // load


		/**
		 * @brief Writes the stored tracks to settings.
		 */
		private void persist()
		{
			var builder = new VariantBuilder(new VariantType(VARIANT_TYPE));
			foreach (var track in _tracks)
			{
				builder.add(ROW_TYPE,
					track.station_uuid,
					track.station_name,
					track.title,
					track.played_at,
					track.played_seconds);
			}

			_settings.set_value(SETTINGS_KEY, builder.end());
			_dirty = false;
		} // persist
	} // HeartedArchive
} // Tuner.Models
