document.querySelector("#action").addEventListener("click", async () => {
  try {
    const response = await window.__ORBIT__.invoke("example.ping");
    document.querySelector("#message").textContent = response.message;
  } catch (error) {
    document.querySelector("#message").textContent = `IPC error: ${error.code}`;
  }
});

document.querySelector("#pick-file").addEventListener("click", async () => {
  const selection = document.querySelector("#selection");
  selection.textContent = "";
  try {
    const response = await window.__ORBIT__.invoke("orbit.dialog.open", {
      title: "Choose a file",
      filters: [{ name: "Text and source files", extensions: ["txt", "md", "mbt"] }]
    });
    if (response.cancelled) {
      selection.textContent = "Selection cancelled.";
    } else {
      const file = response.files[0];
      const content = await window.__ORBIT__.invoke("orbit.fs.read_text", { id: file.id });
      selection.textContent = `${file.name} (${content.size} bytes, ${file.id})`;
    }
  } catch (error) {
    selection.textContent = `IPC error: ${error.code}`;
  }
});
