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

