const state = document.querySelector("#state");
const status = document.querySelector("#status");
const save = document.querySelector("#save");

async function saveState() {
  save.disabled = true;
  try {
    await window.__ORBIT__.invoke("lifecycle.state.save", { value: state.value });
    status.textContent = "State saved in the MoonBit application.";
  } catch (error) {
    status.textContent = `Save failed: ${error.code ?? "unknown"}`;
  } finally {
    save.disabled = false;
  }
}

async function loadState() {
  try {
    const saved = await window.__ORBIT__.invoke("lifecycle.state.load", {});
    state.value = saved.value ?? "";
    status.textContent = "Saved state restored.";
  } catch (error) {
    status.textContent = `Restore failed: ${error.code ?? "unknown"}`;
  }
}

save.addEventListener("click", saveState);
state.addEventListener("change", saveState);

document.querySelector("#pick-file").addEventListener("click", async () => {
  try {
    const response = await window.__ORBIT__.invoke("orbit.dialog.open", {
      title: "Choose a file",
      filters: [{ name: "Text files", extensions: ["txt", "md"] }],
    });
    status.textContent = response.cancelled
      ? "File selection cancelled."
      : `Selected ${response.files[0].name}.`;
  } catch (error) {
    status.textContent = `File picker failed: ${error.code ?? "unknown"}`;
  }
});

document.querySelector("#print-page").addEventListener("click", async () => {
  try {
    await window.__ORBIT__.invoke("orbit.window.print", {});
    status.textContent = "Print dialog opened.";
  } catch (error) {
    status.textContent = `Print failed: ${error.code ?? "unknown"}`;
  }
});

loadState();
