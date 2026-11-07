/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file StationSession.vala
 *
 * @brief Per-session record of what happened to each station, indexed by station UUID.
 */

using Gee;

namespace Tuner.Models
{
	/**
	 * @brief What this run of the app knows about one station.
	 *
	 * A record is created the first time anything is noted about a station and lives only
	 * for the running session. It is a plain data holder; use StationSession to read and
	 * update records so the session-wide signals and logging stay consistent.
	 */
	public class StationRecord : GLib.Object
	{
		/** @brief RadioBrowser `stationuuid` this record belongs to. */
		public string stationuuid { get; construct; }

		/** @brief Station name when the record was created, for log messages. */
		public string name { get; set; default = ""; }

		/** @brief True while the station is marked broken for this session. */
		public bool broken { get; set; default = false; }

		/** @brief The first playback error reported while the station was broken. */
		public string? broken_reason { get; set; default = null; }

		/** @brief When the station was marked broken. */
		public DateTime? broken_since { get; set; default = null; }

		/** @brief How many times playback has failed this session (counts even after recovery). */
		public uint error_count { get; set; default = 0; }

		/** @brief When playback of the station last started. */
		public DateTime? last_played { get; set; default = null; }

		/** @brief How many times playback of the station has started this session. */
		public uint play_count { get; set; default = 0; }

		/** @brief When this client last sent a click request for the station. */
		public DateTime? last_click_sent { get; set; default = null; }

		/** @brief Seconds played in intervals that have ended this session. */
		public int64 play_seconds_total { get; set; default = 0; }

		/** @brief Monotonic time (microseconds) the open play interval started, or 0 when not playing. */
		public int64 play_started { get; set; default = 0; }

		/** @brief Seconds played this session, including the interval in progress. */
		public int64 play_seconds_now
		{
			get { return play_seconds_total + open_interval_seconds(); }
		}

		/**
		 * @brief Seconds in the play interval in progress, or 0 when not playing.
		 */
		public int64 open_interval_seconds()
		{
			if (play_started == 0)
				return 0;
			return (GLib.get_monotonic_time() - play_started) / TimeSpan.SECOND;
		} // open_interval_seconds

		/**
		 * @brief Creates an empty record.
		 *
		 * @param stationuuid RadioBrowser `stationuuid` of the station.
		 * @param name Station name, for log messages.
		 */
		public StationRecord(string stationuuid, string name)
		{
			Object(stationuuid: stationuuid);
			this.name = name;
		}
	} // StationRecord


	/**
	 * @brief Session-only station state, indexed by station UUID.
	 *
	 * Replaces the old BrokenStations list. Anything the app wants to remember about a
	 * station for the length of one run goes in its StationRecord: whether it is broken,
	 * when it was last played, when a click was last sent. Nothing is saved to disk.
	 *
	 * Records are keyed by RadioBrowser `stationuuid`, not by Station instance, because the
	 * same station is re-created as a new object every time it comes back from a query.
	 *
	 * Jukebox skips stations that are broken. Playing a station by hand is never blocked,
	 * and a station that plays successfully again is taken off the broken list.
	 */
	public class StationSession : GLib.Object
	{
		private HashMap<string, StationRecord> _records = new HashMap<string, StationRecord>();   // stationuuid -> record
		private int _broken_count = 0;
		private StationRecord? _current = null;        // record of the station playing now, if any
		private int64 _play_seconds_closed = 0;        // session total of ended intervals


		/** @brief Number of stations currently marked broken. */
		public int broken_count
		{
			get { return _broken_count; }
		}


		/**
		 * @brief Emitted once each time a station becomes broken.
		 *
		 * @param station The station that failed.
		 * @param reason The first playback error reported for it.
		 */
		public signal void station_marked_broken_sig(Station station, string reason);


		/**
		 * @brief Emitted when a broken station is cleared (it played again, or was cleared by hand).
		 */
		public signal void station_recovered_sig(Station station);


		/**
		 * @brief The record for a station, or null if nothing has been noted about it yet.
		 */
		public StationRecord? lookup(Station station)
		{
			return _records[station.stationuuid];
		} // lookup


		/**
		 * @brief The record for a station, created empty if it does not exist yet.
		 */
		public StationRecord record_for(Station station)
		{
			var rec = _records[station.stationuuid];
			if (rec == null)
			{
				rec = new StationRecord(station.stationuuid, station.name);
				_records[station.stationuuid] = rec;
			}
			return rec;
		} // record_for


		// ----------------------------------------------------------
		// Broken
		// ----------------------------------------------------------

		/**
		 * @brief Whether the station is currently marked broken.
		 */
		public bool is_broken(Station station)
		{
			var rec = _records[station.stationuuid];
			return rec != null && rec.broken;
		} // is_broken


		/**
		 * @brief Mark a station as broken.
		 *
		 * @param station The station that failed to play.
		 * @param reason The playback error, kept for diagnostics.
		 * @return True if the station was newly marked, false if it was already broken.
		 */
		public bool mark_broken(Station station, string reason)
		{
			var rec = record_for(station);
			rec.error_count++;

			if (rec.broken)
				return false;

			rec.broken = true;
			rec.broken_reason = reason;
			rec.broken_since = new DateTime.now_utc();
			_broken_count++;

			warning(@"Station marked broken for this session: '$(station.name)' ($(station.stationuuid)): $(reason) [$(_broken_count) broken]");
			station_marked_broken_sig(station, reason);
			return true;
		} // mark_broken


		/**
		 * @brief Take a station off the broken list. Its other history is kept.
		 */
		public void clear_broken(Station station)
		{
			var rec = _records[station.stationuuid];
			if (rec == null || !rec.broken)
				return;

			rec.broken = false;
			rec.broken_reason = null;
			rec.broken_since = null;
			_broken_count--;

			if (Tuner.debug_enabled ())
				debug(@"Station no longer marked broken: '$(station.name)' ($(station.stationuuid)) [$(_broken_count) broken]");
			station_recovered_sig(station);
		} // clear_broken


		/**
		 * @brief Take every station off the broken list.
		 */
		public void clear_all_broken()
		{
			foreach (var rec in _records.values)
			{
				rec.broken = false;
				rec.broken_reason = null;
				rec.broken_since = null;
			}
			_broken_count = 0;
		} // clear_all_broken


		// ----------------------------------------------------------
		// Played
		// ----------------------------------------------------------

		/**
		 * @brief Note that playback of the station just started.
		 *
		 * A station that plays is not broken, so this also clears the broken mark.
		 */
		private void mark_played(Station station)
		{
			var rec = record_for(station);
			rec.last_played = new DateTime.now_utc();
			rec.play_count++;
			clear_broken(station);
		} // mark_played


		/**
		 * @brief Open a play interval for the station.
		 *
		 * Any interval still open is closed first, so a switch from one station to another
		 * with no stop in between is counted correctly. A repeat call for the station that
		 * is already playing does nothing.
		 *
		 * @return True if a new interval was opened, false if the station was already playing.
		 */
		public bool begin_play(Station station)
		{
			if (_current != null && _current.play_started != 0 && _current.stationuuid == station.stationuuid)
				return false;

			end_play();
			mark_played(station);
			_current = record_for(station);
			_current.play_started = GLib.get_monotonic_time();
			return true;
		} // begin_play


		/**
		 * @brief Close the open play interval, if there is one, and add it to the totals.
		 */
		public void end_play()
		{
			if (_current == null)
				return;

			var seconds = _current.open_interval_seconds();
			_current.play_seconds_total += seconds;
			_current.play_started = 0;
			_play_seconds_closed += seconds;
			_current = null;
		} // end_play


		/**
		 * @brief Seconds played this session across all stations, including the interval in progress.
		 */
		public int64 total_play_seconds
		{
			get { return _play_seconds_closed + current_stretch_seconds; }
		}


		/**
		 * @brief Seconds since the current station started playing, or 0 when nothing is playing.
		 */
		public int64 current_stretch_seconds
		{
			get { return _current != null ? _current.open_interval_seconds() : 0; }
		}


		/**
		 * @brief Close any open interval and set every play-time total to zero.
		 *
		 * Play counts and last-played times are kept.
		 */
		public void reset_play_times()
		{
			end_play();
			foreach (var rec in _records.values)
				rec.play_seconds_total = 0;
			_play_seconds_closed = 0;
		} // reset_play_times


		/**
		 * @brief When playback of the station last started this session, or null if it has not.
		 */
		public DateTime? get_last_played(Station station)
		{
			var rec = _records[station.stationuuid];
			return rec != null ? rec.last_played : null;
		} // get_last_played


		// ----------------------------------------------------------
		// Clicks
		// ----------------------------------------------------------

		/**
		 * @brief When this client last sent a click request for the station.
		 *
		 * The Station's own `clicktimestamp` is the server's last click from any listener;
		 * this is the client's own record, used to send at most one click per station per day.
		 *
		 * @return The time of the last click request, or null if none was sent this session.
		 */
		public DateTime? get_last_click_sent(Station station)
		{
			var rec = _records[station.stationuuid];
			return rec != null ? rec.last_click_sent : null;
		} // get_last_click_sent


		/**
		 * @brief Record that a click request was just sent for the station.
		 */
		public void set_last_click_sent(Station station, DateTime when)
		{
			record_for(station).last_click_sent = when;
		} // set_last_click_sent
	} // StationSession
}
