/* TurfZone front-end: vanilla JS talking to the FastAPI backend */
const $ = (s) => document.querySelector(s);
const state = { user: null, users: [], sports: [], turfs: [], bk: null, reviewTurf: null };
const EMOJI = { Football: "⚽", Cricket: "🏏", Badminton: "🏸", Pickleball: "🏓", Basketball: "🏀", Tennis: "🎾" };
const money = (n) => "₹" + Number(n).toLocaleString("en-IN");
const t5 = (s) => String(s).slice(0, 5);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const modal = (id) => bootstrap.Modal.getOrCreateInstance(document.getElementById(id));
const fmtDate = (d) => new Date(d + "T00:00:00").toLocaleDateString("en-IN", { weekday: "short", day: "numeric", month: "short", year: "numeric" });
const today = () => { const d = new Date(); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); return d.toISOString().slice(0, 10); };

async function api(path, opts = {}) {
  const res = await fetch("/api" + path, {
    headers: { "Content-Type": "application/json" }, ...opts,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const d = data.detail;
    throw new Error(Array.isArray(d) ? d.map((x) => x.loc.slice(-1) + ": " + x.msg).join(", ") : d || "Request failed");
  }
  return data;
}
function toast(msg, ok = true) {
  const el = document.createElement("div");
  el.className = `toast align-items-center text-bg-${ok ? "success" : "danger"} border-0`;
  el.innerHTML = `<div class="d-flex"><div class="toast-body">${esc(msg)}</div><button class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button></div>`;
  $("#toasts").appendChild(el);
  const t = new bootstrap.Toast(el, { delay: 4000 }); t.show();
  el.addEventListener("hidden.bs.toast", () => el.remove());
}
const run = (fn) => async (...a) => { try { await fn(...a); } catch (e) { toast(e.message, false); } };

/* ---------------- navigation ---------------- */
function show(page) {
  if ((page === "admin" || page === "lab") && state.user?.role !== "admin") {
    page = "turfs";
  }
  document.querySelectorAll(".page").forEach((p) => p.classList.add("d-none"));
  $("#page-" + page).classList.remove("d-none");
  document.querySelectorAll("[data-page]").forEach((a) => a.classList.toggle("active", a.dataset.page === page && a.classList.contains("nav-link")));
  if (page === "turfs") loadTurfs();
  if (page === "bookings") loadMyBookings();
  if (page === "admin") loadAdmin();
  if (page === "lab") loadLab();
}
document.querySelectorAll("[data-page]").forEach((a) => a.addEventListener("click", (e) => { e.preventDefault(); show(a.dataset.page); }));

/* ---------------- users ---------------- */
async function loadUsers(selectId) {
  state.users = await api("/users");
  $("#userSelect").innerHTML = state.users.map((u) => `<option value="${u.user_id}">${esc(u.full_name)}${u.role === "admin" ? " (admin)" : ""}</option>`).join("");
  const saved = selectId || Number(localStorage.getItem("turfUser")) || (state.users.find((u) => u.role === "customer") || state.users[0]).user_id;
  setUser(saved);
}
function setUser(id) {
  state.user = state.users.find((u) => u.user_id == id) || state.users[0];
  $("#userSelect").value = state.user.user_id;
  try { localStorage.setItem("turfUser", state.user.user_id); } catch (e) {}
  const isAdmin = state.user && state.user.role === "admin";
  const adminLink = $("#adminLink");
  const labLink = $("#labLink");
  if (adminLink) {
    if (isAdmin) adminLink.classList.remove("d-none");
    else adminLink.classList.add("d-none");
  }
  if (labLink) {
    if (isAdmin) labLink.classList.remove("d-none");
    else labLink.classList.add("d-none");
  }
}
$("#userSelect").addEventListener("change", (e) => {
  setUser(e.target.value);
  const cur = document.querySelector(".page:not(.d-none)").id.replace("page-", "");
  show((cur === "admin" || cur === "lab") && state.user.role !== "admin" ? "turfs" : cur);
});
function openUserModal() { ["umName", "umEmail", "umPhone"].forEach((i) => ($("#" + i).value = "")); modal("userModal").show(); }
const saveUser = run(async () => {
  const u = await api("/users", { method: "POST", body: { full_name: $("#umName").value.trim(), email: $("#umEmail").value.trim(), phone: $("#umPhone").value.trim() } });
  modal("userModal").hide(); await loadUsers(u.user_id); toast(`Welcome, ${u.full_name}!`); show("turfs");
});

/* ---------------- turfs ---------------- */
async function loadFilters() {
  state.sports = await api("/sports");
  const cities = await api("/cities");
  $("#fCity").innerHTML = '<option value="">All cities</option>' + cities.map((c) => `<option>${esc(c.city)}</option>`).join("");
  $("#fSport").innerHTML = '<option value="">All sports</option>' + state.sports.map((s) => `<option>${esc(s.sport_name)}</option>`).join("");
}
const stars = (r) => (Number(r) ? `<span class="star">★</span> ${Number(r).toFixed(1)}` : '<span class="text-muted">New</span>');
const loadTurfs = run(async () => {
  const p = new URLSearchParams({ sort: $("#fSort").value });
  if ($("#fSearch").value.trim()) p.set("q", $("#fSearch").value.trim());
  if ($("#fCity").value) p.set("city", $("#fCity").value);
  if ($("#fSport").value) p.set("sport", $("#fSport").value);
  if ($("#fPrice").value) p.set("max_price", $("#fPrice").value);
  state.turfs = await api("/turfs?" + p);
  $("#turfGrid").innerHTML = state.turfs.length ? state.turfs.map((t) => `
    <div class="col-md-6 col-lg-4"><div class="card turf-card h-100">
      <div class="turf-banner">${EMOJI[t.sport_list[0]?.name] || "🏟️"}<span class="price">${money(t.price_per_hour)}/hr</span></div>
      <div class="card-body d-flex flex-column">
        <div class="d-flex justify-content-between"><h5 class="mb-0">${esc(t.name)}</h5><div>${stars(t.avg_rating)} <small class="text-muted">(${t.review_count})</small></div></div>
        <div class="text-muted small mb-2">📍 ${esc(t.area)}, ${esc(t.city)} · 👥 up to ${t.capacity}</div>
        <div class="mb-2">${t.sport_list.map((s) => `<span class="sport-chip">${EMOJI[s.name] || ""} ${esc(s.name)}</span>`).join("")}</div>
        <p class="small text-muted flex-grow-1">${esc(t.description)}</p>
        <button class="btn btn-success w-100" onclick="openBooking(${t.turf_id})">Book a slot</button>
      </div></div></div>`).join("") : '<p class="text-center text-muted py-5">No turfs match your filters.</p>';
});
["fSearch", "fPrice"].forEach((i) => $("#" + i).addEventListener("input", () => { clearTimeout(window._t); window._t = setTimeout(loadTurfs, 300); }));
["fCity", "fSport", "fSort"].forEach((i) => $("#" + i).addEventListener("change", loadTurfs));

/* ---------------- booking flow ---------------- */
const openBooking = run(async (id) => {
  const t = state.turfs.find((x) => x.turf_id === id);
  state.bk = { turf: t, hour: null, slots: [] };
  $("#bkTitle").textContent = `${t.name} - ${t.area}, ${t.city}`;
  $("#bkDesc").textContent = t.description || "";
  $("#bkSport").innerHTML = t.sport_list.map((s) => `<option value="${s.id}">${EMOJI[s.name] || ""} ${esc(s.name)}</option>`).join("");
  $("#bkDate").min = $("#bkDate").value = today(); $("#bkHours").value = "1";
  const reviews = await api(`/turfs/${id}/reviews`);
  $("#bkReviews").innerHTML = reviews.length ? "<strong>Recent reviews</strong>" + reviews.slice(0, 3).map((r) =>
    `<div><span class="star">${"★".repeat(r.rating)}</span> ${esc(r.comment || "")} <em class="text-muted">- ${esc(r.full_name)}</em></div>`).join("") : "";
  modal("bookModal").show(); await loadSlots();
});
const loadSlots = run(async () => {
  const b = state.bk; b.hour = null;
  b.slots = await api(`/turfs/${b.turf.turf_id}/slots?date=${$("#bkDate").value}`);
  renderSlots();
});
function fits(h, n) { return Array.from({ length: n }, (_, i) => state.bk.slots.find((s) => s.hour === h + i)).every((s) => s && s.available); }
function renderSlots() {
  const b = state.bk, n = Number($("#bkHours").value);
  $("#slotGrid").innerHTML = b.slots.map((s) => {
    const sel = b.hour !== null && s.hour >= b.hour && s.hour < b.hour + n;
    return `<button class="slot ${sel ? (s.hour === b.hour ? "selected" : "inrange") : ""}" ${s.available ? "" : "disabled"} onclick="pickSlot(${s.hour})">${s.label}</button>`;
  }).join("");
  const wk = [0, 6].includes(new Date($("#bkDate").value + "T00:00:00").getDay());
  const total = b.turf.price_per_hour * n * (wk ? 1.2 : 1);
  $("#bkTotal").textContent = money(total);
  $("#bkNote").textContent = wk ? "Weekend rate applied (+20%)" : "Weekday rate";
  $("#bkConfirm").disabled = b.hour === null;
}
function pickSlot(h) {
  const n = Number($("#bkHours").value);
  if (!fits(h, n)) return toast(`${n} hour(s) from ${String(h).padStart(2, "0")}:00 overlaps a booked or closed slot`, false);
  state.bk.hour = h; renderSlots();
}
$("#bkDate").addEventListener("change", loadSlots);
$("#bkHours").addEventListener("change", () => { const b = state.bk; if (b.hour !== null && !fits(b.hour, Number($("#bkHours").value))) b.hour = null; renderSlots(); });
$("#bkConfirm").addEventListener("click", run(async () => {
  const b = state.bk;
  await api("/bookings", { method: "POST", body: {
    user_id: state.user.user_id, turf_id: b.turf.turf_id, sport_id: Number($("#bkSport").value), date: $("#bkDate").value,
    start: String(b.hour).padStart(2, "0") + ":00", hours: Number($("#bkHours").value), method: $("#bkMethod").value } });
  modal("bookModal").hide(); toast("Booking confirmed! See you on the turf 🎉"); show("bookings");
}));

/* ---------------- my bookings ---------------- */
const badge = (s) => `<span class="badge text-bg-${{ CONFIRMED: "success", COMPLETED: "secondary", CANCELLED: "danger" }[s]}">${s}</span>`;
const loadMyBookings = run(async () => {
  const rows = await api("/bookings?user_id=" + state.user.user_id); state.myBookings = rows;
  $("#myBookings").innerHTML = rows.length ? rows.map((b) => `<tr>
    <td>${b.booking_id}</td><td><strong>${esc(b.turf_name)}</strong><div class="small text-muted">${esc(b.area)}, ${esc(b.city)}</div></td>
    <td>${esc(b.sport_name || "-")}</td><td>${fmtDate(b.booking_date)}</td><td>${t5(b.start_time)} - ${t5(b.end_time)}</td>
    <td>${money(b.total_amount)}</td><td>${badge(b.status)}</td><td>${esc(b.payment_method || "")} <small class="text-muted">${esc(b.payment_status || "")}</small></td>
    <td class="text-nowrap">${b.status === "CONFIRMED" ? `<button class="btn btn-sm btn-outline-primary" onclick="openReschedule(${b.booking_id})">Reschedule</button>
      <button class="btn btn-sm btn-outline-danger" onclick="cancelBooking(${b.booking_id})">Cancel</button>` : ""}
      ${b.status === "COMPLETED" ? `<button class="btn btn-sm btn-outline-warning" onclick="openReview(${b.user_id},${b.turf_id},'${esc(b.turf_name).replace(/'/g, "")}')">★ Review</button>` : ""}</td></tr>`).join("")
    : '<tr><td colspan="9" class="text-center text-muted py-4">No bookings yet - go find a turf!</td></tr>';
});
const cancelBooking = run(async (id) => {
  if (!confirm("Cancel this booking? A refund will be initiated.")) return;
  toast((await api(`/bookings/${id}/cancel`, { method: "PUT" })).message); loadMyBookings();
});
function openReschedule(id) {
  const b = state.myBookings ? state.myBookings.find((x) => x.booking_id === id) : null;
  $("#rsBookingId").value = id;
  $("#rsDate").min = today();
  $("#rsDate").value = b ? b.booking_date : today();
  $("#rsStart").value = b ? t5(b.start_time) : "18:00";
  $("#rsDetails").textContent = b ? `${b.turf_name} (Current: ${fmtDate(b.booking_date)}, ${t5(b.start_time)} - ${t5(b.end_time)})` : `Booking #${id}`;
  modal("rescheduleModal").show();
}

const confirmReschedule = run(async () => {
  const id = $("#rsBookingId").value;
  const date = $("#rsDate").value;
  const start = $("#rsStart").value;
  if (!date || !start) {
    toast("Please choose a date and start time.", false);
    return;
  }
  const res = await api(`/bookings/${id}/reschedule`, { method: "PUT", body: { date, start } });
  modal("rescheduleModal").hide();
  toast(res.message);
  loadMyBookings();
});
function openReview(uid, tid, name) { state.reviewTurf = { uid, tid }; $("#rvTitle").textContent = "Review " + name; $("#rvComment").value = ""; modal("reviewModal").show(); }
const saveReview = run(async () => {
  const r = state.reviewTurf;
  toast((await api("/reviews", { method: "POST", body: { user_id: r.uid, turf_id: r.tid, rating: Number($("#rvRating").value), comment: $("#rvComment").value } })).message);
  modal("reviewModal").hide();
});

/* ---------------- admin ---------------- */
const loadAdmin = run(async () => {
  if (state.user.role !== "admin") return show("turfs");
  const [d, turfs, bookings, users] = await Promise.all([api("/dashboard"), api("/turfs?include_inactive=true&sort=name"), api("/bookings"), api("/users")]);
  const kpi = (label, val, bg) => `<div class="col-6 col-lg-3"><div class="card kpi p-3" style="background:${bg}"><div>${label}</div><div class="num">${val}</div></div></div>`;
  $("#kpis").innerHTML = kpi("Active turfs", d.turfs, "#15803d") + kpi("Customers", d.customers, "#0369a1") + kpi("Upcoming bookings", d.upcoming, "#b45309") + kpi("Revenue collected", money(d.revenue), "#7c3aed");
  state.turfs = turfs;
  $("#adminTurfs").innerHTML = turfs.map((t) => `<tr><td>${t.turf_id}</td><td>${esc(t.name)}</td><td>${esc(t.area)}, ${esc(t.city)}</td><td>${money(t.price_per_hour)}</td>
    <td>${t.sport_list.map((s) => esc(s.name)).join(", ")}</td><td>${t.total_bookings}</td><td>${money(t.revenue)}</td>
    <td>${t.is_active ? '<span class="badge text-bg-success">Active</span>' : '<span class="badge text-bg-secondary">Hidden</span>'}</td>
    <td class="text-nowrap"><button class="btn btn-sm btn-outline-primary" onclick="openTurfModal(${t.turf_id})">Edit</button>
      <button class="btn btn-sm btn-outline-secondary" onclick="toggleTurf(${t.turf_id})">${t.is_active ? "Hide" : "Show"}</button>
      <button class="btn btn-sm btn-outline-danger" onclick="deleteTurf(${t.turf_id})">Delete</button></td></tr>`).join("");
  $("#adminBookings").innerHTML = bookings.map((b) => `<tr><td>${b.booking_id}</td><td>${esc(b.full_name)}</td><td>${esc(b.turf_name)}</td><td>${fmtDate(b.booking_date)}</td>
    <td>${t5(b.start_time)}-${t5(b.end_time)}</td><td>${money(b.total_amount)}</td><td>${badge(b.status)}</td>
    <td><button class="btn btn-sm btn-outline-danger" onclick="deleteBooking(${b.booking_id})">Delete</button></td></tr>`).join("");
  $("#adminUsers").innerHTML = users.map((u) => `<tr><td>${u.user_id}</td><td>${esc(u.full_name)}</td><td>${esc(u.email)}</td><td>${esc(u.phone)}</td>
    <td><span class="badge text-bg-${u.role === "admin" ? "warning" : "light"}">${u.role}</span></td><td>${u.bookings}</td>
    <td><button class="btn btn-sm btn-outline-danger" onclick="deleteUser(${u.user_id})">Delete</button></td></tr>`).join("");
});
function openTurfModal(id) {
  const t = state.turfs.find((x) => x.turf_id === id) || { name: "", city: "", area: "", price_per_hour: "", capacity: "", description: "", sport_list: [] };
  $("#tmTitle").textContent = id ? "Edit turf" : "Add turf"; $("#tmId").value = id || "";
  $("#tmName").value = t.name; $("#tmCity").value = t.city; $("#tmArea").value = t.area; $("#tmPrice").value = t.price_per_hour; $("#tmCap").value = t.capacity; $("#tmDesc").value = t.description || "";
  $("#tmSports").innerHTML = state.sports.map((s) => `<div class="form-check"><input class="form-check-input" type="checkbox" value="${s.sport_id}" id="sp${s.sport_id}" ${t.sport_list.some((x) => x.id === s.sport_id) ? "checked" : ""}>
    <label class="form-check-label" for="sp${s.sport_id}">${esc(s.sport_name)}</label></div>`).join("");
  modal("turfModal").show();
}
const saveTurf = run(async () => {
  const id = $("#tmId").value;
  const body = { name: $("#tmName").value.trim(), city: $("#tmCity").value.trim(), area: $("#tmArea").value.trim(), price_per_hour: Number($("#tmPrice").value),
    capacity: Number($("#tmCap").value), description: $("#tmDesc").value.trim(), sport_ids: [...document.querySelectorAll("#tmSports input:checked")].map((c) => Number(c.value)),
    is_active: id ? state.turfs.find((x) => x.turf_id == id).is_active : true };
  await api(id ? `/turfs/${id}` : "/turfs", { method: id ? "PUT" : "POST", body });
  modal("turfModal").hide(); toast("Turf saved"); loadAdmin(); loadFilters();
});
const toggleTurf = run(async (id) => { await api(`/turfs/${id}/toggle`, { method: "PATCH" }); loadAdmin(); });
const deleteTurf = run(async (id) => { if (confirm("Delete this turf and ALL its bookings?")) { toast((await api(`/turfs/${id}`, { method: "DELETE" })).message); loadAdmin(); } });
const deleteBooking = run(async (id) => { if (confirm("Delete this booking record?")) { toast((await api(`/bookings/${id}`, { method: "DELETE" })).message); loadAdmin(); } });
const deleteUser = run(async (id) => {
  if (!confirm("Delete this user and their bookings/reviews?")) return;
  toast((await api(`/users/${id}`, { method: "DELETE" })).message);
  await loadUsers(state.user.user_id == id ? null : state.user.user_id); loadAdmin();
});

/* ---------------- DB lab ---------------- */
let lab = [], labSel = null;
const loadLab = run(async () => {
  if (!lab.length) {
    lab = await api("/lab");
    const cats = [...new Set(lab.map((q) => q.category))];
    $("#labCat").innerHTML = '<option value="">All categories</option>' + cats.map((c) => `<option>${esc(c)}</option>`).join("");
  }
  renderLabList();
});
function renderLabList() {
  const cat = $("#labCat").value;
  $("#labList").innerHTML = lab.filter((q) => !cat || q.category === cat).map((q) =>
    `<button class="list-group-item list-group-item-action ${labSel === q.key ? "active" : ""}" onclick="selectLab('${q.key}')"><div class="fw-semibold">${esc(q.title)}</div><small>${esc(q.category)}</small></button>`).join("");
}
$("#labCat").addEventListener("change", renderLabList);
function selectLab(key) {
  labSel = key; const q = lab.find((x) => x.key === key);
  $("#labTitle").textContent = q.title; $("#labDesc").textContent = q.desc; $("#labSql").textContent = q.sql;
  $("#labRun").disabled = false; $("#labTable").innerHTML = ""; $("#labCount").textContent = "Results"; renderLabList();
}
$("#labRun").addEventListener("click", run(async () => {
  const r = await api("/lab/" + labSel);
  const cols = r.rows.length ? Object.keys(r.rows[0]) : [];
  $("#labCount").textContent = `${r.rows.length} row(s)`;
  $("#labTable").innerHTML = cols.length ? `<thead><tr>${cols.map((c) => `<th>${esc(c)}</th>`).join("")}</tr></thead><tbody>${r.rows.map((row) =>
    `<tr>${cols.map((c) => `<td>${esc(row[c])}</td>`).join("")}</tr>`).join("")}</tbody>` : '<tbody><tr><td class="text-muted p-3">Query returned no rows.</td></tr></tbody>';
}));

/* ---------------- boot ---------------- */
(async () => { try { await loadFilters(); await loadUsers(); show("turfs"); } catch (e) { toast("Cannot reach the API: " + e.message, false); } })();
