/*
 * Copyright (c) 2000-2002,2010,2013 by Solar Designer.  See LICENSE.
 * Copyright (c) 2014 Parallels, Inc.
 */
({define:typeof define!="undefined"?define:function(deps, factory){module.exports = factory(exports, require("./dictionary"));}}).
define(["exports", "./dictionary"], function(exports, dict){
	var dictionary = dict.dictionary;

	var FIXED_BITS = 15;

	/*
	 * Calculates the expected number of different characters for a random
	 * password of a given length.  The result is rounded down.  We use this
	 * with the _requested_ minimum length (so longer passwords don't have
	 * to meet this strict requirement for their length).
	 */
	function expected_different(charset, length){
		var x, y, z;

		x = ((charset - 1) << FIXED_BITS) / charset;
		y = x;
		while (--length > 0)
			y = (y * x) >> FIXED_BITS;
		z = charset * ((1 << FIXED_BITS) - y);

		return (z >> FIXED_BITS)|0;
	}

	/*
	 * A password is too simple if it is too short for its class, or doesn't
	 * contain enough different characters for its class, or doesn't contain
	 * enough words for a passphrase.
	 *
	 * The biases are added to the length, and they may be positive or negative.
	 * The passphrase length check uses passphrase_bias instead of bias so that
	 * zero may be passed for this parameter when the (other) bias is non-zero
	 * because of a dictionary word, which is perfectly normal for a passphrase.
	 * The biases do not affect the number of different characters, character
	 * classes, and word count.
	 */
	function is_simple(params, newpass,	bias, passphrase_bias){
		var length, classes, words, chars,
			digits, lowers, uppers, others, unknowns,
			c, p;

		length = classes = words = chars = 0;
		digits = lowers = uppers = others = unknowns = 0;
		p = ' ';
		while (c = newpass[length]) {
			length++;

			if (!isascii(c))
				unknowns++;
			else if (isdigit(c))
				digits++;
			else if (islower(c))
				lowers++;
			else if (isupper(c))
				uppers++;
			else
				others++;
	/* A word starts when a letter follows a non-letter or when a non-ASCII
	 * character follows a space character.  We treat all non-ASCII characters
	 * as non-spaces, which is not entirely correct (there's the non-breaking
	 * space character at 0xa0, 0x9a, or 0xff), but it should not hurt. */
			if (isascii(p)) {
				if (isascii(c)) {
					if (isalpha(c) && !isalpha(p))
						words++;
				} else if (isspace(p))
					words++;
			}
			p = c;

	/* Count this character just once: when we're not going to see it anymore */
			if(newpass.slice(length).indexOf(c) === -1)
				chars++;
		}

		length = strlen(newpass);

		if (!length)
			return 1;

	/* Upper case characters and digits used in common ways don't increase the
	 * strength of a password */
		c = newpass[0];
		if (uppers && isascii(c) && isupper(c))
			uppers--;
		c = newpass[length - 1];
		if (digits && isascii(c) && isdigit(c))
			digits--;

	/* Count the number of different character classes we've seen.  We assume
	 * that there are no non-ASCII characters for digits. */
		classes = 0;
		if (digits)
			classes++;
		if (lowers)
			classes++;
		if (uppers)
			classes++;
		if (others)
			classes++;
		if (unknowns && classes <= 1 && (!classes || digits || words >= 2))
			classes++;

		for (var min = params.min; classes > 0; classes--)
			switch (classes) {
				case 1:
					if (length + bias >= min[0] &&
						chars >= expected_different(10, min[0]) - 1)
						return 0;
					return 1;

				case 2:
					if (length + bias >= min[1] &&
						chars >= expected_different(36, min[1]) - 1)
						return 0;
					if (!params.passphrase_words ||
						words < params.passphrase_words)
						continue;
					if (length + passphrase_bias >= min[2] &&
						chars >= expected_different(27, min[2]) - 1)
						return 0;
					continue;

				case 3:
					if (length + bias >= min[3] &&
						chars >= expected_different(62, min[3]) - 1)
						return 0;
					continue;

				case 4:
					if (length + bias >= min[4] &&
						chars >= expected_different(95, min[4]) - 1)
						return 0;
					continue;
			}

		return 1;
	}

	function unify(dst, src){
		for (var i = 0; i < src.length; i++){
			var c = src.charAt(i);
			if (isascii(c) && isupper(c))
				c = c.toLowerCase();
			switch (c) {
			case 'a': case '@':
				c = '4'; break;
			case 'e':
				c = '3'; break;
	/* Unfortunately, if we translate both 'i' and 'l' to '1', this would
	 * associate these two letters with each other - e.g., "mile" would
	 * match "MLLE", which is undesired.  To solve this, we'd need to test
	 * different translations separately, which is not implemented yet. */
			case 'i': case '|':
				c = '!'; break;
			case 'l':
				c = '1'; break;
			case 'o':
				c = '0'; break;
			case 's': case '$':
				c = '5'; break;
			case 't': case '+':
				c = '7'; break;
			}
			dst += c;
		}

		return dst;
	}

	function reverse(src){
		return src.split("").reverse().join("");
	}

	/*
	 * Needle is based on haystack if both contain a long enough common
	 * substring and needle would be too simple for a password with the
	 * substring either removed with partial length credit for it added
	 * or partially discounted for the purpose of the length check.
	 */
	function is_based(params, haystack, needle, original, mode){
		var scratch, length, i, j, p, worst_bias;

		if (!params.match_length)	// disabled
			return 0;

		if (params.match_length < 0)	// misconfigured
			return 1;

		scratch = null;
		worst_bias = 0;

		length = needle.length;
		for (i = 0; i <= length - params.match_length; i++)
			for (j = params.match_length; i + j <= length; j++) {
				var bias = 0, j1 = j - 1;
				var q0 = needle[i], q1 = needle.slice(i+1);

				for (var k=0; k<haystack.length; k++)
					if (haystack[k] == q0 &&  haystack.substring(k+1, k+1+j1) == q1.substring(0,j1)) { // or memcmp()
						if ((mode & 0xff) == 0) { // remove & credit
							// remove j chars
							var pos = length - (i + j);
							if (!(mode & 0x100)) // not reversed
								pos = i;

							scratch = original.substring(0, pos) + original.substring(pos+j);

							// add credit for match_length - 1 chars
							bias = params.match_length - 1;
							if (is_simple(params, scratch, bias, bias))
								return 1;
						} else { // discount
	// Require a 1 character longer match for substrings containing leetspeak
	// when matching against dictionary words
							bias = -1;
							if ((mode & 0xff) == 1) { // words
								var pos = i, end = i + j;
								if (mode & 0x100) { // reversed
									pos = length - end;
									end = length - i;
								}
								for (; pos < end; pos++)
									if (!isalpha(original[pos])) {
										if (j == params.match_length){
											var cnt = true;
											break;
										}
										bias = 0;
										break;
									}
								if(cnt){
									cnt = false;
									continue;
								}
							}

							// discount j - (match_length + bias) chars
							bias += params.match_length - j;
							// bias <= -1
							if (bias < worst_bias) {
								if (is_simple(params, original, bias,
									(mode & 0xff) == 1 ? 0 : bias))
									return 1;
								worst_bias = bias;
							}
						}
					}

	 // Zero bias implies that there were no matches for this length.  If so,
	 // * there's no reason to try the next substring length (it would result in
	 // * no matches as well).  We break out of the substring length loop and
	 // * proceed with all substring lengths for the next position in needle.
				if (!bias)
					break;
			}

		return 0;
	}

	/*
	 * Common sequences of characters.
	 * We don't need to list any of the entire strings in reverse order because the
	 * code checks the new password in both "unified" and "unified and reversed"
	 * form against these strings (unifying them first indeed).  We also don't have
	 * to include common repeats of characters (e.g., "777", "!!!", "1000") because
	 * these are often taken care of by the requirement on the number of different
	 * characters.
	 */
	var seq = [
		"0123456789",
		"`1234567890-=",
		"~!@#$%^&*()_+",
		"abcdefghijklmnopqrstuvwxyz",
		"a1b2c3d4e5f6g7h8i9j0",
		"1a2b3c4d5e6f7g8h9i0j",
		"abc123",
		"qwertyuiop[]\\asdfghjkl;'zxcvbnm,./",
		"qwertyuiop{}|asdfghjkl:\"zxcvbnm<>?",
		"qwertyuiopasdfghjklzxcvbnm",
		"1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik,9ol.0p;/-['=]\\",
		"!qaz@wsx#edc$rfv%tgb^yhn&ujm*ik<(ol>)p:?_{\"+}|",
		"qazwsxedcrfvtgbyhnujmikolp",
		"1q2w3e4r5t6y7u8i9o0p-[=]",
		"q1w2e3r4t5y6u7i8o9p0[-]=\\",
		"1qaz1qaz",
		"1qaz!qaz", /* can't unify '1' and '!' - see comment in unify() */
		"1qazzaq1",
		"zaq!1qaz",
		"zaq!2wsx"
	];

	/*
	 * This wordlist check is now the least important given the checks above
	 * and the support for passphrases (which are based on dictionary words,
	 * and checked by other means).  It is still useful to trap simple short
	 * passwords (if short passwords are allowed) that are word-based, but
	 * passed the other checks due to uncommon capitalization, digits, and
	 * special characters.  We (mis)use the same set of words that are used
	 * to generate random passwords.  This list is much smaller than those
	 * used for password crackers, and it doesn't contain common passwords
	 * that aren't short English words.  Perhaps support for large wordlists
	 * should still be added, even though this is now of little importance.
	 */
	function is_word_based(params, needle, original, is_reversed){
		var word, unified, i, length, mode;

		if (!params.match_length)	/* disabled */
			return null;

		mode = is_reversed | 1;
		word = "";
		for (i = 0; i < 0x1000; i++) {
			word = dictionary[i];
			length = strlen(word);
			if (length < params.match_length)
				continue;

			word = unify("", word);
			if (is_based(params, word, needle, original, mode))
				return REASON_WORD;
		}

		mode = is_reversed | 2;
		for (i = 0; i < seq.length; i++) {
			unified = unify("", seq[i]);
			if (!unified)
				return REASON_ERROR;
			if (is_based(params, unified, needle, original, mode))
				return REASON_SEQ;
		}

		if (params.match_length <= 4)
			for (i = 1900; i <= 2039; i++) {
				if (is_based(params, i.toString(), needle, original, mode))
					return REASON_SEQ;
			}

		return null;
	}

	function passwdqc_check(params, newpass, oldpass, pw){
		var truncated, u_newpass, u_reversed, u_oldpass,
			u_name, u_gecos, u_dir, reason, length;

		u_newpass = u_reversed = null;
		u_oldpass = null;
		u_name = u_gecos = u_dir = null;

		reason = REASON_ERROR;

		if (oldpass && oldpass == newpass)
			return REASON_SAME;

		length = strlen(newpass);

		if (length < params.min[4])
			return REASON_SHORT;

		if (length > params.max) {
			if (params.max == 8) {
				truncated = newpass.substr(0, 8);
				newpass = truncated;
				if (oldpass && !oldpass.substr(0, 8) !== newpass.substr(0, 8))
					return REASON_SAME;
			} else {
				return REASON_LONG;
			}
		}

		if (is_simple(params, newpass, 0, 0)) {
			reason = REASON_SIMPLE;
			if (length < params.min[1] && params.min[1] <= params.max)
				reason = REASON_SIMPLESHORT;
			return reason;
		}

		if (!(u_newpass = unify("", newpass)))
			return reason; /* REASON_ERROR */
		if (!(u_reversed = reverse(u_newpass)))
			return reason;
		if (oldpass && !(u_oldpass = unify("", oldpass)))
			return reason;
		if (pw) {
			if (!(u_name = unify("", pw.pw_name)) ||
				!(u_gecos = unify("", pw.pw_gecos)) ||
				!(u_dir = unify("", pw.pw_dir)))
				return reason;
		}

		if (oldpass && params.similar_deny &&
			(is_based(params, u_oldpass, u_newpass, newpass, 0) ||
			 is_based(params, u_oldpass, u_reversed, newpass, 0x100)))
			return REASON_SIMILAR;

		if (pw &&
			(is_based(params, u_name, u_newpass, newpass, 0) ||
			 is_based(params, u_name, u_reversed, newpass, 0x100) ||
			 is_based(params, u_gecos, u_newpass, newpass, 0) ||
			 is_based(params, u_gecos, u_reversed, newpass, 0x100) ||
			 is_based(params, u_dir, u_newpass, newpass, 0) ||
			 is_based(params, u_dir, u_reversed, newpass, 0x100)))
			return REASON_PERSONAL;

		reason = is_word_based(params, u_newpass, newpass, 0);
		if (!reason)
			reason = is_word_based(params, u_reversed, newpass, 0x100);

		return reason;
	}

	function isascii(c){
		return /^[\x00-\x7F]?$/.test(c);
	}

	function isdigit(c){
		return /^\d?$/.test(c);
	}

	function islower(c){
		return isalpha(c) && c.toLowerCase() === c;
	}

	function isupper(c){
		return isalpha(c) && c.toUpperCase() === c;
	}

	function isalpha(c){
		return /^\w?$/.test(c) && c != '_' && /^\D?$/.test(c);
	}

	function isspace(c){
		return /^\s?$/.test(c);
	}

	function strlen(str){
		var length = str.length, count = 0, ch = 0;
		for(var i=0; i < length; i++){
			ch = str.charCodeAt(i);
			if(ch <= 127){
				count++;
			}else if(ch <= 2047){
				count += 2;
			}else if(ch <= 65535){
				count += 3;
			}else if(ch <= 2097151){
				count += 4;
			}else if(ch <= 67108863){
				count += 5;
			}else{
				count += 6;
			}
		}

		return count;
	}

	var REASON_ERROR		 = "check failed",
		REASON_SAME			 = "is the same as the old one",
		REASON_SIMILAR		 = "is based on the old one",
		REASON_SHORT 		 = "too short",
		REASON_LONG			 = "too long",
		REASON_SIMPLESHORT	 = "not enough different characters or classes for this length",
		REASON_SIMPLE 		 = "not enough different characters or classes",
		REASON_PERSONAL		 = "based on personal login information",
		REASON_WORD			 = "based on a dictionary word and not a passphrase",
		REASON_SEQ			 = "based on a common sequence of characters and not a passphrase",
		INT_MAX 			 = 2147483647;

	var params = {
		min: [INT_MAX, 24, 11, 8, 7],
		max: 40,
		passphrase_words: 3,
		match_length: 4,
		similar_deny: 1,
		random_bits: 47,
		flags: 3,
		retry: 3
	}

	function check(newpass, oldpass, login, gecos, pms){
		return passwdqc_check(pms || params, newpass, oldpass, login ? { pw_name: login, pw_gecos: gecos } : login);
	}

	exports.check = check;

	return exports;
});