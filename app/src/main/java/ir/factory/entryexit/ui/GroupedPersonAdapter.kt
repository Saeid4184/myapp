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
    private val onClick: (PersonEntity) -> Unit
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
        }
    }

    companion object {
        private const val VIEW_TYPE_HEADER = 0
        private const val VIEW_TYPE_ITEM = 1
    }
}
