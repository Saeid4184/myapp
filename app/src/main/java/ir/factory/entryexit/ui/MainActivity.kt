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
            else -> super.onOptionsItemSelected(item)
        }
    }

    companion object {
        const val EXTRA_JUMP_TO_TYPE = "extra_jump_to_type"
    }
}
