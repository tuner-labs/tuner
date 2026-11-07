/**
 * SPDX-FileCopyrightText: Copyright © 2020-2024 Louis Brauer <louis@brauer.family>
 * SPDX-FileCopyrightText: Copyright © 2024 technosf <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file CategoryExpansion.vala
 *
 * @brief Remembers which collapsible source list sections are open.
 */

using Tuner.Widgets.Granite;

/**
 * @brief Keeps the open or closed state of the collapsible source list sections in the settings.
 *
 * The state is a bitmask with one bit for each section, in the order the sections are given:
 * the first section is bit 0, and so on. The saved state is applied when this is created, and every
 * change the user makes is saved.
 */
public class Tuner.Widgets.CategoryExpansion : Object
{
	private Settings _settings;
	private SourceList.ExpandableItem[] _categories;
	private bool _applying = false;     // Applying the saved state must not save it again


	/**
	 * @param settings Where the state is saved
	 * @param categories The collapsible sections, in the order of their bits in the saved mask
	 */
	public CategoryExpansion (Settings settings, SourceList.ExpandableItem[] categories)
	{
		Object ();
		_settings   = settings;
		_categories = categories;

		foreach (var category in _categories)
		{
			category.collapsible = true;
			category.expanded    = false;
		}
		apply (_settings.category_expanded_mask);

		foreach (var category in _categories)
			category.notify["expanded"].connect (() => { save (); });
	} // CategoryExpansion


	private void apply (uint mask)
	{
		_applying = true;
		for (int i = 0; i < _categories.length; i++)
			_categories[i].expanded = (mask & (1u << i)) != 0;
		_applying = false;
	} // apply


	private void save ()
	{
		if (_applying)
			return;

		uint mask = 0;
		for (int i = 0; i < _categories.length; i++)
		{
			if (_categories[i].expanded)
				mask |= 1u << i;
		}
		_settings.persist_category_expanded_mask (mask);
	} // save
} // CategoryExpansion
