package ir.factory.entryexit.data

import androidx.lifecycle.LiveData

/**
 * Single place where the app's core rule lives: a person cannot be checked in again until
 * their previous check-in has been checked out. Also owns fleet seeding and quick search.
 */
class Repository(private val personDao: PersonDao, private val logDao: LogDao) {

    fun getPersonsByType(type: PersonType): LiveData<List<PersonEntity>> = personDao.getByType(type.name)

    fun getInsidePersonsByType(type: PersonType): LiveData<List<PersonEntity>> =
        personDao.getInsideByType(type.name)

    fun getRecentActivity(limit: Int = 20): LiveData<List<LogEntity>> = logDao.getRecent(limit)

    fun getRecentActivityByType(type: PersonType, limit: Int = 10): LiveData<List<LogEntity>> =
        logDao.getRecentByType(type.name, limit)

    fun search(query: String): LiveData<List<PersonEntity>> = personDao.searchAll(query)

    /** Inserts the fixed machinery fleet exactly once (safe to call on every app start). */
    suspend fun ensureFleetSeeded() {
        if (personDao.countByType(PersonType.MACHINERY.name) == 0) {
            personDao.insertAll(Fleet.buildInitialRoster())
        }
    }

    /** Registers a brand-new person/machine (name-only, or with a department/group). */
    suspend fun addPerson(name: String, type: PersonType, group: String? = null, extraInfo: String? = null): Result<Long> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) {
            return Result.failure(IllegalArgumentException("نام نمی‌تواند خالی باشد"))
        }
        if (personDao.countByNameAndType(type.name, trimmed) > 0) {
            return Result.failure(IllegalStateException("این نام قبلاً ثبت شده است"))
        }
        val id = personDao.insert(
            PersonEntity(
                name = trimmed,
                type = type.name,
                group = group?.trim()?.ifEmpty { null },
                extraInfo = extraInfo?.trim()?.ifEmpty { null }
            )
        )
        return Result.success(id)
    }

    suspend fun updatePersonImage(personId: Long, imageUri: String?): Result<Unit> {
        val fresh = personDao.getById(personId) ?: return Result.failure(IllegalStateException("فرد یافت نشد"))
        personDao.update(fresh.copy(imageUri = imageUri))
        return Result.success(Unit)
    }

    /** Edits an existing person/machine's name, department/group, and extra info. */
    suspend fun updatePerson(personId: Long, name: String, group: String?, extraInfo: String?): Result<Unit> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return Result.failure(IllegalArgumentException("نام نمی‌تواند خالی باشد"))
        val fresh = personDao.getById(personId) ?: return Result.failure(IllegalStateException("مورد یافت نشد"))

        if (!trimmed.equals(fresh.name, ignoreCase = false)) {
            val duplicateCount = personDao.countByNameAndType(fresh.type, trimmed)
            if (duplicateCount > 0) {
                return Result.failure(IllegalStateException("این نام قبلاً برای مورد دیگری ثبت شده است"))
            }
        }

        personDao.update(
            fresh.copy(
                name = trimmed,
                group = group?.trim()?.ifEmpty { null },
                extraInfo = extraInfo?.trim()?.ifEmpty { null }
            )
        )
        return Result.success(Unit)
    }

    suspend fun getRosterOnce(type: PersonType): List<PersonEntity> = personDao.getByTypeOnce(type.name)

    /**
     * Check a person **in**. Fails if they are already marked as inside — this is what
     * prevents duplicate/erroneous consecutive check-ins.
     */
    suspend fun checkIn(personId: Long, detail: String? = null): Result<PersonEntity> {
        val fresh = personDao.getById(personId) ?: return Result.failure(IllegalStateException("فرد یافت نشد"))

        if (fresh.isInside) {
            return Result.failure(IllegalStateException("${fresh.name} قبلاً ورود ثبت کرده و هنوز خروج نزده است"))
        }

        val now = System.currentTimeMillis()
        val updated = fresh.copy(isInside = true, lastEventAt = now)
        personDao.update(updated)
        logDao.insert(
            LogEntity(
                personId = fresh.id,
                personName = fresh.name,
                type = fresh.type,
                group = fresh.group,
                action = ACTION_IN,
                timestamp = now,
                detail = detail?.trim()?.ifEmpty { null }
            )
        )
        return Result.success(updated)
    }

    /**
     * Check a person **out**. Fails if they are not currently inside. On success the person
     * is removed from the "currently inside" list.
     */
    suspend fun checkOut(personId: Long): Result<PersonEntity> {
        val fresh = personDao.getById(personId) ?: return Result.failure(IllegalStateException("فرد یافت نشد"))

        if (!fresh.isInside) {
            return Result.failure(IllegalStateException("${fresh.name} ورودی ثبت‌شده‌ای ندارد"))
        }

        val now = System.currentTimeMillis()
        val updated = fresh.copy(isInside = false, lastEventAt = now)
        personDao.update(updated)
        logDao.insert(
            LogEntity(
                personId = fresh.id,
                personName = fresh.name,
                type = fresh.type,
                group = fresh.group,
                action = ACTION_OUT,
                timestamp = now
            )
        )
        return Result.success(updated)
    }

    /**
     * One-step flow for a guest: register the visitor by name and immediately check them in
     * against the department they are visiting. Every visit creates a fresh record, since
     * guests are transient and may visit different departments on different days.
     */
    suspend fun checkInVisitor(name: String, department: String): Result<Unit> {
        val trimmedName = name.trim()
        val trimmedDept = department.trim()
        if (trimmedName.isEmpty()) return Result.failure(IllegalArgumentException("نام مهمان نمی‌تواند خالی باشد"))
        if (trimmedDept.isEmpty()) return Result.failure(IllegalArgumentException("وارد کردن واحد مورد مراجعه الزامی است"))

        val id = personDao.insert(PersonEntity(name = trimmedName, type = PersonType.VISITOR.name))
        return checkIn(id, trimmedDept).map { }
    }

    /**
     * One-step flow for a driver: register by name and immediately check them in against the
     * vehicle they are assigned to for this trip.
     */
    suspend fun checkInDriver(name: String, vehicle: String): Result<Unit> {
        val trimmedName = name.trim()
        val trimmedVehicle = vehicle.trim()
        if (trimmedName.isEmpty()) return Result.failure(IllegalArgumentException("نام راننده نمی‌تواند خالی باشد"))
        if (trimmedVehicle.isEmpty()) return Result.failure(IllegalArgumentException("وارد کردن ماشین مربوطه الزامی است"))

        val id = personDao.insert(PersonEntity(name = trimmedName, type = PersonType.DRIVER.name))
        return checkIn(id, trimmedVehicle).map { }
    }

    suspend fun getLogsInRange(startInclusive: Long, endInclusive: Long): List<LogEntity> =
        logDao.getLogsInRange(startInclusive, endInclusive)

    /** Real-time count (not range-bound) — used for the "currently inside right now" summary metric. */
    suspend fun countCurrentlyInside(type: PersonType): Int = personDao.countInsideByType(type.name)

    companion object {
        const val ACTION_IN = "IN"
        const val ACTION_OUT = "OUT"
    }
}

