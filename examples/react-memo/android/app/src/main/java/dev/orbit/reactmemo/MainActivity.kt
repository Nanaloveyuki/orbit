package dev.orbit.reactmemo

import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import androidx.activity.ComponentActivity
import dev.nanaloveyuki.ajni.host.NativeBridge

class MainActivity : ComponentActivity() {
  private lateinit var webViewContainer: FrameLayout
  private val layoutListener = View.OnLayoutChangeListener { view, left, top, right, bottom, _, _, _, _ ->
    val width = right - left
    val height = bottom - top
    if (width > 0 && height > 0) NativeBridge.surfaceChanged(width, height)
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    NativeBridge.initialize(this)
    webViewContainer = FrameLayout(this)
    setContentView(webViewContainer)
    NativeBridge.attachWebViewContainer(webViewContainer)
    webViewContainer.addOnLayoutChangeListener(layoutListener)
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_CREATED)
  }

  override fun onStart() {
    super.onStart()
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_STARTED)
  }

  override fun onResume() {
    super.onResume()
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_RESUMED)
  }

  override fun onPause() {
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_PAUSED)
    super.onPause()
  }

  override fun onStop() {
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_STOPPED)
    super.onStop()
  }

  override fun onDestroy() {
    webViewContainer.removeOnLayoutChangeListener(layoutListener)
    NativeBridge.lifecycle(NativeBridge.LIFECYCLE_DESTROYED)
    NativeBridge.detachWebViewContainer(webViewContainer)
    NativeBridge.shutdown()
    super.onDestroy()
  }
}
