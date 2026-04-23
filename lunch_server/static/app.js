const mealKeys = ["breakfast", "lunch", "dinner"];
const mealLabels = { breakfast: "조식", lunch: "중식", dinner: "석식" };

const state = {
  current: new Date(),
  selectedDate: null,
  selectedPayload: null,
  monthRecords: {},
};

const monthTitle = document.getElementById("monthTitle");
const calendarGrid = document.getElementById("calendarGrid");
const selectedDateLabel = document.getElementById("selectedDateLabel");
const detailTitle = document.getElementById("detailTitle");
const menuStatus = document.getElementById("menuStatus");
const menuItems = document.getElementById("menuItems");
const mealSelector = document.getElementById("mealSelector");
const datePicker = document.getElementById("datePicker");

document.getElementById("prevMonth").addEventListener("click", () => moveMonth(-1));
document.getElementById("nextMonth").addEventListener("click", () => moveMonth(1));
mealSelector.addEventListener("change", () => {
  if (state.selectedPayload) renderDetail(state.selectedPayload);
});
selectedDateLabel.addEventListener("click", () => {
  if (datePicker.showPicker) datePicker.showPicker();
  else datePicker.focus();
});
datePicker.addEventListener("change", () => {
  if (!datePicker.value) return;
  const [year, month] = datePicker.value.split("-").map(Number);
  state.current = new Date(year, month - 1, 1);
  loadMonth().then(() => selectDate(datePicker.value));
});

function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function moveMonth(delta) {
  state.current = new Date(state.current.getFullYear(), state.current.getMonth() + delta, 1);
  loadMonth();
}

async function loadMonth() {
  const year = state.current.getFullYear();
  const month = state.current.getMonth() + 1;
  monthTitle.textContent = `${year}년 ${month}월`;
  const response = await fetch(`/api/menus?year=${year}&month=${month}`);
  const payload = await readJson(response);
  state.monthRecords = payload.menus || {};
  renderCalendar();
}

function renderCalendar() {
  calendarGrid.innerHTML = "";
  const year = state.current.getFullYear();
  const month = state.current.getMonth();
  const first = new Date(year, month, 1);
  const startOffset = (first.getDay() + 6) % 7;
  const start = new Date(year, month, 1 - startOffset);

  for (let i = 0; i < 42; i += 1) {
    const date = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
    const key = formatDate(date);
    const record = state.monthRecords[key];
    const button = document.createElement("button");
    button.type = "button";
    button.className = "day-cell";
    if (date.getMonth() !== month) button.classList.add("outside");
    if (key === state.selectedDate) button.classList.add("selected");
    button.addEventListener("click", () => selectDate(key));

    const number = document.createElement("span");
    number.className = "day-number";
    number.textContent = String(date.getDate());
    button.appendChild(number);

    const chip = document.createElement("span");
    chip.className = "day-chip";
    const summary = summarizeDay(record, date);
    chip.textContent = summary.text;
    if (summary.kind) chip.classList.add(summary.kind);
    button.appendChild(chip);
    calendarGrid.appendChild(button);
  }
}

async function selectDate(key) {
  state.selectedDate = key;
  datePicker.value = key;
  renderCalendar();
  selectedDateLabel.textContent = key;
  detailTitle.textContent = "식단";
  menuStatus.className = "status-line";
  menuStatus.textContent = "";
  menuItems.innerHTML = "";

  try {
    const response = await fetch(`/api/meals?date=${encodeURIComponent(key)}`);
    const payload = await readJson(response);
    state.selectedPayload = payload;
    renderDetail(payload);
    window.dispatchEvent(new CustomEvent("meal-date-selected", { detail: payload }));
  } catch (error) {
    menuStatus.className = "status-line error";
    menuStatus.textContent = "실패";
  }
}

function renderDetail(payload) {
  selectedDateLabel.textContent = payload.date || state.selectedDate || "";
  menuItems.innerHTML = "";

  if (!payload.record && payload.status === "no_menu_info") {
    menuStatus.textContent = "미등록";
    return;
  }
  if (!payload.record && payload.status === "no_meal") {
    menuStatus.textContent = payload.code === "weekend" ? "주말" : "식사 없음";
    return;
  }

  const meals = payload.record?.meals || payload.meals || emptyMeals();
  const selectedMeal = mealSelector.value;
  menuItems.appendChild(renderMealBlock(selectedMeal, meals[selectedMeal] || emptyMeal()));

  if (payload.status === "no_menu_info") {
    menuStatus.textContent = "미등록";
  } else if (payload.status === "no_meal") {
    menuStatus.textContent = payload.code === "weekend" ? "주말" : "식사 없음";
  } else {
    menuStatus.textContent = "";
  }
}

function renderMealBlock(mealKey, mealRecord) {
  const section = document.createElement("section");
  section.className = "meal-card";

  const items = collectMenuItems(mealRecord.menu);
  if (mealRecord.hasMeal === false || items.length === 0) {
    const empty = document.createElement("p");
    empty.className = "meal-empty";
    empty.textContent = mealRecord.hasMeal === false ? "미제공" : "미등록";
    section.appendChild(empty);
    return section;
  }

  const list = document.createElement("ul");
  list.className = "menu-list";
  for (const item of items) {
    const li = document.createElement("li");
    li.textContent = item;
    list.appendChild(li);
  }
  section.appendChild(list);
  return section;
}

function summarizeDay(record, date) {
  if (!record) {
    return date.getDay() === 0 || date.getDay() === 6
      ? { text: "주말", kind: "closed" }
      : { text: "미등록", kind: "empty" };
  }

  const meals = record.meals || {};
  const availableCount = mealKeys.filter((mealKey) => mealHasContent(meals[mealKey])).length;
  if (availableCount === 3) return { text: "식사 있음", kind: "available" };
  if (availableCount > 0) return { text: "일부 있음", kind: "partial" };

  const allExplicitlyClosed = mealKeys.every((mealKey) => meals[mealKey]?.hasMeal === false);
  if (allExplicitlyClosed) return { text: "미제공", kind: "closed" };
  return { text: "식사 없음", kind: "closed" };
}

function mealHasContent(mealRecord = {}) {
  return mealRecord.hasMeal !== false && collectMenuItems(mealRecord.menu).length > 0;
}

function collectMenuItems(menu = {}) {
  const items = [];
  if (menu.main) items.push(menu.main);
  if (menu.soup) items.push(menu.soup);
  for (const item of menu.sideDishes || []) items.push(item);
  if (menu.dessert) items.push(menu.dessert);
  if (menu.drink) items.push(menu.drink);
  for (const item of menu.items || []) {
    if (!items.includes(item)) items.push(item);
  }
  return items;
}

function emptyMeals() {
  return Object.fromEntries(mealKeys.map((mealKey) => [mealKey, emptyMeal()]));
}

function emptyMeal() {
  return {
    hasMeal: true,
    reason: "",
    reasonCode: "",
    menu: { main: "", soup: "", sideDishes: [], dessert: "", drink: "", items: [] },
  };
}

async function readJson(response) {
  const contentType = response.headers.get("content-type") || "";
  if (contentType.includes("application/json")) return response.json();
  throw new Error("non-json-response");
}

loadMonth().then(() => {
  selectDate(formatDate(new Date()));
});
