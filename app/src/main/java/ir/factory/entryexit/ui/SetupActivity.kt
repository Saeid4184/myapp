package ir.factory.entryexit.ui

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.material.tabs.TabLayout
import ir.factory.entryexit.R
import ir.factory.entryexit.data.PersonEntity
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.databinding.ActivitySetupBinding
import ir.factory.entryexit.databinding.ItemSetupEntryBinding
import ir.factory.entryexit.viewmodel.FactoryViewModel

/**
 * Lets the office set up profile photos for personnel and equipment photos for machinery
 * before the app goes into daily use. Photos are picked via the system document/gallery
 * picker; the resulting content:// URI is persisted (with permission) directly on the
 * person/machine record.
 */
class SetupActivity : AppCompatActivity() {

    private lateinit var binding: ActivitySetupBinding
    private lateinit var viewModel: FactoryViewModel
    private lateinit var adapter: SetupAdapter
    private var currentType: PersonType = PersonType.PERSONNEL
    private var pendingTargetId: Long = -1L

    private val pickImage = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && pendingTargetId != -1L) {
            runCatching {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            viewModel.updatePersonImage(pendingTargetId, uri.toString()) { result ->
                result.onSuccess {
                    android.widget.Toast.makeText(this, getString(R.string.setup_image_updated), android.widget.Toast.LENGTH_SHORT).show()
                    loadRoster()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySetupBinding.inflate(layoutInflater)
        setContentView(binding.root)

        viewModel = ViewModelProvider(this)[FactoryViewModel::class.java]

        binding.toolbar.title = getString(R.string.setup_title)
        binding.toolbar.setNavigationOnClickListener { finish() }

        adapter = SetupAdapter(currentType) { person -> launchPicker(person) }
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = adapter

        binding.tabLayout.addTab(binding.tabLayout.newTab().setText(getString(R.string.setup_subtitle_personnel)))
        binding.tabLayout.addTab(binding.tabLayout.newTab().setText(getString(R.string.setup_subtitle_machinery)))
        binding.tabLayout.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                currentType = if (tab.position == 0) PersonType.PERSONNEL else PersonType.MACHINERY
                adapter = SetupAdapter(currentType) { person -> launchPicker(person) }
                binding.recyclerView.adapter = adapter
                loadRoster()
            }
            override fun onTabUnselected(tab: TabLayout.Tab) {}
            override fun onTabReselected(tab: TabLayout.Tab) {}
        })

        loadRoster()
    }

    private fun launchPicker(person: PersonEntity) {
        pendingTargetId = person.id
        pickImage.launch(arrayOf("image/*"))
    }

    private fun loadRoster() {
        viewModel.loadRosterOnce(currentType) { roster -> adapter.submit(roster) }
    }

    private class SetupAdapter(private val type: PersonType, private val onPick: (PersonEntity) -> Unit) :
        RecyclerView.Adapter<SetupAdapter.VH>() {

        private var items: List<PersonEntity> = emptyList()

        fun submit(list: List<PersonEntity>) {
            items = list
            notifyDataSetChanged()
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val binding = ItemSetupEntryBinding.inflate(LayoutInflater.from(parent.context), parent, false)
            return VH(binding)
        }

        override fun onBindViewHolder(holder: VH, position: Int) = holder.bind(items[position])
        override fun getItemCount(): Int = items.size

        inner class VH(private val binding: ItemSetupEntryBinding) : RecyclerView.ViewHolder(binding.root) {
            fun bind(person: PersonEntity) {
                binding.tvName.text = person.name
                val iconRes = if (type == PersonType.PERSONNEL) R.drawable.ic_personnel else R.drawable.ic_machinery

                if (person.imageUri != null) {
                    binding.ivTypeIcon.visibility = View.GONE
                    binding.ivPhoto.visibility = View.VISIBLE
                    Glide.with(binding.root.context)
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

                binding.btnPickImage.setOnClickListener { onPick(person) }
            }
        }
    }
}
