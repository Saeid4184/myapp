package ir.factory.entryexit.data

/** Departments used to sub-categorize personnel. */
enum class Department(val displayName: String) {
    MANAGEMENT("مدیریت"),
    SALES("فروش"),
    FINANCE_ADMIN("مالی و اداری"),
    SECURITY("حراست"),
    BATCHING("باچینگ"),
    TRANSPORT("حمل و نقل"),
    MACHINERY_DEPT("ماشین‌آلات");

    companion object {
        fun fromDisplayNameOrNull(name: String): Department? = values().firstOrNull { it.displayName == name }
    }
}
