///|
test "MoonView factory is usable through the runtime abstraction" {
  let factory = @orbit-runtime-moonview.MoonViewRuntimeFactory::new()
    as &@orbit_runtime.RuntimeFactory
  ignore(factory)
}
