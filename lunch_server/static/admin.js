const form = document.getElementById("menuForm");
const deleteButton = document.getElementById("deleteButton");
const importForm = document.getElementById("importForm");
const importResult = document.getElementById("importResult");
const importConfirm = document.getElementById("importConfirm");
const confirmImportButton = document.getElementById("confirmImportButton");
const cancelImportButton = document.getElementById("cancelImportButton");
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || "";

let pendingImportId = null;

window.addEventListener("meal-date-selected", (event) => {
  const meals = event.detail.record?.meals || emptyMeals();
  for (const mealKey of mealKeys) {
    fillMealForm(mealKey, meals[mealKey] || emptyMeal());
  }
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!state.selectedDate) return;

  const payload = {
    source: "manual",
    meals: Object.fromEntries(mealKeys.map((mealKey) => [mealKey, readMealForm(mealKey)])),
  };

  try {
    const response = await fetch(`/api/admin/menus/${state.selectedDate}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify(payload),
    });
    const result = await readJson(response);
    if (result.status !== "ok") throw new Error("save-failed");
    await loadMonth();
    await selectDate(state.selectedDate);
  } catch (error) {
    importResult.textContent = "실패";
    importResult.style.display = "block";
  }
});

deleteButton.addEventListener("click", async () => {
  if (!state.selectedDate) return;
  try {
    const response = await fetch(`/api/admin/menus/${state.selectedDate}`, {
      method: "DELETE",
      headers: { "X-CSRF-Token": csrfToken },
    });
    const result = await readJson(response);
    if (result.status !== "ok") throw new Error("delete-failed");
    await loadMonth();
    await selectDate(state.selectedDate);
  } catch (error) {
    importResult.textContent = "실패";
    importResult.style.display = "block";
  }
});

importForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const file = document.getElementById("xlsxFile").files[0];
  if (!file) return;

  resetImportConfirm();
  importResult.style.display = "block";
  importResult.textContent = "분석 중";

  const formData = new FormData();
  formData.append("file", file);

  try {
    const response = await fetch("/api/admin/preview-xlsx", {
      method: "POST",
      headers: { "X-CSRF-Token": csrfToken },
      body: formData,
    });
    const result = await readJson(response);
    if (result.status !== "ok") throw new Error("preview-failed");

    pendingImportId = result.importId;
    document.getElementById("confirmTotal").textContent = String(result.totalDates || 0);
    document.getElementById("confirmOverwrite").textContent = String(result.overwriteDates || 0);
    document.getElementById("confirmFailed").textContent = String(result.failedDates || 0);
    importResult.textContent = "분석 완료";
    importConfirm.hidden = false;
  } catch (error) {
    importResult.textContent = "실패";
  }
});

confirmImportButton.addEventListener("click", async () => {
  if (!pendingImportId) return;
  try {
    const response = await fetch("/api/admin/commit-import", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ importId: pendingImportId }),
    });
    const result = await readJson(response);
    if (result.status !== "ok") throw new Error("commit-failed");
    importResult.textContent = "성공";
    resetImportConfirm();
    await loadMonth();
    if (state.selectedDate) await selectDate(state.selectedDate);
  } catch (error) {
    importResult.textContent = "실패";
  }
});

cancelImportButton.addEventListener("click", () => {
  importResult.textContent = "";
  importResult.style.display = "none";
  resetImportConfirm();
});

function fillMealForm(mealKey, mealRecord) {
  const menu = mealRecord.menu || {};
  field(mealKey, "HasMeal").value = String(mealRecord.hasMeal !== false);
  field(mealKey, "Reason").value = mealRecord.reason || "";
  field(mealKey, "Main").value = menu.main || "";
  field(mealKey, "Soup").value = menu.soup || "";
  field(mealKey, "SideDishes").value = (menu.sideDishes || []).join("\n");
  field(mealKey, "Dessert").value = menu.dessert || "";
  field(mealKey, "Drink").value = menu.drink || "";
  field(mealKey, "Items").value = (menu.items || []).join("\n");
}

function readMealForm(mealKey) {
  return {
    hasMeal: field(mealKey, "HasMeal").value === "true",
    reason: field(mealKey, "Reason").value,
    reasonCode: field(mealKey, "HasMeal").value === "true" ? "" : "closed",
    menu: {
      main: field(mealKey, "Main").value,
      soup: field(mealKey, "Soup").value,
      sideDishes: lines(field(mealKey, "SideDishes").value),
      dessert: field(mealKey, "Dessert").value,
      drink: field(mealKey, "Drink").value,
      items: lines(field(mealKey, "Items").value),
      notes: "",
      rawText: "",
    },
  };
}

function field(mealKey, suffix) {
  return document.getElementById(`${mealKey}${suffix}`);
}

function resetImportConfirm() {
  pendingImportId = null;
  importConfirm.hidden = true;
}

function lines(value) {
  return value
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean);
}
