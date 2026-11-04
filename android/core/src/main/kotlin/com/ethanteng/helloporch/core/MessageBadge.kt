package com.ethanteng.helloporch.core

/** The app badge on a phone in several families: unplayed messages from all of them. A message notification's badge
 * already counted every family, so the badge waits until each one has checked in, or failed to. Otherwise the first
 * family to check in would lower it to its own count. */
object MessageBadge {
    /** `unplayed` has one count per family, null for one that hasn't checked in yet. Null while any is still waiting. */
    fun count(unplayed: List<Int?>): Int? {
        if (unplayed.isEmpty() || unplayed.any { it == null }) return null
        return unplayed.sumOf { it ?: 0 }
    }
}
