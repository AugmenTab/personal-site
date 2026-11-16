// Work index: search and category filter (Phase 05).
//
// Progressive enhancement. The HTML already lists every published project,
// and the controls (#work-filter) and the empty-result message (#work-empty)
// are `hidden`; without this script the page is a complete, static list.
// The script reveals the controls and shows or hides the existing cards. It
// reads only what the generator rendered (README "Search and filtering"):
//
//   li.work__item[data-category]  a category id from Site.Taxonomy
//   li.work__item[data-search]    title, summary, category, technologies and
//                                 topics, lowercased, single-spaced
//
// Semantics: a project is shown when it is in the selected category (All:
// any category) AND its text contains every word of the query (in any
// order, case-insensitive, extra whitespace ignored).
//
// Nothing is fetched, stored or sent anywhere.

const root = document.getElementById("work-filter");
const list = document.getElementById("work-list");
const input = document.getElementById("work-search");
const status = document.getElementById("work-status");
const empty = document.getElementById("work-empty");

if (root && list && input && status && empty) {
  const reset = empty.querySelector(".work-filter__reset");
  const chips = [...root.querySelectorAll(".work-filter__chip")];
  const items = [...list.querySelectorAll(".work__item")];
  const total = items.length;
  let category = "";

  const normalise = (text) => text.toLowerCase().replace(/\s+/g, " ").trim();
  const plural = (n) => (n === 1 ? "project" : "projects");

  const apply = () => {
    const terms = normalise(input.value).split(" ").filter(Boolean);
    let shown = 0;
    for (const item of items) {
      const text = item.dataset.search || "";
      const match =
        (category === "" || item.dataset.category === category) &&
        terms.every((term) => text.includes(term));
      item.hidden = !match;
      if (match) shown += 1;
    }
    empty.hidden = shown !== 0;
    const filtering = category !== "" || terms.length > 0;
    status.textContent = filtering
      ? `${shown} of ${total} ${plural(total)}`
      : `${total} ${plural(total)}`;
    // Never leave keyboard focus inside a card that was just hidden.
    const active = document.activeElement;
    if (active && active.closest && active.closest(".work__item[hidden]")) {
      input.focus();
    }
  };

  const select = (value) => {
    category = value;
    for (const chip of chips) {
      chip.setAttribute("aria-pressed", String(chip.dataset.category === value));
    }
    apply();
  };

  for (const chip of chips) {
    chip.type = "button";
    chip.addEventListener("click", () => select(chip.dataset.category || ""));
  }
  input.addEventListener("input", apply);
  if (reset) {
    reset.type = "button";
    reset.addEventListener("click", () => {
      input.value = "";
      select("");
      input.focus();
    });
  }

  root.hidden = false;
  // A restored page (back/forward cache, form restoration) may already
  // carry a query: filter to match it.
  apply();
}
