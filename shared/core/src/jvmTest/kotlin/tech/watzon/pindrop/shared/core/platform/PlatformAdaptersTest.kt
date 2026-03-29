package tech.watzon.pindrop.shared.core.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import tech.watzon.pindrop.shared.schemasettings.SecretSchema
import java.io.File
import java.nio.file.Files
import java.nio.file.Path

class SettingsPersistenceTest {
    private val tempDir = Files.createTempDirectory("pindrop-test")
    private val adapter = SettingsPersistence(tempDir.toString())

    @Test
    fun writeSettingsAndReadBackSameValues() {
        adapter.load()
        adapter.setString("selectedModel", "whisper-large-v3")
        adapter.setBool("launchAtLogin", true)
        adapter.setInt("currentOnboardingStep", 3)
        adapter.setDouble("contextCaptureTimeoutSeconds", 5.0)
        adapter.save()
        adapter.load()
        assertEquals("whisper-large-v3", adapter.getString("selectedModel"))
        assertTrue(adapter.getBool("launchAtLogin")!!)
        assertEquals(3, adapter.getInt("currentOnboardingStep"))
        assertEquals(5.0, adapter.getDouble("contextCaptureTimeoutSeconds")!!)
    }

    @Test
    fun readFromMissingFileReturnsNull() {
        adapter.load()
        assertNull(adapter.getString("selectedModel"))
        assertNull(adapter.getBool("launchAtLogin"))
        assertNull(adapter.getInt("currentOnboardingStep"))
    }

    @Test
    fun removeDeletesKeyFromStore() {
        adapter.load()
        adapter.setString("selectedModel", "some-model")
        adapter.save()
        adapter.remove("selectedModel")
        adapter.save()
        adapter.load()
        assertNull(adapter.getString("selectedModel"))
    }

    @Test
    fun allSettingsReturnsCurrentKeyValuePairs() {
        adapter.load()
        adapter.setString("key1", "value1")
        adapter.setBool("key2", true)
        adapter.save()
        adapter.load()
        val settings = adapter.allSettings()
        assertEquals("value1", settings["key1"])
        assertTrue(settings["key2"] as Boolean)
    }
}

class SecretStorageTest {
    private val adapter = SecretStorage()

    @Test
    fun storeSecretAndRetrieveSameSecret() {
        val stored = adapter.storeSecret("api-key-openai", SecretSchema.keychainServiceName, "sk-test-123")
        assertTrue(stored)
        val result = adapter.retrieveSecret("api-key-openai", SecretSchema.keychainServiceName)
        assertEquals("sk-test-123", result)
    }

    @Test
    fun retrieveUnknownKeyReturnsNull() {
        val result = adapter.retrieveSecret("unknown-key", SecretSchema.keychainServiceName)
        assertNull(result)
    }

    @Test
    fun deleteSecretAndRetrieveReturnsNull() {
        adapter.storeSecret("api-key-delete", SecretSchema.keychainServiceName, "to-delete")
        val deleted = adapter.deleteSecret("api-key-delete", SecretSchema.keychainServiceName)
        assertTrue(deleted)
        assertNull(adapter.retrieveSecret("api-key-delete", SecretSchema.keychainServiceName))
    }

    @Test
    fun storeSecretsInMultipleAccounts() {
        adapter.storeSecret("account-a", SecretSchema.keychainServiceName, "secret-a")
        adapter.storeSecret("account-b", SecretSchema.keychainServiceName, "secret-b")
        adapter.storeSecret("account-c", SecretSchema.keychainServiceName, "secret-c")
        assertEquals("secret-a", adapter.retrieveSecret("account-a", SecretSchema.keychainServiceName))
        assertEquals("secret-b", adapter.retrieveSecret("account-b", SecretSchema.keychainServiceName))
        assertEquals("secret-c", adapter.retrieveSecret("account-c", SecretSchema.keychainServiceName))
    }

    @Test
    fun storeOverwritesExistingSecret() {
        adapter.storeSecret("overwrite-key", SecretSchema.keychainServiceName, "original")
        adapter.storeSecret("overwrite-key", SecretSchema.keychainServiceName, "updated")
        assertEquals("updated", adapter.retrieveSecret("overwrite-key", SecretSchema.keychainServiceName))
    }

    @Test
    fun deleteNonExistentKeyReturnsFalse() {
        val result = adapter.deleteSecret("non-existent", SecretSchema.keychainServiceName)
        assertFalse(result)
    }
}

class AutostartManagerTest {
    private val tempDir = Files.createTempDirectory("pindrop-autostart-test")
    private val autostartDir = tempDir.resolve(".config/autostart")
    private val desktopFilePath = autostartDir.resolve("pindrop.desktop")
    private val manager = AutostartManager(autostartDir.toString())

    @Test
    fun enableAutostartCreatesDesktopFile() {
        val result = manager.enableAutostart()
        assertTrue(result)
        assertTrue(Files.exists(desktopFilePath))
    }

    @Test
    fun disableAutostartRemovesDesktopFile() {
        manager.enableAutostart()
        val result = manager.disableAutostart()
        assertTrue(result)
        assertFalse(Files.exists(desktopFilePath))
    }

    @Test
    fun isAutostartEnabledReflectsFileExistence() {
        assertFalse(manager.isAutostartEnabled())
        manager.enableAutostart()
        assertTrue(manager.isAutostartEnabled())
        manager.disableAutostart()
        assertFalse(manager.isAutostartEnabled())
    }
}
