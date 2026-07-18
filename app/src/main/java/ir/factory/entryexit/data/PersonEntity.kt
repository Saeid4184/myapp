package ir.factory.entryexit.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * A registered person / machine / driver / visitor.
 *
 * [isInside] is the single source of truth for whether they are currently inside the factory;
 * it is what enforces the "no duplicate check-in" business rule.
 * [group] is the sub-category used for sectioned lists: a department name for personnel,
 * or a fleet/model group (e.g. "میکسر - آمیکو") for machinery. Null for visitors/drivers.
 * [imageUri] is a persisted content:// URI to a profile/equipment photo picked from the
 * device gallery during setup; null falls back to a text/icon placeholder.
 * [lastEventAt] is updated on every check-in/out and used to sort "currently inside" lists
 * by recency.
 */
@Entity(tableName = "persons")
data class PersonEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val type: String, // matches PersonType.name
    @ColumnInfo(name = "group_name") val group: String? = null,
    val extraInfo: String? = null,
    val imageUri: String? = null,
    val isInside: Boolean = false,
    val lastEventAt: Long = 0L
)
