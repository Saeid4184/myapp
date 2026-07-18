package ir.factory.entryexit.util

private val PERSIAN_DIGITS = charArrayOf('۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹')

/** Converts a non-negative integer to a zero-padded Persian-numeral string, e.g. 3 -> "۰۳". */
fun Int.toPersianDigits(minWidth: Int = 2): String {
    val raw = this.toString().padStart(minWidth, '0')
    val sb = StringBuilder(raw.length)
    for (c in raw) {
        sb.append(if (c.isDigit()) PERSIAN_DIGITS[c - '0'] else c)
    }
    return sb.toString()
}

/** Converts any western digits inside a string to Persian-Indic digits (for display only). */
fun String.toPersianDigitsInString(): String {
    val sb = StringBuilder(this.length)
    for (c in this) {
        sb.append(if (c.isDigit()) PERSIAN_DIGITS[c - '0'] else c)
    }
    return sb.toString()
}
