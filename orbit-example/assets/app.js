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

document.querySelector("#save-file").addEventListener("click", async () => {
  const selection = document.querySelector("#selection");
  selection.textContent = "";
  try {
    const response = await window.__ORBIT__.invoke("orbit.dialog.save", {
      title: "Save an Orbit text copy",
      default_name: "orbit-example.txt",
      filters: [{ name: "Text files", extensions: ["txt"] }]
    });
    if (response.cancelled) {
      selection.textContent = "Save cancelled.";
    } else {
      const file = response.files[0];
      const saved = await window.__ORBIT__.invoke("orbit.fs.write_text", {
        id: file.id,
        text: "Saved by the Orbit handle-bound file capability.\n"
      });
      selection.textContent = `${file.name} (${saved.size} bytes, ${file.id})`;
    }
  } catch (error) {
    selection.textContent = `IPC error: ${error.code}`;
  }
});

document.querySelector("#pick-directory").addEventListener("click", async () => {
  const selection = document.querySelector("#selection");
  selection.textContent = "";
  document.querySelector("#directory-entries").replaceChildren();
  try {
    const response = await window.__ORBIT__.invoke("orbit.dialog.pick_directory", {
      title: "Choose a folder to inspect"
    });
    if (response.cancelled) {
      selection.textContent = "Folder selection cancelled.";
    } else {
      await showDirectory(response.files[0]);
    }
  } catch (error) {
    selection.textContent = `IPC error: ${error.code}`;
  }
});

async function showDirectory(directory) {
  const selection = document.querySelector("#selection");
  const entries = document.querySelector("#directory-entries");
  const listing = await window.__ORBIT__.invoke("orbit.fs.read_directory", {
    id: directory.id
  });
  selection.textContent = `${directory.name}: ${listing.entries.length || "empty folder"}`;
  entries.replaceChildren();
  for (const entry of listing.entries) {
    const row = document.createElement("div");
    row.className = "directory-entry";
    if (entry.id) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = entry.name;
      button.addEventListener("click", async () => {
        try {
          if (entry.kind === "directory") {
            await showDirectory({ id: entry.id, name: entry.name });
          } else {
            const content = await window.__ORBIT__.invoke("orbit.fs.read_text", {
              id: entry.id
            });
            selection.textContent = `${entry.name}: ${content.size} bytes`;
          }
        } catch (error) {
          selection.textContent = `IPC error: ${error.code}`;
        }
      });
      row.append(button);
    } else {
      row.textContent = entry.name;
    }
    entries.append(row);
  }
}
