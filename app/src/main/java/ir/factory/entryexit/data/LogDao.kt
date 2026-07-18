package ir.factory.entryexit.data

import androidx.lifecycle.LiveData
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface LogDao {

    @Insert
    suspend fun insert(log: LogEntity)

    @Query("SELECT * FROM logs WHERE personId = :personId ORDER BY timestamp DESC")
    fun getLogsForPerson(personId: Long): LiveData<List<LogEntity>>

    @Query("SELECT * FROM logs ORDER BY timestamp DESC LIMIT :limit")
    fun getRecent(limit: Int = 20): LiveData<List<LogEntity>>

    @Query("SELECT * FROM logs WHERE type = :type ORDER BY timestamp DESC LIMIT :limit")
    fun getRecentByType(type: String, limit: Int = 10): LiveData<List<LogEntity>>

    /** Used by the Excel export: every log row inside an inclusive [start, end] timestamp range. */
    @Query("SELECT * FROM logs WHERE timestamp BETWEEN :start AND :end ORDER BY timestamp ASC")
    suspend fun getLogsInRange(start: Long, end: Long): List<LogEntity>
}
