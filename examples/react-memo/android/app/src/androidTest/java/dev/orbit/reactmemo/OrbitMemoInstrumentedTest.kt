package dev.orbit.reactmemo

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class OrbitMemoInstrumentedTest {
  @Test
  fun embeddedReactAppCompletesOrbitIpcRoundTrip() {
    ActivityScenario.launch(MainActivity::class.java).use { scenario ->
      val webView = waitForWebView(scenario)
      assertNotNull("Orbit WebView was not attached", webView)
      waitForPage(scenario, requireNotNull(webView))

      val result = arrayOfNulls<String>(1)
      val completed = CountDownLatch(1)
      scenario.onActivity {
        webView.evaluateJavascript(
          "window.__ORBIT__.invoke('memo.runtime', {}, { timeout: 3000 }).then(runtime => JSON.stringify({ runtime, reactMounted: document.body.innerText.includes('Orbit Memo') })).catch(error => 'ERROR:' + error.message)",
        ) { value ->
          result[0] = value
          completed.countDown()
        }
      }
      assertTrue("Orbit IPC invocation timed out", completed.await(5, TimeUnit.SECONDS))
      assertTrue("Orbit IPC did not report the native runtime: ${result[0]}", result[0].orEmpty().contains("\\\"runtime\\\":\\\"Orbit\\\""))
      assertTrue("Orbit React application did not mount: ${result[0]}", result[0].orEmpty().contains("\\\"reactMounted\\\":true"))
    }
  }

  private fun waitForWebView(scenario: ActivityScenario<MainActivity>): WebView? {
    repeat(100) {
      var candidate: WebView? = null
      scenario.onActivity { activity ->
        candidate = findWebView(activity.findViewById(android.R.id.content))
      }
      if (candidate != null) return candidate
      Thread.sleep(50)
    }
    return null
  }

  private fun waitForPage(scenario: ActivityScenario<MainActivity>, webView: WebView) {
    repeat(100) {
      var loaded = false
      scenario.onActivity {
        loaded = webView.url == "https://orbit.local/assets/index.html" && webView.progress == 100
      }
      if (loaded) return
      Thread.sleep(50)
    }
    throw AssertionError("Orbit embedded page did not finish loading")
  }

  private fun findWebView(view: View): WebView? {
    if (view is WebView) return view
    if (view is ViewGroup) {
      for (index in 0 until view.childCount) {
        findWebView(view.getChildAt(index))?.let { return it }
      }
    }
    return null
  }
}
