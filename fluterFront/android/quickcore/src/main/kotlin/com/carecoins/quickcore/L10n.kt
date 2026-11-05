package com.carecoins.quickcore

import android.content.Context
import android.content.res.Configuration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

object L10n {
    const val PREF_LANGUAGE = QuickCore.PREF_LANGUAGE

    fun setLanguage(context: Context, code: String?) {
        val editor = DeviceKeyStore.prefs(context).edit()
        if (!code.isNullOrBlank()) {
            editor.putString(PREF_LANGUAGE, code)
        } else {
            editor.remove(PREF_LANGUAGE)
        }
        editor.apply()
    }

    fun getLanguage(context: Context): String? {
        return runCatching {
            DeviceKeyStore.prefs(context).getString(PREF_LANGUAGE, null)?.takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    fun resourceName(key: String): String = key.replace('.', '_')

    private fun resolveLocale(context: Context): Locale {
        val code = getLanguage(context)
        if (!code.isNullOrBlank()) {
            return Locale.forLanguageTag(code)
        }
        val config = runCatching { context.resources?.configuration }.getOrNull()
        val locales = config?.locales
        if (locales != null && !locales.isEmpty) {
            return locales[0]
        }
        return Locale.getDefault()
    }

    private fun localizedContext(context: Context): Context {
        val code = getLanguage(context)
        if (code.isNullOrBlank()) return context
        return runCatching {
            val locale = Locale.forLanguageTag(code)
            val baseConfig = context.resources?.configuration
            val config = if (baseConfig != null) Configuration(baseConfig) else Configuration()
            config.setLocale(locale)
            context.createConfigurationContext(config) ?: context
        }.getOrDefault(context)
    }

    fun t(context: Context, key: String, vararg args: Any): String {
        val resName = resourceName(key)
        val locCtx = localizedContext(context)
        val resId = runCatching {
            R.string::class.java.getDeclaredField(resName).getInt(null)
        }.getOrElse {
            runCatching {
                locCtx.resources.getIdentifier(resName, "string", locCtx.packageName)
            }.getOrDefault(0)
        }
        if (resId == 0) return key
        return runCatching {
            if (args.isEmpty()) {
                locCtx.getString(resId)
            } else {
                locCtx.getString(resId, *args)
            }
        }.getOrDefault(key)
    }

    @JvmOverloads
    fun shortTime(
        context: Context,
        instant: Instant,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): String {
        val locale = resolveLocale(context)
        val formatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)
        return instant.atZone(zoneId).format(formatter)
    }
}
