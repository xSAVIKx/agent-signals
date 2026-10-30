// The filter box of the facts table. The page works without this script:
// the box stays hidden and the table shows all facts.
(function () {
  "use strict";
  var box = document.getElementById("fact-filter-box");
  var input = document.getElementById("fact-filter");
  var status = document.getElementById("fact-filter-status");
  var table = document.getElementById("facts-table");
  if (!box || !input || !status || !table) {
    return;
  }
  var rows = Array.prototype.slice.call(table.tBodies[0].rows);
  var timer = 0;

  function apply() {
    var words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    var shown = 0;
    rows.forEach(function (row) {
      var text = row.textContent.toLowerCase();
      var match = words.every(function (w) { return text.indexOf(w) >= 0; });
      row.hidden = !match;
      if (match) {
        shown += 1;
      }
    });
    status.textContent = words.length === 0
      ? ""
      : shown + " of " + rows.length + " facts shown.";
  }

  input.addEventListener("input", function () {
    window.clearTimeout(timer);
    timer = window.setTimeout(apply, 150);
  });
  box.hidden = false;
})();
