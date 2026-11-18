const playlists = [
  "Enjoy romantic moments - jazz cafe is open",
  "High-energy battle songs - decisive clash",
  "Familiar melodies - top K-pop groups",
];
const charts = [
  ["TOP500", "2026-11-18 08:00"],
  ["Starlight Chart", "Weekly update"],
  ["Mainland Chart", "2026-11-18 10:00"],
  ["Trending", "2026-11-18 09:00"],
];
document.getElementById("playlists").innerHTML = playlists
  .map((t) => `<div class="card"><div class="thumb"></div><p>${t}</p></div>`).join("");
document.getElementById("charts").innerHTML = charts
  .map(([t, s]) => `<div class="chart"><b>${t}</b><small>${s}</small></div>`).join("");
