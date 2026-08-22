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

      scenario.onActivity {
        webView.evaluateJavascript(
          "window.__orbitTestResult = null; Promise.resolve().then(() => window.__ORBIT__.invoke('memo.runtime', {}, { timeout: 3000 })).then(runtime => { window.__orbitTestResult = JSON.stringify({ runtime, reactMounted: document.body.innerText.includes('Orbit Memo') }); }).catch(error => { window.__orbitTestResult = 'ERROR:' + error.message; });",
          null,
        )
      }
      val result = waitForJavascriptValue(scenario, webView, "window.__orbitTestResult")
      assertTrue("Orbit IPC did not report the native runtime: $result", result.contains("\\\"runtime\\\":\\\"Orbit\\\""))
      assertTrue("Orbit React application did not mount: $result", result.contains("\\\"reactMounted\\\":true"))
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

  private fun waitForJavascriptValue(
    scenario: ActivityScenario<MainActivity>,
    webView: WebView,
    expression: String,
  ): String {
    repeat(100) {
      val completed = CountDownLatch(1)
      var result: String? = null
      scenario.onActivity {
        webView.evaluateJavascript(expression) { value ->
          result = value
          completed.countDown()
        }
      }
      if (completed.await(1, TimeUnit.SECONDS) && result != null && result != "null") {
        return requireNotNull(result)
      }
      Thread.sleep(50)
    }
    throw AssertionError("JavaScript result did not become available")
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
