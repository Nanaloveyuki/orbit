window.moonview.onmessage = event => {
  const response = JSON.parse(event.data);
  const text = response.ok
    ? response.result.message
    : `IPC error: ${response.error.code}`;
  document.querySelector("#message").textContent = text;
};

document.querySelector("#action").addEventListener("click", () => {
  window.moonview.postMessage(JSON.stringify({
    version: 1,
    id: "example-ping",
    command: "example.ping",
    payload: null,
  }));
});
