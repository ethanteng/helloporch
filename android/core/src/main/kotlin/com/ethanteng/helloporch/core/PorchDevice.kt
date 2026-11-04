package com.ethanteng.helloporch.core

import java.security.MessageDigest
import java.security.SecureRandom
import java.text.BreakIterator
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** This device's pairings and the mode it runs in. `defaultOrigin` is the server the app is built with. */
class PorchDevice(
    private val settings: PorchSettings,
    private val secrets: SecretStore,
    val defaultOrigin: String,
    /** Only a tablet becomes the bedside: it stays with them. A phone is family. */
    val canBeBedside: Boolean,
) {
    var experience: PorchExperience
        get() = settings.getString(experienceKey)?.let(::experienceNamed)
            ?: if (canBeBedside) PorchExperience.BEDSIDE else PorchExperience.FAMILY
        set(value) = settings.putString(experienceKey, value.rawValue)

    /** A device that has never been set up either way, and hasn't been told which it is: Porch asks first. Anything
     * that says otherwise, such as a pairing or a keypad, counts. */
    val needsWelcome: Boolean
        get() {
            if (settings.getString(experienceKey) != null) return false
            return credential(PorchExperience.BEDSIDE) == null && families.isEmpty() && caregiverCode.isEmpty() &&
                !CallSlots.isSaved(settings) && bedsideActivation == null
        }

    /** Writes down the mode a set-up device has been using, which it otherwise works out from the device, so it never
     * looks new to [needsWelcome]. */
    fun rememberExperience() {
        if (settings.getString(experienceKey) != null) return
        if (credential(PorchExperience.BEDSIDE) == null && families.isEmpty()) return
        settings.putString(experienceKey, experience.rawValue)
    }

    /** The bedside's pairing, or on a family phone the family its screens are showing (see [families]). */
    fun credential(role: PorchExperience): FamilyCredential? =
        if (role == PorchExperience.FAMILY) currentFamily else stored(bedsideAccount)

    private fun stored(account: String): FamilyCredential? =
        secrets.read(account)?.let { decodedOrNull { PorchJson.decodeFromString(FamilyCredential.serializer(), it.decodeToString()) } }

    /** Every family this phone has joined, such as both sets of parents, in the order it joined them. Each is its own
     * pairing: the families never learn about each other. */
    val families: List<FamilyCredential>
        get() {
            val data = secrets.read(familiesAccount) ?: return emptyList()
            return decodedOrNull { PorchJson.decodeFromString(ListSerializer(FamilyCredential.serializer()), data.decodeToString()) } ?: emptyList()
        }

    /** The family whose messages, profile and caregiver mode the phone's screens are showing. */
    val currentFamily: FamilyCredential?
        get() {
            val all = families
            val current = settings.getString(currentFamilyKey)
            return all.firstOrNull { it.deviceID == current } ?: all.firstOrNull()
        }

    fun select(credential: FamilyCredential) = settings.putString(currentFamilyKey, credential.deviceID)

    /** The pairing a call or message for `memberID` belongs to. Each family knows this phone by a different ID. */
    fun family(memberID: String?): FamilyCredential? = memberID?.let { id -> families.firstOrNull { it.deviceID == id } }

    /** Readable after the first unlock, so a call can ring on a locked phone that just restarted. */
    private fun saveFamilies(families: List<FamilyCredential>) {
        val json = PorchJson.encodeToString(ListSerializer(FamilyCredential.serializer()), families)
        secrets.write(familiesAccount, json.encodeToByteArray(), SecretStore.Access.AFTER_FIRST_UNLOCK)
    }

    /** Takes a family off this phone, with what the phone called it. Leaving it on the server is up to the caller. */
    fun removeFamily(credential: FamilyCredential) {
        saveFamilies(families.filter { it.deviceID != credential.deviceID })
        for (key in listOf(nicknamesKey, householdsKey)) setDictionary(key, dictionary(key) - credential.deviceID)
    }

    /** What this phone calls a family, shown only once it's in more than one: the name chosen here, or its household's,
     * numbered when a family it joined earlier has the same one. */
    fun familyName(credential: FamilyCredential): String? {
        val all = families
        val index = all.indexOfFirst { it.deviceID == credential.deviceID }
        if (index < 0) return unnumberedName(credential)
        return FamilyNames.distinct(all.map(::unnumberedName))[index]
    }

    /** The name chosen here, or its household's, before any number that tells it from another family's. */
    fun unnumberedName(credential: FamilyCredential): String? =
        FamilyNames.family(nickname(credential), household(credential)?.get("name"))

    fun nickname(credential: FamilyCredential): String? = dictionary(nicknamesKey)[credential.deviceID]?.string

    fun setNickname(nickname: String?, credential: FamilyCredential) {
        val names = dictionary(nicknamesKey).toMutableMap()
        val trimmed = nickname?.trim()
        if (!trimmed.isNullOrEmpty()) names[credential.deviceID] = JsonPrimitive(trimmed.prefixCharacters(80))
        else names.remove(credential.deviceID)
        setDictionary(nicknamesKey, names)
    }

    /** The household a family's pairing belongs to, as it last checked in: so a call that rings before Porch has
     * checked in can still say which family it's from, and a second invitation to the same family replaces the first. */
    fun noteHousehold(state: FamilySnapshot, credential: FamilyCredential) {
        val household = mapOf("id" to state.householdID, "name" to state.householdName)
        if (household(credential) == household) return
        setDictionary(householdsKey, dictionary(householdsKey) + (credential.deviceID to JsonObject(household.mapValues { JsonPrimitive(it.value) })))
    }

    fun householdID(credential: FamilyCredential): String? = household(credential)?.get("id")

    private fun household(credential: FamilyCredential): Map<String, String>? {
        val entry = dictionary(householdsKey)[credential.deviceID] as? JsonObject ?: return null
        return entry.mapValues { it.value.string ?: return null }
    }

    val bedsideActivation: String?
        get() = secrets.read(activationAccount)?.decodeToString()?.ifEmpty { null }

    fun saveActivation(url: String?) {
        secrets.write(activationAccount, (url ?: "").encodeToByteArray())
    }

    /** Before this tablet becomes another household's bedside, its old household stops ringing it. The household itself,
     * with its number and family, stays. A pairing the server no longer accepts, such as for a deleted household, has
     * nothing left to stop; anything else, such as no connection, stops the replacement until it's tried again. */
    suspend fun leaveBedside(credential: FamilyCredential, serviceFor: (FamilyCredential) -> FamilyService) {
        for (action in listOf("registerVoIP", "registerAlerts")) {
            try {
                serviceFor(credential).send(action, mapOf("token" to JsonNull))
            } catch (error: FamilyServiceException) {
                if (error.status in listOf(401, 403, 404, 410)) return
                throw error
            }
        }
    }

    @Serializable
    private class Pending(val profile: FamilyCredential, val scope: String)

    fun pending(role: PorchExperience, origin: String, invitation: String = ""): FamilyCredential {
        val account = "porch.family.pending.${role.rawValue}"
        val scope = MessageDigest.getInstance("SHA-256").digest((origin + invitation).encodeToByteArray()).hex()
        val saved = secrets.read(account)?.let { decodedOrNull { PorchJson.decodeFromString(Pending.serializer(), it.decodeToString()) } }
        if (saved != null && saved.scope == scope) return saved.profile
        val secret = ByteArray(32).also(SecureRandom()::nextBytes).hex()
        val profile = FamilyCredential(origin, "${UUID.randomUUID().toString().lowercase()}.$secret", role)
        secrets.write(account, PorchJson.encodeToString(Pending.serializer(), Pending(profile, scope)).encodeToByteArray())
        return profile
    }

    fun registration(profile: FamilyCredential): Map<String, JsonElement> {
        val pieces = profile.credential.split('.')
        return mapOf("deviceID" to JsonPrimitive(pieces[0]), "deviceSecret" to JsonPrimitive(pieces[1]))
    }

    /** Saves the bedside's pairing, or adds a family to the ones this phone is in. A family already here (the same
     * device identity) keeps its place. Both are readable after the first unlock, so a call can ring on a locked phone. */
    fun save(credential: FamilyCredential) {
        if (credential.role != PorchExperience.FAMILY) {
            val json = PorchJson.encodeToString(FamilyCredential.serializer(), credential)
            secrets.write(bedsideAccount, json.encodeToByteArray(), SecretStore.Access.AFTER_FIRST_UNLOCK)
            return
        }
        val all = families.toMutableList()
        val index = all.indexOfFirst { it.deviceID == credential.deviceID }
        if (index >= 0) all[index] = credential else all.add(credential)
        saveFamilies(all)
    }

    private val caregiverCode: String get() = secrets.read(caregiverCodeAccount)?.decodeToString() ?: ""

    // What iOS keeps as a dictionary in UserDefaults is a JSON object here.
    private fun dictionary(key: String): Map<String, JsonElement> =
        settings.getString(key)?.let { text -> decodedOrNull { PorchJson.parseToJsonElement(text) as? JsonObject } } ?: emptyMap()

    private fun setDictionary(key: String, value: Map<String, JsonElement>) = settings.putString(key, JsonObject(value).toString())

    private companion object {
        const val experienceKey = "porch.experience"
        const val bedsideAccount = "porch.family.bedside"
        const val familiesAccount = "porch.family.families"
        const val activationAccount = "porch.bedside.activation"
        const val caregiverCodeAccount = "porch.contact-setup-code"
        const val currentFamilyKey = "porch.family.current"
        const val nicknamesKey = "porch.family.nicknames"
        const val householdsKey = "porch.family.households"

        fun experienceNamed(name: String): PorchExperience? = PorchExperience.entries.firstOrNull { it.rawValue == name }

        inline fun <T> decodedOrNull(decode: () -> T): T? = try { decode() } catch (_: IllegalArgumentException) { null }
    }
}

/** The name iOS saves and the server sends: "bedside" or "family". */
internal val PorchExperience.rawValue: String
    get() = when (this) {
        PorchExperience.BEDSIDE -> "bedside"
        PorchExperience.FAMILY -> "family"
    }

private val JsonElement.string: String? get() = (this as? JsonPrimitive)?.takeIf { it.isString }?.content

private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

/** The first `count` characters as Swift counts them, so a name is never cut inside an emoji. */
private fun String.prefixCharacters(count: Int): String {
    val characters = BreakIterator.getCharacterInstance()
    characters.setText(this)
    var end = 0
    repeat(count) {
        val next = characters.next()
        if (next == BreakIterator.DONE) return this
        end = next
    }
    return substring(0, end)
}
