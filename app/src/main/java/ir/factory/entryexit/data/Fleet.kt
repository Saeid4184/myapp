package ir.factory.entryexit.data

import ir.factory.entryexit.util.toPersianDigits

/**
 * The factory's fixed machinery roster. Used once, on first launch, to pre-populate the
 * `persons` table so the machinery tab opens already organized by model/brand.
 * Users can still register additional machinery manually afterwards.
 */
object Fleet {

    /** One production line of identical vehicles, e.g. "15 Amico mixers". */
    private data class FleetLine(
        val groupLabel: String,
        val namePrefix: String,
        val count: Int
    )

    // Group labels double as section headers in the Machinery tab, and are used to sort it.
    private val lines = listOf(
        FleetLine("میکسر - آمیکو", "میکسر آمیکو", 15),
        FleetLine("میکسر - ایوکو", "میکسر ایوکو", 15),
        FleetLine("پمپ بتن - بدسند", "پمپ بدسند", 7),
        FleetLine("کمپرسور تریلر - فاو", "کمپرسور فاو", 6),
        FleetLine("کمپرسور تریلر - اسکانیا F", "کمپرسور اسکانیا F", 1),
        FleetLine("کامیون ۱۰ چرخ - آمیکو", "کامیون ۱۰چرخ آمیکو", 6),
        FleetLine("وانت", "وانت نیسان (تدارکات)", 1),
        FleetLine("وانت", "وانت پژو (تعمیرگاه)", 1)
    )

    /** Builds the full list of [PersonEntity] rows to insert on first run. */
    fun buildInitialRoster(): List<PersonEntity> {
        val result = mutableListOf<PersonEntity>()
        for (line in lines) {
            if (line.count == 1) {
                // Single, uniquely-named unit (pickups) -> no numeric suffix needed.
                result += PersonEntity(
                    name = line.namePrefix,
                    type = PersonType.MACHINERY.name,
                    group = line.groupLabel
                )
            } else {
                for (i in 1..line.count) {
                    result += PersonEntity(
                        name = "${line.namePrefix} ${i.toPersianDigits()}",
                        type = PersonType.MACHINERY.name,
                        group = line.groupLabel
                    )
                }
            }
        }
        return result
    }
}
