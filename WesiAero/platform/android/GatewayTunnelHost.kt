package com.wesi.aero.gateway

/**
 * Contract between Flutter UI and the privileged Android VpnService host.
 *
 * The implementation must delegate cryptography to pinned Xray-core and
 * AmneziaWG builds. It must never establish a TUN interface unless the chosen
 * transport engine is loaded and ready to consume packets.
 */
interface GatewayTunnelHost {
    fun preparePermission(callback: (PermissionResult) -> Unit)
    fun connect(request: TunnelRequest, callback: (Result<Unit>) -> Unit)
    fun disconnect(callback: (Result<Unit>) -> Unit)
    fun importProfile(profile: ImportedProfile, callback: (Result<Unit>) -> Unit)
    fun setListener(listener: TunnelEventListener?)
}

data class TunnelRequest(
    val nodeId: String,
    val protocol: String,
    val splitMode: String,
    val killSwitch: Boolean,
    val rules: List<RoutingRule>,
)

data class RoutingRule(
    val kind: String,
    val value: String,
)

data class ImportedProfile(
    val protocol: String,
    val displayName: String,
    val encryptedPayload: ByteArray,
)

sealed interface PermissionResult {
    data object Granted : PermissionResult
    data class RequiresUserConsent(val requestCode: Int) : PermissionResult
    data class Denied(val reason: String) : PermissionResult
}

fun interface TunnelEventListener {
    fun onEvent(event: TunnelEvent)
}

data class TunnelEvent(
    val status: String,
    val protocol: String?,
    val nodeId: String?,
    val downloadBps: Long,
    val uploadBps: Long,
    val downloadedBytes: Long,
    val uploadedBytes: Long,
    val pingMs: Int?,
    val connectedAtIso8601: String?,
    val errorCode: String?,
)
