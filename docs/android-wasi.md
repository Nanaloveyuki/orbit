# Android WASI Integration

Orbit Android remains a native MoonBit and JNI/WebView application. A
core-Wasm guest is therefore hosted by the Android JVM side, not imported into
the native Orbit MoonBit target.

The optional integration boundary is:

~~~text
Orbit Activity
  -> WaseeHostSession
  -> wasee-moon android/host library
  -> Chicory WASI Preview 1
  -> Wasee bridge package
  -> madk transport and AoaSession
  -> Android UsbManager
~~~

The Wasee library owns the bounded USB host, Chicory runner, error/status
mapping, and AOA re-enumeration behavior. Orbit owns Activity lifecycle,
permission UI, application policy, and the frontend IPC surface. Neither side
copies madk protocol code.

The React memo Android example has an opt-in source set under
examples/react-memo/android/app/src/wasee. It is excluded from the normal
Orbit build. To compile the integration against a sibling Wasee checkout:

~~~text
gradle -PwaseeAndroidDir=<path-to-wasee-moon>/android :app:assembleDebug --no-daemon
~~~

The optional build also needs MoonBit 0.10.9, Android platform 36, and Build
Tools 37.0.0 in addition to the normal Orbit Android toolchain. The Gradle task
updates the Wasee checkout before building its guest artifact.

The build then:

1. includes Wasee's host library through a Gradle composite dependency;
2. builds the Wasee guest wasm artifact;
3. copies that artifact into the Orbit app's ignored Wasee asset directory;
4. compiles WaseeHostSession against the reusable host facade.

This is an integration build contract, not a desktop Orbit dependency. The
standard Android preview build remains independent of Wasee and does not make
Android a desktop beta support target.
