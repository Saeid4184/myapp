#!/bin/bash
set -e

# Safety check: refuse to run unless we're in the actual project root
# (prevents accidentally creating a stray "app/" folder somewhere else).
if [ ! -f "settings.gradle" ]; then
    echo "ERROR: settings.gradle not found in the current directory."
    echo "cd into your ConcreteFactoryApp project folder first, then run this script again."
    exit 1
fi

mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="28" />

    <uses-permission android:name="android.permission.VIBRATE" />

    <application
        android:name=".FactoryApp"
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.ConcreteFactory">

        <activity
            android:name=".ui.MainActivity"
            android:exported="true"
            android:label="@string/app_name">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <activity
            android:name=".ui.GlobalSearchActivity"
            android:exported="false"
            android:label="@string/global_search_title"
            android:parentActivityName=".ui.MainActivity" />

        <activity
            android:name=".ui.SetupActivity"
            android:exported="false"
            android:label="@string/setup_title"
            android:parentActivityName=".ui.MainActivity" />

        <activity
            android:name=".ui.ReportActivity"
            android:exported="false"
            android:label="@string/report_title"
            android:parentActivityName=".ui.MainActivity" />

        <activity
            android:name=".ui.SettingsActivity"
            android:exported="false"
            android:label="@string/settings_title"
            android:parentActivityName=".ui.MainActivity" />

        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>

    </application>

</manifest>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit"
cat > "app/src/main/java/ir/factory/entryexit/FactoryApp.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit

import android.app.Application
import ir.factory.entryexit.util.AppPreferences

class FactoryApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppPreferences.applyThemeMode(AppPreferences.getThemeMode(this))
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/data"
cat > "app/src/main/java/ir/factory/entryexit/data/PersonDao.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.data

import androidx.lifecycle.LiveData
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Update

@Dao
interface PersonDao {

    @Insert
    suspend fun insert(person: PersonEntity): Long

    @Insert
    suspend fun insertAll(persons: List<PersonEntity>)

    @Update
    suspend fun update(person: PersonEntity)

    /** Full roster for a category, sorted so section headers (by group) come out in order. */
    @Query("SELECT * FROM persons WHERE type = :type ORDER BY group_name ASC, name ASC")
    fun getByType(type: String): LiveData<List<PersonEntity>>

    /** Currently-inside roster, most recently checked-in first. */
    @Query("SELECT * FROM persons WHERE type = :type AND isInside = 1 ORDER BY lastEventAt DESC")
    fun getInsideByType(type: String): LiveData<List<PersonEntity>>

    @Query("SELECT * FROM persons WHERE id = :id LIMIT 1")
    suspend fun getById(id: Long): PersonEntity?

    @Query("SELECT COUNT(*) FROM persons WHERE type = :type AND name = :name")
    suspend fun countByNameAndType(type: String, name: String): Int

    @Query("SELECT COUNT(*) FROM persons WHERE type = :type")
    suspend fun countByType(type: String): Int

    @Query("SELECT COUNT(*) FROM persons WHERE type = :type AND isInside = 1")
    suspend fun countInsideByType(type: String): Int

    /** Quick search across every category (used by the global search screen). */
    @Query(
        "SELECT * FROM persons WHERE name LIKE '%' || :query || '%' " +
            "OR group_name LIKE '%' || :query || '%' ORDER BY type ASC, name ASC"
    )
    fun searchAll(query: String): LiveData<List<PersonEntity>>

    /** All personnel/machinery for setup screens (photo assignment), sorted by group. */
    @Query("SELECT * FROM persons WHERE type = :type ORDER BY group_name ASC, name ASC")
    suspend fun getByTypeOnce(type: String): List<PersonEntity>
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/data"
cat > "app/src/main/java/ir/factory/entryexit/data/Repository.kt" << 'CLAUDE_EOF_MARKER'
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

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/viewmodel"
cat > "app/src/main/java/ir/factory/entryexit/viewmodel/FactoryViewModel.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.switchMap
import androidx.lifecycle.viewModelScope
import ir.factory.entryexit.data.AppDatabase
import ir.factory.entryexit.data.LogEntity
import ir.factory.entryexit.data.PersonEntity
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.data.Repository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Single ViewModel shared by MainActivity and all four tab fragments
 * (via `by activityViewModels()`), so every screen sees the same live data.
 */
class FactoryViewModel(app: Application) : AndroidViewModel(app) {

    val repository: Repository = run {
        val db = AppDatabase.getInstance(app)
        Repository(db.personDao(), db.logDao())
    }

    init {
        viewModelScope.launch { repository.ensureFleetSeeded() }
    }

    fun personsByType(type: PersonType): LiveData<List<PersonEntity>> = repository.getPersonsByType(type)

    fun insideByType(type: PersonType): LiveData<List<PersonEntity>> = repository.getInsidePersonsByType(type)

    fun recentActivity(type: PersonType): LiveData<List<LogEntity>> = repository.getRecentActivityByType(type)

    private val searchQuery = MutableLiveData("")
    val searchResults: LiveData<List<PersonEntity>> = searchQuery.switchMap { query ->
        if (query.isBlank()) {
            MutableLiveData<List<PersonEntity>>(emptyList())
        } else {
            repository.search(query)
        }
    }

    fun setSearchQuery(query: String) {
        searchQuery.value = query
    }

    fun search(query: String): LiveData<List<PersonEntity>> = repository.search(query)

    fun addPerson(
        name: String,
        type: PersonType,
        group: String?,
        extraInfo: String?,
        onResult: (Result<Long>) -> Unit
    ) {
        viewModelScope.launch { onResult(repository.addPerson(name, type, group, extraInfo)) }
    }

    fun checkIn(personId: Long, detail: String? = null, onResult: (Result<PersonEntity>) -> Unit) {
        viewModelScope.launch {
            val result = repository.checkIn(personId, detail)
            if (result.isSuccess) triggerBackup()
            onResult(result)
        }
    }

    fun checkOut(personId: Long, onResult: (Result<PersonEntity>) -> Unit) {
        viewModelScope.launch {
            val result = repository.checkOut(personId)
            if (result.isSuccess) triggerBackup()
            onResult(result)
        }
    }

    fun checkInVisitor(name: String, department: String, onResult: (Result<Unit>) -> Unit) {
        viewModelScope.launch {
            val result = repository.checkInVisitor(name, department)
            if (result.isSuccess) triggerBackup()
            onResult(result)
        }
    }

    fun checkInDriver(name: String, vehicle: String, onResult: (Result<Unit>) -> Unit) {
        viewModelScope.launch {
            val result = repository.checkInDriver(name, vehicle)
            if (result.isSuccess) triggerBackup()
            onResult(result)
        }
    }

    private suspend fun triggerBackup() {
        withContext(Dispatchers.IO) {
            ir.factory.entryexit.util.BackupManager.backupNow(getApplication())
        }
    }

    fun updatePersonImage(personId: Long, imageUri: String?, onResult: (Result<Unit>) -> Unit) {
        viewModelScope.launch { onResult(repository.updatePersonImage(personId, imageUri)) }
    }

    fun updatePerson(personId: Long, name: String, group: String?, extraInfo: String?, onResult: (Result<Unit>) -> Unit) {
        viewModelScope.launch { onResult(repository.updatePerson(personId, name, group, extraInfo)) }
    }

    fun loadRosterOnce(type: PersonType, onResult: (List<PersonEntity>) -> Unit) {
        viewModelScope.launch {
            val roster = withContext(Dispatchers.IO) { repository.getRosterOnce(type) }
            onResult(roster)
        }
    }

    fun exportRange(startInclusive: Long, endInclusive: Long, onResult: (List<LogEntity>) -> Unit) {
        viewModelScope.launch {
            val logs = withContext(Dispatchers.IO) { repository.getLogsInRange(startInclusive, endInclusive) }
            onResult(logs)
        }
    }

    fun currentlyInsideCounts(onResult: (Map<PersonType, Int>) -> Unit) {
        viewModelScope.launch {
            val counts = withContext(Dispatchers.IO) {
                PersonType.values().associateWith { repository.countCurrentlyInside(it) }
            }
            onResult(counts)
        }
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/util"
cat > "app/src/main/java/ir/factory/entryexit/util/AppPreferences.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.util

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate

/**
 * Lightweight wrapper around SharedPreferences for the app's display/interaction settings.
 * Read directly (no LiveData) since these are checked at the moment of an action/bind, not
 * observed continuously.
 */
object AppPreferences {

    private const val PREFS_NAME = "app_settings"

    private const val KEY_HAPTIC_ENABLED = "haptic_enabled"
    private const val KEY_SHOW_RECENT_ACTIVITY = "show_recent_activity"
    private const val KEY_QUICK_TAP_MODE = "quick_tap_mode"
    private const val KEY_INSIDE_FIRST_SORT = "inside_first_sort"
    private const val KEY_THEME_MODE = "theme_mode"

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // --- Haptic feedback on successful check-in/out ---
    fun isHapticEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_HAPTIC_ENABLED, true)
    fun setHapticEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_HAPTIC_ENABLED, enabled).apply()
    }

    // --- Recent-activity ticker under the status badge ---
    fun isRecentActivityVisible(context: Context): Boolean = prefs(context).getBoolean(KEY_SHOW_RECENT_ACTIVITY, true)
    fun setRecentActivityVisible(context: Context, visible: Boolean) {
        prefs(context).edit().putBoolean(KEY_SHOW_RECENT_ACTIVITY, visible).apply()
    }

    // --- Click behavior: tapping an outside person/machine directly checks them in
    //     instead of opening the ورود/خروج chooser first. Checkout always keeps its
    //     confirmation dialog regardless of this setting, to avoid accidental exits. ---
    fun isQuickTapEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_QUICK_TAP_MODE, false)
    fun setQuickTapEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_QUICK_TAP_MODE, enabled).apply()
    }

    // --- Sort order within each group section: currently-inside items shown first ---
    fun isInsideFirstSort(context: Context): Boolean = prefs(context).getBoolean(KEY_INSIDE_FIRST_SORT, false)
    fun setInsideFirstSort(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_INSIDE_FIRST_SORT, enabled).apply()
    }

    // --- Theme: SYSTEM (default), LIGHT, DARK ---
    enum class ThemeMode { SYSTEM, LIGHT, DARK }

    fun getThemeMode(context: Context): ThemeMode {
        val raw = prefs(context).getString(KEY_THEME_MODE, ThemeMode.SYSTEM.name)
        return runCatching { ThemeMode.valueOf(raw ?: ThemeMode.SYSTEM.name) }.getOrDefault(ThemeMode.SYSTEM)
    }

    fun setThemeMode(context: Context, mode: ThemeMode) {
        prefs(context).edit().putString(KEY_THEME_MODE, mode.name).apply()
        applyThemeMode(mode)
    }

    fun applyThemeMode(mode: ThemeMode) {
        val nightMode = when (mode) {
            ThemeMode.SYSTEM -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            ThemeMode.LIGHT -> AppCompatDelegate.MODE_NIGHT_NO
            ThemeMode.DARK -> AppCompatDelegate.MODE_NIGHT_YES
        }
        AppCompatDelegate.setDefaultNightMode(nightMode)
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/util"
cat > "app/src/main/java/ir/factory/entryexit/util/XlsxWriter.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.util

import java.io.File
import java.io.OutputStreamWriter
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Writes a minimal but fully valid .xlsx (Office Open XML spreadsheet) file, without pulling in
 * a heavy dependency like Apache POI (which has known compatibility problems on Android).
 *
 * Cells are written as inline strings (`t="inlineStr"`), which keeps the implementation simple
 * (no shared-strings table bookkeeping) while still opening correctly in Excel, Google Sheets,
 * and LibreOffice. Every sheet is marked right-to-left so Persian columns read naturally.
 *
 * Supports multiple sheets in one workbook (e.g. a raw "detail" sheet for pivot-table analysis
 * plus a human-readable "summary" sheet), so the exported file works both for accounting
 * (readable rows) and analysis (structured, one-row-per-event data).
 */
object XlsxWriter {

    data class Sheet(val name: String, val headers: List<String>, val rows: List<List<String>>)

    /** Single-sheet convenience overload (kept for simple exports). */
    fun write(destination: File, sheetName: String, headers: List<String>, rows: List<List<String>>) {
        write(destination, listOf(Sheet(sheetName, headers, rows)))
    }

    /** Multi-sheet export: each [Sheet] becomes its own tab in the workbook, in order. */
    fun write(destination: File, sheets: List<Sheet>) {
        require(sheets.isNotEmpty()) { "At least one sheet is required" }
        destination.parentFile?.mkdirs()
        ZipOutputStream(destination.outputStream()).use { zip ->
            writeEntry(zip, "[Content_Types].xml", contentTypesXml(sheets.size))
            writeEntry(zip, "_rels/.rels", rootRelsXml())
            writeEntry(zip, "xl/workbook.xml", workbookXml(sheets))
            writeEntry(zip, "xl/_rels/workbook.xml.rels", workbookRelsXml(sheets.size))
            writeEntry(zip, "xl/styles.xml", stylesXml())
            sheets.forEachIndexed { index, sheet ->
                writeEntry(zip, "xl/worksheets/sheet${index + 1}.xml", sheetXml(sheet.headers, sheet.rows))
            }
        }
    }

    private fun writeEntry(zip: ZipOutputStream, name: String, content: String) {
        zip.putNextEntry(ZipEntry(name))
        val writer = OutputStreamWriter(zip, Charsets.UTF_8)
        writer.write(content)
        writer.flush()
        zip.closeEntry()
    }

    private fun escapeXml(text: String): String = text
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")

    private fun contentTypesXml(sheetCount: Int): String {
        val overrides = (1..sheetCount).joinToString("\n  ") { i ->
            """<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"""
        }
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  $overrides
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>"""
    }

    private fun rootRelsXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"""

    private fun workbookXml(sheets: List<Sheet>): String {
        val entries = sheets.mapIndexed { index, sheet ->
            val sheetNum = index + 1
            """<sheet name="${escapeXml(sheet.name)}" sheetId="$sheetNum" r:id="rId$sheetNum"/>"""
        }.joinToString("\n    ")
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    $entries
  </sheets>
</workbook>"""
    }

    private fun workbookRelsXml(sheetCount: Int): String {
        val sheetRels = (1..sheetCount).joinToString("\n  ") { i ->
            """<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>"""
        }
        val stylesRelId = sheetCount + 1
        return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  $sheetRels
  <Relationship Id="rId$stylesRelId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""
    }

    private fun stylesXml() = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><sz val="11"/><name val="Calibri"/><b/></font>
  </fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
</styleSheet>"""

    /** Converts a 0-based column index to a spreadsheet column letter: 0->A, 1->B, 26->AA, ... */
    private fun columnLetter(index: Int): String {
        var i = index
        val sb = StringBuilder()
        do {
            sb.insert(0, ('A' + (i % 26)))
            i = i / 26 - 1
        } while (i >= 0)
        return sb.toString()
    }

    private fun cellXml(colIndex: Int, rowIndex: Int, value: String, headerStyle: Boolean): String {
        val ref = "${columnLetter(colIndex)}$rowIndex"
        val style = if (headerStyle) " s=\"1\"" else ""
        return "<c r=\"$ref\" t=\"inlineStr\"$style><is><t xml:space=\"preserve\">${escapeXml(value)}</t></is></c>"
    }

    private fun sheetXml(headers: List<String>, rows: List<List<String>>): String {
        val sb = StringBuilder()
        sb.append("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>""")
        sb.append("\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">")

        // Right-to-left sheet view so Persian columns read in natural order.
        sb.append("<sheetViews><sheetView rightToLeft=\"1\" workbookViewId=\"0\"/></sheetViews>")

        // Reasonable default column widths.
        sb.append("<cols>")
        for (i in headers.indices) {
            sb.append("<col min=\"${i + 1}\" max=\"${i + 1}\" width=\"22\" customWidth=\"1\"/>")
        }
        sb.append("</cols>")

        sb.append("<sheetData>")

        // Header row (bold style).
        sb.append("<row r=\"1\">")
        for ((colIndex, header) in headers.withIndex()) {
            sb.append(cellXml(colIndex, 1, header, headerStyle = true))
        }
        sb.append("</row>")

        // One row per log entry — never compressed into a single cell.
        for ((rowOffset, row) in rows.withIndex()) {
            val rowIndex = rowOffset + 2
            sb.append("<row r=\"$rowIndex\">")
            for ((colIndex, value) in row.withIndex()) {
                sb.append(cellXml(colIndex, rowIndex, value, headerStyle = false))
            }
            sb.append("</row>")
        }

        sb.append("</sheetData>")
        sb.append("</worksheet>")
        return sb.toString()
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/ui"
cat > "app/src/main/java/ir/factory/entryexit/ui/GroupedPersonAdapter.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.ui

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import ir.factory.entryexit.R
import ir.factory.entryexit.data.PersonEntity
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.databinding.ItemRosterEntryBinding
import ir.factory.entryexit.databinding.ItemSectionHeaderBinding

/** A single row shown in the roster list: either a section header or a person/machine entry. */
sealed class RosterRow {
    data class Header(val title: String) : RosterRow()
    data class Item(val person: PersonEntity) : RosterRow()
}

/**
 * Displays a roster grouped into sections (by department or fleet group). Pass a flat,
 * already-sorted [List]<[PersonEntity]> to [submit]; the adapter inserts header rows itself
 * whenever the group changes. When [showGroups] is false (visitors/drivers), no headers are
 * inserted at all.
 */
class GroupedPersonAdapter(
    private val type: PersonType,
    private val showGroups: Boolean,
    private val onClick: (PersonEntity) -> Unit,
    private val onLongClick: (PersonEntity) -> Unit = {}
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private var rows: List<RosterRow> = emptyList()

    fun submit(persons: List<PersonEntity>) {
        rows = if (showGroups) buildGroupedRows(persons) else persons.map { RosterRow.Item(it) }
        notifyDataSetChanged()
    }

    private fun buildGroupedRows(persons: List<PersonEntity>): List<RosterRow> {
        val result = mutableListOf<RosterRow>()
        var currentGroup: String? = null
        for (p in persons) {
            val groupLabel = p.group ?: "سایر"
            if (groupLabel != currentGroup) {
                result += RosterRow.Header(groupLabel)
                currentGroup = groupLabel
            }
            result += RosterRow.Item(p)
        }
        return result
    }

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is RosterRow.Header -> VIEW_TYPE_HEADER
        is RosterRow.Item -> VIEW_TYPE_ITEM
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == VIEW_TYPE_HEADER) {
            val binding = ItemSectionHeaderBinding.inflate(LayoutInflater.from(parent.context), parent, false)
            HeaderViewHolder(binding)
        } else {
            val binding = ItemRosterEntryBinding.inflate(LayoutInflater.from(parent.context), parent, false)
            ItemViewHolder(binding)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is RosterRow.Header -> (holder as HeaderViewHolder).bind(row.title)
            is RosterRow.Item -> (holder as ItemViewHolder).bind(row.person)
        }
    }

    override fun getItemCount(): Int = rows.size

    inner class HeaderViewHolder(private val binding: ItemSectionHeaderBinding) :
        RecyclerView.ViewHolder(binding.root) {
        fun bind(title: String) {
            (binding.root as android.widget.TextView).text = title
        }
    }

    inner class ItemViewHolder(private val binding: ItemRosterEntryBinding) :
        RecyclerView.ViewHolder(binding.root) {

        fun bind(person: PersonEntity) {
            val context = binding.root.context
            binding.tvName.text = person.name

            val iconRes = when (type) {
                PersonType.PERSONNEL -> R.drawable.ic_personnel
                PersonType.MACHINERY -> R.drawable.ic_machinery
                PersonType.VISITOR -> R.drawable.ic_visitor
                PersonType.DRIVER -> R.drawable.ic_driver
            }

            if (person.imageUri != null) {
                binding.ivTypeIcon.visibility = View.GONE
                binding.ivPhoto.visibility = View.VISIBLE
                Glide.with(context)
                    .load(android.net.Uri.parse(person.imageUri))
                    .placeholder(iconRes)
                    .error(iconRes)
                    .circleCrop()
                    .into(binding.ivPhoto)
            } else {
                binding.ivPhoto.visibility = View.GONE
                binding.ivTypeIcon.visibility = View.VISIBLE
                binding.ivTypeIcon.setImageResource(iconRes)
            }

            val subtitleParts = mutableListOf<String>()
            person.extraInfo?.takeIf { it.isNotBlank() }?.let { subtitleParts += it }
            subtitleParts += context.getString(
                R.string.last_status_format,
                if (person.isInside) context.getString(R.string.status_inside)
                else context.getString(R.string.status_outside)
            )
            binding.tvSubtitle.text = subtitleParts.joinToString(" · ")

            if (person.isInside) {
                binding.tvStatusBadge.text = context.getString(R.string.status_inside)
                binding.tvStatusBadge.setBackgroundResource(R.drawable.bg_status_inside)
                binding.tvStatusBadge.setTextColor(context.getColor(R.color.status_green))
            } else {
                binding.tvStatusBadge.text = context.getString(R.string.status_outside)
                binding.tvStatusBadge.setBackgroundResource(R.drawable.bg_status_outside)
                binding.tvStatusBadge.setTextColor(context.getColor(R.color.concrete_500))
            }

            binding.root.setOnClickListener { onClick(person) }
            binding.root.setOnLongClickListener {
                onLongClick(person)
                true
            }
        }
    }

    companion object {
        private const val VIEW_TYPE_HEADER = 0
        private const val VIEW_TYPE_ITEM = 1
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/ui"
cat > "app/src/main/java/ir/factory/entryexit/ui/MainActivity.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.ui

import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.tabs.TabLayoutMediator
import ir.factory.entryexit.R
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var pagerAdapter: CategoryPagerAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setSupportActionBar(binding.toolbar)
        supportActionBar?.title = getString(R.string.app_name)
        binding.toolbar.logo = androidx.core.content.ContextCompat.getDrawable(this, R.drawable.app_logo)

        pagerAdapter = CategoryPagerAdapter(this)
        binding.viewPager.adapter = pagerAdapter

        val tabIcons = intArrayOf(
            R.drawable.ic_personnel,
            R.drawable.ic_machinery,
            R.drawable.ic_visitor,
            R.drawable.ic_driver
        )
        val tabTitles = arrayOf(
            getString(R.string.category_personnel),
            getString(R.string.category_machinery),
            getString(R.string.category_visitor),
            getString(R.string.category_driver)
        )

        TabLayoutMediator(binding.tabLayout, binding.viewPager) { tab, position ->
            tab.text = tabTitles[position]
            tab.setIcon(tabIcons[position])
        }.attach()

        // Jump directly to a tab, e.g. when returning from global search.
        intent?.getStringExtra(EXTRA_JUMP_TO_TYPE)?.let { typeName ->
            val type = runCatching { PersonType.valueOf(typeName) }.getOrNull()
            type?.let { binding.viewPager.setCurrentItem(pagerAdapter.positionOf(it), false) }
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_search -> {
                startActivity(Intent(this, GlobalSearchActivity::class.java))
                true
            }
            R.id.action_report -> {
                startActivity(Intent(this, ReportActivity::class.java))
                true
            }
            R.id.action_setup -> {
                startActivity(Intent(this, SetupActivity::class.java))
                true
            }
            R.id.action_settings -> {
                startActivity(Intent(this, SettingsActivity::class.java))
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    companion object {
        const val EXTRA_JUMP_TO_TYPE = "extra_jump_to_type"
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/ui"
cat > "app/src/main/java/ir/factory/entryexit/ui/SettingsActivity.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.ui

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import ir.factory.entryexit.R
import ir.factory.entryexit.databinding.ActivitySettingsBinding
import ir.factory.entryexit.util.AppPreferences

/** Display/interaction/theme customization, requested separately from the one-time
 *  "تنظیمات اولیه" (photo assignment) setup screen. */
class SettingsActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.toolbar.title = getString(R.string.settings_title)
        binding.toolbar.setNavigationOnClickListener { finish() }

        // Load current values without triggering the listeners below.
        binding.switchRecentActivity.isChecked = AppPreferences.isRecentActivityVisible(this)
        binding.switchInsideFirst.isChecked = AppPreferences.isInsideFirstSort(this)
        binding.switchHaptic.isChecked = AppPreferences.isHapticEnabled(this)
        binding.switchQuickTap.isChecked = AppPreferences.isQuickTapEnabled(this)

        when (AppPreferences.getThemeMode(this)) {
            AppPreferences.ThemeMode.SYSTEM -> binding.radioThemeSystem.isChecked = true
            AppPreferences.ThemeMode.LIGHT -> binding.radioThemeLight.isChecked = true
            AppPreferences.ThemeMode.DARK -> binding.radioThemeDark.isChecked = true
        }

        binding.switchRecentActivity.setOnCheckedChangeListener { _, checked ->
            AppPreferences.setRecentActivityVisible(this, checked)
        }
        binding.switchInsideFirst.setOnCheckedChangeListener { _, checked ->
            AppPreferences.setInsideFirstSort(this, checked)
        }
        binding.switchHaptic.setOnCheckedChangeListener { _, checked ->
            AppPreferences.setHapticEnabled(this, checked)
        }
        binding.switchQuickTap.setOnCheckedChangeListener { _, checked ->
            AppPreferences.setQuickTapEnabled(this, checked)
        }

        binding.radioGroupTheme.setOnCheckedChangeListener { _, checkedId ->
            val mode = when (checkedId) {
                R.id.radioThemeLight -> AppPreferences.ThemeMode.LIGHT
                R.id.radioThemeDark -> AppPreferences.ThemeMode.DARK
                else -> AppPreferences.ThemeMode.SYSTEM
            }
            AppPreferences.setThemeMode(this, mode)
        }
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/ui"
cat > "app/src/main/java/ir/factory/entryexit/ui/ReportActivity.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.ui

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import com.google.android.material.datepicker.MaterialDatePicker
import ir.factory.entryexit.R
import ir.factory.entryexit.data.LogEntity
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.databinding.ActivityReportBinding
import ir.factory.entryexit.util.XlsxWriter
import ir.factory.entryexit.viewmodel.FactoryViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Date-range filtered report screen with a one-tap Excel export, ready for accounting. */
class ReportActivity : AppCompatActivity() {

    private lateinit var binding: ActivityReportBinding
    private lateinit var viewModel: FactoryViewModel

    // Default range = today, in the device's local timezone.
    private var rangeStart: Long = startOfToday()
    private var rangeEnd: Long = endOfToday()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityReportBinding.inflate(layoutInflater)
        setContentView(binding.root)

        viewModel = ViewModelProvider(this)[FactoryViewModel::class.java]

        binding.toolbar.title = getString(R.string.report_title)
        binding.toolbar.setNavigationOnClickListener { finish() }

        updateDateRangeLabel()
        refreshRowCount()

        binding.btnDateRange.setOnClickListener { showDateRangePicker() }
        binding.btnExport.setOnClickListener { exportToExcel() }
    }

    private fun showDateRangePicker() {
        val picker = MaterialDatePicker.Builder.dateRangePicker()
            .setTitleText(getString(R.string.report_title))
            .setSelection(androidx.core.util.Pair(rangeStart, rangeEnd))
            .build()

        picker.addOnPositiveButtonClickListener { selection ->
            rangeStart = startOfDay(selection.first ?: rangeStart)
            rangeEnd = endOfDay(selection.second ?: rangeEnd)
            updateDateRangeLabel()
            refreshRowCount()
        }
        picker.show(supportFragmentManager, "date_range_picker")
    }

    private fun updateDateRangeLabel() {
        val fmt = SimpleDateFormat("yyyy/MM/dd", Locale.US)
        binding.btnDateRange.text = "${getString(R.string.report_from_date)}: ${fmt.format(Date(rangeStart))}   |   " +
            "${getString(R.string.report_to_date)}: ${fmt.format(Date(rangeEnd))}"
    }

    private fun refreshRowCount() {
        viewModel.exportRange(rangeStart, rangeEnd) { logs ->
            binding.tvRowCount.text = getString(R.string.report_row_count_format, logs.size)
        }
    }

    private fun exportToExcel() {
        viewModel.exportRange(rangeStart, rangeEnd) { logs ->
            if (logs.isEmpty()) {
                Toast.makeText(this, R.string.report_export_empty, Toast.LENGTH_SHORT).show()
                return@exportRange
            }
            launchExport(logs)
        }
    }

    private fun launchExport(logs: List<LogEntity>) {
        lifecycleScope.launch {
            val insideCounts = withContext(Dispatchers.IO) { awaitInsideCounts() }
            val file = withContext(Dispatchers.IO) { buildXlsxFile(logs, insideCounts) }
            withContext(Dispatchers.IO) { saveToDownloads(file) }
            Toast.makeText(this@ReportActivity, R.string.report_export_success, Toast.LENGTH_LONG).show()
            shareFile(file)
        }
    }

    /** Bridges the ViewModel's callback-based currentlyInsideCounts() into a suspend call. */
    private suspend fun awaitInsideCounts(): Map<PersonType, Int> =
        kotlinx.coroutines.suspendCancellableCoroutine { cont ->
            viewModel.currentlyInsideCounts { counts -> cont.resumeWith(Result.success(counts)) }
        }

    private fun buildXlsxFile(logs: List<LogEntity>, insideCounts: Map<PersonType, Int>): File {
        val fmt = SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US)

        val detailHeaders = listOf(
            getString(R.string.col_name),
            getString(R.string.col_category),
            getString(R.string.col_department),
            getString(R.string.col_action),
            getString(R.string.col_timestamp)
        )
        val detailRows = logs.map { log ->
            val categoryLabel = runCatching { PersonType.valueOf(log.type).displayName }.getOrDefault(log.type)
            val actionLabel = if (log.action == "IN") getString(R.string.action_in_label) else getString(R.string.action_out_label)
            listOf(
                log.personName,
                categoryLabel,
                log.detail ?: log.group.orEmpty(),
                actionLabel,
                fmt.format(Date(log.timestamp))
            )
        }

        val summaryHeaders = listOf(getString(R.string.col_summary_metric), getString(R.string.col_summary_value))
        val summaryRows = mutableListOf<List<String>>()
        summaryRows += listOf(getString(R.string.summary_total_events), logs.size.toString())
        summaryRows += listOf(getString(R.string.summary_total_in), logs.count { it.action == "IN" }.toString())
        summaryRows += listOf(getString(R.string.summary_total_out), logs.count { it.action == "OUT" }.toString())
        summaryRows += listOf("", "")
        summaryRows += listOf(getString(R.string.summary_by_category_header), "")
        for (type in PersonType.values()) {
            val inCount = logs.count { it.type == type.name && it.action == "IN" }
            val outCount = logs.count { it.type == type.name && it.action == "OUT" }
            summaryRows += listOf(
                "${type.displayName} — ${getString(R.string.action_in_label)}",
                inCount.toString()
            )
            summaryRows += listOf(
                "${type.displayName} — ${getString(R.string.action_out_label)}",
                outCount.toString()
            )
        }
        summaryRows += listOf("", "")
        summaryRows += listOf(getString(R.string.summary_currently_inside), "")
        for (type in PersonType.values()) {
            summaryRows += listOf(type.displayName, (insideCounts[type] ?: 0).toString())
        }

        val outDir = File(cacheDir, "exports").apply { mkdirs() }
        val fileName = "traffic_report_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}.xlsx"
        val file = File(outDir, fileName)
        XlsxWriter.write(
            file,
            listOf(
                XlsxWriter.Sheet(getString(R.string.report_title), detailHeaders, detailRows),
                XlsxWriter.Sheet(getString(R.string.report_analytics_sheet_name), summaryHeaders, summaryRows)
            )
        )
        return file
    }

    /** Also drops a copy in the public Downloads folder so it's easy to find without sharing. */
    private fun saveToDownloads(file: File) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                    put(MediaStore.MediaColumns.MIME_TYPE, XLSX_MIME)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/ConcreteFactoryReports")
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return
                contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
            } else {
                @Suppress("DEPRECATION")
                val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val folder = File(downloads, "ConcreteFactoryReports").apply { mkdirs() }
                file.copyTo(File(folder, file.name), overwrite = true)
            }
        } catch (_: Exception) {
            // Sharing the cache copy below still works even if the Downloads copy fails.
        }
    }

    private fun shareFile(file: File) {
        val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = XLSX_MIME
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, getString(R.string.report_export_button)))
    }

    companion object {
        private const val XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

        private fun startOfToday(): Long = startOfDay(System.currentTimeMillis())
        private fun endOfToday(): Long = endOfDay(System.currentTimeMillis())

        private fun startOfDay(timeMillis: Long): Long {
            val cal = Calendar.getInstance(TimeZone.getDefault())
            cal.timeInMillis = timeMillis
            cal.set(Calendar.HOUR_OF_DAY, 0); cal.set(Calendar.MINUTE, 0)
            cal.set(Calendar.SECOND, 0); cal.set(Calendar.MILLISECOND, 0)
            return cal.timeInMillis
        }

        private fun endOfDay(timeMillis: Long): Long {
            val cal = Calendar.getInstance(TimeZone.getDefault())
            cal.timeInMillis = timeMillis
            cal.set(Calendar.HOUR_OF_DAY, 23); cal.set(Calendar.MINUTE, 59)
            cal.set(Calendar.SECOND, 59); cal.set(Calendar.MILLISECOND, 999)
            return cal.timeInMillis
        }
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/java/ir/factory/entryexit/ui/fragments"
cat > "app/src/main/java/ir/factory/entryexit/ui/fragments/CategoryFragment.kt" << 'CLAUDE_EOF_MARKER'
package ir.factory.entryexit.ui.fragments

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.text.Editable
import android.text.TextWatcher
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.View
import android.widget.ArrayAdapter
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import ir.factory.entryexit.R
import ir.factory.entryexit.data.Department
import ir.factory.entryexit.data.PersonEntity
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.databinding.DialogAddPersonBinding
import ir.factory.entryexit.databinding.DialogManualCheckinBinding
import ir.factory.entryexit.databinding.FragmentCategoryBinding
import ir.factory.entryexit.ui.GroupedPersonAdapter
import ir.factory.entryexit.util.AppPreferences
import ir.factory.entryexit.viewmodel.FactoryViewModel

/**
 * One fragment class drives all four tabs. Personnel/Machinery behave as a persistent,
 * grouped roster (register once, then repeat check-in/out). Visitors/Drivers behave as a
 * transient, manual-entry log (a fresh record is created on every check-in, so only the
 * currently-inside list is shown).
 */
class CategoryFragment : Fragment(R.layout.fragment_category) {

    private val viewModel: FactoryViewModel by activityViewModels()
    private var _binding: FragmentCategoryBinding? = null
    private val binding get() = _binding!!

    private lateinit var type: PersonType
    private lateinit var adapter: GroupedPersonAdapter
    private var rawList: List<PersonEntity> = emptyList()

    private val isManualEntry: Boolean
        get() = type == PersonType.VISITOR || type == PersonType.DRIVER

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        type = PersonType.valueOf(requireArguments().getString(ARG_TYPE)!!)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        _binding = FragmentCategoryBinding.bind(view)

        setupList()
        setupFab()
        setupSearch()
        observeData()

        binding.swipeRefresh.setOnRefreshListener {
            // Room's LiveData is already live; this just gives reassuring pull-to-refresh feedback.
            binding.swipeRefresh.isRefreshing = false
        }
    }

    private fun setupList() {
        adapter = GroupedPersonAdapter(
            type,
            showGroups = !isManualEntry,
            onClick = { person -> onPersonClicked(person) },
            onLongClick = { person -> if (!isManualEntry) showEditPersonDialog(person) }
        )
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
        binding.tvLongPressHint.visibility = if (isManualEntry) View.GONE else View.VISIBLE
    }

    override fun onResume() {
        super.onResume()
        // Preferences may have changed in the Settings screen since this fragment was created.
        applyFilter(binding.etSearch.text?.toString().orEmpty())
        if (!AppPreferences.isRecentActivityVisible(requireContext())) {
            binding.tvRecentActivity.visibility = View.GONE
        }
    }

    private fun setupFab() {
        binding.fabAdd.text = if (isManualEntry) {
            getString(if (type == PersonType.VISITOR) R.string.new_visitor_checkin_title else R.string.new_driver_checkin_title)
        } else {
            getString(R.string.add_new)
        }
        binding.fabAdd.setOnClickListener {
            if (isManualEntry) showManualCheckInDialog() else showAddPersonDialog()
        }
    }

    private fun setupSearch() {
        binding.etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                applyFilter(s?.toString().orEmpty())
            }
            override fun afterTextChanged(s: Editable?) {}
        })
    }

    private fun observeData() {
        val listSource = if (isManualEntry) viewModel.insideByType(type) else viewModel.personsByType(type)
        listSource.observe(viewLifecycleOwner) { list ->
            rawList = list
            applyFilter(binding.etSearch.text?.toString().orEmpty())
        }

        viewModel.insideByType(type).observe(viewLifecycleOwner) { insideList ->
            binding.tvInsideCount.text = getString(R.string.inside_count_format, insideList.size)
        }

        viewModel.recentActivity(type).observe(viewLifecycleOwner) { logs ->
            if (!AppPreferences.isRecentActivityVisible(requireContext())) {
                binding.tvRecentActivity.visibility = View.GONE
                return@observe
            }
            val latest = logs.firstOrNull()
            if (latest == null) {
                binding.tvRecentActivity.visibility = View.GONE
            } else {
                binding.tvRecentActivity.visibility = View.VISIBLE
                binding.tvRecentActivity.text = if (latest.action == "IN") {
                    getString(R.string.log_entered_format, latest.personName)
                } else {
                    getString(R.string.log_exited_format, latest.personName)
                }
            }
        }
    }

    private fun applyFilter(query: String) {
        var filtered = if (query.isBlank()) {
            rawList
        } else {
            rawList.filter {
                it.name.contains(query, ignoreCase = true) ||
                    it.group?.contains(query, ignoreCase = true) == true
            }
        }

        if (!isManualEntry && AppPreferences.isInsideFirstSort(requireContext())) {
            // Keep group order intact (list already sorted by group,name from Room), but within
            // each group, show currently-inside items first.
            val groupOrder = LinkedHashSet<String>()
            for (p in filtered) groupOrder.add(p.group ?: "سایر")
            val byGroup = filtered.groupBy { it.group ?: "سایر" }
            filtered = groupOrder.flatMap { g ->
                byGroup[g].orEmpty().sortedWith(compareByDescending<PersonEntity> { it.isInside }.thenBy { it.name })
            }
        }

        adapter.submit(filtered)

        val emptyRes = when {
            filtered.isNotEmpty() -> null
            query.isNotBlank() -> R.string.empty_search
            isManualEntry -> R.string.empty_list_inside
            else -> R.string.empty_list_roster
        }
        binding.tvEmpty.visibility = if (emptyRes != null) View.VISIBLE else View.GONE
        emptyRes?.let { binding.tvEmpty.text = getString(it) }
    }

    // ---- Roster mode (Personnel / Machinery): tap -> choose ورود/خروج ----

    private fun onPersonClicked(person: PersonEntity) {
        if (isManualEntry) {
            confirmCheckOut(person)
        } else if (AppPreferences.isQuickTapEnabled(requireContext()) && !person.isInside) {
            // Quick-tap mode: an outside person/machine is checked in immediately, no chooser.
            // Checkout always keeps its confirmation regardless of this setting.
            viewModel.checkIn(person.id) { result -> handleActionResult(result.map { }, R.string.checkin_success) }
        } else if (AppPreferences.isQuickTapEnabled(requireContext()) && person.isInside) {
            confirmCheckOut(person)
        } else {
            val items = arrayOf(getString(R.string.btn_checkin), getString(R.string.btn_checkout))
            MaterialAlertDialogBuilder(requireContext())
                .setTitle(person.name)
                .setItems(items) { _, which ->
                    if (which == 0) {
                        viewModel.checkIn(person.id) { result -> handleActionResult(result.map { }, R.string.checkin_success) }
                    } else {
                        confirmCheckOut(person)
                    }
                }
                .setNegativeButton(R.string.btn_cancel, null)
                .show()
        }
    }

    private fun confirmCheckOut(person: PersonEntity) {
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.btn_checkout)
            .setMessage(getString(R.string.confirm_checkout_message, person.name))
            .setPositiveButton(R.string.btn_confirm_checkout) { _, _ ->
                viewModel.checkOut(person.id) { result -> handleActionResult(result.map { }, R.string.checkout_success) }
            }
            .setNegativeButton(R.string.btn_cancel, null)
            .show()
    }

    private fun showAddPersonDialog() {
        val dialogBinding = DialogAddPersonBinding.inflate(LayoutInflater.from(requireContext()))

        if (type == PersonType.PERSONNEL) {
            dialogBinding.tilGroup.hint = getString(R.string.hint_department)
            val departments = Department.values().map { it.displayName }
            dialogBinding.etGroup.setAdapter(
                ArrayAdapter(requireContext(), android.R.layout.simple_list_item_1, departments)
            )
            dialogBinding.tilExtraInfo.hint = getString(R.string.hint_extra_info)
        } else {
            // MACHINERY: free-text fleet/model group, no fixed list.
            dialogBinding.tilGroup.hint = getString(R.string.hint_machinery_group)
            dialogBinding.etGroup.inputType = android.text.InputType.TYPE_CLASS_TEXT
            dialogBinding.tilExtraInfo.hint = getString(R.string.hint_extra_info_machinery)
        }

        val dialog = MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.add_new_person_title)
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.btn_save, null)
            .setNegativeButton(R.string.btn_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = dialogBinding.etName.text?.toString().orEmpty()
                if (name.isBlank()) {
                    dialogBinding.tilName.error = getString(R.string.error_name_empty)
                    return@setOnClickListener
                }
                val group = dialogBinding.etGroup.text?.toString()
                val extra = dialogBinding.etExtraInfo.text?.toString()
                viewModel.addPerson(name, type, group, extra) { result ->
                    result.onSuccess {
                        performHaptic()
                        toast(getString(R.string.person_added_success))
                        dialog.dismiss()
                    }.onFailure { error ->
                        dialogBinding.tilName.error = error.message ?: getString(R.string.error_generic)
                    }
                }
            }
        }
        dialog.show()
    }

    // ---- Editing an existing Personnel/Machinery entry (long-press) ----

    private fun showEditPersonDialog(person: PersonEntity) {
        val dialogBinding = DialogAddPersonBinding.inflate(LayoutInflater.from(requireContext()))
        dialogBinding.etName.setText(person.name)
        dialogBinding.etExtraInfo.setText(person.extraInfo)

        if (type == PersonType.PERSONNEL) {
            dialogBinding.tilGroup.hint = getString(R.string.hint_department)
            val departments = Department.values().map { it.displayName }
            dialogBinding.etGroup.setAdapter(
                ArrayAdapter(requireContext(), android.R.layout.simple_list_item_1, departments)
            )
            dialogBinding.etGroup.setText(person.group, false)
            dialogBinding.tilExtraInfo.hint = getString(R.string.hint_extra_info)
        } else {
            dialogBinding.tilGroup.hint = getString(R.string.hint_machinery_group)
            dialogBinding.etGroup.inputType = android.text.InputType.TYPE_CLASS_TEXT
            dialogBinding.etGroup.setText(person.group)
            dialogBinding.tilExtraInfo.hint = getString(R.string.hint_extra_info_machinery)
        }

        val dialog = MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.edit_person_title)
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.btn_edit, null)
            .setNegativeButton(R.string.btn_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val name = dialogBinding.etName.text?.toString().orEmpty()
                if (name.isBlank()) {
                    dialogBinding.tilName.error = getString(R.string.error_name_empty)
                    return@setOnClickListener
                }
                val group = dialogBinding.etGroup.text?.toString()
                val extra = dialogBinding.etExtraInfo.text?.toString()
                viewModel.updatePerson(person.id, name, group, extra) { result ->
                    result.onSuccess {
                        performHaptic()
                        toast(getString(R.string.edit_success))
                        dialog.dismiss()
                    }.onFailure { error ->
                        dialogBinding.tilName.error = error.message ?: getString(R.string.error_generic)
                    }
                }
            }
        }
        dialog.show()
    }

    // ---- Manual-entry mode (Visitor / Driver): tap FAB -> name + department/vehicle ----

    private fun showManualCheckInDialog() {
        val dialogBinding = DialogManualCheckinBinding.inflate(LayoutInflater.from(requireContext()))

        val isVisitor = type == PersonType.VISITOR
        dialogBinding.tilPrimary.hint = getString(if (isVisitor) R.string.hint_visitor_name else R.string.hint_driver_name)
        dialogBinding.tilSecondary.hint = getString(if (isVisitor) R.string.hint_visitor_department else R.string.hint_driver_vehicle)

        val dialog = MaterialAlertDialogBuilder(requireContext())
            .setTitle(if (isVisitor) R.string.new_visitor_checkin_title else R.string.new_driver_checkin_title)
            .setView(dialogBinding.root)
            .setPositiveButton(R.string.btn_checkin, null)
            .setNegativeButton(R.string.btn_cancel, null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val primary = dialogBinding.etPrimary.text?.toString().orEmpty()
                val secondary = dialogBinding.etSecondary.text?.toString().orEmpty()

                var hasError = false
                if (primary.isBlank()) {
                    dialogBinding.tilPrimary.error = getString(R.string.error_name_empty)
                    hasError = true
                } else {
                    dialogBinding.tilPrimary.error = null
                }
                if (secondary.isBlank()) {
                    dialogBinding.tilSecondary.error =
                        getString(if (isVisitor) R.string.error_department_empty else R.string.error_vehicle_empty)
                    hasError = true
                } else {
                    dialogBinding.tilSecondary.error = null
                }
                if (hasError) return@setOnClickListener

                val onResult: (Result<Unit>) -> Unit = { result ->
                    result.onSuccess {
                        performHaptic()
                        toast(getString(R.string.checkin_success))
                        dialog.dismiss()
                    }.onFailure { error ->
                        toast(error.message ?: getString(R.string.error_generic))
                    }
                }
                if (isVisitor) {
                    viewModel.checkInVisitor(primary, secondary, onResult)
                } else {
                    viewModel.checkInDriver(primary, secondary, onResult)
                }
            }
        }
        dialog.show()
    }

    // ---- Shared helpers ----

    private fun handleActionResult(result: Result<Unit>, successMessage: Int) {
        result.onSuccess {
            performHaptic()
            toast(getString(successMessage))
        }.onFailure { error ->
            toast(error.message ?: getString(R.string.error_generic))
        }
    }

    /** Confirms a successful two-tap check-in/out with a short haptic buzz. Never crashes the
     *  calling action if the device/permission doesn't cooperate — haptics are a nice-to-have. */
    private fun performHaptic() {
        if (!AppPreferences.isHapticEnabled(requireContext())) return
        runCatching {
            view?.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        }
        runCatching {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (requireContext().getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                requireContext().getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(35, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(35)
            }
        }
    }

    private fun toast(message: String) {
        Toast.makeText(requireContext(), message, Toast.LENGTH_SHORT).show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    companion object {
        private const val ARG_TYPE = "arg_type"

        fun newInstance(type: PersonType): CategoryFragment = CategoryFragment().apply {
            arguments = Bundle().apply { putString(ARG_TYPE, type.name) }
        }
    }
}

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/strings.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">حراست سبحان بتن</string>
    <string name="app_subtitle">مدیریت ورود و خروج</string>

    <string name="category_personnel">پرسنل</string>
    <string name="category_machinery">ماشین‌آلات</string>
    <string name="category_visitor">مراجعین</string>
    <string name="category_driver">رانندگان</string>

    <string name="inside_count_format">%1$d نفر / مورد داخل کارخانه</string>

    <string name="empty_list_roster">هنوز موردی ثبت نشده است.\nبرای افزودن، دکمه + را بزنید.</string>
    <string name="empty_list_inside">در حال حاضر کسی داخل کارخانه نیست.</string>
    <string name="empty_search">نتیجه‌ای یافت نشد.</string>

    <string name="add_new">افزودن جدید</string>
    <string name="add_new_person_title">ثبت مورد جدید</string>
    <string name="hint_name">نام</string>
    <string name="hint_extra_info">اطلاعات تکمیلی (اختیاری)</string>
    <string name="hint_extra_info_machinery">شماره پلاک (اختیاری)</string>
    <string name="hint_department">دپارتمان</string>
    <string name="hint_machinery_group">گروه ماشین (مثلاً: میکسر، پمپ، وانت)</string>

    <string name="new_visitor_checkin_title">ثبت ورود مهمان جدید</string>
    <string name="hint_visitor_name">نام مهمان</string>
    <string name="hint_visitor_department">واحد یا بخش مورد مراجعه</string>

    <string name="new_driver_checkin_title">ثبت ورود راننده جدید</string>
    <string name="hint_driver_name">نام راننده</string>
    <string name="hint_driver_vehicle">ماشین مربوطه</string>

    <string name="btn_save">ثبت</string>
    <string name="btn_cancel">انصراف</string>
    <string name="btn_checkin">ورود</string>
    <string name="btn_checkout">خروج</string>
    <string name="btn_confirm_checkout">تایید خروج</string>

    <string name="status_inside">داخل</string>
    <string name="status_outside">خارج</string>

    <string name="checkin_success">ورود ثبت شد</string>
    <string name="checkout_success">خروج ثبت شد</string>
    <string name="person_added_success">با موفقیت ثبت شد</string>
    <string name="error_generic">خطایی رخ داد</string>
    <string name="error_name_empty">وارد کردن نام الزامی است</string>
    <string name="error_department_empty">وارد کردن واحد مورد مراجعه الزامی است</string>
    <string name="error_vehicle_empty">وارد کردن ماشین مربوطه الزامی است</string>

    <string name="confirm_checkout_message">آیا از ثبت خروج «%1$s» اطمینان دارید؟</string>
    <string name="last_status_format">وضعیت: %1$s</string>

    <string name="log_entered_format">%1$s وارد شد</string>
    <string name="log_exited_format">%1$s خارج شد</string>
    <string name="recent_activity_empty">هنوز رویدادی ثبت نشده است</string>

    <string name="search_hint">جست‌وجوی سریع…</string>
    <string name="menu_search">جست‌وجو</string>
    <string name="menu_setup">تنظیمات اولیه</string>
    <string name="menu_report">گزارش‌ها</string>
    <string name="menu_settings">تنظیمات نمایش</string>

    <string name="settings_title">تنظیمات نمایش و کلیک</string>
    <string name="settings_section_display">نمایش</string>
    <string name="settings_section_interaction">تعامل / کلیک</string>
    <string name="settings_section_theme">پوسته برنامه</string>
    <string name="settings_show_recent_activity">نمایش فعالیت اخیر در هر تب</string>
    <string name="settings_inside_first">نمایش موارد «داخل» در بالای هر بخش</string>
    <string name="settings_haptic">لرزش هنگام تایید ورود/خروج</string>
    <string name="settings_quick_tap">کلیک سریع (رد کردن منوی انتخاب برای ورود)</string>
    <string name="settings_quick_tap_hint">در این حالت، کلیک روی یک مورد «خارج» بلافاصله ورود آن را ثبت می‌کند. خروج همیشه نیاز به تایید دارد.</string>
    <string name="settings_theme_system">پیش‌فرض سیستم</string>
    <string name="settings_theme_light">روشن</string>
    <string name="settings_theme_dark">تیره</string>

    <string name="edit_person_title">ویرایش مشخصات</string>
    <string name="btn_edit">ویرایش</string>
    <string name="edit_success">تغییرات ذخیره شد</string>
    <string name="long_press_hint">برای ویرایش مشخصات، لمس طولانی کنید</string>

    <string name="report_analytics_sheet_name">خلاصه آماری</string>
    <string name="col_summary_metric">شاخص</string>
    <string name="col_summary_value">مقدار</string>
    <string name="summary_total_events">کل رویدادها در این بازه</string>
    <string name="summary_total_in">کل ورودها</string>
    <string name="summary_total_out">کل خروج‌ها</string>
    <string name="summary_currently_inside">در حال حاضر داخل کارخانه (اکنون)</string>
    <string name="summary_by_category_header">بر اساس دسته</string>

    <string name="setup_title">تنظیمات اولیه</string>
    <string name="setup_subtitle_personnel">افزودن عکس پرسنلی</string>
    <string name="setup_subtitle_machinery">افزودن عکس ماشین‌آلات</string>
    <string name="setup_pick_image">انتخاب عکس</string>
    <string name="setup_image_updated">عکس به‌روزرسانی شد</string>

    <string name="report_title">گزارش‌ها و خروجی اکسل</string>
    <string name="report_from_date">از تاریخ</string>
    <string name="report_to_date">تا تاریخ</string>
    <string name="report_export_button">دریافت خروجی اکسل</string>
    <string name="report_export_success">فایل اکسل با موفقیت ساخته شد</string>
    <string name="report_export_empty">در این بازه زمانی هیچ رویدادی ثبت نشده است</string>
    <string name="report_row_count_format">%1$d ردیف برای خروجی یافت شد</string>

    <string name="col_name">نام / مورد</string>
    <string name="col_category">دسته</string>
    <string name="col_department">واحد / گروه</string>
    <string name="col_action">نوع رویداد</string>
    <string name="col_timestamp">تاریخ و ساعت</string>
    <string name="action_in_label">ورود</string>
    <string name="action_out_label">خروج</string>

    <string name="global_search_title">جست‌وجوی کلی</string>
</resources>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.ConcreteFactory" parent="Theme.MaterialComponents.DayNight.NoActionBar">
        <item name="colorPrimary">@color/colorPrimary</item>
        <item name="colorPrimaryVariant">@color/colorPrimaryVariant</item>
        <item name="colorOnPrimary">@color/white</item>
        <item name="colorSecondary">@color/colorSecondary</item>
        <item name="colorSecondaryVariant">@color/colorSecondaryVariant</item>
        <item name="colorOnSecondary">@color/concrete_900</item>
        <item name="android:statusBarColor">@color/concrete_900</item>
        <item name="android:windowBackground">@color/colorBackground</item>
        <item name="android:windowLightStatusBar" tools:targetApi="m">false</item>
        <item name="materialButtonStyle">@style/Widget.ConcreteFactory.Button</item>
    </style>

    <style name="Widget.ConcreteFactory.Button" parent="Widget.MaterialComponents.Button">
        <item name="cornerRadius">14dp</item>
        <item name="android:textAllCaps">false</item>
        <item name="android:letterSpacing">0</item>
    </style>

    <style name="Widget.ConcreteFactory.Button.Outlined" parent="Widget.MaterialComponents.Button.OutlinedButton">
        <item name="cornerRadius">14dp</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <style name="CategoryTile">
        <item name="android:layout_width">0dp</item>
        <item name="android:layout_height">140dp</item>
        <item name="cardCornerRadius">20dp</item>
        <item name="cardElevation">3dp</item>
    </style>

    <style name="SettingsSectionHeader">
        <item name="android:layout_width">wrap_content</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:layout_marginStart">20dp</item>
        <item name="android:layout_marginTop">20dp</item>
        <item name="android:layout_marginBottom">8dp</item>
        <item name="android:textColor">@color/concrete_500</item>
        <item name="android:textSize">13sp</item>
        <item name="android:textStyle">bold</item>
    </style>

    <style name="SettingsCard">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:layout_marginHorizontal">16dp</item>
        <item name="cardBackgroundColor">@color/colorSurface</item>
        <item name="cardCornerRadius">16dp</item>
        <item name="cardElevation">1dp</item>
    </style>

    <style name="SettingsSwitchRow">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">wrap_content</item>
        <item name="android:paddingHorizontal">16dp</item>
        <item name="android:paddingVertical">14dp</item>
        <item name="android:textSize">14sp</item>
    </style>

    <style name="SettingsDivider">
        <item name="android:layout_width">match_parent</item>
        <item name="android:layout_height">1dp</item>
        <item name="android:layout_marginHorizontal">16dp</item>
        <item name="android:background">@color/concrete_200</item>
    </style>
</resources>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/menu"
cat > "app/src/main/res/menu/menu_main.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<menu xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto">

    <item
        android:id="@+id/action_search"
        android:icon="@drawable/ic_search"
        android:title="@string/menu_search"
        android:contentDescription="@string/menu_search"
        app:iconTint="@color/white"
        app:showAsAction="ifRoom" />

    <item
        android:id="@+id/action_report"
        android:icon="@drawable/ic_report"
        android:title="@string/menu_report"
        android:contentDescription="@string/menu_report"
        app:iconTint="@color/white"
        app:showAsAction="ifRoom" />

    <item
        android:id="@+id/action_setup"
        android:icon="@drawable/ic_setup"
        android:title="@string/menu_setup"
        android:contentDescription="@string/menu_setup"
        app:iconTint="@color/white"
        app:showAsAction="ifRoom" />

    <item
        android:id="@+id/action_settings"
        android:icon="@drawable/ic_settings_gear"
        android:title="@string/menu_settings"
        android:contentDescription="@string/menu_settings"
        app:iconTint="@color/white"
        app:showAsAction="never" />

</menu>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/layout"
cat > "app/src/main/res/layout/fragment_category.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<androidx.coordinatorlayout.widget.CoordinatorLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/colorBackground">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical">

        <com.google.android.material.textfield.TextInputLayout
            android:id="@+id/tilSearch"
            style="@style/Widget.MaterialComponents.TextInputLayout.OutlinedBox"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_margin="16dp"
            android:layout_marginBottom="8dp"
            android:hint="@string/search_hint"
            app:boxCornerRadiusBottomEnd="14dp"
            app:boxCornerRadiusBottomStart="14dp"
            app:boxCornerRadiusTopEnd="14dp"
            app:boxCornerRadiusTopStart="14dp"
            app:startIconDrawable="@drawable/ic_search">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/etSearch"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="text"
                android:maxLines="1" />
        </com.google.android.material.textfield.TextInputLayout>

        <LinearLayout
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginHorizontal="16dp"
            android:layout_marginBottom="10dp"
            android:background="@drawable/bg_status_inside"
            android:orientation="horizontal"
            android:padding="14dp">

            <ImageView
                android:layout_width="20dp"
                android:layout_height="20dp"
                android:layout_gravity="center_vertical"
                android:src="@drawable/ic_check_in"
                app:tint="@color/status_green" />

            <TextView
                android:id="@+id/tvInsideCount"
                android:layout_width="0dp"
                android:layout_height="wrap_content"
                android:layout_marginStart="10dp"
                android:layout_weight="1"
                android:gravity="center_vertical"
                android:textColor="@color/status_green"
                android:textSize="15sp"
                android:textStyle="bold" />
        </LinearLayout>

        <TextView
            android:id="@+id/tvRecentActivity"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginHorizontal="16dp"
            android:layout_marginBottom="4dp"
            android:ellipsize="end"
            android:maxLines="1"
            android:textColor="@color/concrete_500"
            android:textSize="12sp"
            android:visibility="gone" />

        <TextView
            android:id="@+id/tvLongPressHint"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginHorizontal="16dp"
            android:layout_marginBottom="10dp"
            android:text="@string/long_press_hint"
            android:textColor="@color/concrete_300"
            android:textSize="11sp"
            android:visibility="gone" />

        <TextView
            android:id="@+id/tvEmpty"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="60dp"
            android:gravity="center"
            android:padding="24dp"
            android:textColor="@color/concrete_500"
            android:textSize="15sp"
            android:visibility="gone" />

        <androidx.swiperefreshlayout.widget.SwipeRefreshLayout
            android:id="@+id/swipeRefresh"
            android:layout_width="match_parent"
            android:layout_height="0dp"
            android:layout_weight="1">

            <androidx.recyclerview.widget.RecyclerView
                android:id="@+id/recyclerView"
                android:layout_width="match_parent"
                android:layout_height="match_parent"
                android:clipToPadding="false"
                android:paddingHorizontal="16dp"
                android:paddingBottom="90dp" />
        </androidx.swiperefreshlayout.widget.SwipeRefreshLayout>

    </LinearLayout>

    <com.google.android.material.floatingactionbutton.ExtendedFloatingActionButton
        android:id="@+id/fabAdd"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|start"
        android:layout_margin="20dp"
        android:backgroundTint="@color/safety_amber"
        android:textColor="@color/concrete_900"
        app:icon="@drawable/ic_plus"
        app:iconTint="@color/concrete_900" />

</androidx.coordinatorlayout.widget.CoordinatorLayout>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/layout"
cat > "app/src/main/res/layout/activity_settings.xml" << 'CLAUDE_EOF_MARKER'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/colorBackground">

    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="vertical"
        android:paddingBottom="24dp">

        <androidx.appcompat.widget.Toolbar
            android:id="@+id/toolbar"
            android:layout_width="match_parent"
            android:layout_height="?attr/actionBarSize"
            android:background="@color/concrete_900"
            android:navigationIcon="@drawable/ic_arrow_back"
            app:titleTextColor="@color/white" />

        <!-- Display -->
        <TextView
            style="@style/SettingsSectionHeader"
            android:text="@string/settings_section_display" />

        <androidx.cardview.widget.CardView
            style="@style/SettingsCard">
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical">

                <com.google.android.material.materialswitch.MaterialSwitch
                    android:id="@+id/switchRecentActivity"
                    style="@style/SettingsSwitchRow"
                    android:text="@string/settings_show_recent_activity" />

                <View style="@style/SettingsDivider" />

                <com.google.android.material.materialswitch.MaterialSwitch
                    android:id="@+id/switchInsideFirst"
                    style="@style/SettingsSwitchRow"
                    android:text="@string/settings_inside_first" />
            </LinearLayout>
        </androidx.cardview.widget.CardView>

        <!-- Interaction -->
        <TextView
            style="@style/SettingsSectionHeader"
            android:text="@string/settings_section_interaction" />

        <androidx.cardview.widget.CardView
            style="@style/SettingsCard">
            <LinearLayout
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical">

                <com.google.android.material.materialswitch.MaterialSwitch
                    android:id="@+id/switchHaptic"
                    style="@style/SettingsSwitchRow"
                    android:text="@string/settings_haptic" />

                <View style="@style/SettingsDivider" />

                <com.google.android.material.materialswitch.MaterialSwitch
                    android:id="@+id/switchQuickTap"
                    style="@style/SettingsSwitchRow"
                    android:text="@string/settings_quick_tap" />

                <TextView
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:paddingHorizontal="16dp"
                    android:paddingBottom="14dp"
                    android:text="@string/settings_quick_tap_hint"
                    android:textColor="@color/concrete_500"
                    android:textSize="12sp" />
            </LinearLayout>
        </androidx.cardview.widget.CardView>

        <!-- Theme -->
        <TextView
            style="@style/SettingsSectionHeader"
            android:text="@string/settings_section_theme" />

        <androidx.cardview.widget.CardView
            style="@style/SettingsCard">

            <RadioGroup
                android:id="@+id/radioGroupTheme"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:orientation="vertical"
                android:paddingVertical="4dp">

                <RadioButton
                    android:id="@+id/radioThemeSystem"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:paddingHorizontal="16dp"
                    android:paddingVertical="12dp"
                    android:text="@string/settings_theme_system" />

                <RadioButton
                    android:id="@+id/radioThemeLight"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:paddingHorizontal="16dp"
                    android:paddingVertical="12dp"
                    android:text="@string/settings_theme_light" />

                <RadioButton
                    android:id="@+id/radioThemeDark"
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:paddingHorizontal="16dp"
                    android:paddingVertical="12dp"
                    android:text="@string/settings_theme_dark" />
            </RadioGroup>
        </androidx.cardview.widget.CardView>

    </LinearLayout>
</ScrollView>

CLAUDE_EOF_MARKER

mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_settings_gear.xml" << 'CLAUDE_EOF_MARKER'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path android:fillColor="#FF000000"
        android:pathData="M3,17v2h6v-2H3zM3,5v2h10V5H3zM13,21v-2h8v-2h-8v-2h-2v6h2zM7,9v2H3v2h4v2h2V9H7zM21,13v-2H11v2h10zM15,9h2V7h4V5h-4V3h-2v6z"/>
</vector>

CLAUDE_EOF_MARKER

echo "=== Verification ==="
grep -c VIBRATE app/src/main/AndroidManifest.xml
grep -c AppPreferences app/src/main/java/ir/factory/entryexit/ui/fragments/CategoryFragment.kt
echo All files written.
