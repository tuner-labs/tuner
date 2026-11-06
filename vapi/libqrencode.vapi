/**
 * SPDX-FileCopyrightText: Copyright © 2026 <https://github.com/technosf>
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * @file libqrencode.vapi
 *
 * @brief Minimal Vala binding for the part of libqrencode that Tuner uses.
 *
 * libqrencode ships no Vala binding; this covers QRcode_encodeString() and the QRcode result only.
 * Named after the pkg-config package so that meson's dependency('libqrencode') finds it through --vapidir.
 */

[CCode (cheader_filename = "qrencode.h")]
namespace Qr
{
	/** Error correction level: how much of the code can be damaged and still scan. */
	[CCode (cname = "QRecLevel", cprefix = "QR_ECLEVEL_", has_type_id = false)]
	public enum EcLevel
	{
		L,	// about 7 % recoverable
		M,	// about 15 %
		Q,	// about 25 %
		H	// about 30 %
	}

	/** Encoding mode, also used as a hint to the encoder. */
	[CCode (cname = "QRencodeMode", cprefix = "QR_MODE_", has_type_id = false)]
	public enum Mode
	{
		NUL = -1,
		NUM,
		AN,
		[CCode (cname = "QR_MODE_8")]
		BYTE,
		KANJI,
		STRUCTURE,
		ECI,
		FNC1FIRST,
		FNC1SECOND
	}

	/** An encoded QR symbol: a `width` x `width` grid of modules, one byte per module (bit 0 set = dark). */
	[Compact, CCode (cname = "QRcode", free_function = "QRcode_free", has_type_id = false)]
	public class Code
	{
		public int version;
		public int width;
		public uint8* data;

		/**
		 * @param str Text to encode (UTF-8 bytes).
		 * @param version QR version 1-40, or 0 to choose the smallest that fits.
		 * @param level Error correction level.
		 * @param hint Encoding mode; BYTE for arbitrary text.
		 * @param casesensitive 1 to keep the case of the text (needed for URIs).
		 * @return The symbol, or null if the text is too long.
		 */
		[CCode (cname = "QRcode_encodeString")]
		public static Code? encode_string (string str, int version, EcLevel level, Mode hint, int casesensitive);
	}
}
