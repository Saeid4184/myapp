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
        adapter = GroupedPersonAdapter(type, showGroups = !isManualEntry) { person -> onPersonClicked(person) }
        binding.recyclerView.layoutManager = LinearLayoutManager(requireContext())
        binding.recyclerView.adapter = adapter
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
        val filtered = if (query.isBlank()) {
            rawList
        } else {
            rawList.filter {
                it.name.contains(query, ignoreCase = true) ||
                    it.group?.contains(query, ignoreCase = true) == true
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

    /** Confirms a successful two-tap check-in/out with a short haptic buzz. */
    private fun performHaptic() {
        view?.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
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
