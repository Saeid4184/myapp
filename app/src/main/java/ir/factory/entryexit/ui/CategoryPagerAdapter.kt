package ir.factory.entryexit.ui

import androidx.fragment.app.FragmentActivity
import androidx.viewpager2.adapter.FragmentStateAdapter
import ir.factory.entryexit.data.PersonType
import ir.factory.entryexit.ui.fragments.CategoryFragment

/** Backs the 4 tabs (Personnel, Machinery, Visitors, Drivers) in MainActivity's ViewPager2. */
class CategoryPagerAdapter(activity: FragmentActivity) : FragmentStateAdapter(activity) {

    private val tabs = listOf(
        PersonType.PERSONNEL,
        PersonType.MACHINERY,
        PersonType.VISITOR,
        PersonType.DRIVER
    )

    override fun getItemCount(): Int = tabs.size

    override fun createFragment(position: Int) = CategoryFragment.newInstance(tabs[position])

    fun typeAt(position: Int): PersonType = tabs[position]

    fun positionOf(type: PersonType): Int = tabs.indexOf(type)
}
