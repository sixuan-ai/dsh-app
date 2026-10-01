package dev.dsh.dsh_mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.TimeUnit
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Credentials
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val nativeProbeClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.SECONDS)
        .build()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // mDNS discovery (multicast_dns) needs a multicast lock on Android:
        // without it the socket never receives multicast responses.
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            wifi.createMulticastLock("dsh-mdns").apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (_: Exception) {
            // Multicast stays unavailable; discovery degrades gracefully.
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.dsh.dsh_mobile/installer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Hands a downloaded APK to the system package installer.
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad-arg", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileProvider",
                            File(path),
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                            )
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install-failed", e.message, null)
                    }
                }
                // Whether the user already granted install-unknown-apps.
                "canInstallApk" ->
                    result.success(packageManager.canRequestPackageInstalls())
                // Opens the system page granting install-unknown-apps to us.
                "requestInstallPermission" -> {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings-failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.dsh.dsh_mobile/native_network",
        ).setMethodCallHandler { call, result ->
            if (call.method != "probeDsh") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrEmpty()) {
                result.error("bad-arg", "url required", null)
                return@setMethodCallHandler
            }
            probeDsh(
                url = url,
                username = call.argument<String>("username"),
                password = call.argument<String>("password"),
                result = result,
            )
        }
    }

    private fun probeDsh(
        url: String,
        username: String?,
        password: String?,
        result: MethodChannel.Result,
    ) {
        val startedAt = System.nanoTime()
        val rpcId = "native-${System.currentTimeMillis()}"
        val payload =
            """{"type":"client-request","rpcId":"$rpcId","method":"host.describe","payload":{}}"""
        val requestBuilder = Request.Builder()
            .url(url.trimEnd('/') + "/api/host.describe")
            .post(payload.toRequestBody("application/json".toMediaType()))
        if (!username.isNullOrEmpty()) {
            requestBuilder.header("Authorization", Credentials.basic(username, password.orEmpty()))
        }
        nativeProbeClient.newCall(requestBuilder.build()).enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "ok" to false,
                            "elapsedMs" to elapsedMs,
                            "errorType" to error.javaClass.name,
                            "error" to (error.message ?: error.toString()),
                        ),
                    )
                }
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)
                    val body = it.body?.string().orEmpty()
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "ok" to it.isSuccessful,
                                "statusCode" to it.code,
                                "elapsedMs" to elapsedMs,
                                "body" to body.take(500),
                            ),
                        )
                    }
                }
            }
        })
    }
}
