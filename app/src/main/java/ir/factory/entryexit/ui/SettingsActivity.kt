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

