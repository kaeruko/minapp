package jp.cloxs.min

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val HOST_PERMISSION_CHANNEL = "jp.cloxs.min/host_permissions"
        private const val MICROPHONE_PERMISSION_REQUEST_CODE = 4101
    }

    private var pendingMicrophonePermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOST_PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophonePermission" -> requestMicrophonePermission(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        if (pendingMicrophonePermissionResult != null) {
            result.error(
                "microphone_permission_request_in_progress",
                "Another microphone permission request is already in progress.",
                null,
            )
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        pendingMicrophonePermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MICROPHONE_PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != MICROPHONE_PERMISSION_REQUEST_CODE) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }

        val pending = pendingMicrophonePermissionResult
            ?: throw IllegalStateException(
                "Microphone permission result arrived without a pending request.",
            )
        pendingMicrophonePermissionResult = null

        if (permissions.size != 1 || permissions[0] != Manifest.permission.RECORD_AUDIO) {
            pending.error(
                "unexpected_microphone_permission_result",
                "Unexpected permission result payload.",
                mapOf("permissions" to permissions.toList()),
            )
            return
        }
        if (grantResults.size != 1) {
            pending.error(
                "unexpected_microphone_permission_result",
                "Unexpected microphone grant result payload.",
                mapOf("grantResults" to grantResults.toList()),
            )
            return
        }

        pending.success(grantResults[0] == PackageManager.PERMISSION_GRANTED)
    }
}
