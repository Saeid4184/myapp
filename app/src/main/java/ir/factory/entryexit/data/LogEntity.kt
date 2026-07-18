package ir.factory.entryexit.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * An immutable historical record of a single check-in or check-out event — the basis for the
 * Excel export. [personName]/[type]/[group] are denormalized (copied at event time) so history
 * remains accurate even if the person record is later edited.
 * [detail] holds context specific to the event: department visited (for visitors) or assigned
 * vehicle (for drivers). Null for personnel/machinery.
 */
@Entity(tableName = "logs")
data class LogEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val personId: Long,
    val personName: String,
    val type: String,
    @ColumnInfo(name = "group_name") val group: String? = null,
    val action: String, // "IN" or "OUT"
    val timestamp: Long,
    val detail: String? = null
)
