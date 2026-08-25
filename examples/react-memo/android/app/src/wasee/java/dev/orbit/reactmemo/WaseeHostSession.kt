package dev.orbit.reactmemo

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.hardware.usb.UsbDevice
import dev.nanaloveyuki.wasee.host.GuestRunResult
import dev.nanaloveyuki.wasee.host.UsbAllowlistEntry
import dev.nanaloveyuki.wasee.host.WaseeHostController

/**
 * Optional Orbit Android integration compiled when waseeAndroidDir is set.
 *
 * Orbit owns Activity lifecycle and permission UI. Wasee owns Chicory, the
 * bounded Android USB host, and the guest-to-madk bridge.
 */
class WaseeHostSession(
  private val activity: Activity,
  private val onLine: (String) -> Unit,
) : AutoCloseable {
  private val controller = WaseeHostController(
    context = activity,
    allowlist = setOf(
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D00),
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D01),
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D02),
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D03),
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D04),
      UsbAllowlistEntry(vendorId = 0x18D1, productId = 0x2D05),
      UsbAllowlistEntry(vendorId = 0x346D, productId = 0x5678),
    ),
    onLine = onLine,
  )

  fun firstDeviceWithoutPermission(): UsbDevice? =
    controller.firstDeviceWithoutPermission()

  fun requestPermission(device: UsbDevice, action: String) {
    val permissionIntent = PendingIntent.getBroadcast(
      activity,
      0,
      Intent(action).setPackage(activity.packageName),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    controller.requestPermission(device, permissionIntent)
  }

  fun runGuest(): GuestRunResult =
    activity.assets.open("wasee/guest.wasm").use { input ->
      controller.runGuest(input)
    }

  override fun close() {
    controller.close()
  }
}
