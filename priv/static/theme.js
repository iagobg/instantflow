try {
  const saved = localStorage.getItem("instantflow-theme");
  if (saved === "light" || saved === "dark") document.documentElement.dataset.theme = saved;
} catch (_) {}
document.addEventListener("click", (event) => {
  if (!event.target.closest("#theme-toggle")) return;
  const current = document.documentElement.dataset.theme || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const next = current === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem("instantflow-theme", next); } catch (_) {}
});
