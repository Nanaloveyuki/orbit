document.querySelector("#action").addEventListener("click", async () => {
  try {
    const response = await window.__ORBIT__.invoke("example.ping");
    document.querySelector("#message").textContent = response.message;
  } catch (error) {
    document.querySelector("#message").textContent = `IPC error: ${error.code}`;
  }
});
